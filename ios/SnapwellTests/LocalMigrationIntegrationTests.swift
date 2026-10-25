import Foundation
import Testing
@testable import Snapwell

@Suite("Local to cloud migration", .tags(.integration, .filesystem))
struct LocalMigrationIntegrationTests {
    private let migrationKey = "localToiCloudMigrationComplete_v1"

    @Test("Image and video migrations copy all files before removing their local source", arguments: ["image", "video"])
    func successfulMigration(type: String) async throws {
        try await withRoots { local, cloud, defaults in
            let ext = type == "video" ? "mp4" : "png"
            let json = sidecar(type: type)
            try stage(local, json: json, ext: ext)
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(try Data(contentsOf: cloud.appendingPathComponent("images/item.\(ext)")) == Data([1, 2, 3]))
            #expect(try Data(contentsOf: cloud.appendingPathComponent("metadata/item.json")) == json)
            #expect(try Data(contentsOf: cloud.appendingPathComponent("thumbnails/item.jpg")) == Data([4, 5]))
            #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("metadata/item.json").path))
            #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("images/item.\(ext)").path))
            #expect(defaults.bool(forKey: migrationKey))
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(try Data(contentsOf: cloud.appendingPathComponent("metadata/item.json")) == json)
        }
    }

    @Test("A blocked destination preserves local data and retries after repair")
    func destinationFailure() async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar())
            let blocked = cloud.appendingPathComponent("images")
            try FileManager.default.removeItem(at: blocked)
            try Data([9]).write(to: blocked)
            let completed = await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(!completed)
            #expect(!defaults.bool(forKey: migrationKey))
            #expect(try Data(contentsOf: local.appendingPathComponent("images/item.png")) == Data([1, 2, 3]))
            #expect(try Data(contentsOf: local.appendingPathComponent("metadata/item.json")) == sidecar())
            try FileManager.default.removeItem(at: blocked)
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(defaults.bool(forKey: migrationKey))
            #expect(try Data(contentsOf: cloud.appendingPathComponent("images/item.png")) == Data([1, 2, 3]))
        }
    }

    @Test("A sidecar without recoverable media is retained for retry")
    func missingMedia() async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar())
            try FileManager.default.removeItem(at: local.appendingPathComponent("images/item.png"))
            let completed = await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(!completed)
            #expect(!defaults.bool(forKey: migrationKey))
            #expect(FileManager.default.fileExists(atPath: local.appendingPathComponent("metadata/item.json").path))
            #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("metadata/item.json").path))
        }
    }

    @Test("Spaces migrate even when the local media library is empty")
    func spacesOnly() async throws {
        try await withRoots { local, cloud, defaults in
            let data = spaces(name: "Local", guidance: "Local guidance")
            try data.write(to: local.appendingPathComponent("spaces.json"))
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(try Data(contentsOf: cloud.appendingPathComponent("spaces.json")) == data)
            #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("spaces.json").path))
            #expect(defaults.bool(forKey: migrationKey))
        }
    }

    @Test("Spaces merge by ID while retaining cloud names and guidance")
    func spaceConflicts() async throws {
        try await withRoots { local, cloud, defaults in
            try spaces(name: "Local", guidance: "Local guidance", extra: true).write(to: local.appendingPathComponent("spaces.json"))
            try spaces(name: "Cloud", guidance: "Cloud guidance").write(to: cloud.appendingPathComponent("spaces.json"))
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            let data = try Data(contentsOf: cloud.appendingPathComponent("spaces.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(SidecarSpacesFile.self, from: data)
            #expect(file.spaces.count == 2)
            #expect(file.spaces.first(where: { $0.id == "work" })?.name == "Cloud")
            #expect(file.spaces.contains(where: { $0.id == "local-only" }))
            #expect(file.allSpaceGuidance == "Cloud guidance")
            #expect(file.useAllSpaceGuidance)
        }
    }

    @Test("The newest analysis survives duplicate migration", arguments: [true, false])
    func analysisConflict(localIsNewer: Bool) async throws {
        try await withRoots { local, cloud, defaults in
            let localJSON = sidecar(summary: "Local", analyzedAt: localIsNewer ? "2026-10-25T00:00:00Z" : "2026-10-23T00:00:00Z")
            let remoteJSON = sidecar(summary: "Cloud", analyzedAt: "2026-10-24T00:00:00Z")
            try stage(local, json: localJSON)
            try stage(cloud, json: remoteJSON)
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(try Data(contentsOf: cloud.appendingPathComponent("metadata/item.json")) == (localIsNewer ? localJSON : remoteJSON))
            #expect(defaults.bool(forKey: migrationKey))
        }
    }

    @Test("Corrupt metadata or spaces never triggers local cleanup", arguments: ["metadata", "spaces"])
    func corruptInput(kind: String) async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar())
            let broken = kind == "metadata" ? "metadata/item.json" : "spaces.json"
            try Data("not JSON".utf8).write(to: local.appendingPathComponent(broken))
            let completed = await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(!completed)
            #expect(!defaults.bool(forKey: migrationKey))
            #expect(FileManager.default.fileExists(atPath: local.appendingPathComponent("images/item.png").path))
            #expect(FileManager.default.fileExists(atPath: local.appendingPathComponent("metadata/item.json").path))
        }
    }

    @Test("A remote placeholder postpones migration until the real sidecar arrives")
    func remotePlaceholder() async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar())
            let placeholder = cloud.appendingPathComponent("metadata/.item.json.icloud")
            try Data().write(to: placeholder)
            let completed = await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(!completed)
            #expect(!defaults.bool(forKey: migrationKey))
            #expect(FileManager.default.fileExists(atPath: local.appendingPathComponent("images/item.png").path))
            #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("metadata/item.json").path))
            try FileManager.default.removeItem(at: placeholder)
            try stage(cloud, json: sidecar(summary: "Cloud", analyzedAt: "2026-10-25T00:00:00Z"))
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(defaults.bool(forKey: migrationKey))
            #expect(try Data(contentsOf: cloud.appendingPathComponent("metadata/item.json")) == sidecar(summary: "Cloud", analyzedAt: "2026-10-25T00:00:00Z"))
        }
    }

    @Test("Cleanup preserves unrelated media, queued imports and trash")
    func preservesUnrelatedFiles() async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar())
            let names = ["images/unpublished.png", ".trash/deleted.png", "queue/incoming.png"]
            for name in names {
                let url = local.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data([8]).write(to: url)
            }
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            for name in names { #expect(try Data(contentsOf: local.appendingPathComponent(name)) == Data([8])) }
        }
    }

    @Test("A partial earlier migration repairs missing remote media without replacing newer analysis")
    func resumePartialMigration() async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar())
            let remote = sidecar(summary: "Cloud", analyzedAt: "2026-10-25T00:00:00Z")
            try remote.write(to: cloud.appendingPathComponent("metadata/item.json"))
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(try Data(contentsOf: cloud.appendingPathComponent("images/item.png")) == Data([1, 2, 3]))
            #expect(try Data(contentsOf: cloud.appendingPathComponent("metadata/item.json")) == remote)
            #expect(defaults.bool(forKey: migrationKey))
        }
    }

    @Test("Unreadable remote metadata preserves the source instead of marking migration complete")
    func unreadableRemoteSidecar() async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar())
            try FileManager.default.createDirectory(at: cloud.appendingPathComponent("metadata/item.json"), withIntermediateDirectories: true)
            let completed = await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            #expect(!completed)
            #expect(!defaults.bool(forKey: migrationKey))
            #expect(try Data(contentsOf: local.appendingPathComponent("metadata/item.json")) == sidecar())
            #expect(try Data(contentsOf: local.appendingPathComponent("images/item.png")) == Data([1, 2, 3]))
        }
    }

    @Test("Newer local analysis preserves remotely edited memberships and source URL")
    func analysisMergePreservesRemoteFields() async throws {
        try await withRoots { local, cloud, defaults in
            try stage(local, json: sidecar(summary: "Local", analyzedAt: "2026-10-25T00:00:00Z"))
            var remote = try JSONSerialization.jsonObject(with: sidecar(summary: "Cloud", analyzedAt: "2026-10-24T00:00:00Z")) as! [String: Any]
            remote["spaceIds"] = ["remote-space"]
            remote["sourceURL"] = "https://example.com/remote"
            try stage(cloud, json: JSONSerialization.data(withJSONObject: remote))
            await LocalToiCloudMigrationService.migrate(from: local, to: cloud, defaults: defaults)
            let merged = try JSONSerialization.jsonObject(with: Data(contentsOf: cloud.appendingPathComponent("metadata/item.json"))) as! [String: Any]
            #expect(merged["spaceIds"] as? [String] == ["remote-space"])
            #expect(merged["sourceURL"] as? String == "https://example.com/remote")
            #expect(merged["imageSummary"] as? String == "Local")
            #expect(defaults.bool(forKey: migrationKey))
        }
    }

    private func stage(_ root: URL, json: Data, ext: String = "png") throws {
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("images/item.\(ext)"))
        try json.write(to: root.appendingPathComponent("metadata/item.json"))
        try Data([4, 5]).write(to: root.appendingPathComponent("thumbnails/item.jpg"))
    }

    private func sidecar(type: String = "image", summary: String? = nil, analyzedAt: String? = nil) -> Data {
        var object: [String: Any] = ["id": "item", "type": type, "width": 800, "height": 600, "createdAt": "2026-10-23T00:00:00Z"]
        object["imageSummary"] = summary
        object["analyzedAt"] = analyzedAt
        return try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    private func spaces(name: String, guidance: String, extra: Bool = false) -> Data {
        var entries: [[String: Any]] = [["id": "work", "name": name, "order": 0, "createdAt": "2026-10-23T00:00:00Z"]]
        if extra { entries.append(["id": "local-only", "name": "Local only", "order": 1, "createdAt": "2026-10-23T00:00:00Z"]) }
        return try! JSONSerialization.data(withJSONObject: ["spaces": entries, "allSpaceGuidance": guidance, "useAllSpaceGuidance": true], options: .sortedKeys)
    }

    private func withRoots(body: (URL, URL, UserDefaults) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapwellMigrationTests/\(UUID().uuidString)")
        let suite = "SnapwellMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        for base in [local, cloud] {
            for name in ["images", "metadata", "thumbnails"] {
                try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
            }
        }
        try await body(local, cloud, defaults)
    }
}
