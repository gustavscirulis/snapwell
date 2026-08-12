import Foundation

struct ScannedFile: Sendable {
    let id: String
    let url: URL
    let modDate: Date
    let state: DownloadState
}

enum ContainerScanner {
    /// Returns nil when the directory could not be read. Callers must not treat that as
    /// an empty library — an unreadable directory looks identical to a deleted one, and
    /// acting on it would delete every record.
    static func scanMetadata(_ directory: URL, isUsingiCloud: Bool) -> [String: ScannedFile]? {
        scan(directory, requiredExtension: "json", isUsingiCloud: isUsingiCloud)
    }

    /// Scans once and preserves the real media extension instead of deriving it
    /// from the sidecar's broad image/video type. Nil when the directory is unreadable.
    static func scanMedia(_ directory: URL, isUsingiCloud: Bool) -> [String: ScannedFile]? {
        scan(directory, requiredExtension: nil, isUsingiCloud: isUsingiCloud)
    }

    private static func scan(
        _ directory: URL,
        requiredExtension: String?,
        isUsingiCloud: Bool
    ) -> [String: ScannedFile]? {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .ubiquitousItemDownloadingStatusKey,
            .isDirectoryKey,
        ]
        guard let listedURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return nil }

        var result: [String: ScannedFile] = [:]
        for listedURL in listedURLs {
            let listedName = listedURL.lastPathComponent
            let placeholderName = ICloudFile.canonicalName(fromPlaceholder: listedName)
            if placeholderName != nil && !isUsingiCloud { continue }

            let canonicalName = placeholderName ?? listedName
            let canonicalURL = directory.appendingPathComponent(canonicalName)
            if let requiredExtension,
               canonicalURL.pathExtension.lowercased() != requiredExtension {
                continue
            }
            guard !canonicalURL.pathExtension.isEmpty else { continue }

            let values = try? listedURL.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }

            let id = canonicalURL.deletingPathExtension().lastPathComponent
            guard !id.isEmpty, !id.hasPrefix(".") else { continue }

            let scanned = ScannedFile(
                id: id,
                url: canonicalURL,
                modDate: values?.contentModificationDate ?? .distantPast,
                state: ICloudFile.downloadState(of: canonicalURL, isUsingiCloud: isUsingiCloud)
            )

            // During materialization Finder can briefly expose both names. Prefer
            // the canonical/downloaded entry so callers never regress its state.
            if let existing = result[id], existing.state == .downloaded {
                continue
            }
            result[id] = scanned
        }
        return result
    }
}
