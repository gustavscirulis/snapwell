import SwiftUI
import AVFoundation

enum DetailCoordinateSpace {
    static let splitViewRoot = "DetailSplitViewRoot"
}

/* ─────────────────────────────────────────────────────────
 * DETAIL ITEM VIEW
 *
 * Pushed via NavigationStack with .navigationTransition(.zoom).
 * Shows full-resolution image/video with metadata, swipe
 * navigation between items, and pinch-to-zoom.
 *
 * Video playback is self-contained — owns its own AVPlayer.
 * Grid hover previews are handled separately by FloatingVideoLayer.
 *
 * METADATA REVEAL
 *    After view appears, metadata fades in with staggered timing:
 *    title → pills → description → file info.
 * ───────────────────────────────────────────────────────── */

private enum MetadataReveal {
    static let titleDelay:       Duration = .milliseconds(100)
    static let pillsDelay:       Duration = .milliseconds(300)
    static let tagStagger:       Double   = 0.05
    static let descriptionDelay: Duration = .milliseconds(450)
    static let fileInfoDelay:    Duration = .milliseconds(600)
    static let slideDistance:    CGFloat  = 8
    static let spring = SnapSpring.metadata
}

struct DetailItemView: View {
    let startItemId: String
    let sourceFrame: CGRect
    let onClose: () -> Void
    let onCurrentItemChanged: ((String) -> Void)?
    let onShare: ((String, CGRect) -> Void)?
    let onRedoAnalysis: ((String) -> Void)?
    let onDelete: ((String) -> Void)?
    let onChangeSpaceMembership: ((String, SpaceMembershipAction) -> Void)?
    let spaces: [Space]
    let activeSpaceId: String?

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var items: [MediaItem]
    @State private var currentIndex: Int
    @State private var image: NSImage?
    /// Full-res bitmap that finished loading mid-hero. Held until the spring lands — see
    /// `loadFullResImageFor`.
    @State private var pendingFullResImage: NSImage?
    @State private var isLoadingFullRes = false
    @State private var swipeOffset: CGFloat = 0
    @State private var isNavigating = false
    @State private var adjacentImages: [String: NSImage] = [:]
    @State private var loadTask: Task<Void, Never>?
    @State private var lastWindowWidth: CGFloat = 800
    @State private var detailColumnLeadingInset: CGFloat = 0
    @State private var trackpadScroll = TrackpadScrollState()
    @State private var scrollOffset: CGFloat = 0
    @State private var metadataStage: Int = 0
    @State private var revealTask: Task<Void, Never>?
    @State private var navigationFallbackTask: Task<Void, Never>?
    @State private var isZoomed = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomPanDelta: CGSize = .zero

    /// false = hero image at source position, true = expanded to final frame.
    /// The spring between these two states IS the hero animation.
    @State private var isExpanded = false
    /// true = settled ScrollView layout with metadata (after hero completes).
    @State private var heroComplete = false
    @State private var isClosing = false
    /// Live source frame for close animation (updated by GridItemView during scroll).
    @State private var closeTargetFrame: CGRect
    /// Overlay's GeometryReader origin — for global↔local coordinate conversion.
    @State private var geoOrigin: CGPoint = .zero

    // Video playback — owned by this view
    @State private var videoPlayer: AVPlayer?
    @State private var videoLoopObserver: NSObjectProtocol?

    @FocusState private var isFocused: Bool

    private var currentItem: MediaItem { items[currentIndex] }

    private var pageTravelDistance: CGFloat {
        lastWindowWidth + detailColumnLeadingInset
    }

