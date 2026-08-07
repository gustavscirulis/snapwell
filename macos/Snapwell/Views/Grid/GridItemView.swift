import SwiftUI
import AppKit
import AVFoundation

struct GridItemView: View, Equatable {
    let item: MediaItem
    let width: CGFloat
    /// Resolved only when a drag actually starts. A stored array here would be compared
    /// element-by-element for every cell on every update pass — O(n²) across the grid.
    let orderedItems: () -> [MediaItem]
    /// Order-sensitive fingerprint of the parent's item list. Never read by `body`; it exists so
    /// `==` invalidates cells whose captured closures have gone stale.
    let itemsFingerprint: Int
    let activeSpaceId: String?
    let onSelect: (CGRect) -> Void
    let onToggleSelect: () -> Void
    let onShiftSelect: () -> Void
    let onDelete: (Set<String>) -> Void
    let onChangeSpaceMembership: (Set<String>, SpaceMembershipAction) -> Void
    let onRetryAnalysis: (Set<String>) -> Void
    let onShare: (Set<String>, CGRect) -> Void

    @Environment(VideoPreviewManager.self) private var videoPreview
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.gridSpaces) private var spaces
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var loadFailed = false
    @State private var globalFrame: CGRect = .zero
    @State private var hoverTask: Task<Void, Never>?
    /// Suppresses the first `.onHover(false)` after a video preview starts.
    /// The floating NSView (AVPlayerLayer) causes a spurious exit event
    /// that macOS never corrects with a re-entry.
    @State private var suppressHoverExit = false

    // Eagerly resolved SwiftData properties — prevents faults on detached backing stores
    // when SwiftUI re-evaluates the body (e.g. for context menu snapshots).
    private let itemIsVideo: Bool
    private let itemSpaceIds: [String]
    private let itemAspectRatio: CGFloat

    // Selection state derived from AppState — changes only invalidate this view,
    // not the parent MasonryGridView (which no longer depends on selectedIds).
    private var isSelected: Bool { appState.selectedIds.contains(item.id) }
    private var selectedCount: Int { appState.selectedIds.count }
    private var effectiveIds: Set<String> {
        isSelected && selectedCount > 1 ? appState.selectedIds : [item.id]
    }

    init(item: MediaItem, width: CGFloat, orderedItems: @escaping () -> [MediaItem], itemsFingerprint: Int, activeSpaceId: String?, onSelect: @escaping (CGRect) -> Void, onToggleSelect: @escaping () -> Void, onShiftSelect: @escaping () -> Void, onDelete: @escaping (Set<String>) -> Void, onChangeSpaceMembership: @escaping (Set<String>, SpaceMembershipAction) -> Void, onRetryAnalysis: @escaping (Set<String>) -> Void, onShare: @escaping (Set<String>, CGRect) -> Void) {
        self.item = item
        self.width = width
        self.orderedItems = orderedItems
        self.itemsFingerprint = itemsFingerprint
        self.activeSpaceId = activeSpaceId
        self.onSelect = onSelect
        self.onToggleSelect = onToggleSelect
        self.onShiftSelect = onShiftSelect
        self.onDelete = onDelete
        self.onChangeSpaceMembership = onChangeSpaceMembership
        self.onRetryAnalysis = onRetryAnalysis
        self.onShare = onShare
        self.itemIsVideo = item.isVideo
        self.itemSpaceIds = item.orderedSpaceIDs
        self.itemAspectRatio = item.gridAspectRatio
        _thumbnail = State(initialValue: ImageCacheService.shared.image(forKey: item.id))
    }

    /// Only the fields `body` cannot re-read observably. Everything read directly off the `@Model`
    /// (`isAnalyzing`, `analysisResult`, `analysisError`, `width`/`height`) is tracked by
    /// Observation and invalidates independently; so do `AppState`, `VideoPreviewManager`, and the
    /// environment. The eagerly-snapshotted properties below are *not* observable, so omitting one
    /// would leave stale UI.
    nonisolated static func == (lhs: GridItemView, rhs: GridItemView) -> Bool {
        lhs.item === rhs.item
            && lhs.width == rhs.width
            && lhs.activeSpaceId == rhs.activeSpaceId
            && lhs.itemsFingerprint == rhs.itemsFingerprint
            && lhs.itemAspectRatio == rhs.itemAspectRatio
            && lhs.itemIsVideo == rhs.itemIsVideo
            && lhs.itemSpaceIds == rhs.itemSpaceIds
    }

    private var height: CGFloat {
        width / itemAspectRatio
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if itemIsVideo { parts.append("Video") } else { parts.append("Image") }
        if let summary = item.analysisResult?.imageSummary, !summary.isEmpty {
            parts.append(summary)
        }
        parts.append("\(item.width) by \(item.height)")
        if item.isAnalyzing { parts.append("Analyzing") }
        if item.analysisError != nil { parts.append("Analysis failed") }
        if loadFailed { parts.append("Preview unavailable, click to retry") }
        return parts.joined(separator: ", ")
    }

    private var gridItemOpacity: Double {
        item.id == appState.detailItem ? 0 : 1
    }

    private var deleteStage: Int {
        appState.deleteStage(for: item.id)
    }

    private var isDeleting: Bool {
        deleteStage > 0
    }

    /// Whether this item is part of a multi-selection context menu
    private var isBulk: Bool {
        isSelected && selectedCount > 1
    }

    private var isInActiveSpace: Bool {
        guard let activeSpaceId else { return false }
        return itemSpaceIds.contains(activeSpaceId)
    }

    /// Hover state that stays true while the floating video layer covers this item.
    /// The NSView-backed AVPlayerLayer causes a spurious onHover(false) when it appears
    /// on top; this keeps hover UI visible for the duration of the grid preview.
    private var effectiveHover: Bool {
        isHovered || (itemIsVideo && videoPreview.activeItemId == item.id && videoPreview.displayState == .grid)
    }

    /// Whether to show the SwiftUI gradient scrim behind pattern pills.
    /// Suppressed for video items when the floating video layer provides its own CAGradientLayer.
    /// Guarded by `itemIsVideo` so non-video items never subscribe to `activeItemId` changes.
    private var showHoverGradient: Bool {
        guard effectiveHover else { return false }
        guard itemIsVideo else { return true }
        return videoPreview.activeItemId != item.id
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // LAYER 1: Background selection button
            Button {
                let flags = NSEvent.modifierFlags
                if flags.contains(.command) {
                    onToggleSelect()
                } else if flags.contains(.shift) {
                    onShiftSelect()
                } else if loadFailed {
                    // Retry through the button rather than a tap gesture on the placeholder —
                    // a gesture inside a Button label competes with the button itself.
                    loadFailed = false
                    Task { await loadThumbnail() }
                } else {
                    onSelect(globalFrame)
                }
            } label: {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    } else if loadFailed {
                        Rectangle()
                            .fill(Color.snapMuted)
                            .frame(width: width, height: height)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "icloud.and.arrow.down")
                                        .font(.body)
                                    Text("Click to retry")
                                        .font(.caption2)
                                }
                                .foregroundStyle(Color.snapMutedForeground)
                            }
                    } else {
                        Rectangle()
                            .fill(Color.snapMuted)
                            .frame(width: width, height: height)
                    }
                }
            }
            .buttonStyle(.plain)

            // LAYER 2: Non-interactive visual overlays
            Group {
                // Video badge (hidden during active preview — floating layer renders video)
                if itemIsVideo && videoPreview.activeItemId != item.id {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(8)
                        }
                    }
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
                }

                // Bottom overlay: analyzing shimmer or hover-only pattern tags
                VStack {
                    Spacer()

                    if item.isAnalyzing {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(
                                colors: [.black.opacity(0.5), .black.opacity(0.15), .clear],
                                startPoint: .bottom,
                                endPoint: .init(x: 0.5, y: 0.3)
                            )

                            HStack {
                                shimmerBadge
                                Spacer()
                            }
                            .padding(8)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 6)),
                                removal: .opacity
                            )
                        )
                    } else if item.analysisError == nil, let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
                        // Gradient backdrop + staggered pattern tags (hover only)
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(
                                colors: [.black.opacity(0.35), .black.opacity(0.1), .clear],
                                startPoint: .bottom,
                                endPoint: .init(x: 0.5, y: 0.55)
                            )
                            .opacity(showHoverGradient ? 1 : 0)
                            .offset(y: effectiveHover ? 0 : (reduceMotion ? 0 : 20))
                            .animation(SnapSpring.standard(reduced: reduceMotion), value: effectiveHover)

                            HStack {
                                FlowLayout(spacing: 4) {
                                    ForEach(Array(patterns.prefix(5).enumerated()), id: \.element.name) { index, pattern in
                                        PatternPill(name: pattern.name, useGlass: false)
                                            .opacity(effectiveHover ? 1 : 0)
                                            .offset(y: effectiveHover ? 0 : (reduceMotion ? 0 : 8))
                                            .animation(
                                                reduceMotion
                                                    ? .easeInOut(duration: 0.1)
                                                    : SnapSpring.fast.delay(Double(index) * 0.025),
                                                value: effectiveHover
                                            )
                                    }
                                }
                                Spacer()
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(width: width, height: height, alignment: .bottomLeading)
                .animation(SnapSpring.standard(reduced: reduceMotion), value: item.isAnalyzing)
            }
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        // LAYER 3: Interactive action buttons as overlays
        .overlay(alignment: .topTrailing) {
            if effectiveHover {
                Button { onDelete(effectiveIds) } label: {
                    hoverButtonIcon("trash", size: 10)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Delete")
                .accessibilityHint("Moves this item to the trash")
            }
        }
        .overlay(alignment: .topLeading) {
            if effectiveHover && isInActiveSpace, let activeSpaceId {
                Button { onChangeSpaceMembership(effectiveIds, .remove(activeSpaceId)) } label: {
                    hoverButtonIcon("folder.badge.minus", size: 10)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Remove from space")
                .accessibilityHint("Removes this item from the current space")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !item.isAnalyzing && item.analysisError != nil {
                Button { onRetryAnalysis(effectiveIds) } label: {
                    retryBadge
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Redo analysis")
                .accessibilityHint("Runs AI analysis again on this item")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isDeleting ? DeleteAnim.targetScale : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected && !isDeleting ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(
            color: .black.opacity(isDeleting ? 0 : (effectiveHover ? 0.1 : 0.05)),
            radius: effectiveHover ? 6 : 2,
            x: 0,
            y: effectiveHover ? 4 : 1
        )
        .animation(SnapSpring.fast(reduced: reduceMotion), value: effectiveHover)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHidden(isDeleting)
        .onHover { hovering in
            guard !isDeleting else {
                isHovered = false
                return
            }
            isHovered = hovering
            hoverTask?.cancel()
            if itemIsVideo {
                if hovering {
                    // Don't start preview during rubber band selection or drag
                    guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                    suppressHoverExit = false
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        // Only arm the suppress flag when actually creating a new preview —
                        // re-entering an already-previewing item won't spawn a new layer.
                        if videoPreview.activeItemId != item.id {
                            suppressHoverExit = true
                        }
                        videoPreview.startPreview(
                            itemId: item.id,
                            url: MediaStorageService.shared.mediaURL(filename: item.filename),
                            frame: globalFrame,
                            patternNames: item.analysisResult?.patterns.prefix(5).map(\.name) ?? [],
                            isAnalyzing: item.isAnalyzing,
                            hasAnalysisError: !item.isAnalyzing && item.analysisError != nil
                        )
                    }
                } else if videoPreview.activeItemId == item.id {
                    // The floating NSView causes one spurious onHover(false) when it
                    // first appears. Suppress that single exit; subsequent exits are genuine.
                    if suppressHoverExit {
                        suppressHoverExit = false
                        if mouseIsInsideGridItem() {
                            // Genuinely spurious exit — poll for real exit since
                            // macOS won't send another onHover(false).
                            hoverTask = Task {
                                while !Task.isCancelled {
                                    try? await Task.sleep(for: .milliseconds(100))
                                    guard !Task.isCancelled else { return }
                                    if !mouseIsInsideGridItem() {
                                        videoPreview.stopPreview()
                                        return
                                    }
                                }
                            }
                            return
                        }
                        // Mouse already left — fall through to delayed stopPreview
                    }
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        videoPreview.stopPreview()
                    }
                } else {
                    videoPreview.stopPreview()
                }
            }
        }
        .overlay {
            dragSourceOverlay
        }
        .opacity(isDeleting ? 0 : gridItemOpacity)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            // Deadband — skip state write when frame barely moved (< 1pt).
            // Reduces @State churn for all visible items during scroll.
            guard abs(newValue.origin.x - globalFrame.origin.x) > 1 ||
                  abs(newValue.origin.y - globalFrame.origin.y) > 1 ||
                  abs(newValue.size.width - globalFrame.size.width) > 1 ||
                  abs(newValue.size.height - globalFrame.size.height) > 1 else { return }
            globalFrame = newValue
            // Keep the floating video layer in sync with scroll/resize
            if itemIsVideo && videoPreview.activeItemId == item.id {
                videoPreview.updateGridFrame(newValue)
            }
            // Keep detail source frame in sync when this item is the active detail
            if appState.detailItem == item.id {
                appState.detailSourceFrame = newValue
            }
        }
        .onChange(of: appState.detailItem) { oldId, newId in
            if newId == item.id {
                appState.detailSourceFrame = globalFrame
            } else if oldId == item.id {
                // Detail dismissed — mouse may have moved, so clear stale hover state.
                isHovered = false
                suppressHoverExit = false
            }
        }
        .onChange(of: item.isAnalyzing) {
            updateVideoPreviewAnalysisState()
        }
        .onChange(of: item.analysisError) {
            updateVideoPreviewAnalysisState()
        }
        .contextMenu {
            let removeFromActiveSpace: (() -> Void)? = {
                guard let activeSpaceId, itemSpaceIds.contains(activeSpaceId) else {
                    return nil
                }
                return { onChangeSpaceMembership(effectiveIds, .remove(activeSpaceId)) }
            }()

            MediaItemContextMenu(
                spaces: spaces,
                activeSpaceId: activeSpaceId,
                currentSpaceIds: itemSpaceIds,
                bulkCount: isBulk ? selectedCount : nil,
                onToggleSpace: { spaceId in
                    onChangeSpaceMembership(effectiveIds, .toggle(spaceId))
                },
                onRemoveFromActiveSpace: removeFromActiveSpace,
                onShare: { onShare(effectiveIds, globalFrame) },
                onRedoAnalysis: { onRetryAnalysis(effectiveIds) },
                onDelete: { onDelete(effectiveIds) }
            )
        }
        .task {
            guard thumbnail == nil else { return }
            await loadThumbnail()
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailsRegenerated)) { _ in
            thumbnail = nil
            loadFailed = false
            Task { await loadThumbnail() }
        }
    }

    // MARK: - Glass-aware sub-views

    private var dragSourceOverlay: some View {
        GridDragSourceRepresentable(
            isSuppressed: appState.detailItem != nil,
            payloadProvider: makeDragExportPayload,
            previewImageProvider: { thumbnail },
            onDragStarted: {
                appState.isDraggingFromApp = true
                videoPreview.stopPreview()
            },
            onDragEnded: {
                appState.isDraggingFromApp = false
            }
        )
    }

    /// "Analyzing..." shimmer badge with glass on macOS 26+.
    @ViewBuilder
    private var shimmerBadge: some View {
        let base = ShimmerText("Analyzing...")
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

        #if compiler(>=6.3)
        if #available(macOS 26, *) {
            base
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        } else {
            base
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        }
        #else
        base
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, .dark)
        #endif
    }

    private func hoverButtonIcon(_ systemName: String, size: CGFloat) -> some View {
        HoverActionIcon(systemName: systemName, size: size)
    }

    /// Retry analysis badge with red-tinted glass on macOS 26+.
    @ViewBuilder
    private var retryBadge: some View {
        let base = HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.caption2)
            Text("Retry")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)

        #if compiler(>=6.3)
        if #available(macOS 26, *) {
            base.glassEffect(.regular.tint(.red).interactive(), in: .rect(cornerRadius: 6))
        } else {
            base
                .background(.red.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        #else
        base
            .background(.red.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        #endif
    }

    /// Check if the mouse cursor is currently inside this grid item's frame.
    /// Converts AppKit window coordinates (origin bottom-left) to SwiftUI's
    /// flipped global space (origin top-left of content area).
    private func mouseIsInsideGridItem() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        let mouseLoc = window.mouseLocationOutsideOfEventStream
        let contentRect = window.contentLayoutRect
        let swiftUIPoint = CGPoint(
            x: mouseLoc.x,
            y: contentRect.maxY - mouseLoc.y
        )
        return globalFrame.contains(swiftUIPoint)
    }

    private func loadThumbnail(isRetry: Bool = false) async {
        if let loaded = await ImageCacheService.shared.loadThumbnail(id: item.id, filename: item.filename) {
            self.thumbnail = loaded
            return
        }

        // Auto-retry once — an iCloud file may arrive just after the first attempt.
        if !isRetry {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await loadThumbnail(isRetry: true)
        } else {
            loadFailed = true
        }
    }

    private func makeDragExportPayload() -> GridDragExportPayload {
        GridDragExportPayload(
            draggedItem: item,
            effectiveIds: effectiveIds,
            orderedItems: orderedItems(),
            storage: MediaStorageService.shared
        )
    }

    private func updateVideoPreviewAnalysisState() {
        guard videoPreview.activeItemId == item.id else { return }
        videoPreview.updateAnalysisState(
            isAnalyzing: item.isAnalyzing,
            hasError: !item.isAnalyzing && item.analysisError != nil
        )
    }
}

