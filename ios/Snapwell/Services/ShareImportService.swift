import Foundation

/// Moves media saved by the Share Extension from the App Group staging area
/// into the iCloud container so they sync to the Mac app for analysis.
enum ShareImportService {

    private static let appGroupID = "group.co.snapwell"

    /// Check the App Group pending directory and move any media + metadata
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

        // Ensure destination directories exist
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)

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

            // Copy first and retain both staged files until metadata commits. If a write
            // fails, the next foreground import can retry without losing its source media.
            guard fm.fileExists(atPath: srcMedia.path) else { continue }
            do {
                if fm.fileExists(atPath: dstImage.path) {
                    guard fm.contentsEqual(atPath: dstImage.path, andPath: srcMedia.path) else {
                        continue // A conflicting destination must not be overwritten.
                    }
                } else {
                    try fm.copyItem(at: srcMedia, to: dstImage)
                }
                if !fm.fileExists(atPath: dstMetadata.path) {
                    try data.write(to: dstMetadata, options: .atomic)
                } else {
                    // Preserve a sidecar already enriched by sync or analysis.
                    let existing = try Data(contentsOf: dstMetadata)
                    guard let object = try JSONSerialization.jsonObject(with: existing) as? [String: Any],
                          object["id"] as? String == id else { continue }
                }
                try fm.removeItem(at: jsonURL)
                try? fm.removeItem(at: srcMedia)
            } catch {
                #if DEBUG
                print("[ShareImport] Failed to import \(id): \(error)")
                #endif
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
