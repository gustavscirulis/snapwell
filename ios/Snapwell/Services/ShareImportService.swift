import Foundation

/// Publishes media saved by the Share Extension from the App Group staging area
/// into the iCloud container so they sync to the Mac app for analysis.
enum ShareImportService {

    private static let appGroupID = "group.co.snapwell"

    /// Check the App Group pending directory and publish any media + metadata
    /// into the iCloud container. Safe to call multiple times — completed
    /// imports are deleted from the staging area.
    static func importPendingItems(to rootURL: URL) {
        // Automation hosts must never consult the real App Group.
        guard !AutomationEnvironment.isEnabled,
              let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        importPendingItems(from: containerURL.appendingPathComponent("pending", isDirectory: true), to: rootURL)
    }

    static func importPendingItems(from pendingDir: URL, to rootURL: URL) {
        let fm = FileManager.default
        let pendingImages = pendingDir.appendingPathComponent("images", isDirectory: true)
        let pendingMetadata = pendingDir.appendingPathComponent("metadata", isDirectory: true)

        guard fm.fileExists(atPath: pendingMetadata.path) else { return }

        let imagesDir = rootURL.appendingPathComponent("images", isDirectory: true)
        let metadataDir = rootURL.appendingPathComponent("metadata", isDirectory: true)

        do {
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)
        } catch {
            print("[ShareImport] Cannot prepare destination: \(error)")
            return
        }

        // List pending metadata files
        guard let metadataFiles = try? fm.contentsOfDirectory(
            at: pendingMetadata,
            includingPropertiesForKeys: nil
        ) else { return }

        let jsonFiles = metadataFiles.filter { $0.pathExtension == "json" }
        guard !jsonFiles.isEmpty else { return }

        #if DEBUG
        print("[ShareImport] Found \(jsonFiles.count) pending import(s)")
        #endif

        for jsonURL in jsonFiles {
            let id = jsonURL.deletingPathExtension().lastPathComponent

            // Leave incomplete or malformed shares staged for recovery.
            guard let data = try? Data(contentsOf: jsonURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["id"] as? String == id,
                  let type = json["type"] as? String, ["image", "video"].contains(type),
                  let ext = mediaExtension(for: jsonURL) else { continue }
            let mediaFilename = "\(id).\(ext)"

            let srcMedia = pendingImages.appendingPathComponent(mediaFilename)
            let dstImage = imagesDir.appendingPathComponent(mediaFilename)
            let dstMetadata = metadataDir.appendingPathComponent(jsonURL.lastPathComponent)

            do {
                // A published file may be evicted. Wait for it rather than replacing it.
                let mediaState = ICloudFile.downloadState(of: dstImage, isUsingiCloud: true)
                let metadataState = ICloudFile.downloadState(of: dstMetadata, isUsingiCloud: true)
                if mediaState == .downloading || metadataState == .downloading {
                    if mediaState == .downloading { DownloadRequester.shared.requestDownload(for: dstImage) }
                    if metadataState == .downloading { DownloadRequester.shared.requestDownload(for: dstMetadata) }
                    continue
                }

                if mediaState == .downloaded, fm.fileExists(atPath: srcMedia.path),
                   !fm.contentsEqual(atPath: dstImage.path, andPath: srcMedia.path) {
                    continue
                }

                if mediaState == .notPresent {
                    let temporaryMedia = imagesDir.appendingPathComponent(".\(mediaFilename).importing")
                    defer { try? fm.removeItem(at: temporaryMedia) }
                    if fm.fileExists(atPath: temporaryMedia.path) {
                        try fm.removeItem(at: temporaryMedia)
                    }
                    try fm.copyItem(at: srcMedia, to: temporaryMedia)
                    try fm.moveItem(at: temporaryMedia, to: dstImage)
                }

                if metadataState == .notPresent {
                    let data = try Data(contentsOf: jsonURL)
                    let temporaryMetadata = metadataDir.appendingPathComponent(".\(id).json.importing")
                    defer { try? fm.removeItem(at: temporaryMetadata) }
                    try data.write(to: temporaryMetadata, options: .atomic)
                    try fm.moveItem(at: temporaryMetadata, to: dstMetadata)
                } else {
                    // A previous attempt may have published metadata that was edited since.
                    let data = try Data(contentsOf: dstMetadata)
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard json?["id"] as? String == id else { continue }
                }

                // Retire the commit marker last so interrupted cleanup can also be retried.
                if fm.fileExists(atPath: srcMedia.path) {
                    try fm.removeItem(at: srcMedia)
                }
                try fm.removeItem(at: jsonURL)
            } catch {
                print("[ShareImport] Pending import \(id) will be retried: \(error)")
                continue
            }

            #if DEBUG
            print("[ShareImport] Imported \(id)")
            #endif
        }
    }

    /// Read the sidecar JSON to determine whether this is a video or image.
    static func mediaExtension(for sidecarURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sidecarURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        return type == "video" ? "mp4" : "png"
    }
}
