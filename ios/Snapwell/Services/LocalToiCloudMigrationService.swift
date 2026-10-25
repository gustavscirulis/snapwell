import Foundation

/// Silently migrates local media files to iCloud when iCloud becomes available.
/// Uses ID-based dedup (UUIDs) so the operation is idempotent and safe to retry.
/// Copies first, then deletes local copies — no data loss on interruption.
enum LocalToiCloudMigrationService {

    private static let migrationKey = "localToiCloudMigrationComplete_v1"

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Migrate local files to the iCloud container.
    /// Safe to call multiple times — guarded by UserDefaults flag and ID dedup.
    @discardableResult
    static func migrate(from localRoot: URL, to iCloudRoot: URL, defaults: UserDefaults = .standard) async -> Bool {
        guard !defaults.bool(forKey: migrationKey) else { return true }

        let fm = FileManager.default
        let localMetadata = localRoot.appendingPathComponent("metadata")
        let localImages = localRoot.appendingPathComponent("images")
        let localThumbnails = localRoot.appendingPathComponent("thumbnails")

        let iCloudMetadata = iCloudRoot.appendingPathComponent("metadata")
        let iCloudImages = iCloudRoot.appendingPathComponent("images")
        let iCloudThumbnails = iCloudRoot.appendingPathComponent("thumbnails")

        // An unreadable source/destination is a retryable failure, never an empty library.
        let localJsons: [URL]
        do {
            for dir in [iCloudMetadata, iCloudImages, iCloudThumbnails] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            localJsons = fm.fileExists(atPath: localMetadata.path)
                ? try fm.contentsOfDirectory(at: localMetadata, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
                : []
        } catch { return false }

        var migrated = 0

        for jsonURL in localJsons {
            let id = jsonURL.deletingPathExtension().lastPathComponent

            do {
                try Task.checkCancellation()
                if fm.fileExists(atPath: iCloudMetadata.appendingPathComponent(".\(id).json.icloud").path) {
                    return false // Wait for the remote sidecar before resolving conflicts.
                }
                if fm.fileExists(atPath: iCloudMetadata.appendingPathComponent("\(id).json").path) {
                    try mergeAnalysisIfNewer(localJSON: jsonURL, iCloudMetadataDir: iCloudMetadata, id: id)
                }
                try copyItemToiCloud(
                    id: id, localJSON: jsonURL, localImages: localImages,
                    localThumbnails: localThumbnails, iCloudMetadata: iCloudMetadata,
                    iCloudImages: iCloudImages, iCloudThumbnails: iCloudThumbnails
                )
                migrated += 1
            } catch { return false }

            // Yield periodically to avoid blocking
            if migrated % 10 == 0 { await Task.yield() }
        }

        // Merge spaces.json
        do { try mergeSpaces(from: localRoot, to: iCloudRoot) } catch { return false }

        // Only remove copied files after every write succeeds. Preserve unrelated files and trash.
        cleanupLocalStorage(localRoot, jsonFiles: localJsons)

        defaults.set(true, forKey: migrationKey)
        print("[Migration] Migrated \(migrated) items from local to iCloud")
        return true
    }

    // MARK: - Copy

    private static func copyItemToiCloud(
        id: String,
        localJSON: URL,
        localImages: URL,
        localThumbnails: URL,
        iCloudMetadata: URL,
        iCloudImages: URL,
        iCloudThumbnails: URL
    ) throws {
        let fm = FileManager.default
        let sidecar = try decoder.decode(SidecarMetadata.self, from: Data(contentsOf: localJSON))
        guard sidecar.id == id, ["image", "video"].contains(sidecar.type) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let ext = mediaExtension(for: localJSON)

        // Publish media before metadata, including retries after a partial copy.
        let mediaFilename = "\(id).\(ext)"
        let srcMedia = localImages.appendingPathComponent(mediaFilename)
        let dstMedia = iCloudImages.appendingPathComponent(mediaFilename)
        if !fm.fileExists(atPath: dstMedia.path) {
            try fm.copyItem(at: srcMedia, to: dstMedia)
        } else {
            // Existing IDs may be legitimate duplicates, but not unreadable placeholders/directories.
            let values = try dstMedia.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
            guard values.isRegularFile == true, values.isReadable == true else {
                throw CocoaError(.fileReadNoPermission)
            }
        }
        let dstJSON = iCloudMetadata.appendingPathComponent("\(id).json")
        if !fm.fileExists(atPath: dstJSON.path) {
            try fm.copyItem(at: localJSON, to: dstJSON)
        }

        // Copy thumbnail
        let srcThumb = localThumbnails.appendingPathComponent("\(id).jpg")
        let dstThumb = iCloudThumbnails.appendingPathComponent("\(id).jpg")
        if fm.fileExists(atPath: srcThumb.path) && !fm.fileExists(atPath: dstThumb.path) {
            try fm.copyItem(at: srcThumb, to: dstThumb)
        }
    }

    // MARK: - Merge Analysis

    private static func mergeAnalysisIfNewer(localJSON: URL, iCloudMetadataDir: URL, id: String) throws {
        let localData = try Data(contentsOf: localJSON)
        let localSidecar = try decoder.decode(SidecarMetadata.self, from: localData)
        let iCloudJSON = iCloudMetadataDir.appendingPathComponent("\(id).json")
        let iCloudSidecar = try decoder.decode(SidecarMetadata.self, from: Data(contentsOf: iCloudJSON))
        guard let localAnalyzedAt = localSidecar.analyzedAt else { return }

        let shouldUpdate: Bool
        if let remoteAnalyzedAt = iCloudSidecar.analyzedAt {
            shouldUpdate = localAnalyzedAt > remoteAnalyzedAt
        } else {
            shouldUpdate = true // Local has analysis, remote doesn't
        }

        if shouldUpdate {
            // Analysis timestamps do not establish ownership of remotely edited spaces/source fields.
            var remote = try JSONSerialization.jsonObject(with: Data(contentsOf: iCloudJSON)) as! [String: Any]
            let local = try JSONSerialization.jsonObject(with: localData) as! [String: Any]
            for key in ["imageContext", "imageSummary", "patterns", "analyzedAt"] { remote[key] = local[key] }
            try JSONSerialization.data(withJSONObject: remote, options: .sortedKeys).write(to: iCloudJSON, options: .atomic)
        }
    }

    // MARK: - Merge Spaces

    private static func mergeSpaces(from localRoot: URL, to iCloudRoot: URL) throws {
        let localSpaces = localRoot.appendingPathComponent("spaces.json")
        let iCloudSpaces = iCloudRoot.appendingPathComponent("spaces.json")

        guard FileManager.default.fileExists(atPath: localSpaces.path) else { return }
        let localData = try Data(contentsOf: localSpaces)

        let localFile: SidecarSpacesFile?
        if let decoded = try? decoder.decode(SidecarSpacesFile.self, from: localData) {
            localFile = decoded
        } else if let legacySpaces = try? decoder.decode([SidecarSpace].self, from: localData) {
            localFile = SidecarSpacesFile(spaces: legacySpaces, allSpaceGuidance: nil, useAllSpaceGuidance: false)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let localFile else { throw CocoaError(.fileReadCorruptFile) }

        // If no iCloud spaces file, just copy local
        guard !FileManager.default.fileExists(atPath: iCloudRoot.appendingPathComponent(".spaces.json.icloud").path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        guard FileManager.default.fileExists(atPath: iCloudSpaces.path) else {
            try localData.write(to: iCloudSpaces, options: .atomic)
            return
        }
        let iCloudData = try Data(contentsOf: iCloudSpaces)

        // Merge: union by ID, prefer iCloud version for conflicts
        let iCloudFile: SidecarSpacesFile?
        if let decoded = try? decoder.decode(SidecarSpacesFile.self, from: iCloudData) {
            iCloudFile = decoded
        } else if let legacySpaces = try? decoder.decode([SidecarSpace].self, from: iCloudData) {
            iCloudFile = SidecarSpacesFile(spaces: legacySpaces, allSpaceGuidance: nil, useAllSpaceGuidance: false)
        } else {
            iCloudFile = nil
        }

        guard let iCloudFile else { throw CocoaError(.fileReadCorruptFile) }

        var mergedById: [String: SidecarSpace] = [:]
        // Add local spaces first
        for space in localFile.spaces {
            mergedById[space.id] = space
        }
        // iCloud spaces override (preferred for conflicts)
        for space in iCloudFile.spaces {
            mergedById[space.id] = space
        }

        let mergedSpaces = Array(mergedById.values).sorted { $0.order < $1.order }
        let merged = SidecarSpacesFile(
            spaces: mergedSpaces,
            allSpaceGuidance: iCloudFile.allSpaceGuidance ?? localFile.allSpaceGuidance,
            useAllSpaceGuidance: iCloudFile.useAllSpaceGuidance
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(merged).write(to: iCloudSpaces, options: .atomic)
    }

    // MARK: - Cleanup

    private static func cleanupLocalStorage(_ localRoot: URL, jsonFiles: [URL]) {
        let fm = FileManager.default
        for json in jsonFiles {
            let id = json.deletingPathExtension().lastPathComponent
            let ext = mediaExtension(for: json)
            for url in [json, localRoot.appendingPathComponent("images/\(id).\(ext)"),
                        localRoot.appendingPathComponent("thumbnails/\(id).jpg")] {
                try? fm.removeItem(at: url)
            }
        }
        try? fm.removeItem(at: localRoot.appendingPathComponent("spaces.json"))
        // Removing a directory recursively here could delete a concurrent import.
    }

    // MARK: - Helpers

    private static func mediaExtension(for sidecarURL: URL) -> String {
        guard let data = try? Data(contentsOf: sidecarURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return "png"
        }
        return type == "video" ? "mp4" : "png"
    }
}
