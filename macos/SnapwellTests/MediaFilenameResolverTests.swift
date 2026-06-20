import Foundation
import Testing
@testable import Snapwell

/// Tests for `MediaFilenameResolver` (probes the real on-disk extension instead of
/// guessing png/mp4) and `iCloudDownloadManager.ensureDownloaded` (read-safety guard
/// that returns immediately for already-local files).
@Suite("Media filename resolution + iCloud read safety", .tags(.filesystem, .sync))
struct MediaFilenameResolverTests {

    // MARK: - Resolver: real extensions

    @Test("Resolves a non-normalized image extension (heic)")
    func resolvesHeic() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        let id = "img_heic"
        try IntegrationTestSupport.createDummyMedia(id: id, ext: "heic", in: root)

        #expect(MediaFilenameResolver.resolveMediaFilename(id: id, in: images) == "\(id).heic")
        #expect(MediaFilenameResolver.resolveMediaURL(id: id, in: images)?.lastPathComponent == "\(id).heic")
    }

    @Test("Resolves a non-normalized video extension (m4v)")
    func resolvesM4V() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        let id = "vid_m4v"
        try IntegrationTestSupport.createDummyMedia(id: id, ext: "m4v", in: root)

        #expect(MediaFilenameResolver.resolveMediaFilename(
            id: id, in: images, preferredExtensions: ["mp4", "mov"]) == "\(id).m4v")
    }

    @Test("Resolves webm")
    func resolvesWebm() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        let id = "clip_webm"
        try IntegrationTestSupport.createDummyMedia(id: id, ext: "webm", in: root)

        #expect(MediaFilenameResolver.resolveMediaFilename(id: id, in: images) == "\(id).webm")
    }

    @Test("Resolves webp and avi")
    func resolvesWebpAndAvi() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        try IntegrationTestSupport.createDummyMedia(id: "a_webp", ext: "webp", in: root)
        try IntegrationTestSupport.createDummyMedia(id: "b_avi", ext: "avi", in: root)

        #expect(MediaFilenameResolver.resolveMediaFilename(id: "a_webp", in: images) == "a_webp.webp")
        #expect(MediaFilenameResolver.resolveMediaFilename(id: "b_avi", in: images) == "b_avi.avi")
    }

    @Test("Returns nil when no supported file is present")
    func returnsNilWhenMissing() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        #expect(MediaFilenameResolver.resolveMediaFilename(id: "ghost", in: images) == nil)
        #expect(MediaFilenameResolver.resolveMediaURL(id: "ghost", in: images) == nil)
    }

    @Test("Ignores unsupported extensions")
    func ignoresUnsupported() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        let id = "doc"
        let url = images.appendingPathComponent("\(id).txt")
        try IntegrationTestSupport.dummyPNGData.write(to: url, options: .atomic)

        #expect(MediaFilenameResolver.resolveMediaFilename(id: id, in: images) == nil)
    }

    @Test("Preferred extension wins when multiple files share an id")
    func preferredExtensionWins() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        let id = "dup"
        // Both a png and an mp4 exist; with a video-preference we should get mp4 first.
        try IntegrationTestSupport.createDummyMedia(id: id, ext: "png", in: root)
        try IntegrationTestSupport.createDummyMedia(id: id, ext: "mp4", in: root)

        #expect(MediaFilenameResolver.resolveMediaFilename(
            id: id, in: images, preferredExtensions: ["mp4"]) == "\(id).mp4")
        #expect(MediaFilenameResolver.resolveMediaFilename(
            id: id, in: images, preferredExtensions: ["png"]) == "\(id).png")
    }

    @Test("Resolves an iCloud placeholder to the real filename")
    func resolvesICloudPlaceholder() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let images = root.appendingPathComponent("images")

        let id = "evicted"
        // Simulate an evicted file: only the ".{id}.heic.icloud" placeholder exists.
        let placeholder = images.appendingPathComponent(".\(id).heic.icloud")
        try IntegrationTestSupport.dummyPNGData.write(to: placeholder, options: .atomic)

        #expect(MediaFilenameResolver.resolveMediaFilename(id: id, in: images) == "\(id).heic")
    }

    // MARK: - ensureDownloaded: read-safety guard

    @Test("ensureDownloaded returns true immediately for an already-local file")
    func ensureDownloadedLocalFile() async throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }

        let id = "local"
        try IntegrationTestSupport.createDummyMedia(id: id, ext: "png", in: root)
        let url = root.appendingPathComponent("images/\(id).png")

        let start = Date()
        let ok = await iCloudDownloadManager.ensureDownloaded(at: url)
        let elapsed = Date().timeIntervalSince(start)

        #expect(ok == true)
        // Must not block/poll for a file that is already present.
        #expect(elapsed < 0.25)
    }

    @Test("isReadable is true for a local file, false for a missing one")
    func isReadableReflectsPresence() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }

        let id = "present"
        try IntegrationTestSupport.createDummyMedia(id: id, ext: "png", in: root)
        let present = root.appendingPathComponent("images/\(id).png")
        let missing = root.appendingPathComponent("images/nope.png")

        #expect(iCloudDownloadManager.isReadable(present) == true)
        #expect(iCloudDownloadManager.isReadable(missing) == false)
    }

    @Test("ensureDownloaded returns false for a missing non-iCloud file within timeout")
    func ensureDownloadedMissingFile() async throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }

        let url = root.appendingPathComponent("images/missing.png")
        // Short timeout — there is no iCloud item, so it can never become readable.
        let ok = await iCloudDownloadManager.ensureDownloaded(at: url, timeout: 0.5)
        #expect(ok == false)
    }
}
