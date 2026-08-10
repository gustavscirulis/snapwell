#if DEBUG
import SwiftUI
import DialKit

/// Debug-only DialKit drawer. Triggers the one-time nudge sheets on demand and
/// tunes their layout while they're on screen, so the shipped values in
/// `NudgeSheetMetrics` get chosen by looking rather than guessing.
///
/// This is the only file in the app that imports DialKit.
struct DebugDialOverlay: View {
    @Binding var metrics: NudgeSheetMetrics
    let onShowNudge: (Nudge) -> Void
    let onResetNudges: () -> Void

    @StateObject private var dial = DebugDialPanel.nudges

    var body: some View {
        DialRoot(
            position: .bottomRight,
            defaultOpen: false,
            mode: .drawer,
            storageID: "snapwell-debug"
        )
        .onAppear {
            DebugDialActions.onShowNudge = onShowNudge
            DebugDialActions.onResetNudges = onResetNudges
        }
        .onChange(of: dial.values) { _, newValue in
            metrics = newValue
        }
    }
}

/// `DialPanelState` registers itself with DialKit's global store on init, and
/// SwiftUI re-runs view initialisers freely — so the panel is built once here
/// rather than inline in the view, which would register a duplicate every pass.
@MainActor
private enum DebugDialPanel {
    static let nudges = DialPanelState(
        name: "Nudges",
        initial: NudgeSheetMetrics(),
        controls: [
            .slider("imageCornerRadius", keyPath: \.imageCornerRadius, range: 0...32, step: 1, unit: "pt"),
            .slider("contentSpacing", keyPath: \.contentSpacing, range: 8...40, step: 4, unit: "pt"),
            .slider("bodyOpacity", keyPath: \.bodyOpacity, range: 0.3...1.0, step: 0.05),
            .group("shadow", children: [
                .slider("radius", keyPath: \.shadowRadius, range: 0...60, step: 1, unit: "pt"),
                .slider("y", keyPath: \.shadowY, range: 0...40, step: 1, unit: "pt"),
                .slider("opacity", keyPath: \.shadowOpacity, range: 0...1, step: 0.05)
            ]),
            .group("show", children: [
                .action("macApp"),
                .action("apiKey"),
                .action("resetSeen")
            ])
        ],
        onAction: { path in
            Task { @MainActor in
                switch path {
                case "show.macApp": DebugDialActions.onShowNudge?(.macApp)
                case "show.apiKey": DebugDialActions.onShowNudge?(.apiKey)
                case "show.resetSeen": DebugDialActions.onResetNudges?()
                default: break
                }
            }
        }
    )
}

/// Indirection so the long-lived panel above can reach the current view's
/// callbacks without capturing them at init time.
@MainActor
private enum DebugDialActions {
    static var onShowNudge: ((Nudge) -> Void)?
    static var onResetNudges: (() -> Void)?
}
#endif
