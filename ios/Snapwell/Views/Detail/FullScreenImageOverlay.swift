import SwiftUI
import AVKit

/* ─────────────────────────────────────────────────────────
 * ANIMATION STORYBOARD — Thumbnail → Detail Hero (iOS)
 *
 * OPEN
 *    0ms   thumbnail hidden, backdrop 0 → 1.0
 *          hero image springs from sourceRect → finalFrame
 *
 * SETTLED (after hero completes)
 *          Image centered; details peek in when there is room
 *          Swipe horizontal to navigate, drag down to dismiss
 *          Pinch/double-tap to zoom
 *
 * CLOSE (hero back to grid)
 *    0ms   switch to hero image, backdrop 1.0 → 0
 *          hero springs back to a frozen visible grid target
 *  ~360ms  overlay removed
 *
 * CLOSE (when grid cell not visible)
 *    0ms   media shrinks in place and fades
 *  ~200ms  overlay removed
 *
 * METADATA REVEAL
 *    After hero animation completes, details appear in order:
 *    narrative → patterns → file info.
 * ───────────────────────────────────────────────────────── */

enum MetadataReveal {
    static let narrativeDelay:   Duration = .milliseconds(100)
    static let patternsDelay:    Duration = .milliseconds(300)
    static let tagStagger:       Double   = 0.05
    static let recordDelay:      Duration = .milliseconds(600)
    static let slideDistance:    CGFloat  = 8
}

private enum DetailTransitionPhase {
    case opening, settled, closingToGrid, closingCentered

    var isClosing: Bool { self == .closingToGrid || self == .closingCentered }
}

enum DetailHeroCrop {
    static func tallestBox(_ boxes: CGSize...) -> CGSize {
        boxes.filter { $0.width > 0 && $0.height > 0 }
            .max { $0.height / $0.width < $1.height / $1.width } ?? .zero
    }

    static func sliceHeight(pixelWidth: CGFloat, pixelHeight: CGFloat, covering box: CGSize) -> Int? {
        guard pixelWidth > 0, pixelHeight > 0, box.width > 0, box.height > 0 else { return nil }
        let needed = Int((pixelWidth * box.height / box.width).rounded(.up))
        return needed < Int(pixelHeight) ? needed : nil
    }

    static func topSlice(_ image: UIImage, covering box: CGSize) -> UIImage {
        guard let cgImage = image.cgImage,
              let height = sliceHeight(
                pixelWidth: CGFloat(cgImage.width), pixelHeight: CGFloat(cgImage.height), covering: box
              ),
              let sliced = cgImage.cropping(to: CGRect(x: 0, y: 0, width: cgImage.width, height: height))
        else { return image }
        return UIImage(cgImage: sliced, scale: image.scale, orientation: image.imageOrientation)
    }
}

enum DetailOverlayGeometry {
    static func localFrame(_ globalFrame: CGRect, in viewport: CGRect) -> CGRect {
        globalFrame.offsetBy(dx: -viewport.minX, dy: -viewport.minY)
    }

    static func localTopInset(_ globalTopY: CGFloat, in viewport: CGRect) -> CGFloat {
        max(0, globalTopY - viewport.minY)
    }

    static func displayedMediaFrame(
        _ mediaFrame: CGRect,
        in viewport: CGSize,
        scrollOffset: CGFloat,
        dragOffset: CGFloat,
        scale: CGFloat,
        swipeOffset: CGFloat
    ) -> CGRect {
        let viewportCenter = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let mediaCenter = CGPoint(x: mediaFrame.midX, y: mediaFrame.midY - scrollOffset)
        let size = CGSize(width: mediaFrame.width * scale, height: mediaFrame.height * scale)
        let center = CGPoint(
            x: viewportCenter.x + (mediaCenter.x - viewportCenter.x) * scale + swipeOffset,
            y: viewportCenter.y + (mediaCenter.y - viewportCenter.y) * scale + dragOffset
        )
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private enum DeleteAnimation {
    static let shrinkFade = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let targetScale: CGFloat = 0.8
    static let commitDelay: Duration = .milliseconds(250)
}

// MARK: - Stage Reveal Modifier

extension View {
    func stageReveal(stage: Int, threshold: Int, reduceMotion: Bool) -> some View {
        self
            .opacity(stage >= threshold ? 1 : 0)
            .offset(y: reduceMotion || stage >= threshold ? 0 : 4)
            .animation(SnapSpring.resolvedMetadata, value: stage)
    }

    @ViewBuilder
    func detailScrollTracking(contentOffset: Binding<CGFloat>) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Preserve negative rubber-band offset during a dismiss drag.
                // The closing hero needs the image's actual displayed position.
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                contentOffset.wrappedValue = newOffset
            }
        } else {
            self.onPreferenceChange(DetailScrollOffsetKey.self) { newOffset in
                contentOffset.wrappedValue = newOffset
            }
        }
    }
}

private struct DetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Full Screen Image Overlay

struct FullScreenImageOverlay: View {
    let sourceRect: CGRect
    let thumbnailImage: UIImage?
    @Binding var detailGridTarget: DetailGridTarget?
    let closeRequestID: Int
    let shareRequestID: Int
    let deleteRequestID: Int
    let topReservedGlobalY: CGFloat
    var onCurrentItemChanged: ((String) -> Void)?
    var onHeroSettledChanged: ((Bool) -> Void)?
    var onClose: () -> Void
    var onSearchPattern: ((String) -> Void)?
    var onRetryAnalysis: ((MediaItem) -> Void)?
    var onDelete: ((MediaItem) -> Bool)?