    init(
        items: [MediaItem],
        startItemId: String,
        sourceFrame: CGRect,
        onClose: @escaping () -> Void,
        onCurrentItemChanged: ((String) -> Void)? = nil,
        onShare: ((String, CGRect) -> Void)? = nil,
        onRedoAnalysis: ((String) -> Void)? = nil,
        onDelete: ((String) -> Void)? = nil,
        onChangeSpaceMembership: ((String, SpaceMembershipAction) -> Void)? = nil,
        spaces: [Space] = [],
        activeSpaceId: String? = nil
    ) {
        let startIndex = items.firstIndex(where: { $0.id == startItemId }) ?? 0
        _items = State(initialValue: items)
        self.startItemId = startItemId
        self.sourceFrame = sourceFrame
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
        _closeTargetFrame = State(initialValue: sourceFrame)
        _image = State(initialValue: ImageCacheService.shared.image(forKey: items[startIndex].id))
        self.onCurrentItemChanged = onCurrentItemChanged
        self.onShare = onShare
        self.onRedoAnalysis = onRedoAnalysis
        self.onDelete = onDelete
        self.onChangeSpaceMembership = onChangeSpaceMembership
        self.spaces = spaces
        self.activeSpaceId = activeSpaceId
    }

    var body: some View {
        // Backdrop — outside GeometryReader so it can extend under the toolbar
        ZStack {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                (colorScheme == .dark ? Color.black : Color.white).opacity(0.55)
            }
            .opacity(isExpanded ? 1.0 : 0.0)
            .ignoresSafeArea()
            .onTapGesture { triggerClose() }

        GeometryReader { geo in
            let windowSize = geo.size
            let currentGeoOrigin = geo.frame(in: .global).origin
            let detailColumnOrigin = geo.frame(in: .named(DetailCoordinateSpace.splitViewRoot)).origin
            let finalFrame = computeImageFrame(windowSize: windowSize, item: currentItem)
            let localCloseTarget = CGRect(
                x: closeTargetFrame.origin.x - currentGeoOrigin.x,
                y: closeTargetFrame.origin.y - currentGeoOrigin.y,
                width: closeTargetFrame.size.width,
                height: closeTargetFrame.size.height
            )
            let currentFrame = isExpanded ? finalFrame : localCloseTarget
            // Keep one bitmap slice for both endpoints. The image scales uniformly while the
            // animated frame reveals it from the top, instead of morphing between two crops.
            let heroCropBasis = TopCroppedImage.tallestBox(
                localCloseTarget.size,
                finalFrame.size
            )

            ZStack {
                // Adjacent images for swipe navigation (only in settled phase)
                if heroComplete && !isClosing {
                    if currentIndex > 0 {
                        adjacentItemView(for: items[currentIndex - 1], windowSize: windowSize)
                            .offset(x: -pageTravelDistance + swipeOffset)
                    }
                    if currentIndex < items.count - 1 {
                        adjacentItemView(for: items[currentIndex + 1], windowSize: windowSize)
                            .offset(x: pageTravelDistance + swipeOffset)
                    }
                }

                if heroComplete && !isClosing {
                    // SETTLED PHASE: ScrollView with image + metadata, swipe navigation
                    let settledFrame = computeSettledImageFrame(windowSize: windowSize, item: currentItem)
                    settledContent(imageFrame: settledFrame, heroFrame: finalFrame, windowSize: windowSize)
                        .offset(x: swipeOffset)
                } else if let image {
                    // HERO PHASE: Image springs from source position to final position.
                    // Uses .position() — NOT inside ScrollView, so frame animates cleanly.
                    TopCroppedImage(
                        image: image,
                        size: currentFrame.size,
                        cropBasis: heroCropBasis
                    )
                        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 12))
                        .overlay(alignment: .bottomTrailing) { loadingIndicator }
                        .onTapGesture { triggerClose() }
                        .position(x: currentFrame.midX, y: currentFrame.midY)
                }
            }
            .onChange(of: windowSize.width) { _, w in lastWindowWidth = w }
            .onChange(of: detailColumnOrigin.x) { _, x in
                detailColumnLeadingInset = max(0, x)
            }
            .onChange(of: currentGeoOrigin) { _, origin in geoOrigin = origin }
            .onChange(of: appState.detailSourceFrame) { _, newFrame in
                if let newFrame { closeTargetFrame = newFrame }
            }
            .onAppear {
                lastWindowWidth = windowSize.width
                detailColumnLeadingInset = max(0, detailColumnOrigin.x)
                geoOrigin = currentGeoOrigin
            }
        } // GeometryReader
        .ignoresSafeArea(edges: .top)
        } // ZStack (backdrop + content)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            if isZoomed {
                resetZoom()
            } else {
                triggerClose()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard heroComplete && !isNavigating && !isClosing && !isZoomed else { return .ignored }
            navigateTo(currentIndex - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard heroComplete && !isNavigating && !isClosing && !isZoomed else { return .ignored }
            navigateTo(currentIndex + 1)
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeDetail)) { _ in
            triggerClose()
        }
        // Trackpad scroll for swipe navigation
        .onChange(of: trackpadScroll.cumulativeOffset) { _, offset in
            guard heroComplete && !isClosing && !isNavigating && !isZoomed && items.count > 1 else { return }
            var proposed = offset
            if (currentIndex == 0 && proposed > 0) ||
               (currentIndex == items.count - 1 && proposed < 0) {
                proposed *= 0.3
            }
            swipeOffset = proposed
        }
        // Trackpad two-finger scroll for zoom panning
        .onChange(of: trackpadScroll.scrollDelta) { _, delta in
            guard isZoomed else { return }
            zoomPanDelta = delta
        }
        .onChange(of: trackpadScroll.phase) { _, phase in
            guard phase == .ended else { return }
            if isZoomed {
                zoomPanDelta = .zero
                trackpadScroll.reset()
            } else if heroComplete && !isClosing && !isNavigating && items.count > 1 {
                evaluateSwipeEnd()
                trackpadScroll.reset()
            } else {
                trackpadScroll.reset()
                if !isNavigating {
                    withAnimation(SnapSpring.standard(reduced: reduceMotion)) { swipeOffset = 0 }
                }
            }
        }
        .onChange(of: isZoomed) { _, zoomed in
            trackpadScroll.trackBothAxes = zoomed
            trackpadScroll.reset()
            zoomPanDelta = .zero
        }
        .onChange(of: heroComplete) { _, complete in
            if complete && !isZoomed {
                trackpadScroll.activate()
            } else if !complete {
                trackpadScroll.deactivate()
            }
        }
        .task {
            isFocused = true

            // Start hero animation — will complete and set heroComplete = true
            await openHero()
        }
        .onDisappear {
            trackpadScroll.deactivate()
            cleanupVideo()
            loadTask?.cancel()
            revealTask?.cancel()
            navigationFallbackTask?.cancel()
        }
    }

    // MARK: - Hero Phase

    /// Animate the hero open, then transition to settled layout.
    private func openHero() async {
        // Load thumbnail if needed
        if image == nil {
            await loadThumbnailFor(currentItem)
        }

        // Spring from source position to final position
        withAnimation(SnapSpring.hero(reduced: reduceMotion)) {
            isExpanded = true
        } completion: {
            // Switch to settled layout (same image at same position — invisible)
            heroComplete = true
            if let pendingFullResImage {
                image = pendingFullResImage
                self.pendingFullResImage = nil
            }
            startMetadataReveal()
        }

        // Start loading full-res in parallel with the animation
        loadTask = Task { await loadCurrentItem() }
        preloadAdjacentImages()
    }

    // MARK: - Settled Phase

    /// ScrollView layout with image + metadata. Used after the hero animation completes.
    @ViewBuilder
    private func settledContent(imageFrame: CGRect, heroFrame: CGRect, windowSize: CGSize) -> some View {
        // The first viewport belongs to the media, even for small images.
        // Metadata begins just below it and is reached by scrolling.
        let imageBottom = heroFrame.minY + imageFrame.height
        let metadataGap = max(56, windowSize.height - imageBottom + 24)

        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: heroFrame.minY)

                Group {
                    if currentItem.isVideo {
                        videoContent(frame: imageFrame)
                    } else if let image {
                        ZoomableImageView(
                            image: image,
                            frameSize: CGSize(width: imageFrame.width, height: imageFrame.height),
                            windowSize: windowSize,
                            zoomScale: $zoomScale,
                            isZoomed: $isZoomed,
                            trackpadPanDelta: $zoomPanDelta,
                            reduceMotion: reduceMotion,
                            onTap: { triggerClose() }
                        )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !currentItem.isVideo { loadingIndicator }
                }
                .onDrag { makeDragProvider() } preview: { dragPreview }
                .contextMenu { detailContextMenu(frame: imageFrame) }

                DetailMetadataSection(
                    item: currentItem,
                    compact: windowSize.width < 900,
                    stage: metadataStage
                ) { pattern in
                    appState.searchText = pattern
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        triggerClose {
                            NotificationCenter.default.post(name: .focusSearch, object: nil)
                        }
                    }
                }
                .frame(width: min(max(windowSize.width - 72, 0), 980))
                .padding(.top, metadataGap)
                .padding(.bottom, 64)
                .opacity(isZoomed ? 0 : metadataScrollOpacity)
                .animation(SnapSpring.fast, value: isZoomed)
            }
            .frame(maxWidth: .infinity)
            // Covers the gutters beside the media and the gaps around the
            // metadata. Sits behind the content, so the image, video controls
            // and metadata still get first claim on a click.
            .background { backgroundCloseTap }
        }
        // Covers whatever viewport is left when the content is shorter than
        // the window — the VStack background only spans the content itself.
        .background { backgroundCloseTap }
        .scrollDisabled(isZoomed)
        .scrollIndicators(.automatic)
        .defaultScrollAnchor(.top)
        #if compiler(>=6.3)
        .modifier(SoftScrollEdgeModifier())
        #endif
        .id(currentItem.id)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, newOffset in
            scrollOffset = newOffset
        }
    }

    /// Click-through-to-dismiss layer for the empty space around the media.
    /// Kept transparent and always placed behind content — video playback
    /// controls own their own clicks, so the surrounding background is the
    /// only place left to click to close.
    private var backgroundCloseTap: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                if isZoomed { resetZoom() } else { triggerClose() }
            }
    }

    // MARK: - Close

    private func resetViewState() {
        metadataStage = 0
        scrollOffset = 0
        pendingFullResImage = nil
        isZoomed = false
        zoomScale = 1.0
        zoomPanDelta = .zero
    }

    private func triggerClose(then afterClose: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        resetViewState()
        revealTask?.cancel()
        navigationFallbackTask?.cancel()

        if currentItem.isVideo {
            cleanupVideo()
        }

        // Instant switch from settled ScrollView back to hero image
        // (same image at same position — the switch is invisible)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            heroComplete = false
        }

        // Spring the image back to the grid thumbnail position
        withAnimation(SnapSpring.hero(reduced: reduceMotion)) {
            isExpanded = false
        } completion: {
            onClose()
            afterClose?()
        }
    }

    // MARK: - Video Content

    @ViewBuilder
    private func videoContent(frame: CGRect) -> some View {
        ZStack {
            if let player = videoPlayer {
                VideoPlayerNSView(player: player)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        VideoControlsOverlay(player: player)
                    }
            } else {
                // Placeholder while loading
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: frame.width, height: frame.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .bottomTrailing) {
            loadingIndicator
        }
    }

    // MARK: - Video Player Management

    private func startVideoPlayer(for item: MediaItem) {
        cleanupVideo()
        let url = MediaStorageService.shared.mediaURL(filename: item.filename)
        let player = AVPlayer(url: url)
        player.isMuted = !appState.videoAudioEnabled
        videoPlayer = player

        videoLoopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        player.play()
        isLoadingFullRes = false
    }

    private func cleanupVideo() {
        if let observer = videoLoopObserver {
            NotificationCenter.default.removeObserver(observer)
            videoLoopObserver = nil
        }
        videoPlayer?.pause()
        videoPlayer = nil
    }

    // MARK: - Swipe Evaluation

    private func evaluateSwipeEnd() {
        let threshold: CGFloat = 30
        let offset = swipeOffset

        if offset < -threshold && currentIndex < items.count - 1 {
            navigateTo(currentIndex + 1)
        } else if offset > threshold && currentIndex > 0 {
            navigateTo(currentIndex - 1)
        } else {
            withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
                swipeOffset = 0
            }
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ newIndex: Int) {
        guard newIndex >= 0, newIndex < items.count, newIndex != currentIndex else {
            withAnimation(SnapSpring.standard(reduced: reduceMotion)) { swipeOffset = 0 }
            return
        }
        isNavigating = true
        let direction: CGFloat = newIndex > currentIndex ? -1 : 1
        let oldItem = currentItem

        if oldItem.isVideo {
            cleanupVideo()
        }

        withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
            swipeOffset = direction * pageTravelDistance
        } completion: {
            self.completeNavigation(to: newIndex)
        }

        navigationFallbackTask?.cancel()
        navigationFallbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, isNavigating else { return }
            completeNavigation(to: newIndex)
        }
    }

    private func completeNavigation(to newIndex: Int) {
        guard isNavigating else { return }
        navigationFallbackTask?.cancel()

        let t = Transaction(animation: nil)
        withTransaction(t) {
            currentIndex = newIndex
            swipeOffset = 0
            resetViewState()

            let newItem = items[newIndex]
            image = adjacentImages[newItem.id]
                ?? ImageCacheService.shared.image(forKey: newItem.id)
        }

        onCurrentItemChanged?(items[newIndex].id)
        appState.detailItem = items[newIndex].id

        loadTask?.cancel()
        loadTask = Task {
            await loadCurrentItem()
        }

        preloadAdjacentImages()
        isNavigating = false
        startMetadataReveal()
    }

    // MARK: - Item Loading

    private func loadCurrentItem() async {
        let item = currentItem

        if item.isVideo {
            isLoadingFullRes = true
            if image == nil {
                await loadThumbnailFor(item)
            }
            startVideoPlayer(for: item)
        } else {
            if image == nil {
                await loadThumbnailFor(item)
            }
            let mediaURL = MediaStorageService.shared.mediaURL(filename: item.filename)
            if !FileManager.default.fileExists(atPath: mediaURL.path) {
                isLoadingFullRes = true
            }
            await loadFullResImageFor(item)
            withAnimation(.easeOut(duration: 0.2)) {
                isLoadingFullRes = false
            }
        }
    }

    // MARK: - Adjacent Images

    @ViewBuilder
    private func adjacentItemView(for item: MediaItem, windowSize: CGSize) -> some View {
        let frame = computeImageFrame(windowSize: windowSize, item: item)
        let adjImage = adjacentImages[item.id] ?? ImageCacheService.shared.image(forKey: item.id)

        if let adjImage {
            TopCroppedImage(image: adjImage, size: frame.size)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .position(x: windowSize.width / 2, y: windowSize.height / 2)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
                .frame(width: frame.width, height: frame.height)
                .position(x: windowSize.width / 2, y: windowSize.height / 2)
        }
    }

    private func preloadAdjacentImages() {
        let keepIds = Set(
            [currentIndex - 1, currentIndex, currentIndex + 1]
                .filter { $0 >= 0 && $0 < items.count }
                .map { items[$0].id }
        )

        for key in adjacentImages.keys where !keepIds.contains(key) {
            adjacentImages.removeValue(forKey: key)
        }

        for offset in [-1, 1] {
            let idx = currentIndex + offset
            guard idx >= 0, idx < items.count else { continue }
            let adjItem = items[idx]
            if adjacentImages[adjItem.id] != nil { continue }
            if ImageCacheService.shared.image(forKey: adjItem.id) != nil { continue }

            Task {
                if let loaded = await ImageCacheService.shared.loadThumbnail(id: adjItem.id, filename: adjItem.filename) {
                    adjacentImages[adjItem.id] = loaded
                }
            }
        }
    }

    // MARK: - Loading Indicator

    @ViewBuilder
    private var loadingIndicator: some View {
        if isLoadingFullRes {
            let base = ProgressView()
                .controlSize(.small)
                .padding(8)

            #if compiler(>=6.3)
            if #available(macOS 26, *) {
                base
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    .padding(8)
                    .transition(.opacity)
            } else {
                base
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .transition(.opacity)
            }
            #else
            base
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
                .transition(.opacity)
            #endif
        }
    }

    // MARK: - Metadata Reveal

    private func startMetadataReveal() {
        revealTask?.cancel()

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) { metadataStage = 4 }
            return
        }

        revealTask = Task { @MainActor in
            try? await Task.sleep(for: MetadataReveal.titleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 1 }

            try? await Task.sleep(for: MetadataReveal.pillsDelay - MetadataReveal.titleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 2 }

            try? await Task.sleep(for: MetadataReveal.descriptionDelay - MetadataReveal.pillsDelay)
            guard !Task.isCancelled else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 3 }

            try? await Task.sleep(for: MetadataReveal.fileInfoDelay - MetadataReveal.descriptionDelay)
            guard !Task.isCancelled else { return }
            withAnimation(MetadataReveal.spring) { metadataStage = 4 }
        }
    }

    /// Scroll-responsive opacity for metadata: starts partially transparent,
    /// becomes fully opaque after scrolling ~60pt.
    private var metadataScrollOpacity: Double {
        let fade = max(0, 1 - scrollOffset / 60)
        return 1 - 0.6 * fade
    }

    // MARK: - Frame Computation

    private func computeImageFrame(windowSize: CGSize, item: MediaItem) -> CGRect {
        let maxW = windowSize.width * 0.95
        let maxH = (windowSize.height * 0.95) - 80

        if !item.isVideo && item.aspectRatio < 0.5 {
            let w = min(CGFloat(item.width), maxW)
            let h = min(w / item.aspectRatio, windowSize.height - 80)
            return CGRect(x: (windowSize.width - w) / 2, y: 40, width: w, height: h)
        }

        let widthScale = maxW / CGFloat(item.width)
        let heightScale = maxH / CGFloat(item.height)
        let scale = item.isVideo ? min(widthScale, heightScale) : min(widthScale, heightScale, 1.0)
        let w = CGFloat(item.width) * scale
        let h = CGFloat(item.height) * scale
        return CGRect(
            x: (windowSize.width - w) / 2,
            y: (windowSize.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func computeSettledImageFrame(windowSize: CGSize, item: MediaItem) -> CGRect {
        guard !item.isVideo && item.aspectRatio < 0.5 else {
            return computeImageFrame(windowSize: windowSize, item: item)
        }
        let maxW = windowSize.width * 0.95
        let w = min(CGFloat(item.width), maxW)
        let h = w / item.aspectRatio
        return CGRect(x: (windowSize.width - w) / 2, y: 40, width: w, height: h)
    }

    // MARK: - Zoom Reset

    private func resetZoom() {
        zoomPanDelta = .zero
        withAnimation(SnapSpring.standard(reduced: reduceMotion)) {
            zoomScale = 1.0
            isZoomed = false
        }
    }

    // MARK: - Image Loading

    private func loadThumbnailFor(_ item: MediaItem) async {
        if let loaded = await ImageCacheService.shared.loadThumbnail(id: item.id, filename: item.filename) {
            self.image = loaded
        }
    }

    private func loadFullResImageFor(_ item: MediaItem) async {
        guard !item.isVideo else { return }
        let filename = item.filename
        let loaded: NSImage? = await Task.detached(priority: .utility) {
            return NSImage(contentsOf: MediaStorageService.shared.mediaURL(filename: filename))
        }.value
        if let loaded, !Task.isCancelled, items[currentIndex].id == item.id {
            // Swapping a many-megapixel bitmap in while the hero spring is still running forces
            // a re-raster mid-flight and visibly hitches it. Decode in parallel as before, but
            // hold the swap until the animation lands.
            if heroComplete {
                self.image = loaded
            } else {
                self.pendingFullResImage = loaded
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func detailContextMenu(frame: CGRect) -> some View {
        let removeFromActiveSpace: (() -> Void)? = {
            guard let activeSpaceId, currentItem.belongs(to: activeSpaceId) else {
                return nil
            }
            return { onChangeSpaceMembership?(currentItem.id, .remove(activeSpaceId)) }
        }()

        MediaItemContextMenu(
            spaces: spaces,
            activeSpaceId: activeSpaceId,
            currentSpaceIds: currentItem.orderedSpaceIDs,
            onToggleSpace: { spaceId in
                onChangeSpaceMembership?(currentItem.id, .toggle(spaceId))
            },
            onRemoveFromActiveSpace: removeFromActiveSpace,
            onShare: { onShare?(currentItem.id, frame) },
            onRedoAnalysis: { onRedoAnalysis?(currentItem.id) },
            onDelete: {
                triggerClose()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    onDelete?(currentItem.id)
                }
            }
        )
    }

    // MARK: - Drag to Export

    private func makeDragProvider() -> NSItemProvider {
        appState.isDraggingFromApp = true
        let url = MediaStorageService.shared.mediaURL(filename: currentItem.filename)
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        if let name = currentItem.analysisResult?.patterns.first?.name {
            let ext = url.pathExtension
            provider.suggestedName = ext.isEmpty ? name : "\(name).\(ext)"
        }
        return provider
    }

    private var dragPreview: some View {
        DragThumbnailPreview(image: image, aspectRatio: currentItem.aspectRatio)
    }
}


// MARK: - Detail Metadata Section

struct DetailMetadataSection: View {
    let item: MediaItem
    let compact: Bool
    let stage: Int
    var onSearchPattern: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 28) {
                    narrative
                    record
                }
            } else {
                HStack(alignment: .top, spacing: 56) {
                    narrative
                        .frame(maxWidth: .infinity, alignment: .leading)
                    record
                        .frame(width: 250)
                }
            }
        }
        .padding(compact ? 24 : 30)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primary.opacity(0.09))
        }
    }

    private var narrative: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: compact ? 26 : 30, weight: .semibold))
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
                .stageReveal(stage: stage, threshold: 1, reduced: reduceMotion)

            if item.isAnalyzing {
                statusRow("Analyzing…", icon: nil)
                    .padding(.top, 18)
            } else if item.analysisError != nil {
                statusRow("Analysis failed", icon: "exclamationmark.triangle")
                    .padding(.top, 18)
            } else if let description {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                    .stageReveal(stage: stage, threshold: 3, reduced: reduceMotion)
            }

            if let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(Array(patterns.enumerated()), id: \.element.name) { index, pattern in
                        Button {
                            onSearchPattern?(pattern.name)
                        } label: {
                            Text(pattern.name)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.primary.opacity(0.065), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Pattern: \(pattern.name)")
                        .accessibilityHint("Searches for items with this pattern")
                        .opacity(stage >= 2 ? 1 : 0)
                        .offset(y: reduceMotion || stage >= 2 ? 0 : MetadataReveal.slideDistance)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.15)
                                : MetadataReveal.spring.delay(Double(index) * MetadataReveal.tagStagger),
                            value: stage
                        )
                    }
                }
                .padding(.top, 26)
            }
        }
    }

    private var record: some View {
        VStack(spacing: 0) {
            recordRow("Added", item.createdAt.formatted(date: .abbreviated, time: .omitted))
            recordRow("Dimensions", "\(item.width) × \(item.height)", monospacedValue: true)

            let fileExtension = URL(fileURLWithPath: item.filename).pathExtension
            if !fileExtension.isEmpty {
                recordRow("Format", fileExtension.uppercased(), monospacedValue: true)
            }
            if let duration = item.duration {
                recordRow("Duration", formatDuration(duration))
            }
            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Original")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    SourceLinkButton(url: url)
                }
                .font(.system(size: 12))
                .padding(.vertical, 15)
            }
        }
        .stageReveal(stage: stage, threshold: 4, reduced: reduceMotion)
    }

    private var title: String {
        if let summary = item.analysisResult?.imageSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        return item.isVideo ? "Untitled video" : "Untitled image"
    }

    private var description: String? {
        guard let result = item.analysisResult else { return nil }
        let context = result.imageContext.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty || context == result.imageSummary ? nil : context
    }

    private func statusRow(_ label: String, icon: String?) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .stageReveal(stage: stage, threshold: 3, reduced: reduceMotion)
    }

    private func recordRow(_ label: String, _ value: String, monospacedValue: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospacedValue ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
        }
    }
}