// MARK: - Grid Drag Export

struct GridDragExportPayload {
    let orderedIds: [String]
    let fileURLs: [URL]
    let internalString: String

    init(
        draggedItem: MediaItem,
        effectiveIds: Set<String>,
        orderedItems: [MediaItem],
        storage: MediaStorageService
    ) {
        let selectedItems = orderedItems.filter { item in
            effectiveIds.contains(item.id) && !item.isDeleted
        }
        let exportItems = selectedItems.isEmpty ? [draggedItem] : selectedItems

        self.orderedIds = exportItems.map(\.id)
        self.fileURLs = exportItems.map { storage.mediaURL(filename: $0.filename) }
        self.internalString = "snapwell:" + orderedIds.joined(separator: ",")
    }
}

private struct GridDragSourceRepresentable: NSViewRepresentable {
    let isSuppressed: Bool
    let payloadProvider: () -> GridDragExportPayload
    let previewImageProvider: () -> NSImage?
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> GridDragSourceView {
        let view = GridDragSourceView(
            payloadProvider: payloadProvider,
            previewImageProvider: previewImageProvider,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded
        )
        view.isSuppressed = isSuppressed
        return view
    }

    func updateNSView(_ nsView: GridDragSourceView, context: Context) {
        nsView.isSuppressed = isSuppressed
        nsView.payloadProvider = payloadProvider
        nsView.previewImageProvider = previewImageProvider
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
    }
}

