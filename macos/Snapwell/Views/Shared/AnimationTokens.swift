import SwiftUI

/// Named animation presets for consistent motion across the app.
///
/// Three tiers:
///  - **fast**     — micro-interactions: hover shadows, button reveals, small state toggles
///  - **standard** — UI transitions: tab switches, toasts, selection badges, carousel slides
///  - **hero**     — page-level: detail overlay expand/collapse
///
/// All presets have reduced-motion variants that use short ease curves instead of springs.
/// Views should read `@Environment(\.accessibilityReduceMotion)` and pass it to
/// the `reduced:` overloads, or use the static lets when reduce-motion is handled elsewhere.
enum SnapSpring {
    static let fast     = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let standard = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let hero     = Animation.spring(response: 0.36, dampingFraction: 0.87)
    static let metadata = Animation.spring(response: 0.4, dampingFraction: 0.85)

    // MARK: - Reduce Motion Variants

    static func fast(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.1) : fast
    }

    static func standard(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : standard
    }

    static func hero(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.2) : hero
    }

    static func metadata(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : metadata
    }
}

/// Shared hover scale for media thumbnails and their floating video previews.
enum MediaHover {
    static let scale: CGFloat = 1.015

    /// Native springs preserve the current presentation and velocity on rapid reversals.
    /// Critical damping gives the card weight without a bounce on every hover.
    static func spring(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.12)
            : .spring(response: 0.28, dampingFraction: 1, blendDuration: 0.08)
    }

    static func pillAnimation(index: Int, entering: Bool, reduced: Bool) -> Animation {
        spring(reduced: reduced).delay(entering && !reduced ? Double(index) * 0.02 : 0)
    }
}

/// Keep the native animatable properties together, with an explicit value trigger.
struct MediaHoverEffect: ViewModifier {
    let isActive: Bool
    var isEnabled: Bool = true
    var showsShadow: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let scaled = isActive && isEnabled && !reduceMotion
        content
            .shadow(
                color: .black.opacity(showsShadow && isEnabled ? (isActive ? 0.1 : 0.05) : 0),
                radius: isActive ? 6 : 2,
                x: 0,
                y: isActive ? 4 : 1
            )
            .scaleEffect(scaled ? MediaHover.scale : 1)
            .animation(MediaHover.spring(reduced: reduceMotion), value: isActive && isEnabled)
            .animation(MediaHover.spring(reduced: reduceMotion), value: reduceMotion)
    }
}

/// Single-stage delete animation: scale down + fade out, then animated reflow.
enum DeleteAnim {
    static let shrinkFade = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let targetScale: CGFloat = 0.8
    static let commitDelay: Duration = .milliseconds(250)

    static let reducedMotionFade = Animation.easeInOut(duration: 0.15)
    static let reducedMotionDelay: Duration = .milliseconds(200)
}
