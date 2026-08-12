import Foundation
import SwiftData
import Testing
@testable import Snapwell

@Suite(.tags(.integration, .sync))
struct SyncWatcherPlaceholderTests {
    @Test("A sidecar seen before its media is retried")
    @MainActor func sidecarBeforeMediaIsRetried() async throws {
        let fixture = try Fixture(isUsingiCloud: false)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "late-media"),
            to: fixture.root
        )

        await fixture.watcher.initialSync(context: fixture.context)
        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).isEmpty)

        try IntegrationTestSupport.createDummyMedia(id: "late-media", in: fixture.root)
        await fixture.watcher.initialSync(context: fixture.context)

        let items = try fixture.context.fetch(FetchDescriptor<MediaItem>())
        #expect(items.map(\.id) == ["late-media"])
    }

    @Test("A media placeholder imports immediately and requests canonical media")
    @MainActor func mediaPlaceholderStillImports() async throws {
        let fixture = try Fixture(isUsingiCloud: true)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "media-placeholder"),
            to: fixture.root
        )
        try IntegrationTestSupport.writeMediaPlaceholder(
            id: "media-placeholder",
            ext: "png",
            to: fixture.root
        )

        await fixture.watcher.initialSync(context: fixture.context)

        let item = try #require(try fixture.context.fetch(FetchDescriptor<MediaItem>()).first)
        #expect(item.filename == "media-placeholder.png")
        #expect(fixture.spy.requestedURLs.contains(
            fixture.storage.mediaDir.appendingPathComponent("media-placeholder.png").standardizedFileURL
        ))
    }

    @Test("A sidecar placeholder stays pending until it materializes")
    @MainActor func sidecarPlaceholderIsNotMarkedKnown() async throws {
        let fixture = try Fixture(isUsingiCloud: true)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarPlaceholder(id: "sidecar-placeholder", to: fixture.root)

        await fixture.watcher.initialSync(context: fixture.context)
        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).isEmpty)
        #expect(fixture.spy.requestedURLs.contains(
            fixture.storage.metadataDir.appendingPathComponent("sidecar-placeholder.json").standardizedFileURL
        ))

        try FileManager.default.removeItem(
            at: fixture.storage.metadataDir.appendingPathComponent(".sidecar-placeholder.json.icloud")
        )
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "sidecar-placeholder"),
            to: fixture.root
        )
        try IntegrationTestSupport.createDummyMedia(id: "sidecar-placeholder", in: fixture.root)
        await fixture.watcher.initialSync(context: fixture.context)

        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).count == 1)
    }

    @Test(
        "Media extension is resolved from disk",
        arguments: ["heic", "webp", "gif", "m4v", "mov"]
    )
    @MainActor func mediaExtensionResolvedFromDisk(ext: String) async throws {
        let fixture = try Fixture(isUsingiCloud: false)
        defer { fixture.cleanup() }
        let id = "extension-\(ext)"
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: id, type: ["m4v", "mov"].contains(ext) ? "video" : "image"),
            to: fixture.root
        )
        try IntegrationTestSupport.createDummyMedia(id: id, ext: ext, in: fixture.root)

        await fixture.watcher.initialSync(context: fixture.context)

        let item = try #require(try fixture.context.fetch(FetchDescriptor<MediaItem>()).first)
        #expect(item.filename == "\(id).\(ext)")
    }

    @Test("resyncFromDisk imports newly arrived spaces")
    @MainActor func resyncPicksUpNewSpace() async throws {
        let fixture = try Fixture(isUsingiCloud: false)
        defer { fixture.cleanup() }
        await fixture.watcher.initialSync(context: fixture.context)

        let spaces = SidecarSpacesFile(
            spaces: [SidecarSpace(
                id: "late-space",
                name: "Late Space",
                order: 0,
                createdAt: .now,
                customPrompt: nil,
                useCustomPrompt: false
            )],
            allSpaceGuidance: nil,
            useAllSpaceGuidance: false
        )
        try IntegrationTestSupport.writeSpacesJSON(spaces, to: fixture.root)

        await fixture.watcher.resyncFromDisk()

        #expect(try fixture.context.fetch(FetchDescriptor<Space>()).map(\.id) == ["late-space"])
    }

    @Test("A spaces placeholder preserves existing spaces and requests the index")
    @MainActor func spacesPlaceholderDoesNotDeleteExistingSpaces() async throws {
        let fixture = try Fixture(isUsingiCloud: true)
        defer { fixture.cleanup() }
        fixture.context.insert(Space(id: "existing-space", name: "Existing", order: 0))
        fixture.context.saveOrLog()
        try Data().write(to: fixture.root.appendingPathComponent(".spaces.json.icloud"))

        await fixture.watcher.initialSync(context: fixture.context)

        #expect(try fixture.context.fetch(FetchDescriptor<Space>()).map(\.id) == ["existing-space"])
        #expect(fixture.spy.requestedURLs.contains(
            fixture.root.appendingPathComponent("spaces.json").standardizedFileURL
        ))
    }

    @Test("endLocalChange does not mark pending sidecars as known")
    @MainActor func endLocalChangeDoesNotSwallowPendingIds() async throws {
        let fixture = try Fixture(isUsingiCloud: false)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "pending-local-change"),
            to: fixture.root
        )
        await fixture.watcher.initialSync(context: fixture.context)

        fixture.watcher.beginLocalChange()
        fixture.watcher.endLocalChange()
        try IntegrationTestSupport.createDummyMedia(id: "pending-local-change", in: fixture.root)
        await fixture.watcher.initialSync(context: fixture.context)

        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).count == 1)
    }

    @Test("Local mode ignores files that merely look like iCloud placeholders")
    @MainActor func localModeIgnoresICloudLookingFiles() async throws {
        let fixture = try Fixture(isUsingiCloud: false)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarPlaceholder(id: "stray", to: fixture.root)

        await fixture.watcher.initialSync(context: fixture.context)

        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).isEmpty)
        #expect(fixture.spy.requestedURLs.isEmpty)
    }

    @Test("An item trashed on another device is removed on next launch")
    @MainActor func remoteTrashIsRemovedOnLaunch() async throws {
        let fixture = try Fixture(isUsingiCloud: true)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "deleted-elsewhere"),
            to: fixture.root
        )
        try IntegrationTestSupport.createDummyMedia(id: "deleted-elsewhere", in: fixture.root)
        await fixture.watcher.initialSync(context: fixture.context)
        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).count == 1)

        // iOS moves deletions into the shared .trash/, which syncs down to the Mac.
        try IntegrationTestSupport.trashItem(id: "deleted-elsewhere", in: fixture.root)

        // A fresh launch: knownSidecarIds is empty, so only a SwiftData diff can catch this.
        await fixture.watcher.initialSync(context: fixture.context)

        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).isEmpty)
    }

    @Test("A hard delete on another device is removed on resync")
    @MainActor func remoteHardDeleteIsRemovedOnResync() async throws {
        let fixture = try Fixture(isUsingiCloud: true)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "hard-deleted"),
            to: fixture.root
        )
        try IntegrationTestSupport.createDummyMedia(id: "hard-deleted", in: fixture.root)
        await fixture.watcher.initialSync(context: fixture.context)

        try FileManager.default.removeItem(
            at: fixture.storage.metadataDir.appendingPathComponent("hard-deleted.json")
        )
        await fixture.watcher.resyncFromDisk()

        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).isEmpty)
    }

    @Test("A still-downloading sidecar placeholder protects its record")
    @MainActor func pendingSidecarDoesNotDeleteItsRecord() async throws {
        let fixture = try Fixture(isUsingiCloud: true)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "evicted-later"),
            to: fixture.root
        )
        try IntegrationTestSupport.createDummyMedia(id: "evicted-later", in: fixture.root)
        await fixture.watcher.initialSync(context: fixture.context)

        // The sidecar gets evicted to a placeholder — present, just not downloaded.
        try FileManager.default.removeItem(
            at: fixture.storage.metadataDir.appendingPathComponent("evicted-later.json")
        )
        try IntegrationTestSupport.writeSidecarPlaceholder(id: "evicted-later", to: fixture.root)
        await fixture.watcher.resyncFromDisk()

        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).count == 1)
    }

    @Test("An unreadable metadata directory never wipes the library")
    @MainActor func unreadableMetadataDirDoesNotDeleteEverything() async throws {
        let fixture = try Fixture(isUsingiCloud: true)
        defer { fixture.cleanup() }
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "survivor"),
            to: fixture.root
        )
        try IntegrationTestSupport.createDummyMedia(id: "survivor", in: fixture.root)
        await fixture.watcher.initialSync(context: fixture.context)

        try FileManager.default.removeItem(at: fixture.storage.metadataDir)
        await fixture.watcher.resyncFromDisk()

        #expect(try fixture.context.fetch(FetchDescriptor<MediaItem>()).count == 1)
    }

    @Test("Download requests respect the per-URL cooldown")
    func downloadRequestsRespectCooldown() {
        let recorder = SpyDownloadRequester()
        let requester = DownloadRequester(request: recorder.requestDownload)
        let url = URL(fileURLWithPath: "/tmp/SnapwellTests/pending.json")

        requester.requestDownload(for: url)
        requester.requestDownload(for: url)
        requester.requestDownload(for: url)

        #expect(recorder.requestedURLs == [url.standardizedFileURL])
    }
}

@MainActor
private struct Fixture {
    let root: URL
    let storage: MediaStorageService
    let context: ModelContext
    let watcher: SyncWatcher
    let spy: SpyDownloadRequester

    init(isUsingiCloud: Bool) throws {
        root = try IntegrationTestSupport.makeTempRoot()
        storage = MediaStorageService(baseURL: root, isUsingiCloud: isUsingiCloud)
        let sidecarService = MetadataSidecarService(storage: storage)
        context = ModelContext(try TestContainer.create())
        spy = SpyDownloadRequester()
        watcher = SyncWatcher(
            storage: storage,
            sidecarService: sidecarService,
            downloadRequester: spy
        )
    }

    func cleanup() {
        watcher.stopWatching()
        IntegrationTestSupport.cleanup(root)
    }
}
