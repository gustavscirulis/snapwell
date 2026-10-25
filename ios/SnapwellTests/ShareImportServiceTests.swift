import Testing
import Foundation
@testable import Snapwell

@Suite("ShareImportService", .tags(.filesystem))
struct ShareImportServiceTests {

    @Test("Shared media is published intact and staging is retired", arguments: ["image", "video"])
    func publishesSharedMedia(type: String) throws {
        let fixture = try ImportFixture(type: type)
        defer { fixture.cleanup() }

        fixture.run()

        #expect(try Data(contentsOf: fixture.destinationMedia) == fixture.media)
        #expect(try Data(contentsOf: fixture.destinationMetadata) == fixture.metadata)
        #expect(!FileManager.default.fileExists(atPath: fixture.stagedMedia.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.stagedMetadata.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.appendingPathComponent("images").path) == [fixture.destinationMedia.lastPathComponent])

        fixture.run()
        #expect(try Data(contentsOf: fixture.destinationMedia) == fixture.media)
        #expect(try Data(contentsOf: fixture.destinationMetadata) == fixture.metadata)
    }

    @Test("A partial import with published media can finish without its staged media")
    func resumesAfterMediaMoved() throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        try FileManager.default.moveItem(at: fixture.stagedMedia, to: fixture.destinationMedia)

        fixture.run()

        #expect(try Data(contentsOf: fixture.destinationMedia) == fixture.media)
        #expect(try Data(contentsOf: fixture.destinationMetadata) == fixture.metadata)
        #expect(!FileManager.default.fileExists(atPath: fixture.stagedMetadata.path))
    }

    @Test("A metadata failure retains staging and succeeds on retry")
    func retriesMetadataFailure() throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let fm = FileManager.default
        try fm.createDirectory(at: fixture.destinationMetadata, withIntermediateDirectories: false)

        fixture.run()

        #expect(try Data(contentsOf: fixture.destinationMedia) == fixture.media)
        #expect(try Data(contentsOf: fixture.stagedMedia) == fixture.media)
        #expect(try Data(contentsOf: fixture.stagedMetadata) == fixture.metadata)

        try fm.removeItem(at: fixture.destinationMetadata)
        fixture.run()

        #expect(try Data(contentsOf: fixture.destinationMetadata) == fixture.metadata)
        #expect(!fm.fileExists(atPath: fixture.stagedMedia.path))
        #expect(!fm.fileExists(atPath: fixture.stagedMetadata.path))
    }

    @Test("Retry preserves published analysis and memberships", arguments: [true, false])
    func preservesPublishedMetadata(stagedMediaExists: Bool) throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let updated = Data("""
        {"id":"shared-item","type":"image","imageContext":"New analysis","spaceIds":["new-space"]}
        """.utf8)
        try fixture.media.write(to: fixture.destinationMedia)
        try updated.write(to: fixture.destinationMetadata)
        if !stagedMediaExists { try FileManager.default.removeItem(at: fixture.stagedMedia) }

        fixture.run()

        #expect(try Data(contentsOf: fixture.destinationMetadata) == updated)
        #expect(try Data(contentsOf: fixture.destinationMedia) == fixture.media)
        #expect(!FileManager.default.fileExists(atPath: fixture.stagedMetadata.path))
    }

    @Test("Missing media keeps the import pending")
    func missingMediaRemainsPending() throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.stagedMedia)

        fixture.run()

        #expect(try Data(contentsOf: fixture.stagedMetadata) == fixture.metadata)
        #expect(!FileManager.default.fileExists(atPath: fixture.destinationMetadata.path))
    }

    @Test("Evicted destination files are preserved for a later retry", arguments: ["images/shared-item.png", "metadata/shared-item.json"])
    func waitsForDestinationPlaceholder(path: String) throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let placeholder = ICloudFile.placeholderURL(for: fixture.rootURL.appendingPathComponent(path))
        try Data().write(to: placeholder)

        fixture.run()

        #expect(FileManager.default.fileExists(atPath: placeholder.path))
        #expect(try Data(contentsOf: fixture.stagedMedia) == fixture.media)
        #expect(try Data(contentsOf: fixture.stagedMetadata) == fixture.metadata)
        #expect(!FileManager.default.fileExists(atPath: fixture.destinationMedia.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.destinationMetadata.path))
    }

    @Test("An interrupted temporary copy is replaced before publication")
    func retriesPartialTemporaryCopy() throws {
        let fixture = try ImportFixture()
        defer { fixture.cleanup() }
        let temporary = fixture.destinationMedia.deletingLastPathComponent().appendingPathComponent(".shared-item.png.importing")
        let temporaryMetadata = fixture.destinationMetadata.deletingLastPathComponent().appendingPathComponent(".shared-item.json.importing")
        try Data("partial".utf8).write(to: temporary)
        try Data("partial".utf8).write(to: temporaryMetadata)

        fixture.run()

        #expect(try Data(contentsOf: fixture.destinationMedia) == fixture.media)
        #expect(try Data(contentsOf: fixture.destinationMetadata) == fixture.metadata)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(!FileManager.default.fileExists(atPath: temporaryMetadata.path))
    }

    // MARK: - mediaExtension

    @Test("Image sidecar returns png extension")
    func imageExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-image.json")
        let json = Data("""
        {"id": "test", "type": "image", "width": 100, "height": 100, "createdAt": "2024-01-01T00:00:00Z"}
        """.utf8)
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == "png")
    }

    @Test("Video sidecar returns mp4 extension")
    func videoExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-video.json")
        let json = Data("""
        {"id": "test", "type": "video", "width": 1280, "height": 720, "createdAt": "2024-01-01T00:00:00Z"}
        """.utf8)
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == "mp4")
    }

    @Test("Invalid JSON returns nil")
    func invalidJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-bad.json")
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == nil)
    }

    @Test("Missing type field returns nil")
    func missingType() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-notype.json")
        let json = Data("""
        {"id": "test", "width": 100, "height": 100}
        """.utf8)
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ShareImportService.mediaExtension(for: url) == nil)
    }

    @Test("Nonexistent file returns nil")
    func nonexistentFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID()).json")
        #expect(ShareImportService.mediaExtension(for: url) == nil)
    }
}

private struct ImportFixture {
    let rootURL: URL
    let pendingURL: URL
    let stagedMedia: URL
    let stagedMetadata: URL
    let destinationMedia: URL
    let destinationMetadata: URL
    let media = Data("original media bytes".utf8)
    let metadata: Data

    init(type: String = "image") throws {
        rootURL = try IntegrationTestSupport.makeTempRoot()
        pendingURL = rootURL.appendingPathComponent("staging")
        let ext = type == "video" ? "mp4" : "png"
        stagedMedia = pendingURL.appendingPathComponent("images/shared-item.\(ext)")
        stagedMetadata = pendingURL.appendingPathComponent("metadata/shared-item.json")
        destinationMedia = rootURL.appendingPathComponent("images/shared-item.\(ext)")
        destinationMetadata = rootURL.appendingPathComponent("metadata/shared-item.json")
        metadata = Data("""
        {"id":"shared-item","type":"\(type)","width":100,"height":100,"createdAt":"2026-10-24T12:00:00Z"}
        """.utf8)
        try FileManager.default.createDirectory(at: stagedMedia.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagedMetadata.deletingLastPathComponent(), withIntermediateDirectories: true)
        try media.write(to: stagedMedia)
        try metadata.write(to: stagedMetadata)
    }

    func run() {
        ShareImportService.importPendingItems(from: pendingURL, to: rootURL)
    }

    func cleanup() {
        IntegrationTestSupport.cleanup(rootURL)
    }
}
