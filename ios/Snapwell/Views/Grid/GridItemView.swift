import SwiftUI

private struct GridSpacesKey: EnvironmentKey {
    static let defaultValue: [Space] = []
}

extension EnvironmentValues {
    /// Passed through the environment rather than as a stored property on `GridItemView`, so the
    /// array is not compared element-by-element for every cell on every update pass.
    var gridSpaces: [Space] {
        get { self[GridSpacesKey.self] }
        set { self[GridSpacesKey.self] = newValue }
    }
}

struct DetailGridViewportReporter: ViewModifier {
    let host: DetailHost
    @Environment(AppState.self) private var appState
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { geo in geo.frame(in: .global) } action: { newFrame in
                frame = newFrame
                publish()
            }
            .onChange(of: appState.showOverlay) { _, _ in publish() }
            .onChange(of: appState.detailHost) { _, _ in publish() }
    }

    private func publish() {
        guard appState.showOverlay, appState.detailHost == host else { return }
        if appState.detailGridViewport != frame {
            appState.detailGridViewport = frame
        }
    }
}

struct GridItemView: View {
    let item: MediaItem
    let width: CGFloat
    let detailHost: DetailHost
    var isSelected: Bool = false
    var onSelect: ((MediaItem, CGRect, UIImage?) -> Void)?
    var onRetryAnalysis: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?
    var onAssignToSpace: ((String, String?) -> Void)?
    @Environment(AppState.self) private var appState
    @Environment(\.gridSpaces) private var spaces
    @State private var thumbnail: UIImage?
    @State private var loadFailed = false
    @State private var globalFrame: CGRect = .zero

    private var height: CGFloat {
        width / item.gridAspectRatio
    }

    private var targetPixelWidth: CGFloat {
        width * UIScreen.main.scale
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail image
            if let thumbnail {
                let imageHeight = thumbnail.size.height > 0
                    ? width * (thumbnail.size.height / thumbnail.size.width)
                    : height
                Image(uiImage: thumbnail)
                    .resizable()
                    .frame(width: width, height: imageHeight)
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
                    .transition(.opacity)
            } else if loadFailed {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: width, height: height)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Tap to retry")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .onTapGesture {
                        loadFailed = false
                    Task { await loadThumbnail() }
                    }
            } else {
                Rectangle()
                    .fill(Color.snapDarkMuted)
                    .frame(width: width, height: height)
            }

            // Video indicator
            if item.isVideo {
                HStack {
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityHidden(true)
            }

            // Analysis state overlay
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
                .frame(width: width, height: height)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity
                    )
                )
            }
        }
        .frame(width: width, height: height)
        .animation(SnapSpring.resolvedStandard, value: item.isAnalyzing)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(item.isVideo ? "Video" : "Image")
        .accessibilityHint("Double tap to view full screen")
        .opacity(isSelected ? 0 : 1)
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let frame = geo.frame(in: .global)
                        onSelect?(item, frame, thumbnail)
                    }
            }
        )
        .onGeometryChange(for: CGRect.self) { geo in
            geo.frame(in: .global)
        } action: { frame in
            globalFrame = frame
            updateDetailTarget()
        }
        .onChange(of: appState.selectedItemId) { _, _ in updateDetailTarget() }
        .onChange(of: appState.detailGridViewport) { _, _ in updateDetailTarget() }
        .onChange(of: appState.showOverlay) { _, _ in updateDetailTarget() }
        .onDisappear {
            if appState.detailGridTarget?.itemID == item.id,
               appState.detailGridTarget?.host == detailHost {
                appState.detailGridTarget = nil
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !item.isAnalyzing && item.analysisError != nil {
                Button {
                    onRetryAnalysis?()
                } label: {
                    retryBadge
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
                .contentShape(Rectangle())
                .accessibilityLabel("Retry analysis")
                .accessibilityHint("Analyzes this item again")
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .contextMenu {
            Button {
                onShare?()
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }

            Button {
                onRetryAnalysis?()
            } label: {
                Label("Redo Analysis", systemImage: "arrow.clockwise")
            }

            if !spaces.isEmpty {
                Menu {
                    ForEach(spaces) { space in
                        Button {
                            onAssignToSpace?(item.id, space.id)
                        } label: {
                            if item.belongs(to: space.id) {
                                Label(space.name, systemImage: "checkmark")
                            } else {
                                Text(space.name)
                            }
                        }
                    }
                    if !item.spaces.isEmpty {
                        Divider()
                        Button {
                            onAssignToSpace?(item.id, nil)
                        } label: {
                            Label("Remove from All Spaces", systemImage: "folder.badge.minus")
                        }
                    }
                } label: {
                    Label("Update Spaces", systemImage: "folder.badge.plus")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            await loadThumbnail()
        }
        .onChange(of: isSelected) { wasSelected, isNowSelected in
            // Retry thumbnail load after returning from full-screen overlay
            // if the iCloud file has since downloaded
            if wasSelected && !isNowSelected && thumbnail == nil {
                Task { await loadThumbnail() }
            }
        }
    }

    // MARK: - Thumbnail Loading

    private func updateDetailTarget() {
        guard appState.showOverlay,
              appState.detailHost == detailHost,
              appState.selectedItemId == item.id else { return }
        let target = DetailGridTarget.visible(
            itemID: item.id,
            host: detailHost,
            frame: globalFrame,
            viewport: appState.detailGridViewport
        )
        if appState.detailGridTarget != target {
            appState.detailGridTarget = target
        }
    }

    @ViewBuilder
    private var shimmerBadge: some View {
        let base = ShimmerText("Analyzing...")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

        if #available(iOS 26, *) {
            base
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        } else {
            base
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .environment(\.colorScheme, .dark)
        }
    }

    private var retryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
            Text("Retry")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.red, in: RoundedRectangle(cornerRadius: 10))
    }

    private func loadThumbnail() async {
        let cache = ThumbnailCache.shared
        let thumbURL = item.thumbnailURL
        let mediaURL = item.mediaURL
        let pixelWidth = targetPixelWidth
        let loaded = await withTaskGroup(of: UIImage?.self, returning: UIImage?.self) { group in
            if let thumbURL {
                group.addTask {
                    await cache.loadImageWhenReady(for: thumbURL, timeout: 180, targetPixelWidth: pixelWidth).image
                }
            }
            if let mediaURL {
                group.addTask {
                    await cache.loadImageWhenReady(for: mediaURL, timeout: 180, targetPixelWidth: pixelWidth).image
                }
            }
            while let image = await group.next() {
                if let image {
                    group.cancelAll()
                    return image
                }
            }
            return nil
        }
        guard !Task.isCancelled else { return }
        if let loaded {
            withAnimation(.easeIn(duration: 0.25)) { thumbnail = loaded }
        } else {
            loadFailed = true
        }
    }
}

// MARK: - Shimmer Text

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

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if UIAccessibility.isReduceMotionEnabled {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: ShimmerConfig.cycle)
                    / ShimmerConfig.cycle
                let phase = t * (ShimmerConfig.rangeEnd - ShimmerConfig.rangeStart)
                    + ShimmerConfig.rangeStart

                Text(text)
                    .font(.caption2)
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
