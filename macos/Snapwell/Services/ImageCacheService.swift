import AppKit

enum ThumbnailLoadState: Sendable {
    case loaded(NSImage)
    case downloading
    case unavailable
}

/// In-memory thumbnail cache to avoid repeated disk reads.
/// Uses NSCache which automatically evicts under memory pressure.
final class ImageCacheService: @unchecked Sendable {
    static let shared = ImageCacheService()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 1500
        cache.totalCostLimit = 200 * 1024 * 1024 // 200 MB
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String) {
        let cost = image.tiffRepresentation?.count ?? 100_000
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
    }

    /// Load a thumbnail for an item, checking cache first, then disk.
    /// Caches the result for future reads. Runs disk I/O on a background thread.
    /// When no pre-generated thumbnail exists, generates and persists one from the
    /// original file to avoid caching full-resolution images in memory.
    func loadThumbnail(id: String, filename: String) async -> NSImage? {
        if case .loaded(let image) = await loadThumbnailState(id: id, filename: filename) {
            return image
        }
        return nil
    }

    /// Loads the shared thumbnail first. When either the thumbnail or original
    /// is an iCloud placeholder, requests it and reports a transient state so
    /// grid cells can keep waiting instead of presenting a permanent failure.
    func loadThumbnailState(id: String, filename: String) async -> ThumbnailLoadState {
        if let cached = image(forKey: id) {
            return .loaded(cached)
        }

        let result: ThumbnailLoadState = await Task.detached(priority: .utility) {
            let storage = MediaStorageService.shared
            let requester = DownloadRequester.shared
            let thumbnailURL = storage.thumbnailURL(id: id)

            switch ICloudFile.downloadState(of: thumbnailURL, isUsingiCloud: storage.isUsingiCloud) {
            case .downloaded:
                if let thumbnail = NSImage(contentsOf: thumbnailURL) {
                    return .loaded(thumbnail)
                }
            case .downloading:
                requester.requestDownload(for: thumbnailURL)
                return .downloading
            case .notPresent:
                break
            }

            let mediaURL = storage.mediaURL(filename: filename)
            switch ICloudFile.downloadState(of: mediaURL, isUsingiCloud: storage.isUsingiCloud) {
            case .downloading:
                requester.requestDownload(for: mediaURL)
                return .downloading
            case .notPresent:
                return .unavailable
            case .downloaded:
                break
            }

            guard let original = NSImage(contentsOf: mediaURL) else { return .unavailable }

            if let _ = try? ThumbnailService.generateThumbnail(from: original, id: id, storage: storage) {
                if let thumbnail = NSImage(contentsOf: thumbnailURL) {
                    return .loaded(thumbnail)
                }
            }

            if let thumbData = original.thumbnailData(maxWidth: 800, quality: 0.9) {
                if let thumbnail = NSImage(data: thumbData) {
                    return .loaded(thumbnail)
                }
            }
            return .unavailable
        }.value

        if case .loaded(let loaded) = result {
            setImage(loaded, forKey: id)
        }
        return result
    }
}
