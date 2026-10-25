import Foundation
import Testing
#if os(iOS)
import SwiftData
#endif
@testable import Snapwell

@Suite("Share handoff", .tags(.integration, .filesystem))
struct ShareHandoffIntegrationTests {
    @Test("Staged image and video reach the library unchanged and import only once", arguments: ["image", "video"])
    func importShare(type: String) throws {
        try withRoots { pending, library in
            let ext = type == "video" ? "mp4" : "png"
            let media = Data("media from extension".utf8)
            let metadata = sidecar(type: type)
            try ShareStagingStore.stage(media: media, sidecar: metadata, id: "shared", mediaExtension: ext, in: pending)
            ShareImportService.importPendingItems(from: pending, to: library)
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(try Data(contentsOf: library.appendingPathComponent("images/shared.\(ext)")) == media)
            #expect(try Data(contentsOf: library.appendingPathComponent("metadata/shared.json")) == metadata)
            #expect(try FileManager.default.contentsOfDirectory(atPath: pending.appendingPathComponent("metadata").path).isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: pending.appendingPathComponent("images").path).isEmpty)
        }
    }

    @Test("A missing source media file leaves the sidecar staged until its media arrives")
    func incompleteShare() throws {
        try withRoots { pending, library in
            let url = pending.appendingPathComponent("metadata/shared.json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sidecar().write(to: url)
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(!FileManager.default.fileExists(atPath: library.appendingPathComponent("metadata/shared.json").path))
            try FileManager.default.createDirectory(at: pending.appendingPathComponent("images"), withIntermediateDirectories: true)
            try Data([1]).write(to: pending.appendingPathComponent("images/shared.png"))
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent("metadata/shared.json").path))
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("A destination failure retains both staged files and a later retry finishes")
    func failedMetadataWriteCanRetry() throws {
        try withRoots { pending, library in
            let media = Data([1, 2, 3])
            try ShareStagingStore.stage(media: media, sidecar: sidecar(), id: "shared", mediaExtension: "png", in: pending)
            let blocked = library.appendingPathComponent("metadata/shared.json")
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(try Data(contentsOf: pending.appendingPathComponent("images/shared.png")) == media)
            #expect(FileManager.default.fileExists(atPath: pending.appendingPathComponent("metadata/shared.json").path))
            try FileManager.default.removeItem(at: blocked)
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(try Data(contentsOf: library.appendingPathComponent("images/shared.png")) == media)
            #expect(try Data(contentsOf: library.appendingPathComponent("metadata/shared.json")) == sidecar())
            #expect(!FileManager.default.fileExists(atPath: pending.appendingPathComponent("metadata/shared.json").path))
        }
    }

    @Test("A conflicting destination image is preserved along with the pending share")
    func conflictingMedia() throws {
        try withRoots { pending, library in
            try ShareStagingStore.stage(media: Data([1]), sidecar: sidecar(), id: "shared", mediaExtension: "png", in: pending)
            let destination = library.appendingPathComponent("images/shared.png")
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([9]).write(to: destination)
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(try Data(contentsOf: destination) == Data([9]))
            #expect(FileManager.default.fileExists(atPath: pending.appendingPathComponent("metadata/shared.json").path))
        }
    }

    @Test("An already imported sidecar keeps analysis added before a duplicate handoff")
    func enrichedSidecar() throws {
        try withRoots { pending, library in
            let media = Data([1])
            try ShareStagingStore.stage(media: media, sidecar: sidecar(), id: "shared", mediaExtension: "png", in: pending)
            let images = library.appendingPathComponent("images")
            let metadata = library.appendingPathComponent("metadata")
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
            let enriched = Data(#"{"id":"shared","type":"image","imageSummary":"Already analyzed"}"#.utf8)
            try media.write(to: images.appendingPathComponent("shared.png"))
            try enriched.write(to: metadata.appendingPathComponent("shared.json"))
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(try Data(contentsOf: metadata.appendingPathComponent("shared.json")) == enriched)
            #expect(!FileManager.default.fileExists(atPath: pending.appendingPathComponent("metadata/shared.json").path))
        }
    }

    @Test("Malformed or mismatched metadata is retained without publishing it", arguments: ["not JSON", #"{"id":"other","type":"image"}"#, #"{"id":"shared","type":"unknown"}"#])
    func invalidMetadata(json: String) throws {
        try withRoots { pending, library in
            try ShareStagingStore.stage(media: Data([1]), sidecar: Data(json.utf8), id: "shared", mediaExtension: "png", in: pending)
            ShareImportService.importPendingItems(from: pending, to: library)
            #expect(!FileManager.default.fileExists(atPath: library.appendingPathComponent("metadata/shared.json").path))
            #expect(FileManager.default.fileExists(atPath: pending.appendingPathComponent("metadata/shared.json").path))
        }
    }

    #if os(iOS)
    @Test("Share extension handoff syncs source URL and dimensions into SwiftData")
    @MainActor func handoffThenSync() async throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let pending = root.appendingPathComponent("pending")
        try ShareStagingStore.stage(media: IntegrationTestSupport.dummyPNGData, sidecar: sidecar(), id: "shared", mediaExtension: "png", in: pending)
        ShareImportService.importPendingItems(from: pending, to: root)
        let container = try TestContainer.create()
        let context = ModelContext(container)
        await SyncService().sync(rootURL: root, context: context)
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == "shared")
        #expect(item.width == 800 && item.height == 600)
        #expect(item.sourceURL == "https://example.com/shared")
        #expect(item.analysisResult == nil)
    }
    #endif

    private func sidecar(type: String = "image") -> Data {
        Data("""
        {"id":"shared","type":"\(type)","width":800,"height":600,"createdAt":"2026-10-25T00:00:00Z","sourceURL":"https://example.com/shared"}
        """.utf8)
    }

    private func withRoots(body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapwellShareHandoffTests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("pending"), root.appendingPathComponent("library"))
    }
}
