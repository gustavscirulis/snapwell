import Testing
import SwiftData
import Foundation
@testable import Snapwell

/// Integration tests for iOS SidecarWriteService merge-in-place logic.
/// Verifies that writing one field (space membership or analysis) doesn't clobber other fields.
@Suite(.tags(.integration, .filesystem))
struct SidecarWriteServiceIntegrationTests {
    let tempRoot: URL
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        tempRoot = try IntegrationTestSupport.makeTempRoot()
        container = try TestContainer.create()
        context = ModelContext(container)
    }


    // MARK: - Space Membership Merge

    @Test("writeSpaceMembership merges into existing sidecar without losing analysis")
    @MainActor func writeSpaceMembershipMergesIntoExistingSidecar() throws {
        // Write a sidecar with analysis fields
        let sidecar = IntegrationTestSupport.makeSidecar(
            id: "merge-1",
            imageContext: "Dashboard with charts",
            imageSummary: "Dashboard",
            patterns: [SidecarPattern(name: "chart", confidence: 0.9)],
            analyzedAt: Date()
        )
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)

        // Create MediaItem with multiple spaces
        let primarySpace = Space(id: "sp-merge", name: "Dashboards", order: 0)
        let secondarySpace = Space(id: "sp-keep", name: "Review", order: 1)
        context.insert(primarySpace)
        context.insert(secondarySpace)
        let item = MediaItem(id: "merge-1", mediaType: .image, filename: "merge-1.png", width: 800, height: 600)
        item.addSpace(primarySpace)
        item.addSpace(secondarySpace)
        context.insert(item)
        context.saveOrLog()

        // Write memberships — should merge, not clobber
        SidecarWriteService.writeSpaceMembership(for: item, rootURL: tempRoot)

        // Read the raw JSON and verify both fields exist
        let url = tempRoot.appendingPathComponent("metadata/merge-1.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["spaceIds"] as? [String] == ["sp-merge", "sp-keep"])
        #expect(json["spaceId"] == nil)
        #expect(json["imageContext"] as? String == "Dashboard with charts")
        #expect((json["patterns"] as? [[String: Any]])?.count == 1)
    }

    @Test("writeSpaceMembership removes both space keys when item has no spaces")
    @MainActor func writeSpaceMembershipRemovesKeysWhenEmpty() throws {
        // Write a legacy sidecar with spaceId
        let sidecar = IntegrationTestSupport.makeSidecar(id: "remove-space-1", spaceId: "sp-old")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)

        // Create MediaItem with NO space
        let item = MediaItem(id: "remove-space-1", mediaType: .image, filename: "remove-space-1.png", width: 800, height: 600)
        context.insert(item)
        context.saveOrLog()

        SidecarWriteService.writeSpaceMembership(for: item, rootURL: tempRoot)

        let url = tempRoot.appendingPathComponent("metadata/remove-space-1.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Keys should be absent, not null
        #expect(json["spaceId"] == nil)
        #expect(json["spaceIds"] == nil)
    }

    // MARK: - Analysis Merge

    @Test("writeAnalysis merges into existing sidecar without losing spaceIds")
    @MainActor func writeAnalysisMergesIntoExistingSidecar() throws {
        // Write a sidecar with canonical spaceIds
        let sidecar = IntegrationTestSupport.makeSidecar(id: "analysis-merge-1", spaceIds: ["sp-keep", "sp-also"])
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: tempRoot)

        // Create MediaItem with analysis
        let item = MediaItem(id: "analysis-merge-1", mediaType: .image, filename: "analysis-merge-1.png", width: 800, height: 600)
        item.analysisResult = AnalysisResult(
            imageContext: "New analysis",
            imageSummary: "Summary",
            patterns: [PatternTag(name: "pattern", confidence: 0.8)],
            analyzedAt: Date(),
            provider: "openai",
            model: "gpt-4o"
        )
        context.insert(item)
        context.saveOrLog()

        SidecarWriteService.writeAnalysis(for: item, rootURL: tempRoot)

        let url = tempRoot.appendingPathComponent("metadata/analysis-merge-1.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Both fields preserved
        #expect(json["spaceIds"] as? [String] == ["sp-keep", "sp-also"])
        #expect(json["spaceId"] == nil)
        #expect(json["imageContext"] as? String == "New analysis")
        #expect(json["analyzedAt"] != nil)
    }

    @Test("writeAnalysis falls back to full sidecar when file doesn't exist")
    @MainActor func writeAnalysisFallsBackWhenNoFileExists() throws {
        let item = MediaItem(id: "fallback-1", mediaType: .image, filename: "fallback-1.png", width: 1024, height: 768)
        item.analysisResult = AnalysisResult(
            imageContext: "Fallback analysis",
            imageSummary: "Fallback summary",
            patterns: [],
            analyzedAt: Date(),
            provider: "anthropic",
            model: "claude-3"
        )
        context.insert(item)
        context.saveOrLog()

        // No existing sidecar on disk
        SidecarWriteService.writeAnalysis(for: item, rootURL: tempRoot)

        // Complete sidecar should exist now
        let url = tempRoot.appendingPathComponent("metadata/fallback-1.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SidecarMetadata.self, from: data)

        #expect(decoded.id == "fallback-1")
        #expect(decoded.width == 1024)
        #expect(decoded.height == 768)
        #expect(decoded.imageContext == "Fallback analysis")
    }

    @Test("Pending placeholder edit survives reload and preserves remote fields")
    @MainActor func placeholderEditMergesAfterDownload() throws {
        let id = UUID().uuidString
        let url = tempRoot.appendingPathComponent("metadata/\(id).json")
        let placeholder = ICloudFile.placeholderURL(for: url)
        try Data().write(to: placeholder)

        let item = MediaItem(id: id, mediaType: .image, filename: "\(id).png", width: 10, height: 10)
        item.analysisResult = AnalysisResult(
            imageContext: "New analysis", imageSummary: "New summary", patterns: [],
            analyzedAt: Date(), provider: "test", model: "test"
        )
        context.insert(item)
        SidecarWriteService.writeAnalysis(for: item, rootURL: tempRoot)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(SidecarWriteService.hasPendingItemEdit(id: id, rootURL: tempRoot))

        try FileManager.default.removeItem(at: placeholder)
        let remote = SidecarMetadata(
            id: id, type: "image", width: 10, height: 10, createdAt: Date(), duration: nil,
            spaceIds: ["remote-space"], imageContext: "Old analysis", imageSummary: "Old summary",
            patterns: nil, sourceURL: "https://example.com/original", analyzedAt: Date.distantPast
        )
        try IntegrationTestSupport.writeSidecarJSON(remote, to: tempRoot)
        SidecarWriteService.reloadPendingFromDisk()
        SidecarWriteService.flushPending(rootURL: tempRoot)

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let merged = try decoder.decode(SidecarMetadata.self, from: data)
        #expect(merged.imageContext == "New analysis")
        #expect(merged.spaceIds == ["remote-space"])
        #expect(merged.sourceURL == "https://example.com/original")
        #expect(!SidecarWriteService.hasPendingItemEdit(id: id, rootURL: tempRoot))
    }

    @Test("Pending space edit merges with a downloaded remote space")
    @MainActor func placeholderSpaceMerge() throws {
        let url = tempRoot.appendingPathComponent("spaces.json")
        let placeholder = ICloudFile.placeholderURL(for: url)
        try Data().write(to: placeholder)
        let local = Space(id: "local-\(UUID().uuidString)", name: "Local", order: 1)
        context.insert(local)
        SidecarWriteService.upsertSpace(local, rootURL: tempRoot)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.removeItem(at: placeholder)
        let remote = SidecarSpace(
            id: "remote", name: "Remote", order: 0, createdAt: Date(),
            customPrompt: nil, useCustomPrompt: false
        )
        let file = SidecarSpacesFile(spaces: [remote], allSpaceGuidance: "Keep", useAllSpaceGuidance: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var raw = try #require(JSONSerialization.jsonObject(with: encoder.encode(file)) as? [String: Any])
        raw["futureSetting"] = "untouched"
        var remoteSpaces = try #require(raw["spaces"] as? [[String: Any]])
        remoteSpaces[0]["futureSpaceField"] = "also untouched"
        raw["spaces"] = remoteSpaces
        try JSONSerialization.data(withJSONObject: raw).write(to: url)
        SidecarWriteService.flushPending(rootURL: tempRoot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let merged = try decoder.decode(SidecarSpacesFile.self, from: Data(contentsOf: url))
        #expect(Set(merged.spaces.map(\.id)) == Set(["remote", local.id]))
        #expect(merged.allSpaceGuidance == "Keep")
        let mergedRaw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(mergedRaw["futureSetting"] as? String == "untouched")
        let mergedSpaces = try #require(mergedRaw["spaces"] as? [[String: Any]])
        #expect(mergedSpaces.first { $0["id"] as? String == "remote" }?["futureSpaceField"] as? String == "also untouched")
    }

    // MARK: - Roundtrip

    @Test("ImageImportService files can be synced back by SyncService")
    @MainActor func importThenSyncRoundtrip() async throws {
        // Import using ImageImportService (writes to disk)
        let image = createTestUIImage(width: 100, height: 50)
        let result = await ImageImportService.importImages([image], to: tempRoot)
        #expect(result.successCount == 1)

        // Now sync those files into SwiftData
        let service = SyncService()
        await service.sync(rootURL: tempRoot, context: context)

        let items = try context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.mediaType == .image)
        #expect(item.width > 0)
        #expect(item.height > 0)
    }

    // MARK: - Helpers

    private func createTestUIImage(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
