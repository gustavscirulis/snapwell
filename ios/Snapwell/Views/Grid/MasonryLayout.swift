import CoreGraphics

/// One masonry column. `Identifiable` so `ForEach` diffs on identity rather than a
/// non-constant `Range<Int>`, which SwiftUI does not support.
struct MasonryColumn: Identifiable {
    let id: Int
    var items: [MediaItem] = []
}

@MainActor
enum MasonryLayout {
    /// Shortest-column-first packing. Heights are in points, matching `GridItemView.height`.
    static func columnAssignments(itemHeights: [CGFloat], columns: Int, spacing: CGFloat) -> [Int] {
        let count = max(1, columns)
        var heights = [CGFloat](repeating: 0, count: count)
        var result: [Int] = []
        result.reserveCapacity(itemHeights.count)

        for height in itemHeights {
            var shortest = 0
            if count > 1 {
                for column in 1..<count where heights[column] < heights[shortest] {
                    shortest = column
                }
            }
            result.append(shortest)
            heights[shortest] += max(0, height) + spacing
        }

        return result
    }

    static func distribute(
        _ items: [MediaItem],
        columns: Int,
        columnWidth: CGFloat,
        spacing: CGFloat
    ) -> [MasonryColumn] {
        let live = items.filter { !$0.isDeleted }
        let assignments = columnAssignments(
            itemHeights: live.map { columnWidth / $0.gridAspectRatio },
            columns: columns,
            spacing: spacing
        )

        var result = (0..<max(1, columns)).map { MasonryColumn(id: $0) }
        for (item, column) in zip(live, assignments) {
            result[column].items.append(item)
        }
        return result
    }
}
