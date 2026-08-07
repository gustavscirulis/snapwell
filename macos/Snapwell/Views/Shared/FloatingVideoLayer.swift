import AVFoundation
import SwiftUI

// MARK: - The ONE AVPlayerLayer

/// NSView subclass that owns a single AVPlayerLayer and keeps it sized
/// to bounds on every layout pass. Uses .resizeAspect so the video is
/// never cropped — the frame is always sized to match the video's aspect
/// ratio, so .resizeAspect fills identically to .resizeAspectFill
/// without amplifying tiny aspect-ratio mismatches.
class VideoHostView: NSView {
    let playerLayer: AVPlayerLayer
    let gradientLayer: CAGradientLayer

    /// Show/hide the bottom scrim gradient (used during grid hover).
    /// Rendered as a CALayer so it composites above the AVPlayerLayer —
    /// plain SwiftUI views can't reliably render above NSViewRepresentable content.
    var showGradient: Bool = false {
        didSet { gradientLayer.isHidden = !showGradient }
    }

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect

        gradientLayer = CAGradientLayer()
        // macOS CALayer y-axis: 0 = bottom, 1 = top
        gradientLayer.colors = [
            CGColor(gray: 0, alpha: 0.35),    // darkest at bottom
            CGColor(gray: 0, alpha: 0.1),     // subtle mid
            CGColor(gray: 0, alpha: 0),       // clear
        ]
        gradientLayer.locations = [0, 0.25, 0.45]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.isHidden = true

        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        layer?.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        gradientLayer.frame = bounds
        CATransaction.commit()
    }

    // Prevent this NSView from intercepting AppKit hit tests.
    // The floating layer is purely visual — all interaction goes through
    // SwiftUI views overlaid on top.
    // Without this, the NSView can steal hover tracking from grid items
    // underneath, causing spurious onHover(false) events.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Single AVPlayerLayer that lives at the ContentView level.
/// Used for grid hover video previews only.
/// Reusable NSViewRepresentable wrapping an AVPlayerLayer.
/// Used by both FloatingVideoLayer (grid hover) and DetailItemView (detail playback).
struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer
    var showGradient: Bool = false

    func makeNSView(context: Context) -> VideoHostView {
        let view = VideoHostView(player: player)
        view.showGradient = showGradient
        return view
    }

    func updateNSView(_ nsView: VideoHostView, context: Context) {
        nsView.playerLayer.player = player
        nsView.showGradient = showGradient
    }
}

// MARK: - Hover Action Icon

/// Circular hover-action button icon with a static dark background.
/// Glass effect was removed because it adapts to the underlying image,
/// causing a visible dark→transparent shift when the button appears on hover.
/// Shared by GridItemView and the floating video layer so the delete button
/// looks identical whether or not a video preview is covering the cell.
struct HoverActionIcon: View {
    let systemName: String
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(.ultraThinMaterial, in: Circle())
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Floating Video Layer

/// A single floating video view placed at the ContentView ZStack level.
/// Shows grid hover video previews — positioned at the hovered grid cell.
struct FloatingVideoLayer: View {
    /// Deletes the previewed item(s). The layer is drawn above the grid, so
    /// the grid cell's own delete button is hidden behind it — this one takes
    /// its place while a preview is playing.
    let onDelete: (Set<String>) -> Void

    @Environment(VideoPreviewManager.self) private var videoPreview
    @Environment(AppState.self) private var appState