// MARK: - Source Link Button

private struct SourceLinkButton: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    private var isXPost: Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("x.com") || host.contains("twitter.com")
    }

    private var label: String { isXPost ? "View on X" : "View source" }

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Label(label, systemImage: "arrow.up.right")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityHint("Opens the original source in your browser")
    }
}

// MARK: - Stage Reveal Modifier

private extension View {
    func stageReveal(stage: Int, threshold: Int, reduced: Bool) -> some View {
        self
            .opacity(stage >= threshold ? 1 : 0)
            .offset(y: reduced || stage >= threshold ? 0 : 4)
            .animation(reduced ? .easeOut(duration: 0.15) : MetadataReveal.spring, value: stage)
    }
}

// MARK: - Trackpad Scroll State

/// Monitors macOS scroll wheel events (two-finger trackpad swipe) and exposes
/// cumulative offset + phase as @Observable properties for SwiftUI to react to.
@Observable
@MainActor
final class TrackpadScrollState {
    private(set) var cumulativeOffset: CGFloat = 0
    private(set) var scrollDelta: CGSize = .zero
    private(set) var phase: ScrollPhase = .idle
    private var monitor: Any?
    private var isHorizontalLocked = false
    var trackBothAxes = false

    enum ScrollPhase { case idle, scrolling, ended }

