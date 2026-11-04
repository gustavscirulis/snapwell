import Foundation
import Observation

/// Device-local browsing order. Only the enabled flag survives app launches.
@Observable
@MainActor
final class LibraryShufflePreferences {
    static let storageKey = "libraryShuffleEnabled"

    private let defaults: UserDefaults
    private let nextSeed: () -> UInt64
    private var storedEnabled: Bool
    private(set) var seed: UInt64
    private(set) var generation = 0

    var isEnabled: Bool {
        get { storedEnabled }
        set {
            guard newValue != storedEnabled else { return }
            if newValue { seed = nextSeed() }
            storedEnabled = newValue
            defaults.set(newValue, forKey: Self.storageKey)
            generation &+= 1
        }
    }

    init(defaults: UserDefaults = .standard, nextSeed: @escaping () -> UInt64 = LibraryShufflePreferences.randomSeed) {
        self.defaults = defaults
        self.nextSeed = nextSeed
        storedEnabled = defaults.bool(forKey: Self.storageKey)
        seed = nextSeed()
    }

    /// Call with newest-first items. Filtering a shuffled library preserves its relative order.
    func ordered<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID == String {
        guard isEnabled, items.count > 1 else { return items }
        // Decorate once, rather than hashing IDs inside the sort comparator.
        var ranked: [(item: Item, rank: UInt64)] = items.map {
            (item: $0, rank: Self.rank($0.id, seed: seed))
        }
        ranked.sort { a, b in
            if a.rank == b.rank { return a.item.id < b.item.id }
            return a.rank < b.rank
        }
        return ranked.map { $0.item }
    }

    private nonisolated static func rank(_ id: String, seed: UInt64) -> UInt64 {
        // FNV-1a for a stable ID hash, then SplitMix64's avalanche with the session seed.
        var value: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 { value = (value ^ UInt64(byte)) &* 0x100000001b3 }
        value = (value ^ seed) &+ 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }

    nonisolated static func randomSeed() -> UInt64 {
        #if SNAPWELL_AUTOMATION
        if let argument = AutomationEnvironment.argument("--snapwell-shuffle-seed"),
           let seed = UInt64(argument) { return seed }
        #endif
        return UInt64.random(in: .min ... .max)
    }
}
