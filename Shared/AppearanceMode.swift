import SwiftUI

/// A device-local appearance preference. System mode intentionally keeps the
/// legacy `auto` raw value so existing Mac preferences remain compatible.
enum AppearanceMode: String, CaseIterable, Sendable {
    static let storageKey = "appearanceMode"

    case system = "auto"
    case light
    case dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func colorScheme(for storedValue: String) -> ColorScheme? {
        (Self(rawValue: storedValue) ?? .system).colorScheme
    }
}