    /// Mirrors GridItemView.effectiveIds — act on the whole selection when the
    /// previewed item is part of a multi-selection.
    private func effectiveIds(for itemId: String) -> Set<String> {
        appState.selectedIds.contains(itemId) && appState.selectedIds.count > 1
            ? appState.selectedIds
            : [itemId]
    }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            if videoPreview.displayState == .grid, let player = videoPreview.player {
                VideoPlayerNSView(player: player, showGradient: true)
                    // Pattern pills overlay
                    .overlay {
                        if !videoPreview.gridPatternNames.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    FlowLayout(spacing: 4) {
                                        ForEach(videoPreview.gridPatternNames, id: \.self) { name in
                                            PatternPill(name: name, useGlass: false)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(8)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        Group {
                            if videoPreview.isAnalyzing {
                                ShimmerText("Analyzing...")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    .environment(\.colorScheme, .dark)
                            } else if videoPreview.hasAnalysisError {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption2)
                                    Text("Retry")
                                        .font(.caption.weight(.medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.red.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(8)
                        .allowsHitTesting(false)
                    }
                    .frame(width: videoPreview.currentFrame.width, height: videoPreview.currentFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: videoPreview.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: videoPreview.cornerRadius)
                            .strokeBorder(
                                appState.selectedIds.contains(videoPreview.activeItemId ?? "")
                                    ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                    // Everything above is decorative — it must not steal hover
                    // tracking from the grid item underneath.
                    .allowsHitTesting(false)
                    // The delete button is the one exception: it replaces the
                    // grid cell's button, which this layer is covering.
                    .overlay(alignment: .topTrailing) {
                        if let itemId = videoPreview.activeItemId {
                            Button { onDelete(effectiveIds(for: itemId)) } label: {
                                HoverActionIcon(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .accessibilityLabel("Delete")
                            .accessibilityHint("Moves this item to the trash")
                        }
                    }
                    .position(
                        x: videoPreview.currentFrame.midX - origin.x,
                        y: videoPreview.currentFrame.midY - origin.y
                    )
            }
        }
    }
}

// MARK: - Video Controls Overlay

/// Minimal controls (play/pause, scrubber, mute, time) shown on hover over video content.
struct VideoControlsOverlay: View {
    let player: AVPlayer

    @Environment(AppState.self) private var appState
    @AppStorage("videoAudioEnabled") private var videoAudioDefault: Bool = false

    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var showControls = false
    @State private var hasAudio = false
    @State private var timeObserver: Any?
    /// The player instance the time observer was added to — may differ from
    /// `player` if the player was swapped mid-navigation.
    @State private var observedPlayer: AVPlayer?
    @State private var hideTask: Task<Void, Never>?

    // Scrubbing — while a drag is in flight the time observer is ignored so
    // the thumb tracks the pointer instead of fighting playback position.
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var wasPlayingBeforeScrub = false

    /// Session override wins; otherwise follow the setting. Reading the
    /// @AppStorage directly (rather than AppState.videoAudioEnabled) is what
    /// makes this redraw when the Settings window flips the toggle.
    private var audioEnabled: Bool { appState.videoAudioOverride ?? videoAudioDefault }

    /// Position shown by the scrubber and the time label.
    private var displayTime: Double { isScrubbing ? scrubTime : currentTime }

    var body: some View {
        ZStack {
            // Full-size hover target. Without it the ZStack has no subviews
            // while the controls are hidden, collapses to zero size, and
            // .onHover never fires — so the controls could never appear.
            Color.clear
                .contentShape(Rectangle())

            if showControls {
                controlsContent
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            if hovering {
                withAnimation(.easeIn(duration: 0.15)) { showControls = true }
                scheduleHide()
            } else {
                hideTask?.cancel()
                withAnimation(.easeOut(duration: 0.3)) { showControls = false }
            }
        }
        .onTapGesture {
            togglePlayback()
            withAnimation(.easeIn(duration: 0.15)) { showControls = true }
            scheduleHide()
        }
        .onAppear { addTimeObserver() }
        .onDisappear { removeTimeObserver() }
        .onChange(of: ObjectIdentifier(player)) { _, _ in
            addTimeObserver()
            player.isMuted = !audioEnabled
            // Reset per-video playback state for the incoming player.
            isScrubbing = false
            currentTime = 0
            duration = 0
        }
        .onChange(of: audioEnabled) { _, enabled in
            player.isMuted = !enabled
        }
        .task(id: ObjectIdentifier(player)) {
            await loadAssetInfo()
        }
    }

    @ViewBuilder
    private var controlsContent: some View {
        // Center play/pause button
        Button(action: togglePlayback) {
            let icon = Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)

            if #available(macOS 26, *) {
                icon.glassEffect(.regular.interactive(), in: .circle)
            } else {
                icon
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")

        // Bottom bar: elapsed time, scrubber, mute
        VStack {
            Spacer()
            HStack(spacing: 8) {
                let timeText = Text("\(formatTime(displayTime)) / \(formatTime(duration))")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                if #available(macOS 26, *) {
                    timeText.glassEffect(.regular, in: .rect(cornerRadius: 4))
                } else {
                    timeText
                        .background(.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                scrubber

                if hasAudio {
                    muteButton
                }
            }
            .padding(8)
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = duration > 0 ? min(max(displayTime / duration, 0), 1) : 0
            let barHeight: CGFloat = isScrubbing ? 6 : 4

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: barHeight)

                Capsule()
                    .fill(.white)
                    .frame(width: width * fraction, height: barHeight)
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
            // Tall invisible hit area — the bar itself is too thin to grab.
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isScrubbing)
            // minimumDistance 0 so a plain click also seeks, and so the tap
            // never falls through to the overlay's play/pause tap gesture.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0, width > 0 else { return }
                        if !isScrubbing {
                            isScrubbing = true
                            wasPlayingBeforeScrub = player.rate > 0
                            player.pause()
                        }
                        hideTask?.cancel()
                        let position = min(max(value.location.x / width, 0), 1)
                        scrubTime = position * duration
                        seek(to: scrubTime, precise: false)
                    }
                    .onEnded { _ in
                        guard isScrubbing else { return }
                        seek(to: scrubTime, precise: true)
                        currentTime = scrubTime
                        isScrubbing = false
                        if wasPlayingBeforeScrub { player.play() }
                        scheduleHide()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formatTime(displayTime)) of \(formatTime(duration))")
        }
        .frame(height: 20)
    }

    /// Loose tolerance while dragging keeps scrubbing responsive on long
    /// videos; the final seek on release is exact.
    private func seek(to seconds: Double, precise: Bool) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if precise {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
    }

    @ViewBuilder
    private var muteButton: some View {
        Button(action: toggleMute) {
            let icon = Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)

            if #available(macOS 26, *) {
                icon.glassEffect(.regular.interactive(), in: .circle)
            } else {
                icon
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audioEnabled ? "Mute" : "Unmute")
    }

    private func toggleMute() {
        let enabled = !audioEnabled
        appState.videoAudioOverride = enabled
        player.isMuted = !enabled
        scheduleHide()
    }

    /// Loads what the controls need up front: whether there's an audio track
    /// (no track, no mute button) and the duration, so the scrubber is correct
    /// before the first periodic observer tick. Runtime-only — nothing is
    /// persisted to the model or sidecar.
    private func loadAssetInfo() async {
        guard let asset = player.currentItem?.asset else {
            hasAudio = false
            return
        }

        if let loaded = try? await asset.load(.duration), loaded.seconds.isFinite {
            duration = loaded.seconds
        }

        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        hasAudio = !(tracks?.isEmpty ?? true)
    }

    private func togglePlayback() {
        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func addTimeObserver() {
        removeTimeObserver()
        observedPlayer = player
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            Task { @MainActor [weak player] in
                if let item = player?.currentItem {
                    let dur = item.duration.seconds
                    if dur.isFinite { self.duration = dur }
                }
                // A drag in flight owns the playhead — don't fight it.
                guard !self.isScrubbing else { return }
                self.currentTime = time.seconds
                self.isPlaying = (player?.rate ?? 0) > 0
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(observer)
            timeObserver = nil
            self.observedPlayer = nil
        }
        hideTask?.cancel()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showControls = false }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        formatDuration(seconds)
    }
}

/// Shared duration formatting: "m:ss"
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = Int(seconds)
    return "\(total / 60):\(String(format: "%02d", total % 60))"
}