private final class GridDragSourceView: NSView, NSDraggingSource {
    var payloadProvider: () -> GridDragExportPayload
    var previewImageProvider: () -> NSImage?
    var onDragStarted: () -> Void
    var onDragEnded: () -> Void

    var isSuppressed = false

    private var monitor: Any?
    private var mouseDownPoint: NSPoint?
    private var dragStarted = false

    init(
        payloadProvider: @escaping () -> GridDragExportPayload,
        previewImageProvider: @escaping () -> NSImage?,
        onDragStarted: @escaping () -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        self.payloadProvider = payloadProvider
        self.previewImageProvider = previewImageProvider
        self.onDragStarted = onDragStarted
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitor()
        } else {
            removeMonitor()
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        mouseDownPoint = nil
        dragStarted = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Full-screen detail overlay is open: let events pass through to
        // SwiftUI's .onDrag on DetailItemView instead of dragging the grid
        // cell beneath the overlay.
        if isSuppressed {
            mouseDownPoint = nil
            dragStarted = false
            return event
        }
        switch event.type {
        case .leftMouseDown:
            guard contains(event) else { return event }
            mouseDownPoint = event.locationInWindow
            dragStarted = false
            return event

        case .leftMouseDragged:
            guard let mouseDownPoint else { return event }
            if dragStarted { return nil }

            let dx = event.locationInWindow.x - mouseDownPoint.x
            let dy = event.locationInWindow.y - mouseDownPoint.y
            guard dx * dx + dy * dy >= 25 else { return event }

            beginDrag(with: event)
            dragStarted = true
            return nil

        case .leftMouseUp:
            mouseDownPoint = nil
            dragStarted = false
            return event

        default:
            return event
        }
    }

