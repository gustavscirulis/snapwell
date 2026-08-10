import SwiftUI

/// Layout values for the nudge sheets. Defaults are the shipped values; the
/// DEBUG-only DialKit panel binds to these so they can be tuned on-screen.
struct NudgeSheetMetrics: Codable, Equatable {
    var imageCornerRadius: Double = 12
    var contentSpacing: Double = 24
    var bodyOpacity: Double = 0.7
    var shadowRadius: Double = 30
    var shadowY: Double = 16
    var shadowOpacity: Double = 0.9
}

/// A one-time prompt shown over the library. Deliberately plain: one screen,
/// one prominent action, and an obvious way out.
struct NudgeSheetView: View {
    let nudge: Nudge
    var metrics = NudgeSheetMetrics()
    var onOpenAISettings: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let appStoreURL = URL(string: "https://apps.apple.com/us/app/snapwell/id6762541353")!

    private var bodyOpacity: Double {
        contrast == .increased ? max(metrics.bodyOpacity, 0.85) : metrics.bodyOpacity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.contentSpacing) {
                artwork

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.white.opacity(bodyOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    primaryAction
                    Button("Not now") { dismiss() }
                        .buttonStyle(NudgeSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.snapDarkCard)
    }

    /// Proportional rather than fixed heights, so both buttons stay above the
    /// fold on every device while large text sizes fall back to scrolling.
    private var detents: Set<PresentationDetent> {
        // At accessibility sizes nothing fits a partial sheet, so open expanded
        // rather than leaving the primary action below the fold.
        guard !dynamicTypeSize.isAccessibilitySize else { return [.large] }

        switch nudge {
        case .macApp: return [.fraction(0.62), .large]
        case .apiKey: return [.fraction(0.48), .large]
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var artwork: some View {
        switch nudge {
        case .macApp:
            Image("MacAppPromo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                // At accessibility sizes the text needs the room more than the
                // screenshot does, so it gives some back rather than pushing the
                // buttons another screenful down.
                .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 150 : nil)
                .clipShape(RoundedRectangle(cornerRadius: metrics.imageCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.imageCornerRadius)
                        .stroke(Color.snapDarkBorder, lineWidth: 1)
                )
                // Lifts the screenshot off the sheet — both are dark, so the
                // hairline alone doesn't separate them.
                .shadow(
                    color: .black.opacity(metrics.shadowOpacity),
                    radius: metrics.shadowRadius,
                    y: metrics.shadowY
                )
                .accessibilityLabel("Snapwell on a Mac, showing a grid of saved images and videos")
        case .apiKey:
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
    }

    // Copy mirrors the marketing site's voice and its settled phrasing for both
    // of these ideas — see site/src/app/page.tsx.
    private var title: String {
        switch nudge {
        case .macApp: "The same library, on your Mac"
        case .apiKey: "Turn on AI analysis"
        }
    }

    private var message: String {
        switch nudge {
        case .macApp:
            "Everything moves over your own iCloud, so whatever you save here is already there the next time you open your Mac."
        case .apiKey:
            "AI describes and tags everything you save, so you can find anything by what’s in it. Bring your own key for OpenAI, Claude, Gemini, or OpenRouter."
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch nudge {
        case .macApp:
            // ShareLink puts AirDrop first when a Mac is nearby, which is the
            // shortest path from this sheet to the app open on that Mac.
            ShareLink(item: Self.appStoreURL) {
                Text("Send to my Mac")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.white)
            .foregroundStyle(.black)

        case .apiKey:
            Button {
                onOpenAISettings()
                dismiss()
            } label: {
                Text("Set Up AI")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.white)
            .foregroundStyle(.black)
        }
    }
}

/// `.plain` gives a custom label no pressed state at all, which reads dead.
/// This responds on touch-down, the way everything else in the app does.
private struct NudgeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.4 : 0.6))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview("Mac app") {
    Color.snapDarkBackground
        .sheet(isPresented: .constant(true)) {
            NudgeSheetView(nudge: .macApp)
        }
}

#Preview("API key") {
    Color.snapDarkBackground
        .sheet(isPresented: .constant(true)) {
            NudgeSheetView(nudge: .apiKey)
        }
}
