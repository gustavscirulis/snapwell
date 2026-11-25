import SwiftUI
import UIKit

extension Color {
    // The primary app surface follows iOS exactly: white in Light and black in Dark.
    static let snapBackground = Color(uiColor: .systemBackground)

    // Light mode uses only native iOS semantic colors. Dark mode preserves Snapwell's
    // established palette while retaining increased-contrast variants.

    static let snapForeground = adaptiveColor(
        light: .label,
        dark: UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
    )

    static let snapCard = adaptiveColor(
        light: .secondarySystemBackground,
        dark: UIColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1),
        highContrastDark: UIColor(red: 0.098, green: 0.098, blue: 0.098, alpha: 1)
    )

    static let snapMuted = adaptiveColor(
        light: .tertiarySystemFill,
        dark: UIColor(red: 0.173, green: 0.173, blue: 0.173, alpha: 1),
        highContrastDark: UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    )

    static let snapMutedForeground = adaptiveColor(
        light: .secondaryLabel,
        dark: UIColor(red: 0.651, green: 0.651, blue: 0.651, alpha: 1),
        highContrastDark: UIColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1)
    )

    static let snapBorder = adaptiveColor(
        light: .separator,
        dark: UIColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1),
        highContrastDark: UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)
    )

    // Media detail remains a dark viewing surface in every app appearance.
    static let snapMediaPlaceholder = Color(
        uiColor: UIColor(red: 0.173, green: 0.173, blue: 0.173, alpha: 1)
    )

    private static func adaptiveColor(
        light: UIColor,
        dark: UIColor,
        highContrastDark: UIColor? = nil
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            if isDark {
                return isHighContrast ? highContrastDark ?? dark : dark
            }
            return light.resolvedColor(with: traits)
        })
    }
}
