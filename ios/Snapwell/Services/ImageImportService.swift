import UIKit
import Foundation
import AVFoundation

enum PickedMedia {
    case image(UIImage)
    case video(URL)
}

/// Writes images and sidecar JSON directly to the iCloud container.
/// Reuses the same ID and metadata format as the Share Extension.
enum ImageImportService {

    struct ImportResult {
        let successCount: Int
        let failureCount: Int
    }

    /// Import in picker order. The progress callback runs after each selected item.
    @MainActor
    static func importItems(
        _ items: [PickedMedia],
        to rootURL: URL,
        spaceId: String? = nil,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> ImportResult {
        var success = 0
        var failure = 0
        for (index, item) in items.enumerated() {
            switch item {
            case .image(let image):
                let result = await importImages([image], to: rootURL, spaceId: spaceId)
                success += result.successCount
                failure += result.failureCount
            case .video(let stagedURL):
                let imported = await Task.detached(priority: .userInitiated) {
                    await importVideo(stagedURL, to: rootURL, spaceId: spaceId)
                }.value
                if imported {
                    success += 1
                } else {
                    failure += 1
                }
                try? FileManager.default.removeItem(at: stagedURL)
            }
            progress?(index + 1, items.count)
            await Task.yield()
        }
        return ImportResult(successCount: success, failureCount: failure)
    }

    private static func importVideo(_ source: URL, to rootURL: URL, spaceId: String?) async -> Bool {
        let ext = source.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v", "avi", "webm"].contains(ext) else { return false }
        let fm = FileManager.default
        let id = UUID().uuidString
        let mediaDir = rootURL.appendingPathComponent("images", isDirectory: true)
        let metadataDir = rootURL.appendingPathComponent("metadata", isDirectory: true)
        let thumbnailDir = rootURL.appendingPathComponent("thumbnails", isDirectory: true)
        let mediaURL = mediaDir.appendingPathComponent("\(id).\(ext)")
        let metadataURL = metadataDir.appendingPathComponent("\(id).json")
        let thumbnailURL = thumbnailDir.appendingPathComponent("\(id).jpg")
        var committed = false
        defer {
            if !committed {
                try? fm.removeItem(at: mediaURL)
                try? fm.removeItem(at: metadataURL)
                try? fm.removeItem(at: thumbnailURL)
            }
        }
        do {
            for directory in [mediaDir, metadataDir, thumbnailDir] {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let asset = AVURLAsset(url: source)
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1200, height: 1200)
            let frame: CGImage
            do {
                frame = try generator.copyCGImage(at: .zero, actualTime: nil)
            } catch {
                let fallbackSecond = duration.isFinite ? min(max(duration / 2, 0), 1) : 1
                let fallbackTime = CMTime(seconds: fallbackSecond, preferredTimescale: 600)
                frame = try generator.copyCGImage(at: fallbackTime, actualTime: nil)
            }
            guard let thumbnail = UIImage(cgImage: frame).jpegData(compressionQuality: 0.85) else { return false }
            var width = frame.width
            var height = frame.height
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let display = CGRect(origin: .zero, size: size).applying(transform).standardized
                if display.width > 0, display.height > 0 {
                    width = Int(display.width)
                    height = Int(display.height)
                }
            }

            try fm.copyItem(at: source, to: mediaURL)
            try thumbnail.write(to: thumbnailURL, options: .atomic)
            let sidecar = SidecarMetadata(
                id: id, type: "video", width: width, height: height,
                createdAt: Date(), duration: duration.isFinite ? duration : nil,
                spaceIds: spaceId.map { [$0] }, imageContext: nil, imageSummary: nil,
                patterns: nil, sourceURL: nil, analyzedAt: nil
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sidecar).write(to: metadataURL, options: .atomic)
            committed = true
            return true
        } catch {
            print("[ImageImport] Failed to import video: \(error)")
            return false
        }
    }

    /// Import an array of UIImages into the Snapwell iCloud container.
    /// Writes each image as PNG + sidecar JSON to `rootURL/images/` and `rootURL/metadata/`.
    /// If `spaceId` is provided, the sidecar will reference that space membership.
    static func importImages(_ images: [UIImage], to rootURL: URL, spaceId: String? = nil) async -> ImportResult {
        let fm = FileManager.default
        let imagesDir = rootURL.appendingPathComponent("images", isDirectory: true)
        let metadataDir = rootURL.appendingPathComponent("metadata", isDirectory: true)

        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var success = 0
        var failure = 0

        for image in images {
            let ok = autoreleasepool { () -> Bool in
                let id = UUID().uuidString

                guard let pngData = image.pngData() else { return false }

                let width = Int(image.size.width * image.scale)
                let height = Int(image.size.height * image.scale)

                let imageURL = imagesDir.appendingPathComponent("\(id).png")
                let metadataURL = metadataDir.appendingPathComponent("\(id).json")

                do {
                    try pngData.write(to: imageURL, options: .atomic)
                } catch {
                    #if DEBUG
                    print("[ImageImport] Failed to write image \(id): \(error)")
                    #endif
                    return false
                }

                let sidecar = SidecarMetadata(
                    id: id,
                    type: "image",
                    width: width,
                    height: height,
                    createdAt: Date(),
                    duration: nil,
                    spaceIds: spaceId.map { [$0] },
                    imageContext: nil,
                    imageSummary: nil,
                    patterns: nil,
                    sourceURL: nil,
                    analyzedAt: nil
                )

                guard let jsonData = try? encoder.encode(sidecar) else {
                    try? fm.removeItem(at: imageURL)
                    return false
                }

                do {
                    try jsonData.write(to: metadataURL, options: .atomic)
                } catch {
                    #if DEBUG
                    print("[ImageImport] Failed to write metadata \(id): \(error)")
                    #endif
                    // Clean up the image file since metadata failed
                    try? fm.removeItem(at: imageURL)
                    return false
                }

                #if DEBUG
                print("[ImageImport] Imported \(id) (\(width)x\(height))")
                #endif
                return true
            }

            if ok {
                success += 1
            } else {
                failure += 1
            }

            // Yield between images to keep UI responsive
            await Task.yield()
        }

        return ImportResult(successCount: success, failureCount: failure)
    }
}
