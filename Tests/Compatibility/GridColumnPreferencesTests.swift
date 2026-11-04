import Foundation
import Testing
@testable import Snapwell

@Suite("Grid column preferences")
@MainActor
struct GridColumnPreferencesTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let domain = "GridColumnsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        try body(defaults)
    }

    @Test func defaultsMatchDeviceAndRemainLocal() {
        for device in [GridColumnPreferences.Device.phone, .pad, .mac] {
            withDefaults { defaults in
                let preferences = GridColumnPreferences(device: device, defaults: defaults)
                #expect(preferences.preferredColumnCount == (device == .phone ? 2 : 4))
            }
        }
    }

    @Test func narrowingAndWideningPreserveTheSavedPreference() {
        withDefaults { defaults in
            let preferences = GridColumnPreferences(device: .pad, defaults: defaults)
            preferences.preferredColumnCount = 8
            #expect(preferences.columns(availableWidth: 1016, spacing: 8) == 8)
            #expect(preferences.columns(availableWidth: 1015, spacing: 8) == 7)
            #expect(preferences.columns(availableWidth: 375, spacing: 8) == 2)
            #expect(preferences.columns(availableWidth: 1016, spacing: 8) == 8)
            #expect(preferences.preferredColumnCount == 8)
            #expect(defaults.integer(forKey: GridColumnPreferences.storageKey) == 8)
        }
    }

    @Test func phoneFitsFourColumnsAndRespectsPreferredMaximum() {
        withDefaults { defaults in
            let preferences = GridColumnPreferences(device: .phone, defaults: defaults)
            preferences.preferredColumnCount = 4
            #expect(preferences.columns(availableWidth: 351, spacing: 8) == 4)
            #expect(preferences.columns(availableWidth: 296, spacing: 8) == 3)
            preferences.preferredColumnCount = 2
            #expect(preferences.columns(availableWidth: 1000, spacing: 8) == 2)
            #expect(preferences.columns(availableWidth: 120, spacing: 8) == 1)
            #expect(preferences.preferredColumnCount == 2)
        }
    }

    @Test func macSpacingAndContentWidthAreIncluded() {
        #expect(GridColumnPreferences.effectiveColumns(
            preferred: 8, availableWidth: 1072, minimumItemWidth: 120, spacing: 16) == 8)
        #expect(GridColumnPreferences.effectiveColumns(
            preferred: 8, availableWidth: 1071, minimumItemWidth: 120, spacing: 16) == 7)
    }

    @Test func iosOneColumnChoiceSurvivesRecreation() {
        for device in [GridColumnPreferences.Device.phone, .pad] {
            withDefaults { defaults in
                let preferences = GridColumnPreferences(device: device, defaults: defaults)
                preferences.preferredColumnCount = 1
                #expect(preferences.columns(availableWidth: 1200, spacing: 8) == 1)
                #expect(GridColumnPreferences(device: device, defaults: defaults).preferredColumnCount == 1)
                preferences.preferredColumnCount = 0
                #expect(preferences.preferredColumnCount == 1)
            }
        }
    }

    @Test func tinyOrInvalidWidthsStillProduceOneColumn() {
        for width: CGFloat in [-10, 0, 1, 79, .nan, .infinity] {
            #expect(GridColumnPreferences.effectiveColumns(
                preferred: 4, availableWidth: width, minimumItemWidth: 80, spacing: 8) == 1)
        }
    }

    @Test func preferenceSurvivesRecreationAndZoomPersists() {
        withDefaults { defaults in
            let preferences = GridColumnPreferences(device: .mac, defaults: defaults)
            preferences.preferredColumnCount = 6
            preferences.zoomIn()
            #expect(preferences.preferredColumnCount == 5)
            preferences.zoomOut()
            #expect(GridColumnPreferences(device: .mac, defaults: defaults).preferredColumnCount == 6)
            preferences.preferredColumnCount = 1
            preferences.zoomIn()
            #expect(preferences.preferredColumnCount == 2)
            #expect(defaults.integer(forKey: GridColumnPreferences.storageKey) == 2)
            preferences.preferredColumnCount = 8
            preferences.zoomOut()
            #expect(preferences.preferredColumnCount == 8)
        }
    }

    @Test func invalidValuesAreRepairedAndDeviceBoundsAreEnforced() {
        for device in [GridColumnPreferences.Device.phone, .pad, .mac] {
            let minimum = device == .mac ? 2 : 1
            let maximum = device == .phone ? 4 : 8
            for (stored, expected) in [(1, minimum), (0, minimum), (-4, minimum), (99, maximum)] {
                withDefaults { defaults in
                    defaults.set(stored, forKey: GridColumnPreferences.storageKey)
                    let preferences = GridColumnPreferences(device: device, defaults: defaults)
                    #expect(preferences.preferredColumnCount == expected)
                    #expect(defaults.integer(forKey: GridColumnPreferences.storageKey) == expected)
                }
            }
        }
        for value: Any in ["invalid", "3", true, 2.5, [2, 3]] {
            withDefaults { defaults in
                defaults.set(value, forKey: GridColumnPreferences.storageKey)
                #expect(GridColumnPreferences(device: .mac, defaults: defaults).preferredColumnCount == 4)
            }
        }
    }

    @Test func macMigrationRunsOnlyWithoutANewPreference() {
        for (legacy, expected) in [("small", 6), ("medium", 4), ("large", 3), ("extraLarge", 2), ("unknown", 4)] {
            withDefaults { defaults in
                defaults.set(legacy, forKey: "thumbnailSize")
                let preferences = GridColumnPreferences(device: .mac, defaults: defaults)
                #expect(preferences.preferredColumnCount == expected)
                preferences.preferredColumnCount = 7
                #expect(GridColumnPreferences(device: .mac, defaults: defaults).preferredColumnCount == 7)
            }
        }
        withDefaults { defaults in
            defaults.set("small", forKey: "thumbnailSize")
            #expect(GridColumnPreferences(device: .phone, defaults: defaults).preferredColumnCount == 2)
        }
    }
}
