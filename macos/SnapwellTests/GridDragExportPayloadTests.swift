import Testing
import Foundation
@testable import Snapwell

@Suite("Grid drag export payload")
@MainActor
struct GridDragExportPayloadTests {

    @Test("Multi-selection exports every selected file in grid order")
    func multiSelectionExportsEverySelectedFile() {
        let storage = MediaStorageService(baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = MediaItem(id: "a", mediaType: .image, filename: "a.png", width: 100, height: 100)
        let second = MediaItem(id: "b", mediaType: .image, filename: "b.png", width: 100, height: 100)
        let third = MediaItem(id: "c", mediaType: .video, filename: "c.mp4", width: 100, height: 100)

        let payload = GridDragExportPayload(
            draggedItem: third,
            effectiveIds: ["c", "a"],
            orderedItems: [first, second, third],
            storage: storage
        )

        #expect(payload.orderedIds == ["a", "c"])
        #expect(payload.fileURLs == [
            storage.mediaURL(filename: "a.png"),
            storage.mediaURL(filename: "c.mp4"),
        ])
        #expect(payload.internalString == "snapwell:a,c")
    }

    @Test("Single unselected drag exports only the dragged item")
    func singleDragExportsOnlyDraggedItem() {
        let storage = MediaStorageService(baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = MediaItem(id: "a", mediaType: .image, filename: "a.png", width: 100, height: 100)
        let second = MediaItem(id: "b", mediaType: .image, filename: "b.png", width: 100, height: 100)
        let third = MediaItem(id: "c", mediaType: .image, filename: "c.png", width: 100, height: 100)

        let payload = GridDragExportPayload(
            draggedItem: second,
            effectiveIds: ["b"],
            orderedItems: [first, second, third],
            storage: storage
        )

        #expect(payload.orderedIds == ["b"])
        #expect(payload.fileURLs == [storage.mediaURL(filename: "b.png")])
        #expect(payload.internalString == "snapwell:b")
    }
}
