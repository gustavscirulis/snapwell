import SwiftUI

// MARK: - Preference Keys

struct ItemFramePreferenceKey: PreferenceKey {
    nonisolated static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Holds rubber-band hit rects outside SwiftUI's dependency graph. `body` never reads it, so
/// preference deliveries no longer invalidate the grid — previously every delivery during a drag
/// re-ran the whole distribution.
@MainActor
final class ItemFrameStore {
    var frames: [String: CGRect] = [:]
}

// MARK: - Masonry Grid

struct MasonryGridView: View {
    let items: [MediaItem]
    let thumbnailSize: ThumbnailSize
    let spaces: [Space]
    let activeSpaceId: String?
    let onSelect: (String, CGRect) -> Void
    let onToggleSelect: (String) -> Void
    let onShiftSelect: (String) -> Void
    let onDelete: (Set<String>) -> Void
    let onChangeSpaceMembership: (Set<String>, SpaceMembershipAction) -> Void
    let onRetryAnalysis: (Set<String>) -> Void
    let onShare: (Set<String>, CGRect) -> Void
    let onSetSelection: (Set<String>) -> Void
    var coordinateSpaceName: String = "gridContent"
    var topInset: CGFloat = 0
    /// Bumped by the parent when the item set is replaced wholesale (a new search). Resolving a
    /// deep scroll offset against a list whose identity is being replaced is the worst case for
    /// the lazy stacks' size estimation.
    var scrollResetToken: Int = 0

    @Environment(AppState.self) private var appState

    // Rubber band state
    @State private var frameStore = ItemFrameStore()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var rubberBandStart: CGPoint?
    @State private var rubberBandCurrent: CGPoint?
    @State private var rubberBandActive = false
    @State private var frozenSelection: Set<String> = []

    private var rubberBandRect: CGRect? {
        guard let start = rubberBandStart, let current = rubberBandCurrent, rubberBandActive else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 16  // masonry-grid.css:10,16 — 16px column/row gaps
            let horizontalPadding: CGFloat = 24
            let availableWidth = geometry.size.width - horizontalPadding * 2
            let columnCount = thumbnailSize.columns(forWidth: geometry.size.width)
            let columnWidth = max(1, (availableWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
            let columns = MasonryLayout.distribute(
                items,
                columns: columnCount,
                columnWidth: columnWidth,
                spacing: spacing
            )
            let fingerprint = MasonryLayout.fingerprint(items.lazy.map(\.id))

            ScrollView {
                // The lazy stacks must be the scroll view's only sizing child. Putting them in a
                // ZStack alongside a min-height sibling makes the ZStack measure them, which
                // defeats laziness — `LazyVStack.sizeThatFits` then walks the whole library on
                // every layout pass. `background`/`overlay` are layout-neutral, so the rubber-band
                // layers inherit the resolved size instead of participating in it.
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(columns) { column in
                        LazyVStack(spacing: spacing) {
                            ForEach(column.items) { item in
                                if !item.isDeleted {
                                    GridItemView(
                                        item: item,
                                        width: columnWidth,
                                        orderedItems: { items },
                                        itemsFingerprint: fingerprint,
                                        activeSpaceId: activeSpaceId,
                                        onSelect: { frame in onSelect(item.id, frame) },
                                        onToggleSelect: { onToggleSelect(item.id) },
                                        onShiftSelect: { onShiftSelect(item.id) },
                                        onDelete: onDelete,
                                        onChangeSpaceMembership: onChangeSpaceMembership,
                                        onRetryAnalysis: onRetryAnalysis,
                                        onShare: onShare
                                    )
                                    .equatable()
                                    // Outside the EquatableView — this closure captures
                                    // `rubberBandStart`, which legitimately changes every pass.
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: ItemFramePreferenceKey.self,
                                                value: rubberBandStart != nil
                                                    ? [item.id: geo.frame(in: .named(coordinateSpaceName))]
                                                    : [:]
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                // One padding layer, not three chained ones — each adds a layout level the
                // measuring pass has to descend through.
                .padding(EdgeInsets(
                    top: 24 + topInset,
                    leading: horizontalPadding,  // ImageGrid.tsx:598 — px-4
                    bottom: 24,
                    trailing: horizontalPadding
                ))
                .environment(\.gridSpaces, spaces)
                // Outside the padding, so the drag catcher still covers the viewport when the
                // content is shorter than it.
                .frame(
                    minWidth: geometry.size.width,
                    minHeight: geometry.size.height,
                    alignment: .topLeading
                )
                .background(alignment: .topLeading) { rubberBandCatcher }
                .overlay(alignment: .topLeading) { rubberBandVisual }
                .coordinateSpace(.named(coordinateSpaceName))
                // The action is @Sendable with no main-actor guarantee, so `assumeIsolated` here
                // would trap. Hop explicitly instead.
                .onPreferenceChange(ItemFramePreferenceKey.self) { [frameStore] frames in
                    Task { @MainActor in frameStore.frames = frames }
                }
            }
            .scrollPosition($scrollPosition)
            .onChange(of: scrollResetToken) {
                scrollPosition.scrollTo(edge: .top)
            }
            #if compiler(>=6.3)
            .modifier(SoftScrollEdgeModifier())
            #endif
        }
    }

    // MARK: - Rubber Band

    /// Catches drags on empty space. Deliberately has no `.frame` — as a background it inherits
    /// the parent's already-resolved size, which is what keeps it out of the sizing path.
    private var rubberBandCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        if rubberBandStart == nil {
                            rubberBandStart = value.startLocation
                            let flags = NSEvent.modifierFlags
                            frozenSelection = (flags.contains(.shift) || flags.contains(.command))
                                ? appState.selectedIds : Set()
                        }
                        rubberBandCurrent = value.location

                        let dx = value.location.x - value.startLocation.x
                        let dy = value.location.y - value.startLocation.y
                        if !rubberBandActive && (dx * dx + dy * dy >= 9) {
                            rubberBandActive = true
                        }

                        if rubberBandActive, let rect = rubberBandRect {
                            var newSelection = frozenSelection
                            for (id, frame) in frameStore.frames {
                                if rect.intersects(frame) {
                                    newSelection.insert(id)
                                }
                            }
                            onSetSelection(newSelection)
                        }
                    }
                    .onEnded { _ in
                        if !rubberBandActive && frozenSelection.isEmpty {
                            // Click on empty space without modifiers — clear selection
                            onSetSelection([])
                        }
                        rubberBandStart = nil
                        rubberBandCurrent = nil
                        rubberBandActive = false
                        frozenSelection = []
                    }
            )
    }

    @ViewBuilder
    private var rubberBandVisual: some View {
        if let rect = rubberBandRect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.10))
                .overlay(
                    Rectangle()
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                )
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Scroll Edge Effect (macOS 26+)

#if compiler(>=6.3)
struct SoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
#endif
