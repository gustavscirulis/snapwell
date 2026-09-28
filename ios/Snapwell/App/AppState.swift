import SwiftUI

enum AppTab: Hashable {
    case all
    case spaces
    case search
}

enum DetailHost: Equatable {
    case all
    case search
    case space(String)
}

struct DetailGridTarget: Equatable {
    let itemID: String
    let host: DetailHost
    let frame: CGRect

    static func visible(itemID: String, host: DetailHost, frame: CGRect, viewport: CGRect) -> Self? {
        guard frame.width > 0, frame.height > 0, !viewport.isEmpty else { return nil }
        let intersection = frame.intersection(viewport)
        guard !intersection.isNull,
              intersection.width * intersection.height >= frame.width * frame.height * 0.5 else {
            return nil
        }
        return Self(itemID: itemID, host: host, frame: frame)
    }
}

@Observable
@MainActor
final class AppState {
    var selectedTab: AppTab = .all
    var detailHost: DetailHost?
    var selectedIndex: Int?
    var selectedItemId: String?
    var sourceRect: CGRect = .zero
    var thumbnailImage: UIImage?
    var detailGridTarget: DetailGridTarget?
    var detailGridViewport: CGRect = .zero
    var showOverlay = false
    var pendingSearchActivation = false
    var pendingSearchPattern: String?
    var pendingGlobalSearch = false
    var activeSpaceId: String? = nil
    var searchSpaceId: String? = nil
    var searchText = ""
    var searchScores: [String: Double] = [:]
    var searchScoresQuery = ""
    var showPhotosPicker = false
    var showFilesPicker = false
    var isImporting = false
    var importStage = ""
    var importCompletedCount = 0
    var importTotalCount = 0
    var importMessage: String?
    var itemToDelete: MediaItem?
    var shareItem: URL?
    var activeNudge: Nudge?
    var showAISettings = false
    var opensAISettingsAfterNudge = false

    func dismissAPIKeyNudgeIfConfigured(isConfigured: Bool) {
        guard isConfigured, activeNudge == .apiKey else { return }
        activeNudge = nil
    }

    func queuePatternSearch(_ pattern: String) {
        pendingSearchPattern = pattern
        pendingSearchActivation = true
        pendingGlobalSearch = true
    }

    func applyPendingSearchIfNeeded(prefersDedicatedSearchTab: Bool) {
        guard pendingSearchActivation else {
            pendingGlobalSearch = false
            return
        }

        if let pendingSearchPattern {
            searchText = pendingSearchPattern
        }

        selectedTab = prefersDedicatedSearchTab ? .search : .all
        pendingSearchPattern = nil
        pendingSearchActivation = false
    }
}