    private func contains(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    private func beginDrag(with event: NSEvent) {
        let payload = payloadProvider()
        guard !payload.fileURLs.isEmpty else { return }

        let previewImage = previewImageProvider()
        let draggingItems = payload.fileURLs.enumerated().map { index, url in
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
            if index == 0 {
                pasteboardItem.setString(payload.internalString, forType: .string)
            }

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let image = previewImage ?? NSWorkspace.shared.icon(forFile: url.path)
            draggingItem.setDraggingFrame(draggingFrame(for: image, index: index), contents: image)
            return draggingItem
        }

        onDragStarted()
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func draggingFrame(for image: NSImage, index: Int) -> NSRect {
        let maxWidth: CGFloat = 96
        let fallbackSize = CGSize(width: maxWidth, height: 64)
        let imageSize = image.size
        let size: CGSize
        if imageSize.width > 0, imageSize.height > 0 {
            let scale = maxWidth / imageSize.width
            size = CGSize(width: maxWidth, height: max(1, imageSize.height * scale))
        } else {
            size = fallbackSize
        }

        let offset = CGFloat(min(index, 4)) * 4
        return NSRect(
            x: bounds.midX - size.width / 2 + offset,
            y: bounds.midY - size.height / 2 - offset,
            width: size.width,
            height: size.height
        )
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownPoint = nil
        dragStarted = false
        onDragEnded()
    }
}

// MARK: - Shimmer Text

/* ─────────────────────────────────────────────────────────
 * SHIMMER ANIMATION
 *
 * A bright band sweeps left → right across the text in a
 * 2.5s cycle. The gradient starts fully off-screen left
 * (-0.6) and exits fully off-screen right (1.6), so the
 * highlight enters and leaves smoothly with no pop-in.
 * The loop-point jump is invisible (both ends off-screen).
 *
 * Gradient band width: 0.8 (phase ± 0.4)
 * Brightness:  base 0.5 → peak 1.0 → base 0.5
 * ───────────────────────────────────────────────────────── */

private enum ShimmerConfig {
    static let cycle: Double = 1.5     // seconds per sweep
    static let bandHalf: CGFloat = 0.4 // half-width of bright band
    static let rangeStart: CGFloat = -0.6
    static let rangeEnd: CGFloat = 1.6
    static let baseBrightness: CGFloat = 0.5
    static let peakBrightness: CGFloat = 1.0
}

struct ShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if reduceMotion {
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(ShimmerConfig.peakBrightness))
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: ShimmerConfig.cycle)
                    / ShimmerConfig.cycle
                let phase = t * (ShimmerConfig.rangeEnd - ShimmerConfig.rangeStart)
                    + ShimmerConfig.rangeStart

                Text(text)
                    .font(.callout)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                .white.opacity(ShimmerConfig.baseBrightness),
                                .white.opacity(ShimmerConfig.peakBrightness),
                                .white.opacity(ShimmerConfig.baseBrightness),
                            ],
                            startPoint: .init(x: phase - ShimmerConfig.bandHalf, y: 0.5),
                            endPoint: .init(x: phase + ShimmerConfig.bandHalf, y: 0.5)
                        )
                    )
            }
        }
    }
}