    @Environment(\.colorScheme) private var colorScheme

    /// Captured at open time — stays stable even when parent re-filters.
    @State private var items: [MediaItem]
    @State private var currentIndex: Int
    @State private var openingItemID: String?

    // The phase owns interaction and content lifecycle; this flag owns the animated endpoint.
    @State private var phase: DetailTransitionPhase = .opening
    @State private var heroAtDestination = false
    @State private var frozenCloseTargetGlobal: CGRect?
    @State private var frozenHeroStartGlobal: CGRect?
    @State private var retainScrolledContent = false
    @State private var viewportGlobalFrame: CGRect = .zero
    @State private var closeFlightTask: Task<Void, Never>?

    // Content
    @State private var image: UIImage?
    @State private var heroBitmap: UIImage?
    @State private var preparedHeroBitmap: UIImage?
    @State private var preparedHeroSourceID: ObjectIdentifier?
    @State private var preparedHeroTallness: CGFloat = 0
    @State private var pendingFullResImage: UIImage?
    @State private var isLoadingFullRes = false
    @State private var player: AVPlayer?
    @State private var loadTask: Task<Void, Never>?
    @State private var videoTask: Task<Void, Never>?

    // Swipe navigation
    @State private var swipeOffset: CGFloat = 0
    @State private var isNavigating = false
    @State private var navigationGeneration = 0
    @State private var adjacentImages: [String: UIImage] = [:]

    // Dismiss gesture
    @State private var dismissOffset: CGFloat = 0

    // Metadata reveal (scroll up to show)
    @State private var contentOffset: CGFloat = 0
    @State private var metadataStage: Int = 0
    @State private var revealTask: Task<Void, Never>?

    // Zoom state (owned here to avoid gesture conflicts with child views)
    @State private var isZoomed = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomLastScale: CGFloat = 1.0
    @State private var zoomPanOffset: CGSize = .zero
    @State private var zoomPanLastOffset: CGSize = .zero

    // Gesture mode tracking — locked per gesture
    @State private var gestureActive = false
    private enum GestureMode { case none, dismiss, scroll, swipe, zoomPan }
    @State private var gestureMode: GestureMode = .none

    @State private var isDeleting = false

    // Share sheet
    @State private var shareItem: URL?

    // Real-time gesture translation (synchronous updates, no frame delay)
    private struct GestureDrag: Equatable {
        var active: Bool = false
        var translation: CGSize = .zero
    }
    @GestureState private var gestureDrag = GestureDrag()

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private let minZoomScale: CGFloat = 1.0
    private let maxZoomScale: CGFloat = 4.0
    private let doubleTapZoomScale: CGFloat = 2.5

    /// Current item derived from index
    private var item: MediaItem { items[currentIndex] }

    private var displayImage: UIImage? {
        image ?? (item.id == openingItemID ? thumbnailImage : adjacentImages[item.id])
    }
    private var isClosing: Bool { phase.isClosing }
    private var heroComplete: Bool { phase == .settled }
    private var screenSize: CGSize { viewportGlobalFrame.size }
    private var localTopReservedInset: CGFloat {
        DetailOverlayGeometry.localTopInset(topReservedGlobalY, in: viewportGlobalFrame)
    }

    private var zoomedCornerRadius: CGFloat { isZoomed ? 0 : 16 }

    init(
        items: [MediaItem],
        startIndex: Int,
        sourceRect: CGRect,
        thumbnailImage: UIImage?,
        detailGridTarget: Binding<DetailGridTarget?>,
        closeRequestID: Int = 0,
        shareRequestID: Int = 0,
        deleteRequestID: Int = 0,
        topReservedGlobalY: CGFloat = 0,
        onCurrentItemChanged: ((String) -> Void)? = nil,
        onHeroSettledChanged: ((Bool) -> Void)? = nil,
        onClose: @escaping () -> Void,
        onSearchPattern: ((String) -> Void)? = nil,
        onRetryAnalysis: ((MediaItem) -> Void)? = nil,
        onDelete: ((MediaItem) -> Bool)? = nil
    ) {
        _items = State(initialValue: items)
        self.sourceRect = sourceRect
        self.thumbnailImage = thumbnailImage
        _detailGridTarget = detailGridTarget
        self.closeRequestID = closeRequestID
        self.shareRequestID = shareRequestID
        self.deleteRequestID = deleteRequestID
        self.topReservedGlobalY = topReservedGlobalY
        self.onCurrentItemChanged = onCurrentItemChanged
        self.onHeroSettledChanged = onHeroSettledChanged
        self.onClose = onClose
        self.onSearchPattern = onSearchPattern
        self.onRetryAnalysis = onRetryAnalysis
        self.onDelete = onDelete
        let clampedStart = items.indices.contains(startIndex) ? startIndex : 0
        _currentIndex = State(initialValue: clampedStart)
        _openingItemID = State(initialValue: items.indices.contains(clampedStart) ? items[clampedStart].id : nil)
        _image = State(initialValue: thumbnailImage)
        _heroBitmap = State(initialValue: thumbnailImage)
    }

    // MARK: - Computed Properties

    // Effective offsets: prefer @GestureState (synchronous) during active gesture,
    // fall back to @State (for animations) when gesture is inactive.

    private var effectiveSwipeOffset: CGFloat {
        if gestureDrag.active && gestureMode == .swipe {
            var proposed = gestureDrag.translation.width
            if (currentIndex == 0 && proposed > 0) ||
               (currentIndex == items.count - 1 && proposed < 0) {
                proposed *= 0.3
            }
            return proposed
        }
        return swipeOffset
    }

