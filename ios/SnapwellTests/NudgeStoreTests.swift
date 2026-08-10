import Foundation
import Testing
@testable import Snapwell

@Suite("Nudges", .tags(.model))
struct NudgeStoreTests {

    /// Scratch defaults so nothing touches the real app domain.
    private func makeStore() -> (NudgeStore, UserDefaults) {
        let suiteName = "NudgeStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (NudgeStore(defaults: defaults), defaults)
    }

    private let day: TimeInterval = 60 * 60 * 24

    // MARK: - Mac app nudge timing

    @Test("Fresh install does not see the Mac nudge on day one")
    func macNudgeWaitsForTheSecondDay() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: false)

        #expect(store.nextNudge(now: now, hasMedia: true, hasAPIKey: true) == nil)
        #expect(store.nextNudge(now: now.addingTimeInterval(60 * 60), hasMedia: true, hasAPIKey: true) == nil)
    }

    @Test("Mac nudge appears once the calendar day rolls over")
    func macNudgeAppearsOnSecondDay() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: false)

        #expect(store.nextNudge(now: now.addingTimeInterval(day), hasMedia: true, hasAPIKey: true) == .macApp)
    }

    @Test("Someone updating into this build sees the Mac nudge immediately")
    func returningUserIsEligibleRightAway() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: true)

        #expect(store.nextNudge(now: now, hasMedia: true, hasAPIKey: true) == .macApp)
    }

    @Test("First launch is stamped once and never moved")
    func stampIsIdempotent() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: false)
        // A later launch must not push the date forward, or day two never arrives.
        store.stampFirstLaunchIfNeeded(now: now.addingTimeInterval(day * 3), isReturningUser: false)

        #expect(store.nextNudge(now: now.addingTimeInterval(day), hasMedia: true, hasAPIKey: true) == .macApp)
    }

    @Test("No nudge at all before the first launch is stamped")
    func nothingWithoutAStamp() {
        let (store, _) = makeStore()

        #expect(store.nextNudge(now: Date(), hasMedia: false, hasAPIKey: true) == nil)
    }

    // MARK: - API key nudge

    @Test("API key nudge needs media and a missing key")
    func apiKeyNudgeRequiresMediaWithoutKey() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: false)

        #expect(store.nextNudge(now: now, hasMedia: false, hasAPIKey: false) == nil)
        #expect(store.nextNudge(now: now, hasMedia: true, hasAPIKey: true) == nil)
        #expect(store.nextNudge(now: now, hasMedia: true, hasAPIKey: false) == .apiKey)
    }

    @Test("API key nudge outranks the Mac nudge, which follows on the next pass")
    func apiKeyNudgeTakesPriority() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: true)

        let first = store.nextNudge(now: now, hasMedia: true, hasAPIKey: false)
        #expect(first == .apiKey)

        store.markSeen(.apiKey)
        #expect(store.nextNudge(now: now, hasMedia: true, hasAPIKey: false) == .macApp)
    }

    @Test("Saving a key clears an API-key nudge queued behind settings")
    @MainActor func savingKeyClearsQueuedNudge() {
        let state = AppState()
        state.activeNudge = .apiKey

        state.dismissAPIKeyNudgeIfConfigured(isUnlocked: true)

        #expect(state.activeNudge == nil)
    }

    @Test("Unrelated nudges and missing keys are preserved")
    @MainActor func nudgeCancellationIsScopedToConfiguredAPIKey() {
        let state = AppState()
        state.activeNudge = .apiKey
        state.dismissAPIKeyNudgeIfConfigured(isUnlocked: false)
        #expect(state.activeNudge == .apiKey)

        state.activeNudge = .macApp
        state.dismissAPIKeyNudgeIfConfigured(isUnlocked: true)
        #expect(state.activeNudge == .macApp)
    }

    // MARK: - Seen state

    @Test("Each nudge is shown at most once")
    func seenNudgesStaySuppressed() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: true)

        store.markSeen(.apiKey)
        store.markSeen(.macApp)

        #expect(store.hasSeen(.apiKey))
        #expect(store.hasSeen(.macApp))
        #expect(store.nextNudge(now: now, hasMedia: true, hasAPIKey: false) == nil)
    }

    @Test("resetAll clears seen flags and the first-launch stamp")
    func resetAllClearsEverything() {
        let (store, _) = makeStore()
        let now = Date()
        store.stampFirstLaunchIfNeeded(now: now, isReturningUser: true)
        store.markSeen(.apiKey)
        store.markSeen(.macApp)

        store.resetAll()

        #expect(!store.hasSeen(.apiKey))
        #expect(!store.hasSeen(.macApp))
        // The stamp is gone too, so the Mac nudge waits for a fresh day-two.
        #expect(store.nextNudge(now: now, hasMedia: false, hasAPIKey: true) == nil)
        #expect(store.nextNudge(now: now, hasMedia: true, hasAPIKey: false) == .apiKey)
    }
}
