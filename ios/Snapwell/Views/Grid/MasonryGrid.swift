import SwiftUI

struct MasonryGrid: View {
    let items: [MediaItem]
    var spaces: [Space] = []
    let availableWidth: CGFloat
    var selectedItemId: String?
    var onItemSelected: ((MediaItem, CGRect, UIImage?) -> Void)?
    var onRetryAnalysis: ((MediaItem) -> Void)?
    var onShareItem: ((MediaItem) -> Void)?
    var onDeleteItem: ((MediaItem) -> Void)?
    var onAssignToSpace: ((String, String?) -> Void)?

    private let columnCount = 2
    private let spacing: CGFloat = 8

    var body: some View {
        let columnWidth = max(1, (availableWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
        let columns = MasonryLayout.distribute(
            items,
            columns: columnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )

        HStack(alignment: .top, spacing: spacing) {
            ForEach(columns) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(column.items) { item in
                        // The delete path keeps the model alive across the removal animation, so
                        // a cell can be re-evaluated against invalidated backing data.
                        if !item.isDeleted {
                            GridItemView(
                                item: item,
                                width: columnWidth,
                                isSelected: selectedItemId == item.id,
                                onSelect: onItemSelected,
                                onRetryAnalysis: onRetryAnalysis.map { callback in
                                    { callback(item) }
                                },
                                onShare: onShareItem.map { callback in
                                    { callback(item) }
                                },
                                onDelete: onDeleteItem.map { callback in
                                    { callback(item) }
                                },
                                onAssignToSpace: onAssignToSpace
                            )
                        }
                    }
                }
            }
        }
        .environment(\.gridSpaces, spaces)
    }
}
