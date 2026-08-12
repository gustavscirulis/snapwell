import Foundation
import SwiftData
import Testing
@testable import Snapwell

@Suite(.tags(.integration, .sync))
struct DataCleanupSafetyTests {
    @Test("iCloud mode keeps a sidecar whose media has not arrived")
    func iCloudModeDoesNotDeleteSidecarWithMissingMedia() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let storage = MediaStorageService(baseURL: root, isUsingiCloud: true)
        let sidecar = IntegrationTestSupport.makeSidecar(id: "cloud-sidecar")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: root)

        DataCleanupService.cleanOrphanedSidecars(storage: storage)

        #expect(FileManager.default.fileExists(
            atPath: storage.metadataDir.appendingPathComponent("cloud-sidecar.json").path
        ))
    }

    @Test("Local mode still removes a truly orphaned sidecar")
    func localModeStillDeletesTrulyOrphanedSidecar() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let storage = MediaStorageService(baseURL: root)
        let sidecar = IntegrationTestSupport.makeSidecar(id: "local-sidecar")
        try IntegrationTestSupport.writeSidecarJSON(sidecar, to: root)

        DataCleanupService.cleanOrphanedSidecars(storage: storage)

        #expect(!FileManager.default.fileExists(
            atPath: storage.metadataDir.appendingPathComponent("local-sidecar.json").path
        ))
    }

    @Test("iCloud mode keeps a record whose media has not arrived")
    @MainActor func iCloudModeKeepsRecordWhoseMediaIsMissing() throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }
        let storage = MediaStorageService(baseURL: root, isUsingiCloud: true)
        let context = ModelContext(try TestContainer.create())
        context.insert(MediaItem(
            id: "cloud-record",
            mediaType: .image,
            filename: "cloud-record.png",
            width: 100,
            height: 100
        ))
        context.saveOrLog()

        DataCleanupService.cleanOrphanedRecords(context: context, storage: storage)

        #expect(try context.fetch(FetchDescriptor<MediaItem>()).count == 1)
    }
}