    private var effectiveDismissOffset: CGFloat {
        if gestureDrag.active && gestureMode == .dismiss {
            return resistedDismissOffset(for: gestureDrag.translation.height)
        }
        return dismissOffset
    }

    private var effectiveZoomPanOffset: CGSize {
        if gestureDrag.active && gestureMode == .zoomPan {
            let raw = CGSize(
                width: zoomPanLastOffset.width + gestureDrag.translation.width,
                height: zoomPanLastOffset.height + gestureDrag.translation.height
            )
            return rubberBandZoomPanOffset(raw)
        }
        return zoomPanOffset
    }

    /// Hard clamp — used as the snap-back target on gesture end.
    /// Overload without `finalFrame` recomputes it (convenience for gesture handlers).
    private var currentContentFrame: CGRect {
        heroComplete ? computeSettledFrame(for: item) : computeFinalFrame(for: item)
    }

    private func clampedZoomPanOffset(_ offset: CGSize) -> CGSize {
        clampedZoomPanOffset(offset, finalFrame: currentContentFrame)
    }

    private func clampedZoomPanOffset(_ offset: CGSize, finalFrame: CGRect) -> CGSize {
        guard zoomScale > minZoomScale else { return .zero }
        let screen = CGRect(origin: .zero, size: screenSize)
        let maxOffsetX = max(0, (finalFrame.width * zoomScale - screen.width) / 2)
        let maxOffsetY = max(0, (finalFrame.height * zoomScale - screen.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    /// Rubber-band — allows overstretch with logarithmic resistance during live gesture.
    /// Overload without `finalFrame` recomputes it (convenience for gesture handlers).
    private func rubberBandZoomPanOffset(_ offset: CGSize) -> CGSize {
        rubberBandZoomPanOffset(offset, finalFrame: currentContentFrame)
    }

    private func rubberBandZoomPanOffset(_ offset: CGSize, finalFrame: CGRect) -> CGSize {
        guard zoomScale > minZoomScale else { return .zero }
        let screen = CGRect(origin: .zero, size: screenSize)
        let maxOffsetX = max(0, (finalFrame.width * zoomScale - screen.width) / 2)
        let maxOffsetY = max(0, (finalFrame.height * zoomScale - screen.height) / 2)
        return CGSize(
            width: rubberBandAxis(offset.width, limit: maxOffsetX),
            height: rubberBandAxis(offset.height, limit: maxOffsetY)
        )
    }

    /// Applies logarithmic resistance when value exceeds ±limit
    private func rubberBandAxis(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        if value > limit {
            let overshoot = value - limit
            return limit + log2(1 + overshoot / 12) * 12
        } else if value < -limit {
            let overshoot = -value - limit
            return -limit - log2(1 + overshoot / 12) * 12
        }
        return value
    }

    /// Lets the initial pull track the finger, then adds resistance so
    /// downward dismisses feel heavier without changing gesture routing.
    private func resistedDismissOffset(for rawOffset: CGFloat) -> CGFloat {
        let offset = max(0, rawOffset)
        let freeDistance: CGFloat = 56
        guard offset > freeDistance else { return offset }

        let overshoot = offset - freeDistance
        return freeDistance + log2(1 + overshoot / 16) * 18
    }

    private var dismissVisualProgress: CGFloat {
        min(effectiveDismissOffset / 120.0, 1.0)
    }

    private var backdropOpacity: Double {
        if phase == .opening && !heroAtDestination || isClosing && !heroAtDestination { return 0 }
        let dragProgress = dismissVisualProgress
        return 1.0 - dragProgress * 0.5
    }

    private var blurOpacity: Double {
        if phase == .opening && !heroAtDestination || isClosing && !heroAtDestination { return 0 }
        let dragProgress = dismissVisualProgress
        return 1.0 - dragProgress * 0.75
    }

    private var dismissScale: CGFloat {
        let progress = min(abs(effectiveDismissOffset) / 400.0, 1.0)
        return 1.0 - progress * 0.1
    }

    private func computeFinalFrame(for mediaItem: MediaItem) -> CGRect {
        let screen = screenSize
        let maxW = screen.width - 24
        let bottomReservedInset: CGFloat = 88
        let availableHeight = max(screen.height - localTopReservedInset - bottomReservedInset, 1)
        let maxH = min(screen.height * 0.85, availableHeight)
        let itemW = max(CGFloat(mediaItem.width), 1)
        let itemH = max(CGFloat(mediaItem.height), 1)

        if !mediaItem.isVideo && mediaItem.aspectRatio < 0.5 {
            let w = min(itemW, maxW)
            let h = min(w / mediaItem.aspectRatio, maxH)
            return CGRect(
                x: (screen.width - w) / 2,
                y: localTopReservedInset,
                width: w,
                height: h
            )
        }

        let widthScale = maxW / itemW
        let heightScale = maxH / itemH
        let scale = min(widthScale, heightScale)
        let w = itemW * scale
        let h = itemH * scale
        return CGRect(
            x: (screen.width - w) / 2,
            y: localTopReservedInset + ((availableHeight - h) / 2),
            width: w,
            height: h
        )
    }

    private func computeSettledFrame(for mediaItem: MediaItem) -> CGRect {
        guard !mediaItem.isVideo && mediaItem.aspectRatio < 0.5 else {
            return computeFinalFrame(for: mediaItem)
        }
        let screen = screenSize
        let maxW = screen.width - 24
        let itemW = max(CGFloat(mediaItem.width), 1)
        let w = min(itemW, maxW)
        let h = w / mediaItem.aspectRatio
        return CGRect(
            x: (screen.width - w) / 2,
            y: localTopReservedInset,
            width: w,
            height: h
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let measuredFrame = geo.frame(in: .global)
            Group {
                if items.isEmpty {
                    Color.clear.onAppear { onClose() }
                } else if viewportGlobalFrame.isEmpty {
                    Color.clear
                } else {
                    bodyContent
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onAppear { updateViewport(measuredFrame) }
            .onChange(of: measuredFrame) { _, frame in updateViewport(frame) }
        }
        .ignoresSafeArea()
    }

    private func updateViewport(_ frame: CGRect) {
        guard !frame.isEmpty, viewportGlobalFrame != frame else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { viewportGlobalFrame = frame }
    }

    @ViewBuilder
    private var bodyContent: some View {
        let finalFrame = computeFinalFrame(for: item)
        let settledFrame = computeSettledFrame(for: item)

        ZStack {
            // 1. Backdrop — keep the underlying screen visible through blur.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .opacity(blurOpacity)
                (colorScheme == .dark ? Color.black : Color.white).opacity(0.55)
                    .opacity(backdropOpacity)
            }

            // 2. Adjacent images — only after hero, hidden during close
            if phase == .settled {
                if currentIndex > 0 {
                    adjacentItemView(for: items[currentIndex - 1])
                        .offset(x: -screenSize.width + effectiveSwipeOffset)
                }
                if currentIndex < items.count - 1 {
                    adjacentItemView(for: items[currentIndex + 1])
                        .offset(x: screenSize.width + effectiveSwipeOffset)
                }
            }

            // 3. Current content — hero image OR settled ScrollView
            if phase == .settled || (isClosing && retainScrolledContent) {
                settledContentView(finalFrame: settledFrame, heroFrame: finalFrame)
                    .offset(x: effectiveSwipeOffset)
                    .opacity(phase == .settled || heroAtDestination ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: heroAtDestination)
                    .allowsHitTesting(phase == .settled)
            }
            if phase != .settled {
                heroImage(finalFrame: finalFrame)
            }

        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .onAppear {
            impactFeedback.prepare()
            loadFullImage()
            prepareVideoIfNeeded()
            preloadAdjacentImages()
            onCurrentItemChanged?(item.id)
            prepareHeroImage(for: finalFrame.size)
        }
        .task {
            // Let the first geometry pass establish the overlay's global origin.
            await Task.yield()
            guard !Task.isCancelled, phase == .opening else { return }
            withAnimation(SnapSpring.resolvedHero) {
                heroAtDestination = true
            } completion: {
                guard phase == .opening else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    image = heroBitmap ?? image
                    phase = .settled
                }
                onHeroSettledChanged?(true)
                startMetadataReveal()
                applyPendingFullResolution(for: item.id)
            }
        }
        .onChange(of: screenSize) { _, _ in prepareHeroImage(for: computeFinalFrame(for: item).size) }
        .onDisappear {
            closeFlightTask?.cancel()
            loadTask?.cancel()
            videoTask?.cancel()
            player?.pause()
        }
        .onChange(of: closeRequestID) { oldValue, newValue in
            guard newValue != oldValue, !isClosing else { return }
            close()
        }
        .onChange(of: shareRequestID) { oldValue, newValue in
            guard newValue != oldValue else { return }
            prepareShareItem()
        }
        .onChange(of: deleteRequestID) { oldValue, newValue in
            guard newValue != oldValue, !isDeleting, !isClosing else { return }
            handleDelete()
        }
    }

    // MARK: - Hero Image (Phase A/C)

    @ViewBuilder
    private func heroImage(finalFrame: CGRect) -> some View {
        let source = DetailOverlayGeometry.localFrame(sourceRect, in: viewportGlobalFrame)
        let smallFrame = isClosing
            ? frozenCloseTargetGlobal.map { DetailOverlayGeometry.localFrame($0, in: viewportGlobalFrame) } ?? source
            : source
        let largeFrame = isClosing
            ? frozenHeroStartGlobal.map { DetailOverlayGeometry.localFrame($0, in: viewportGlobalFrame) } ?? finalFrame
            : finalFrame
        let currentFrame = heroAtDestination ? largeFrame : smallFrame
        let cornerRadius: CGFloat = heroAtDestination ? 16 : 12

        Group {
            if let bitmap = preparedHeroBitmap ?? heroBitmap {
                let scale = max(
                    currentFrame.width / max(bitmap.size.width, 1),
                    currentFrame.height / max(bitmap.size.height, 1)
                )
                Image(uiImage: bitmap)
                    .resizable()
                    .frame(width: bitmap.size.width * scale, height: bitmap.size.height * scale)
                    .frame(width: currentFrame.width, height: currentFrame.height, alignment: .top)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: currentFrame.width, height: currentFrame.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .position(x: currentFrame.midX, y: currentFrame.midY)
        .opacity(phase == .closingCentered && !heroAtDestination ? 0 : 1)
    }

    // MARK: - Settled Content View (Phase B)

    @ViewBuilder
    private func settledContentView(finalFrame: CGRect, heroFrame: CGRect) -> some View {
        let screen = CGRect(origin: .zero, size: screenSize)
        let imageBottom = heroFrame.minY + finalFrame.height
        // Keep a gap after the media and show up to 96pt of details at rest.
        // Tall media naturally push details below the first viewport.
        let metadataGap = max(48, screen.height - imageBottom - 96)
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: heroFrame.minY)

                ZStack {
                    Group {
                        if item.isVideo, let player {
                            VideoPlayer(player: player)
                                .frame(width: finalFrame.width * zoomScale, height: finalFrame.height * zoomScale)
                        } else if let displayImage {
                            Image(uiImage: displayImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: finalFrame.width * zoomScale, height: finalFrame.height * zoomScale)
                                .clipped()
                                .drawingGroup(opaque: false)
                        } else {
                            Rectangle()
                                .fill(Color.snapDarkMuted)
                                .frame(width: finalFrame.width, height: finalFrame.height)
                                .overlay {
                                    ProgressView()
                                        .tint(.white.opacity(0.3))
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: zoomedCornerRadius))
                    .scaleEffect(isDeleting ? DeleteAnimation.targetScale : 1.0)
                    .opacity(isDeleting ? 0 : 1)
                    .animation(DeleteAnimation.shrinkFade, value: isDeleting)
                    .offset(effectiveZoomPanOffset)
                }
                .frame(width: screen.width, height: finalFrame.height)

                DetailMetadataSection(
                    item: item,
                    compact: screen.width < 900,
                    stage: metadataStage,
                    onRetryAnalysis: { onRetryAnalysis?(item) },
                    onSearchPattern: { pattern in searchAndClose(pattern: pattern) }
                )
                .id(item.id)
                .frame(width: min(max(screen.width - 48, 0), 980))
                .padding(.top, metadataGap)
                .padding(.bottom, 64)
                .opacity(isDeleting || isZoomed ? 0 : metadataDismissOpacity)
                .offset(y: dismissVisualProgress * 24)
            }
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DetailScrollOffsetKey.self,
                        value: -proxy.frame(in: .named("detailScroll")).minY
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDisabled(isZoomed)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.top)
        .coordinateSpace(name: "detailScroll")
        .detailScrollTracking(contentOffset: $contentOffset)
        .contentShape(Rectangle())
        .simultaneousGesture(settledDragGesture)
        .simultaneousGesture(pinchGesture)
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    handleDoubleTap(at: value.location)
                }
        )
        .sheet(isPresented: Binding(
            get: { shareItem != nil },
            set: { if !$0 { shareItem = nil } }
        )) {
            if let url = shareItem {
                ActivityView(activityItems: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        // Dismiss visual effects
        .scaleEffect(effectiveDismissOffset > 0 ? dismissScale : 1.0)
        .offset(y: effectiveDismissOffset)
    }

    /// Copy file to temp directory so share sheet shows "Send a Copy" only (no iCloud collaboration).
    private func prepareShareItem() {
        guard let url = item.mediaURL else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            shareItem = tempURL
        } catch {
            // Fallback to original URL if copy fails
            shareItem = url
        }
    }

    // MARK: - Adjacent Item View

    @ViewBuilder
    private func adjacentItemView(for adjacentItem: MediaItem) -> some View {
        let frame = computeFinalFrame(for: adjacentItem)
        let adjImage = adjacentImages[adjacentItem.id]

        if let adjImage {
            Image(uiImage: adjImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .position(x: frame.midX, y: frame.midY)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.snapDarkMuted)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private var metadataDismissOpacity: Double {
        1.0 - min(dismissVisualProgress * 1.35, 1.0)
    }

    // MARK: - Metadata Reveal

    private func startMetadataReveal() {
        revealTask?.cancel()
        if UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeOut(duration: 0.15)) { metadataStage = 3 }
            return
        }
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: MetadataReveal.narrativeDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(SnapSpring.resolvedMetadata) { metadataStage = 1 }

            try? await Task.sleep(for: MetadataReveal.patternsDelay - MetadataReveal.narrativeDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(SnapSpring.resolvedMetadata) { metadataStage = 2 }

            try? await Task.sleep(for: MetadataReveal.recordDelay - MetadataReveal.patternsDelay)
            guard !Task.isCancelled, heroComplete else { return }
            withAnimation(SnapSpring.resolvedMetadata) { metadataStage = 3 }
        }
    }

    // MARK: - Settled Drag Gesture

    private var settledDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($gestureDrag) { value, state, _ in
                state = GestureDrag(active: true, translation: value.translation)
            }
            .onChanged { value in
                // Only lock gesture mode on first event. No @State offset
                // mutations here — the view reads @GestureState via effective*
                // computed properties. Mutating @State would schedule a second
                // (redundant) render that fights with the synchronous one.
                guard !gestureActive else { return }
                gestureActive = true

                let tx = value.translation.width
                let ty = value.translation.height

                if isZoomed {
                    gestureMode = .zoomPan
                    zoomPanLastOffset = zoomPanOffset
                } else if abs(tx) > abs(ty) + 4 {
                    gestureMode = .swipe
                } else if ty > 0 && contentOffset <= 0.5 {
                    gestureMode = .dismiss
                } else {
                    gestureMode = .scroll
                }
            }
            .onEnded { value in
                let mode = gestureMode
                let tx = value.translation.width
                let ty = value.translation.height

                // Sync @State to final gesture position. This provides
                // the starting point for end-of-gesture animations and
                // the fallback value when @GestureState resets.
                switch mode {
                case .zoomPan:
                    // Store the raw (possibly overstretched) offset so @GestureState
                    // reset doesn't jump — the spring animation below snaps it back.
                    let raw = CGSize(
                        width: zoomPanLastOffset.width + tx,
                        height: zoomPanLastOffset.height + ty
                    )
                    zoomPanOffset = rubberBandZoomPanOffset(raw)
                case .swipe:
                    var proposed = tx
                    if (currentIndex == 0 && proposed > 0) ||
                       (currentIndex == items.count - 1 && proposed < 0) {
                        proposed *= 0.3
                    }
                    swipeOffset = proposed
                case .dismiss:
                    dismissOffset = resistedDismissOffset(for: ty)
                case .scroll:
                    break
                case .none: break
                }

                gestureActive = false
                gestureMode = .none

                // Now handle end-of-gesture animations / navigation
                switch mode {
                case .zoomPan:
                    // Spring back to clamped bounds if overstretched
                    let snapped = clampedZoomPanOffset(zoomPanOffset)
                    if snapped != zoomPanOffset {
                        withAnimation(SnapSpring.resolvedStandard) {
                            zoomPanOffset = snapped
                        }
                    }
                    zoomPanLastOffset = snapped

                case .swipe:
                    let velocity = value.predictedEndTranslation.width - tx
                    let threshold = screenSize.width * 0.3
                    let velocityThreshold: CGFloat = 200

                    var newIndex = currentIndex
                    if swipeOffset < -threshold || velocity < -velocityThreshold {
                        newIndex = min(currentIndex + 1, items.count - 1)
                    } else if swipeOffset > threshold || velocity > velocityThreshold {
                        newIndex = max(currentIndex - 1, 0)
                    }

                    if newIndex != currentIndex {
                        navigateTo(newIndex)
                    } else {
                        withAnimation(SnapSpring.resolvedStandard) {
                            swipeOffset = 0
                        }
                    }

                case .dismiss:
                    if ty > 120 || value.predictedEndTranslation.height > 300 {
                        close()
                    } else {
                        withAnimation(SnapSpring.resolvedStandard) {
                            dismissOffset = 0
                        }
                    }

                case .scroll:
                    break

                case .none:
                    break
                }
            }
    }

    // MARK: - Pinch-to-Zoom Gesture

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let raw = zoomLastScale * value.magnification
                let prevZoom = zoomScale
                let newZoom = rubberBand(raw, min: minZoomScale, max: maxZoomScale)

                // Focal-point zoom: adjust pan so the pinch center stays fixed.
                // Convert startAnchor (UnitPoint 0–1) to screen coordinates.
                if prevZoom > 0 && newZoom != prevZoom {
                    let screen = UIScreen.main.bounds
                    let anchor = CGPoint(
                        x: value.startAnchor.x * screen.width,
                        y: value.startAnchor.y * screen.height
                    )
                    let finalFrame = computeFinalFrame(for: item)
                    let currentOffset = effectiveZoomPanOffset
                    let imageCenterX = finalFrame.midX + currentOffset.width
                    let imageCenterY = finalFrame.midY + currentOffset.height
                    let ratio = newZoom / prevZoom
                    let dx = -(anchor.x - imageCenterX) * (ratio - 1)
                    let dy = -(anchor.y - imageCenterY) * (ratio - 1)
                    zoomPanOffset.width += dx
                    zoomPanOffset.height += dy
                    zoomPanLastOffset.width += dx
                    zoomPanLastOffset.height += dy
                }

                zoomScale = newZoom
                let wasZoomed = isZoomed
                isZoomed = zoomScale > minZoomScale
                if isZoomed && !wasZoomed {
                    // Upgrade simultaneous drag to zoomPan so two-finger
                    // panning works during the same gesture that started the zoom.
                    if gestureActive && gestureMode != .zoomPan {
                        gestureMode = .zoomPan
                        // Subtract accumulated translation for a seamless handoff
                        zoomPanLastOffset = CGSize(
                            width: zoomPanOffset.width - gestureDrag.translation.width,
                            height: zoomPanOffset.height - gestureDrag.translation.height
                        )
                        dismissOffset = 0
                    }
                }
            }
            .onEnded { _ in
                let clamped = min(max(zoomScale, minZoomScale), maxZoomScale)
                withAnimation(SnapSpring.resolvedStandard) {
                    zoomScale = clamped
                    if clamped <= minZoomScale {
                        zoomPanOffset = .zero
                    } else {
                        zoomPanOffset = clampedZoomPanOffset(zoomPanOffset)
                    }
                }
                zoomLastScale = clamped
                isZoomed = clamped > minZoomScale
            }
    }

    // MARK: - Double-Tap to Zoom

    private func handleDoubleTap(at location: CGPoint) {
        let viewCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        withAnimation(SnapSpring.resolvedStandard) {
            if zoomScale > minZoomScale {
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                isZoomed = false
            } else {
                zoomScale = doubleTapZoomScale
                zoomLastScale = doubleTapZoomScale
                let rawOffset = CGSize(
                    width: (viewCenter.x - location.x) * (doubleTapZoomScale - 1),
                    height: (viewCenter.y - location.y) * (doubleTapZoomScale - 1)
                )
                zoomPanOffset = clampedZoomPanOffset(rawOffset)
                isZoomed = true
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func rubberBand(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        if value < minVal {
            let overshoot = minVal - value
            return minVal - log2(1 + overshoot) * 0.15
        } else if value > maxVal {
            let overshoot = value - maxVal
            return maxVal + log2(1 + overshoot) * 0.15
        }
        return value
    }

    // MARK: - Navigation

    private func navigateTo(_ newIndex: Int) {
        guard newIndex >= 0, newIndex < items.count,
              newIndex != currentIndex, !isNavigating, !isClosing else {
            withAnimation(SnapSpring.resolvedStandard) { swipeOffset = 0 }
            return
        }
        isNavigating = true
        navigationGeneration += 1
        let generation = navigationGeneration
        let direction: CGFloat = newIndex > currentIndex ? -1 : 1

        player?.pause()
        videoTask?.cancel()
        player = nil
        impactFeedback.impactOccurred()

        withAnimation(SnapSpring.resolvedStandard) {
            swipeOffset = direction * screenSize.width
        } completion: {
            guard phase == .settled, navigationGeneration == generation else { return }
            // Swap without animation
            let t = Transaction(animation: nil)
            withTransaction(t) {
                currentIndex = newIndex
                swipeOffset = 0
                pendingFullResImage = nil
                metadataStage = 3
                contentOffset = 0
                isZoomed = false
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                zoomPanLastOffset = .zero
                image = adjacentImages[items[newIndex].id]
            }

            onCurrentItemChanged?(items[newIndex].id)

            revealTask?.cancel()

            loadTask?.cancel()
            loadTask = Task {
                await loadCurrentItem()
            }
            preloadAdjacentImages()
            isNavigating = false
        }
    }

    // MARK: - Search & Close

    private func searchAndClose(pattern: String) {
        guard !isClosing else { return }
        onSearchPattern?(pattern)

        // Give the current grid a brief opportunity to publish a valid visible
        // target. If none arrives, close with the centered fallback.
        let targetId = items[currentIndex].id
        Task { @MainActor in
            for _ in 0..<20 { // 20 × 30ms = 600ms max
                try? await Task.sleep(for: .milliseconds(30))
                if detailGridTarget?.itemID == targetId {
                    break
                }
            }
            close()
        }
    }

    // MARK: - Delete

    private func handleDelete() {
        if isZoomed {
            withAnimation(SnapSpring.resolvedFast) {
                zoomScale = minZoomScale
                zoomLastScale = minZoomScale
                zoomPanOffset = .zero
                zoomPanLastOffset = .zero
                isZoomed = false
            }
        }

        let deletedIndex = currentIndex
        let deletedItem = items[deletedIndex]
        let isLastItem = deletedIndex == items.count - 1

        withAnimation(DeleteAnimation.shrinkFade) {
            isDeleting = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: DeleteAnimation.commitDelay)
            guard !Task.isCancelled, !isClosing, items.indices.contains(deletedIndex),
                  items[deletedIndex].id == deletedItem.id else { return }

            guard onDelete?(deletedItem) == true else {
                withAnimation(DeleteAnimation.shrinkFade) { isDeleting = false }
                return
            }
            videoTask?.cancel()
            pendingFullResImage = nil
            items.remove(at: deletedIndex)

            if items.isEmpty {
                onHeroSettledChanged?(false)
                onClose()
                return
            }

            if deletedIndex >= items.count {
                currentIndex = items.count - 1
            }

            onCurrentItemChanged?(items[currentIndex].id)

            player?.pause()
            player = nil
            image = adjacentImages[items[currentIndex].id]
            contentOffset = 0

            let slideFrom = isLastItem ? -screenSize.width : screenSize.width
            swipeOffset = slideFrom
            isDeleting = false
            metadataStage = 0

            withAnimation(SnapSpring.resolvedStandard) {
                swipeOffset = 0
            }

            try? await Task.sleep(for: .milliseconds(200))
            startMetadataReveal()

            loadTask?.cancel()
            loadTask = Task { await loadCurrentItem() }
            preloadAdjacentImages()

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Close

    private func close() {
        guard !isClosing else { return }
        navigationGeneration += 1
        isNavigating = false
        metadataStage = 0
        revealTask?.cancel()
        player?.pause()
        videoTask?.cancel()
        loadTask?.cancel()
        impactFeedback.impactOccurred()

        let wasSettled = phase == .settled
        let scrollAtClose = contentOffset
        let dragAtClose = dismissOffset
        let finalFrame = computeFinalFrame(for: item)
        let settledFrame = computeSettledFrame(for: item)
        let heroStart = DetailOverlayGeometry.displayedMediaFrame(
            settledFrame,
            in: screenSize,
            scrollOffset: scrollAtClose,
            dragOffset: dragAtClose,
            scale: dragAtClose > 0 ? dismissScale : 1,
            swipeOffset: effectiveSwipeOffset
        )
        frozenHeroStartGlobal = heroStart.offsetBy(
            dx: viewportGlobalFrame.minX, dy: viewportGlobalFrame.minY
        )
        retainScrolledContent = wasSettled && scrollAtClose > 4

        let closingID = item.id
        let target = detailGridTarget.flatMap { $0.itemID == closingID ? $0.frame : nil }
        frozenCloseTargetGlobal = target ?? finalFrame
            .insetBy(dx: finalFrame.width * 0.06, dy: finalFrame.height * 0.06)
            .offsetBy(dx: viewportGlobalFrame.minX, dy: viewportGlobalFrame.minY)
        heroBitmap = closingID == openingItemID
            ? (thumbnailImage ?? image)
            : (adjacentImages[closingID] ?? image)
        // Commit the hero at exactly the visible content position before shrinking it.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            phase = target == nil ? .closingCentered : .closingToGrid
            heroAtDestination = true
        }
        prepareHeroImage(for: heroStart.size)
        onHeroSettledChanged?(false)

        // Zoom is no longer interactive during the close flight.
        zoomScale = minZoomScale
        zoomLastScale = minZoomScale
        zoomPanOffset = .zero
        zoomPanLastOffset = .zero
        isZoomed = false

        closeFlightTask?.cancel()
        closeFlightTask = Task { @MainActor in
            // The hero must be laid out at the frozen displayed frame before
            // animating; otherwise insertion and endpoint changes coalesce.
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled, phase.isClosing, item.id == closingID else { return }
            withAnimation(target == nil ? .easeOut(duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.2) : SnapSpring.resolvedHero) {
                heroAtDestination = false
            } completion: {
                guard phase.isClosing, item.id == closingID else { return }
                onClose()
            }
        }
    }

    // MARK: - Image Loading

    private func prepareHeroImage(for finalSize: CGSize) {
        guard let heroBitmap else {
            preparedHeroBitmap = nil
            preparedHeroSourceID = nil
            preparedHeroTallness = 0
            return
        }
        let smallSize: CGSize = if phase.isClosing, let frozenCloseTargetGlobal {
            frozenCloseTargetGlobal.size
        } else {
            sourceRect.size
        }
        let basis = DetailHeroCrop.tallestBox(smallSize, finalSize)
        let tallness = basis.width > 0 ? basis.height / basis.width : 0
        let sourceID = ObjectIdentifier(heroBitmap)
        guard preparedHeroSourceID != sourceID || preparedHeroTallness < tallness else { return }
        preparedHeroBitmap = DetailHeroCrop.topSlice(heroBitmap, covering: basis)
        preparedHeroSourceID = sourceID
        preparedHeroTallness = tallness
    }

    private func applyPendingFullResolution(for itemID: String) {
        guard pendingFullResImage != nil else { return }
        Task { @MainActor in
            await Task.yield()
            guard phase == .settled, item.id == itemID, let pendingFullResImage else { return }
            image = pendingFullResImage
            self.pendingFullResImage = nil
        }
    }

    private func loadFullImage() {
        guard let url = item.mediaURL, !item.isVideo else {
            isLoadingFullRes = false
            return
        }
        isLoadingFullRes = true
        let expectedID = item.id
        loadTask = Task {
            let loaded = await ThumbnailCache.shared.loadImage(for: url).image
            guard !Task.isCancelled, !items.isEmpty, item.id == expectedID else { return }
            if phase == .settled {
                image = loaded
            } else if phase == .opening {
                pendingFullResImage = loaded
            }
            isLoadingFullRes = false
        }
    }

    private func loadCurrentItem() async {
        let currentItem = item

        if currentItem.isVideo {
            prepareVideoIfNeeded()
        } else {
            guard let url = currentItem.mediaURL else {
                isLoadingFullRes = false
                return
            }
            isLoadingFullRes = true
            let loaded = await ThumbnailCache.shared.loadImage(for: url).image
            if !Task.isCancelled {
                image = loaded
                isLoadingFullRes = false
            }
        }
    }

    private func prepareVideoIfNeeded() {
        guard item.isVideo, let url = item.mediaURL else { return }
        let expectedID = item.id
        videoTask?.cancel()
        videoTask = Task {
            let monitor = iCloudDownloadMonitor.shared
            if !monitor.isDownloaded(url) {
                await monitor.waitForDownload(of: url, timeout: 60)
            }
            guard !Task.isCancelled,
                  item.id == expectedID,
                  monitor.isDownloaded(url) else { return }
            let newPlayer = AVPlayer(url: url)
            self.player = newPlayer
            newPlayer.play()
        }
    }

    // MARK: - Adjacent Images

    private func preloadAdjacentImages() {
        var keepIds: Set<String> = [item.id]
        if currentIndex > 0 { keepIds.insert(items[currentIndex - 1].id) }
        if currentIndex < items.count - 1 { keepIds.insert(items[currentIndex + 1].id) }
        for key in adjacentImages.keys where !keepIds.contains(key) {
            adjacentImages.removeValue(forKey: key)
        }

        for offset in [-1, 1] {
            let idx = currentIndex + offset
            guard idx >= 0, idx < items.count else { continue }
            let adjItem = items[idx]
            if adjacentImages[adjItem.id] != nil { continue }

            let preferredURL = adjItem.thumbnailURL ?? adjItem.mediaURL
            let fallbackURL = adjItem.mediaURL
            let expectedID = adjItem.id
            let pixelWidth = screenSize.width * UIScreen.main.scale
            Task {
                guard let preferredURL else { return }
                let cache = ThumbnailCache.shared
                var preview = await cache.loadImage(
                    for: preferredURL, targetPixelWidth: pixelWidth
                ).image
                if preview == nil {
                    preview = await withTaskGroup(of: UIImage?.self, returning: UIImage?.self) { group in
                        group.addTask {
                            await cache.loadImageWhenReady(
                                for: preferredURL, timeout: 30, targetPixelWidth: pixelWidth
                            ).image
                        }
                        if let fallbackURL, fallbackURL != preferredURL {
                            group.addTask {
                                await cache.loadImageWhenReady(
                                    for: fallbackURL, timeout: 30, targetPixelWidth: pixelWidth
                                ).image
                            }
                        }
                        while let result = await group.next() {
                            if let result {
                                group.cancelAll()
                                return result
                            }
                        }
                        return nil
                    }
                }
                guard !Task.isCancelled,
                      let preview,
                      items.indices.contains(currentIndex),
                      abs((items.firstIndex(where: { $0.id == expectedID }) ?? -100) - currentIndex) == 1 else { return }
                adjacentImages[expectedID] = preview
            }
        }
    }
}
