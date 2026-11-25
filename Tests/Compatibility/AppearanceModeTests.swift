import SwiftUI
import Testing
@testable import Snapwell

@Suite("Appearance mode")
struct AppearanceModeTests {
    @Test("System keeps the legacy auto storage value")
    func systemRawValueCompatibility() {
        #expect(AppearanceMode.system.rawValue == "auto")
    }

    @Test("Stored modes resolve to their SwiftUI color schemes")
    func storedModesResolveColorSchemes() {
        #expect(AppearanceMode.colorScheme(for: "auto") == nil)
        #expect(AppearanceMode.colorScheme(for: "light") == .light)
        #expect(AppearanceMode.colorScheme(for: "dark") == .dark)
    }

    @Test("Unknown stored values fall back to System")
    func invalidStoredModeFallsBackToSystem() {
        #expect(AppearanceMode.colorScheme(for: "sepia") == nil)
    }
}
