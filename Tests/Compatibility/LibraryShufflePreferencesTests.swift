import Foundation
import Testing
@testable import Snapwell

@Suite("Library shuffle preferences")
@MainActor
struct LibraryShufflePreferencesTests {
    private struct Item: Identifiable, Equatable {
        let id: String
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let domain = "LibraryShuffleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        try body(defaults)
    }

    private var items: [Item] { (0..<40).map { Item(id: "item-\($0)") } }

    @Test func defaultsOffAndRestoresInputOrderImmediately() {
        withDefaults { defaults in
            let preferences = LibraryShufflePreferences(defaults: defaults, nextSeed: { 42 })
            #expect(!preferences.isEnabled)
            #expect(preferences.ordered(items) == items)
            preferences.isEnabled = true
            #expect(preferences.ordered(items) != items)
            preferences.isEnabled = false
            #expect(preferences.ordered(items) == items)
            #expect(!defaults.bool(forKey: LibraryShufflePreferences.storageKey))
        }
    }

    @Test func onlyFlagPersistsAndNewSessionsGetFreshSeeds() {
        withDefaults { defaults in
            var next: UInt64 = 10
            let makeSeed = { next += 1; return next }
            let first = LibraryShufflePreferences(defaults: defaults, nextSeed: makeSeed)
            first.isEnabled = true
            let firstOrder = first.ordered(items)
            let second = LibraryShufflePreferences(defaults: defaults, nextSeed: makeSeed)
            #expect(second.isEnabled)
            #expect(second.seed != first.seed)
            #expect(second.ordered(items) != firstOrder)
            #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("libraryShuffle") }
                == [LibraryShufflePreferences.storageKey])
        }
    }

    @Test func enablingRefreshesSeedButRepeatedReadsAndAssignmentsDoNot() {
        withDefaults { defaults in
            var next: UInt64 = 0
            let preferences = LibraryShufflePreferences(defaults: defaults, nextSeed: { next += 1; return next })
            let initialSeed = preferences.seed
            preferences.isEnabled = true
            let enabledSeed = preferences.seed
            let order = preferences.ordered(items)
            #expect(enabledSeed != initialSeed)
            #expect(preferences.generation == 1)
            preferences.isEnabled = true
            #expect(preferences.ordered(items) == order)
            #expect(preferences.ordered(Array(items.reversed())) == order)
            #expect(preferences.seed == enabledSeed)
            #expect(preferences.generation == 1)
            preferences.isEnabled = false
            #expect(preferences.seed == enabledSeed)
            preferences.isEnabled = true
            #expect(preferences.seed != enabledSeed)
            #expect(preferences.ordered(items) != order)
            #expect(preferences.generation == 3)
        }
    }

    @Test func shufflePreservesMembershipAndRelativeOrderAcrossLibraryChanges() {
        withDefaults { defaults in
            let preferences = LibraryShufflePreferences(defaults: defaults, nextSeed: { 42 })
            preferences.isEnabled = true
            let order = preferences.ordered(items)
            #expect(Set(order.map(\.id)) == Set(items.map(\.id)))
            #expect(order.count == items.count)
            let added = Item(id: "new-import")
            #expect(preferences.ordered([added] + items).filter { $0 != added } == order)
            let subset = items.filter { $0.id != "item-7" && $0.id != "item-15" }
            #expect(preferences.ordered(subset) == order.filter { subset.contains($0) })
            #expect(preferences.ordered([Item]()).isEmpty)
            #expect(preferences.ordered([added]) == [added])
        }
    }
}
