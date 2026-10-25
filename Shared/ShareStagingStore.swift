import Foundation

/// Publishes the sidecar last so the app never observes an incomplete share.
enum ShareStagingStore {
    static func stage(media: Data, sidecar: Data, id: String, mediaExtension: String,
                      in pendingDirectory: URL,
                      writeSidecar: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        guard !id.isEmpty, id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              ["png", "mp4"].contains(mediaExtension) else { throw CocoaError(.fileWriteInvalidFileName) }
        let fm = FileManager.default
        let images = pendingDirectory.appendingPathComponent("images", isDirectory: true)
        let metadata = pendingDirectory.appendingPathComponent("metadata", isDirectory: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try fm.createDirectory(at: metadata, withIntermediateDirectories: true)
        let mediaURL = images.appendingPathComponent("\(id).\(mediaExtension)")
        let sidecarURL = metadata.appendingPathComponent("\(id).json")
        guard !fm.fileExists(atPath: mediaURL.path), !fm.fileExists(atPath: sidecarURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try media.write(to: mediaURL, options: .atomic)
        do {
            try writeSidecar(sidecar, sidecarURL)
        } catch {
            try? fm.removeItem(at: mediaURL)
            throw error
        }
    }
}
