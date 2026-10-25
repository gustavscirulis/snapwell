import Foundation
import Testing
@testable import Snapwell

@Suite("Share extension staging", .tags(.filesystem))
struct ShareStagingTests {
    @Test("Image and video shares publish their metadata after their media", arguments: ["png", "mp4"])
    func publishShare(ext: String) throws {
        let root = rootURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let media = Data("shared media".utf8)
        let sidecar = Data(#"{"id":"shared"}"#.utf8)
        try ShareStagingStore.stage(media: media, sidecar: sidecar, id: "shared", mediaExtension: ext, in: root) { data, url in
            #expect(try Data(contentsOf: root.appendingPathComponent("images/shared.\(ext)")) == media)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            try data.write(to: url, options: .atomic)
        }
        #expect(try Data(contentsOf: root.appendingPathComponent("metadata/shared.json")) == sidecar)
        #expect(try Data(contentsOf: root.appendingPathComponent("images/shared.\(ext)")) == media)
    }

    @Test("A failed sidecar publication rolls back its media and propagates the error")
    func sidecarFailure() throws {
        let root = rootURL()
        defer { try? FileManager.default.removeItem(at: root) }
        enum Failure: Error { case diskFull }
        #expect(throws: Failure.diskFull) {
            try ShareStagingStore.stage(media: Data([1]), sidecar: Data([2]), id: "shared", mediaExtension: "png", in: root) { _, _ in
                #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("images/shared.png").path))
                throw Failure.diskFull
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("images/shared.png").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("metadata/shared.json").path))
    }

    @Test("A duplicate staging ID cannot overwrite an existing share")
    func collision() throws {
        let root = rootURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try ShareStagingStore.stage(media: Data([1]), sidecar: Data([2]), id: "same", mediaExtension: "png", in: root)
        #expect(throws: (any Error).self) {
            try ShareStagingStore.stage(media: Data([3]), sidecar: Data([4]), id: "same", mediaExtension: "png", in: root)
        }
        #expect(try Data(contentsOf: root.appendingPathComponent("images/same.png")) == Data([1]))
        #expect(try Data(contentsOf: root.appendingPathComponent("metadata/same.json")) == Data([2]))
    }

    @Test("Unsafe IDs cannot write outside the pending directory", arguments: ["../escape", "nested/file", "", ".", ".."])
    func invalidID(id: String) throws {
        let root = rootURL()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) {
            try ShareStagingStore.stage(media: Data([1]), sidecar: Data([2]), id: id, mediaExtension: "png", in: root)
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    private func rootURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SnapwellShareStagingTests/\(UUID().uuidString)")
    }
}
