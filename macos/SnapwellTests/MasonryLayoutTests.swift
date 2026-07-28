import Testing
import Foundation
import SwiftData
import CoreGraphics
@testable import Snapwell

@Suite("Masonry layout", .tags(.layout))
@MainActor
struct MasonryLayoutTests {

    // MARK: - columnAssignments

    /// The regression guard for the ratio-vs-points bug. The old estimate added a unit ratio
    /// (~0.5–2.0) to a 16pt constant, so the constant dominated and packing degenerated to
    /// round-robin. Correct point math keeps column 0 closed until column 1 passes 6000pt.
    @Test("Tall item keeps its column closed until the other catches up")
    func tallItemAbsorbsColumn() {
        let heights: [CGFloat] = [6000] + Array(repeating: 300, count: 20)
        let assignments = MasonryLayout.columnAssignments(
            itemHeights: heights, columns: 2, spacing: 16)

        // Column 0 holds 6016pt after the tall item. Column 1 accumulates 316pt per short
        // item, reaching 6320pt only after 20 of them — so every short item lands in column 1.
        #expect(assignments[0] == 0)
        #expect(assignments.dropFirst().allSatisfy { $0 == 1 })
    }

    @Test("Equal heights round-robin across three columns")
    func equalHeightsRoundRobin() {
        let assignments = MasonryLayout.columnAssignments(
            itemHeights: Array(repeating: 100, count: 9), columns: 3, spacing: 8)

        #expect(assignments == [0, 1, 2, 0, 1, 2, 0, 1, 2])
    }

    @Test("Single column assigns everything to column zero")
    func singleColumn() {
        let assignments = MasonryLayout.columnAssignments(
            itemHeights: [100, 200, 300], columns: 1, spacing: 8)

        #expect(assignments == [0, 0, 0])
    }

    @Test("Zero columns is treated as one and does not trap")
    func zeroColumnsIsSafe() {
        let assignments = MasonryLayout.columnAssignments(
            itemHeights: [100, 200], columns: 0, spacing: 8)

        #expect(assignments == [0, 0])
    }

    @Test("Zero and negative heights do not trap or produce NaN")
    func degenerateHeightsAreSafe() {
        let assignments = MasonryLayout.columnAssignments(
            itemHeights: [0, -500, 100], columns: 2, spacing: 8)

        #expect(assignments.count == 3)
        #expect(assignments.allSatisfy { $0 == 0 || $0 == 1 })
    }

    @Test("Empty input returns no assignments")
    func emptyInput() {
        #expect(MasonryLayout.columnAssignments(itemHeights: [], columns: 3, spacing: 8).isEmpty)
    }

    // MARK: - distribute

    /// Discriminating test for the clamp: with `gridAspectRatio` the tall item is 600pt, so
    /// column 0 reopens after two short items and takes the third. With the raw `aspectRatio`
    /// it would be 6000pt and all three short items would pile into column 1.
    @Test("Distribution uses the clamped grid aspect ratio, not the raw one")
    func distributionUsesClampedRatio() throws {
        let container = try TestContainer.create()
        // 1000x20000 → aspectRatio 0.05, gridAspectRatio 0.5 → 600pt at columnWidth 300.
        let tall = MediaItem(mediaType: .image, filename: "tall.png", width: 1000, height: 20000)
        container.mainContext.insert(tall)
        let short = (0..<3).map { index in
            MediaItem(mediaType: .image, filename: "short\(index).png", width: 1000, height: 1000)
        }
        for item in short { container.mainContext.insert(item) }

        let columns = MasonryLayout.distribute(
            [tall] + short, columns: 2, columnWidth: 300, spacing: 16)

        #expect(columns[0].items.map(\.id) == [tall.id, short[2].id])
        #expect(columns[1].items.map(\.id) == [short[0].id, short[1].id])
    }

    @Test("Distribution spreads items across the requested column count")
    func distributionSpreadsItems() throws {
        let container = try TestContainer.create()
        let items = (0..<6).map { index in
            MediaItem(mediaType: .image, filename: "\(index).png", width: 1000, height: 1000)
        }
        for item in items { container.mainContext.insert(item) }

        let columns = MasonryLayout.distribute(
            items, columns: 3, columnWidth: 300, spacing: 16)

        #expect(columns.count == 3)
        #expect(columns.allSatisfy { $0.items.count == 2 })
        #expect(columns.map(\.id) == [0, 1, 2])
    }

    @Test("Distribution excludes deleted items")
    func distributionExcludesDeleted() throws {
        let container = try TestContainer.create()
        let keep = MediaItem(mediaType: .image, filename: "keep.png", width: 100, height: 100)
        let drop = MediaItem(mediaType: .image, filename: "drop.png", width: 100, height: 100)
        container.mainContext.insert(keep)
        container.mainContext.insert(drop)
        container.mainContext.delete(drop)

        let columns = MasonryLayout.distribute(
            [keep, drop], columns: 2, columnWidth: 300, spacing: 16)

        let distributed = columns.flatMap(\.items)
        #expect(distributed.count == 1)
        #expect(distributed.first?.id == keep.id)
    }

    @Test("Distribution always returns at least one column")
    func distributionMinimumOneColumn() {
        let columns = MasonryLayout.distribute([], columns: 0, columnWidth: 300, spacing: 16)
        #expect(columns.count == 1)
    }

    // MARK: - fingerprint

    @Test("Fingerprint is order-sensitive")
    func fingerprintIsOrderSensitive() {
        #expect(MasonryLayout.fingerprint(["a", "b"]) != MasonryLayout.fingerprint(["b", "a"]))
    }

    @Test("Fingerprint is stable for identical input")
    func fingerprintIsStable() {
        #expect(MasonryLayout.fingerprint(["a", "b", "c"]) == MasonryLayout.fingerprint(["a", "b", "c"]))
    }

    @Test("Fingerprint distinguishes added and removed items")
    func fingerprintDetectsMembershipChange() {
        let base = MasonryLayout.fingerprint(["a", "b"])
        #expect(base != MasonryLayout.fingerprint(["a", "b", "c"]))
        #expect(base != MasonryLayout.fingerprint(["a"]))
    }
}
