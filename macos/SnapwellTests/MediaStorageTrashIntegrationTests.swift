import Testing
import Foundation
@testable import Snapwell

/// Integration tests for Mac MediaStorageService trash operations.
@Suite(.tags(.integration, .filesystem))
struct MediaStorageTrashIntegrationTests {
    let tempRoot: URL
    let storage: MediaStorageService

    init() throws {
        tempRoot = try IntegrationTestSupport.makeTempRoot()
        storage = MediaStorageService(baseURL: tempRoot)
    }


    @Test("moveToTrash moves image, sidecar, and thumbnail to .trash/")
    func moveToTrashMovesAllThreeFiles() throws {
        try IntegrationTestSupport.createDummyMedia(id: "trash-1", in: tempRoot)
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "trash-1"), to: tempRoot)
        try IntegrationTestSupport.createDummyThumbnail(id: "trash-1", in: tempRoot)

        try storage.moveToTrash(filename: "trash-1.png", id: "trash-1")

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: storage.mediaDir.appendingPathComponent("trash-1.png").path))
        #expect(!fm.fileExists(atPath: storage.metadataDir.appendingPathComponent("trash-1.json").path))
        #expect(!fm.fileExists(atPath: storage.thumbnailDir.appendingPathComponent("trash-1.jpg").path))

        #expect(fm.fileExists(atPath: storage.trashMediaDir.appendingPathComponent("trash-1.png").path))
        #expect(fm.fileExists(atPath: storage.trashMetadataDir.appendingPathComponent("trash-1.json").path))
        #expect(fm.fileExists(atPath: storage.trashThumbnailDir.appendingPathComponent("trash-1.jpg").path))
    }

    @Test("moveToTrash handles partial files gracefully")
    func moveToTrashHandlesPartialFiles() throws {
        // Only image exists — no sidecar or thumbnail
        try IntegrationTestSupport.createDummyMedia(id: "partial-1", in: tempRoot)

        try storage.moveToTrash(filename: "partial-1.png", id: "partial-1")

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: storage.mediaDir.appendingPathComponent("partial-1.png").path))
        #expect(fm.fileExists(atPath: storage.trashMediaDir.appendingPathComponent("partial-1.png").path))
    }

    @Test("restoreFromTrash moves files back to original directories")
    func restoreFromTrashMovesBack() throws {
        try IntegrationTestSupport.createDummyMedia(id: "restore-1", in: tempRoot)
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "restore-1"), to: tempRoot)
        try IntegrationTestSupport.createDummyThumbnail(id: "restore-1", in: tempRoot)

        try storage.moveToTrash(filename: "restore-1.png", id: "restore-1")
        try storage.restoreFromTrash(filename: "restore-1.png", id: "restore-1")

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: storage.mediaDir.appendingPathComponent("restore-1.png").path))
        #expect(fm.fileExists(atPath: storage.metadataDir.appendingPathComponent("restore-1.json").path))
        #expect(fm.fileExists(atPath: storage.thumbnailDir.appendingPathComponent("restore-1.jpg").path))
    }

    @Test("Restore fails when the trashed media file is gone")
    func restoreMissingMediaFails() {
        #expect(throws: CocoaError.self) {
            try storage.restoreFromTrash(filename: "missing.png", id: "missing")
        }
    }

    @Test("A sidecar alone cannot make deletion succeed")
    func missingMediaKeepsSidecar() throws {
        let sidecar = storage.metadataDir.appendingPathComponent("orphan.json")
        try Data("{}".utf8).write(to: sidecar)
        #expect(throws: MediaStorageService.TrashError.self) {
            try storage.moveToTrash(filename: "orphan.png", id: "orphan")
        }
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }

    @Test("A failed thumbnail move restores media and sidecar")
    func failedMoveRollsBack() throws {
        try IntegrationTestSupport.createDummyMedia(id: "rollback", in: tempRoot)
        try IntegrationTestSupport.writeSidecarJSON(
            IntegrationTestSupport.makeSidecar(id: "rollback"), to: tempRoot
        )
        try IntegrationTestSupport.createDummyThumbnail(id: "rollback", in: tempRoot)
        try FileManager.default.removeItem(at: storage.trashThumbnailDir)
        try Data("blocked".utf8).write(to: storage.trashThumbnailDir)

        #expect(throws: Error.self) {
            try storage.moveToTrash(filename: "rollback.png", id: "rollback")
        }
        #expect(storage.mediaExists(filename: "rollback.png"))
        #expect(FileManager.default.fileExists(atPath: storage.metadataDir.appendingPathComponent("rollback.json").path))
    }

    @Test("emptyOldTrash removes expired files but keeps recent ones")
    func emptyOldTrashRemovesExpiredFiles() throws {
        let fm = FileManager.default

        // Create "old" file in trash
        let oldURL = storage.trashMediaDir.appendingPathComponent("old-1.png")
        try IntegrationTestSupport.dummyPNGData.write(to: oldURL)
        let oldDate = Date(timeIntervalSinceNow: -31 * 24 * 3600)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldURL.path)

        // Create "recent" file in trash
        let recentURL = storage.trashMediaDir.appendingPathComponent("recent-1.png")
        try IntegrationTestSupport.dummyPNGData.write(to: recentURL)

        storage.emptyOldTrash(olderThan: 30 * 24 * 3600)

        #expect(!fm.fileExists(atPath: oldURL.path))
        #expect(fm.fileExists(atPath: recentURL.path))
    }

    @Test("emptyTrash removes everything")
    func emptyTrashClearsAll() throws {
        // Put files in all trash dirs
        try IntegrationTestSupport.dummyPNGData.write(to: storage.trashMediaDir.appendingPathComponent("a.png"))
        try IntegrationTestSupport.dummyPNGData.write(to: storage.trashMetadataDir.appendingPathComponent("a.json"))
        try IntegrationTestSupport.dummyPNGData.write(to: storage.trashThumbnailDir.appendingPathComponent("a.jpg"))

        storage.emptyTrash()

        let fm = FileManager.default
        let mediaFiles = try fm.contentsOfDirectory(at: storage.trashMediaDir, includingPropertiesForKeys: nil)
        let metaFiles = try fm.contentsOfDirectory(at: storage.trashMetadataDir, includingPropertiesForKeys: nil)
        let thumbFiles = try fm.contentsOfDirectory(at: storage.trashThumbnailDir, includingPropertiesForKeys: nil)

        #expect(mediaFiles.isEmpty)
        #expect(metaFiles.isEmpty)
        #expect(thumbFiles.isEmpty)
    }
}
