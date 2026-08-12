import Foundation

enum DownloadState: Sendable, Equatable {
    case downloaded
    case downloading
    case notPresent
}

enum ICloudFile {
    /// Converts Finder's on-disk placeholder name (`.photo.png.icloud`) to
    /// the canonical iCloud container name (`photo.png`).
    static func canonicalName(fromPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let start = name.index(after: name.startIndex)
        let end = name.index(name.endIndex, offsetBy: -".icloud".count)
        guard start < end else { return nil }
        return String(name[start..<end])
    }

    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    static func downloadState(of url: URL, isUsingiCloud: Bool) -> DownloadState {
        let fileManager = FileManager.default

        guard isUsingiCloud else {
            return fileManager.fileExists(atPath: url.path) ? .downloaded : .notPresent
        }

        if fileManager.fileExists(atPath: url.path) {
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values?.ubiquitousItemDownloadingStatus, status != .current {
                return .downloading
            }
            return .downloaded
        }

        if fileManager.fileExists(atPath: placeholderURL(for: url).path) {
            return .downloading
        }

        return .notPresent
    }
}
