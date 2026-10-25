import Foundation
import SwiftData
import Testing
@testable import Snapwell

@Suite("Persistent library", .tags(.integration, .model))
@MainActor
struct PersistenceIntegrationTests {
    @Test("A new container reloads media, analysis, spaces and guidance from disk")
    func reopenLibrary() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        try withContext(at: url) { context in
            let item = MediaItem(id: "saved", mediaType: .video, filename: "saved.mp4", width: 1920, height: 1080, duration: 4.5)
            item.sourceURL = "https://example.com/shared"
            let space = Space(id: "work", name: "Work", order: 2)
            space.customPrompt = "Find navigation"
            space.useCustomPrompt = true
            space.hideFromAllMedia = true
            let analysis = AnalysisResult(imageContext: "A toolbar", imageSummary: "Toolbar", patterns: [PatternTag(name: "Button", confidence: 0.95)], provider: "openai", model: "test-model")
            context.insert(item)
            context.insert(space)
            context.insert(analysis)
            item.spaces = [space]
            item.analysisResult = analysis
            try context.save()
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        try withContext(at: url) { context in
            let items = try context.fetch(FetchDescriptor<MediaItem>())
            #expect(items.count == 1)
            let item = try #require(items.first)
            #expect(item.id == "saved")
            #expect(item.filename == "saved.mp4")
            #expect(item.mediaType == .video)
            #expect(item.duration == 4.5)
            #expect(item.width == 1920 && item.height == 1080)
            #expect(item.sourceURL == "https://example.com/shared")
            #expect(item.analysisResult?.imageContext == "A toolbar")
            #expect(item.analysisResult?.provider == "openai")
            #expect(item.analysisResult?.model == "test-model")
            #expect(item.analysisResult?.patterns == [PatternTag(name: "Button", confidence: 0.95)])
            let space = try #require(item.spaces.first)
            #expect(space.id == "work")
            #expect(space.name == "Work" && space.order == 2)
            #expect(space.useCustomPrompt && space.hideFromAllMedia)
            #expect(space.customPrompt == "Find navigation")
            #expect(space.items.map(\.id) == ["saved"])
        }
    }

    @Test("Deleting persisted media cascades analysis and keeps its space after reopening")
    func durableCascadeDelete() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        try seed(at: url)
        try withContext(at: url) { context in
            let item = try #require(try context.fetch(FetchDescriptor<MediaItem>()).first)
            context.delete(item)
            try context.save()
        }
        try withContext(at: url) { context in
            #expect(try context.fetchCount(FetchDescriptor<MediaItem>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<AnalysisResult>()) == 0)
            let space = try #require(try context.fetch(FetchDescriptor<Space>()).first)
            #expect(space.items.isEmpty)
        }
    }

    @Test("Deleting a persisted space preserves media and analysis after reopening")
    func durableSpaceDelete() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        try seed(at: url)
        try withContext(at: url) { context in
            let space = try #require(try context.fetch(FetchDescriptor<Space>()).first)
            context.delete(space)
            try context.save()
        }
        try withContext(at: url) { context in
            #expect(try context.fetchCount(FetchDescriptor<Space>()) == 0)
            let item = try #require(try context.fetch(FetchDescriptor<MediaItem>()).first)
            #expect(item.spaces.isEmpty)
            #expect(item.analysisResult?.imageSummary == "Saved")
        }
    }

    @Test("Uncommitted edits do not replace saved library data after reopening")
    func uncommittedEditsThenReopen() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        try seed(at: url)
        try withContext(at: url) { context in
            let item = try #require(try context.fetch(FetchDescriptor<MediaItem>()).first)
            item.filename = "unsaved.png"
            let unsaved = MediaItem(id: "unsaved", mediaType: .image, filename: "new.png", width: 1, height: 1)
            context.insert(unsaved)
        }
        try withContext(at: url) { context in
            let item = try #require(try context.fetch(FetchDescriptor<MediaItem>()).first)
            #expect(try context.fetchCount(FetchDescriptor<MediaItem>()) == 1)
            #expect(item.filename == "saved.png")
            #expect(item.analysisResult?.imageSummary == "Saved")
            #expect(item.spaces.map(\.id) == ["work"])
        }
    }

    @Test("Recovery after reopening clears interrupted analysis and preserves live work and saved results")
    func interruptedAnalysisRecovery() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.store")
        try seed(at: url)
        try withContext(at: url) { context in
            let item = try #require(try context.fetch(FetchDescriptor<MediaItem>()).first)
            item.isAnalyzing = true
            item.analysisError = "Previous failure"
            let active = MediaItem(id: "active", mediaType: .image, filename: "active.png", width: 1, height: 1)
            active.isAnalyzing = true
            context.insert(active)
            try context.save()
        }
        try withContext(at: url) { context in
            #expect(try AnalysisRecovery.clearStaleFlags(in: context, ownedIDs: ["active"]) == 1)
            #expect(try AnalysisRecovery.clearStaleFlags(in: context, ownedIDs: ["active"]) == 0)
            try context.save()
        }
        try withContext(at: url) { context in
            let items = try context.fetch(FetchDescriptor<MediaItem>())
            let saved = try #require(items.first(where: { $0.id == "saved" }))
            let active = try #require(items.first(where: { $0.id == "active" }))
            #expect(!saved.isAnalyzing)
            #expect(saved.analysisError == "Previous failure")
            #expect(saved.analysisResult?.imageSummary == "Saved")
            #expect(active.isAnalyzing)
            #expect(try AnalysisRecovery.clearStaleFlags(in: context) == 1)
            try context.save()
        }
        try withContext(at: url) { context in
            let items = try context.fetch(FetchDescriptor<MediaItem>())
            #expect(items.allSatisfy { !$0.isAnalyzing })
        }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapwellPersistenceTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func withContext(at url: URL, body: (ModelContext) throws -> Void) throws {
        try autoreleasepool {
            let schema = Schema([MediaItem.self, Space.self, AnalysisResult.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try body(context)
        }
    }

    private func seed(at url: URL) throws {
        try withContext(at: url) { context in
            let item = MediaItem(id: "saved", mediaType: .image, filename: "saved.png", width: 10, height: 10)
            let space = Space(id: "work", name: "Work", order: 0)
            let analysis = AnalysisResult(imageContext: "Saved context", imageSummary: "Saved", patterns: [], provider: "test", model: "test")
            context.insert(item)
            context.insert(space)
            context.insert(analysis)
            item.spaces = [space]
            item.analysisResult = analysis
            try context.save()
        }
    }
}