    deinit {
        MainActor.assumeIsolated {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }

    func activate() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    func deactivate() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        reset()
    }

    func reset() {
        if cumulativeOffset != 0 { cumulativeOffset = 0 }
        if scrollDelta != .zero { scrollDelta = .zero }
        if phase != .idle { phase = .idle }
        isHorizontalLocked = false
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }

        if trackBothAxes {
            handleZoomPanScroll(event)
        } else {
            handleNavigationScroll(event)
        }
    }

    private func handleZoomPanScroll(_ event: NSEvent) {
        if event.phase == .began {
            scrollDelta = .zero
            phase = .scrolling
        }

        if event.phase == .changed || event.phase == .began {
            scrollDelta.width += event.scrollingDeltaX
            scrollDelta.height += event.scrollingDeltaY
            phase = .scrolling
        }

        if event.momentumPhase == .changed || event.momentumPhase == .began {
            scrollDelta.width += event.scrollingDeltaX
            scrollDelta.height += event.scrollingDeltaY
            phase = .scrolling
        }

        let fingerEnded = event.phase == .ended || event.phase == .cancelled
        let momentumEnded = event.momentumPhase == .ended

        if momentumEnded {
            phase = .ended
        } else if fingerEnded && event.momentumPhase == [] {
            phase = .ended
        }
    }

    private func handleNavigationScroll(_ event: NSEvent) {
        guard event.momentumPhase == [] else { return }

        if event.phase == .began {
            isHorizontalLocked = false
            cumulativeOffset = 0
        }

        if event.phase == .began || event.phase == .changed {
            if !isHorizontalLocked && (abs(event.scrollingDeltaX) > 2 || abs(event.scrollingDeltaY) > 2) {
                isHorizontalLocked = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            }

            if isHorizontalLocked {
                cumulativeOffset += event.scrollingDeltaX
                phase = .scrolling
            }
        }

        if event.phase == .ended || event.phase == .cancelled {
            phase = .ended
        }
    }
}
