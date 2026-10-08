import AVFoundation
import SwiftUI

// MARK: - Display State

enum VideoDisplayState: Equatable {
    case hidden
    case grid
}

// MARK: - VideoPreviewManager

/// Manages a single AVPlayer for grid hover video previews.
/// The visual hover overlay has a separate lifetime from playback, so its native
/// animations stay continuous across player creation and cleanup.
/// Grid hover only — detail views manage their own players.
@Observable
@MainActor
final class VideoPreviewManager {
    /// The currently active preview player
    private(set) var player: AVPlayer?

    /// The media item ID whose video is currently loaded
    private(set) var activeItemId: String?

    /// The visual hover overlay starts immediately, before the playback dwell completes.
    /// Its identity survives player creation, so pills and lift never restart at that seam.
    private(set) var hoverItemId: String?
    private(set) var isHovering = false

    /// Current display mode for the floating video layer
    private(set) var displayState: VideoDisplayState = .hidden

    /// Resting cell bounds; views apply their hover transform without changing these.
    var currentFrame: CGRect = .zero

    /// Resting corner radius, shared by the cell and floating overlay.
    var cornerRadius: CGFloat = 12

    /// The grid cell's live global frame — updated continuously by GridItemView
    private(set) var gridItemFrame: CGRect = .zero

    /// Pattern names to display on the floating layer during grid hover
    private(set) var gridPatternNames: [String] = []

    /// Whether the previewed item is currently being analyzed
    private(set) var isAnalyzing: Bool = false

    /// Whether the previewed item has a failed analysis (shows retry badge on floating layer)
    private(set) var hasAnalysisError: Bool = false

    private var loopObserver: NSObjectProtocol?
    private var hoverDismissTask: Task<Void, Never>?

    // MARK: - Grid Hover

    func beginHover(itemId: String, frame: CGRect, patternNames: [String], isAnalyzing: Bool, hasAnalysisError: Bool) {
        if hoverItemId != itemId { stopPreview() }
        hoverDismissTask?.cancel()
        hoverDismissTask = nil
        hoverItemId = itemId
        isHovering = true
        if activeItemId == itemId { player?.play() }
        gridItemFrame = frame
        currentFrame = frame
        cornerRadius = 12
        gridPatternNames = patternNames
        self.isAnalyzing = isAnalyzing
        self.hasAnalysisError = hasAnalysisError
    }

    /// Retain the same overlay while its exit spring settles. Re-entry cancels removal.
    func endHover(itemId: String) {
        guard hoverItemId == itemId, isHovering else { return }
        isHovering = false
        player?.pause()
        hoverDismissTask?.cancel()
        hoverDismissTask = Task {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard hoverItemId == itemId, !isHovering else { return }
            stopPreview()
        }
    }

    /// Start hover preview — creates player, positions floating layer at grid cell
    func startPreview(itemId: String, url: URL, frame: CGRect, patternNames: [String] = [], isAnalyzing: Bool = false, hasAnalysisError: Bool = false) {
        if activeItemId == itemId, player != nil {
            gridItemFrame = frame
            if displayState == .grid {
                currentFrame = frame
            }
            return
        }

        if hoverItemId != itemId {
            beginHover(itemId: itemId, frame: frame, patternNames: patternNames,
                       isAnalyzing: isAnalyzing, hasAnalysisError: hasAnalysisError)
        }
        cleanupPlayer()

        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        player = newPlayer
        activeItemId = itemId
        gridItemFrame = frame
        gridPatternNames = patternNames
        self.isAnalyzing = isAnalyzing
        self.hasAnalysisError = hasAnalysisError
        currentFrame = frame
        cornerRadius = 12
        displayState = .grid

        addLoopObserver(for: newPlayer)
        newPlayer.play()
    }

    /// Update the grid cell's live frame (scroll, resize)
    func updateGridFrame(_ frame: CGRect) {
        gridItemFrame = frame
        if hoverItemId != nil || displayState == .grid {
            currentFrame = frame
        }
    }

    /// Update analysis state for the currently previewed item (called reactively from GridItemView)
    func updateAnalysisState(isAnalyzing: Bool, hasError: Bool) {
        self.isAnalyzing = isAnalyzing
        self.hasAnalysisError = hasError
    }

    /// Stop hover preview
    func stopPreview() {
        displayState = .hidden
        cleanupPlayer()
        hoverDismissTask?.cancel()
        hoverDismissTask = nil
        hoverItemId = nil
        isHovering = false
        gridPatternNames = []
        isAnalyzing = false
        hasAnalysisError = false
    }

    // MARK: - Private

    private func cleanupPlayer() {
        removeLoopObserver()
        player?.pause()
        player = nil
        activeItemId = nil
    }

    private func addLoopObserver(for player: AVPlayer?) {
        removeLoopObserver()
        guard let player else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    private func removeLoopObserver() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }
}
