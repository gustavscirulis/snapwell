import Foundation
import UniformTypeIdentifiers

// MARK: - Supported Media Types + Filename Resolution (shared by both apps)
//
// Single source of truth for which extensions/UTTypes are supported and for
// resolving the real on-disk media filename. Previously duplicated across the
// Mac `SupportedMedia` and an iOS copy embedded in `SyncService`.

enum SupportedMedia {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]
    static let videoExtensions: Set<String> = ["mp4", "webm", "mov", "avi", "m4v"]
    static let allExtensions: Set<String> = imageExtensions.union(videoExtensions)

    static func isImage(_ ext: String) -> Bool { imageExtensions.contains(ext.lowercased()) }
    static func isVideo(_ ext: String) -> Bool { videoExtensions.contains(ext.lowercased()) }
    static func isSupported(_ ext: String) -> Bool { allExtensions.contains(ext.lowercased()) }

    /// UTTypes for the import file picker. Note: .webm has no system UTType.
    static let importableContentTypes: [UTType] = [
        .png, .jpeg, .gif, .bmp, .tiff, .webP, .heic,
        .mpeg4Movie, .movie, .avi
    ]

    /// Maps MIME types to file extensions for URL downloads.
    static let mimeToExtension: [String: String] = [
        "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg",
        "image/gif": "gif", "image/webp": "webp", "image/bmp": "bmp",
        "image/tiff": "tiff", "image/heic": "heic",
        "video/mp4": "mp4", "video/webm": "webm",
        "video/quicktime": "mov", "video/x-msvideo": "avi", "video/x-m4v": "m4v",
    ]
}

/// Resolves the real on-disk media filename for an item id by probing the actual
/// files in a directory rather than guessing the extension from the sidecar `type`.
///
/// Import normalises saved files to `png`/`mp4`, but cross-source / cross-device
/// files can be `heic`/`webp`/`m4v`/`avi`/`webm`/`mov`/`jpg`/etc. Guessing from `type`
/// (the old behaviour) silently dropped those. This walks `SupportedMedia.allExtensions`
/// and returns whatever file is genuinely present.
enum MediaFilenameResolver {

    /// Returns `"{id}.{ext}"` for the real media file in `directory`, or `nil` if none
    /// of the supported extensions resolves to an existing file (or an iCloud
    /// placeholder for one).
    ///
    /// - Parameter preferredExtensions: extensions to try first (e.g. derived from the
    ///   sidecar `type`) so the common case resolves on the first probe. The full set
    ///   from `SupportedMedia.allExtensions` is always tried as a fallback.
    static func resolveMediaFilename(
        id: String,
        in directory: URL,
        preferredExtensions: [String] = []
    ) -> String? {
        let fm = FileManager.default
        for ext in orderedExtensions(preferred: preferredExtensions) {
            let filename = "\(id).\(ext)"
            let candidate = directory.appendingPathComponent(filename)
            if fm.fileExists(atPath: candidate.path) {
                return filename
            }
            // Also treat an iCloud placeholder ".{id}.{ext}.icloud" as a match so the
            // caller can trigger a download for the real file.
            let placeholder = directory.appendingPathComponent(".\(filename).icloud")
            if fm.fileExists(atPath: placeholder.path) {
                return filename
            }
        }
        return nil
    }

    /// Convenience returning the full URL for the resolved filename.
    static func resolveMediaURL(
        id: String,
        in directory: URL,
        preferredExtensions: [String] = []
    ) -> URL? {
        resolveMediaFilename(id: id, in: directory, preferredExtensions: preferredExtensions)
            .map { directory.appendingPathComponent($0) }
    }

    /// Preferred extensions first (de-duplicated), then the remaining supported set.
    private static func orderedExtensions(preferred: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for ext in preferred {
            let lower = ext.lowercased()
            if seen.insert(lower).inserted { ordered.append(lower) }
        }
        for ext in SupportedMedia.allExtensions where seen.insert(ext).inserted {
            ordered.append(ext)
        }
        return ordered
    }
}
