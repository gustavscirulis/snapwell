import Foundation

/// One-time prompts shown over the library. Ordered by priority — the first
/// eligible case wins and the rest wait for the next evaluation, so we never
/// stack two modals on top of each other.
enum Nudge: String, Identifiable, CaseIterable {
    /// You have media but no API key, so nothing is being analyzed.
    case apiKey
    /// The same library is available in the Mac app.
    case macApp

    var id: String { rawValue }
}

/// Decides which nudge (if any) to show, and remembers which ones have been seen.
/// Pure logic over UserDefaults — inject a scratch suite in tests.
struct NudgeStore {

    private static let firstLaunchKey = "nudge_firstLaunchDate_v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - First launch

    /// Records when this install started being used. Call once, early in app launch.
    ///
    /// Someone updating into this build has no recorded date but has clearly been
    /// using the app already, so they get `distantPast` — that makes them eligible
    /// for the Mac nudge right away, with no special-casing further downstream.
    func stampFirstLaunchIfNeeded(now: Date, isReturningUser: Bool) {
        guard defaults.object(forKey: Self.firstLaunchKey) == nil else { return }
        let date = isReturningUser ? Date.distantPast : now
        defaults.set(date.timeIntervalSince1970, forKey: Self.firstLaunchKey)
    }

    private var firstLaunchDate: Date? {
        guard defaults.object(forKey: Self.firstLaunchKey) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: Self.firstLaunchKey))
    }

    // MARK: - Eligibility

    /// The highest-priority nudge that should be shown right now, or nil.
    func nextNudge(now: Date, hasMedia: Bool, hasAPIKey: Bool, calendar: Calendar = .current) -> Nudge? {
        if hasMedia, !hasAPIKey, !hasSeen(.apiKey) {
            return .apiKey
        }
        if !hasSeen(.macApp), isSecondDayOrLater(now: now, calendar: calendar) {
            return .macApp
        }
        return nil
    }

    /// True once the calendar day has rolled over at least once since first launch,
    /// i.e. the second day someone opens the app — not 24 hours to the minute.
    private func isSecondDayOrLater(now: Date, calendar: Calendar) -> Bool {
        guard let firstLaunchDate else { return false }
        let start = calendar.startOfDay(for: firstLaunchDate)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return days >= 1
    }

    // MARK: - Seen state

    func hasSeen(_ nudge: Nudge) -> Bool {
        defaults.bool(forKey: Self.seenKey(nudge))
    }

    func markSeen(_ nudge: Nudge) {
        defaults.set(true, forKey: Self.seenKey(nudge))
    }

    /// Clears every nudge flag and the first-launch stamp. Debug affordance only.
    func resetAll() {
        for nudge in Nudge.allCases {
            defaults.removeObject(forKey: Self.seenKey(nudge))
        }
        defaults.removeObject(forKey: Self.firstLaunchKey)
    }

    private static func seenKey(_ nudge: Nudge) -> String {
        "nudge_\(nudge.rawValue)Seen_v1"
    }
}
