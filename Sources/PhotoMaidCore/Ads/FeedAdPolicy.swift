import Foundation

/// Zähler für Werbekarten im Feed (nur Free). Android-Logik, auf iOS **nicht aktiv**, solange Entscheidung E1 offen ist
/// (`AppConfig.adsEnabled == false`). Gezählt werden Entscheidungen, nicht „Zurück“. Lokal, keine Medien-IDs.
public struct FeedAdState: Hashable, Codable, Sendable {
    public var decisionsTotal = 0
    public var sinceLastAd = 0
    public var day: LocalDay?
    public var shownOnDay = 0
    /// Wanduhr (ms) der letzten Werbekarte im Feed – für den Mindestabstand.
    public var lastCardAtMs: Int64 = 0
    public init() {}
}

/// Einzige Stelle für Takt, Schonfrist und Tagesgrenze der Werbekarte.
public enum FeedAdPolicy {
    public static let interval = 7
    public static let warmupDecisions = 30
    public static let dailyCap = 30
    public static let minVisibleMs: Int64 = 1_500
    public static let minGapMs: Int64 = 60_000

    public static func gapElapsed(_ s: FeedAdState, nowMs: Int64) -> Bool {
        s.lastCardAtMs == 0 || nowMs < s.lastCardAtMs || nowMs - s.lastCardAtMs >= minGapMs
    }

    public static func shownToday(_ s: FeedAdState, today: LocalDay) -> Int { s.day == today ? s.shownOnDay : 0 }

    public static func onDecision(_ s: FeedAdState) -> FeedAdState {
        var n = s
        n.decisionsTotal += 1
        n.sinceLastAd += 1
        return n
    }

    public static func isDue(_ s: FeedAdState, today: LocalDay, nowMs: Int64 = .max) -> Bool {
        s.decisionsTotal >= warmupDecisions && s.sinceLastAd >= interval && shownToday(s, today: today) < dailyCap
            && gapElapsed(s, nowMs: nowMs)
    }

    public static func summaryAdAllowed(_ s: FeedAdState, today: LocalDay) -> Bool {
        s.decisionsTotal >= warmupDecisions && shownToday(s, today: today) < dailyCap
    }

    public static func onShown(_ s: FeedAdState, today: LocalDay) -> FeedAdState {
        var n = s
        n.shownOnDay = shownToday(s, today: today) + 1
        n.sinceLastAd = 0
        n.day = today
        return n
    }

    public static func onCardShown(_ s: FeedAdState, today: LocalDay, nowMs: Int64) -> FeedAdState {
        var n = onShown(s, today: today)
        n.lastCardAtMs = nowMs
        return n
    }
}
