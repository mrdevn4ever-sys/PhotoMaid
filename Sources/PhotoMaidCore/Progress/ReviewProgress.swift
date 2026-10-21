import Foundation

/// Fortschritt fürs Durchsehen (Gamification, Nutzerentscheidung 21.10.2026). Nur aus echten Ledger-Daten abgeleitet,
/// nichts davon wird gespeichert. „Durchgesehen“ wie bei den Monaten (`ProgressRules.isReviewed`): Behalten, Papierkorb,
/// entfernt und Später mit Termin oder beiseitegelegt zählen gleich – Löschen wird nie besonders belohnt.
public struct ReviewProgress: Hashable, Sendable {
    /// Medien, die aktuell als durchgesehen gelten.
    public let totalReviewed: Int
    /// Verschiedene Medien mit einer Entscheidung je lokalem Tag (am selben Tag Zurückgenommenes zählt nicht).
    public let perDay: [LocalDay: Int]
    public let today: LocalDay
    public let streak: Int
    /// Überbrückte Pausentage der laufenden Serie (höchstens einer je Woche).
    public let pauseDays: Set<LocalDay>
    public let longestStreak: Int
    /// Erreichte Schwellen (Anzahl je erstmals durchgesehener Medien) mit dem Zeitpunkt des Erreichens.
    public let reviewedMilestones: [Int: Date]
    /// Erreichte Serienlängen mit dem Tag des Erreichens.
    public let streakMilestones: [Int: LocalDay]
    /// Tage mit Entscheidungen in zeitlicher Reihenfolge.
    public let activeDays: [LocalDay]
    public let firstDecisionAt: Date?

    public static let empty = ReviewProgress(totalReviewed: 0, perDay: [:], today: LocalDay(year: 2000, month: 1, day: 1),
                                             streak: 0, pauseDays: [], longestStreak: 0, reviewedMilestones: [:],
                                             streakMilestones: [:], activeDays: [], firstDecisionAt: nil)

    public var reviewedToday: Int { perDay[today] ?? 0 }
    public var level: ReviewLevel { ReviewLevel(total: totalReviewed) }

    /// Durchgesehen je Tag der laufenden Woche (Montag bis Sonntag).
    public var currentWeek: [ReviewDay] {
        let monday = ReviewProgress.monday(of: today)
        return (0..<7).map { offset in
            let d = monday.adding(days: offset)
            return ReviewDay(day: d, reviewed: perDay[d] ?? 0)
        }
    }

    /// Rückblick auf die vorige Woche (Montag bis Sonntag).
    public var previousWeek: (monday: LocalDay, reviewed: Int, activeDays: Int) {
        let monday = ReviewProgress.monday(of: today).adding(days: -7)
        let counts = (0..<7).map { perDay[monday.adding(days: $0)] ?? 0 }
        return (monday, counts.reduce(0, +), counts.filter { $0 > 0 }.count)
    }

    /// Tage mit mindestens `goal` durchgesehenen Medien (für „Tagesziel erreicht“), aufsteigend.
    public func goalDays(_ goal: Int) -> [LocalDay] {
        guard goal > 0 else { return [] }
        return activeDays.filter { (perDay[$0] ?? 0) >= goal }
    }

    public init(totalReviewed: Int, perDay: [LocalDay: Int], today: LocalDay, streak: Int, pauseDays: Set<LocalDay>,
                longestStreak: Int, reviewedMilestones: [Int: Date], streakMilestones: [Int: LocalDay],
                activeDays: [LocalDay], firstDecisionAt: Date?) {
        self.totalReviewed = totalReviewed
        self.perDay = perDay
        self.today = today
        self.streak = streak
        self.pauseDays = pauseDays
        self.longestStreak = longestStreak
        self.reviewedMilestones = reviewedMilestones
        self.streakMilestones = streakMilestones
        self.activeDays = activeDays
        self.firstDecisionAt = firstDecisionAt
    }

    public static let reviewedThresholds = [100, 1_000, 5_000, 10_000]
    public static let streakThresholds = [3, 7, 30, 100]

    /// Berechnet den Fortschritt aus den Verlaufsereignissen (chronologisch) und den aktuellen Datensätzen.
    public static func compute(events: [DecisionEvent], records: [ItemReference: ItemRecord], today: LocalDay,
                               timeZone: TimeZone) -> ReviewProgress {
        let total = records.values.filter { ProgressRules.isReviewed($0) }.count
        var daySets: [LocalDay: Set<ItemReference>] = [:]
        var ever: Set<ItemReference> = []
        var milestones: [Int: Date] = [:]
        var first: Date?
        for e in events.sorted(by: { $0.at < $1.at }) {
            let day = LocalDay(e.at, timeZone: timeZone)
            switch e.kind {
            case .decision, .correction:
                guard isReviewed(e.to) else { continue }
                daySets[day, default: []].insert(e.item)
                if first == nil { first = e.at }
                if ever.insert(e.item).inserted {
                    for t in reviewedThresholds where ever.count == t { milestones[t] = e.at }
                }
            case .undo:
                if !isReviewed(e.to) { daySets[day]?.remove(e.item) }
            default:
                continue
            }
        }
        let perDay = daySets.compactMapValues { $0.isEmpty ? nil : $0.count }
        let active = perDay.keys.sorted()
        let current = currentStreak(active: Set(active), today: today, first: active.first)
        let history = longest(active: active, today: today)
        return ReviewProgress(totalReviewed: total, perDay: perDay, today: today, streak: current.count,
                              pauseDays: current.pauses, longestStreak: max(history.longest, current.count),
                              reviewedMilestones: milestones, streakMilestones: history.reached, activeDays: active,
                              firstDecisionAt: first)
    }

    static func isReviewed(_ s: DecisionSnapshot) -> Bool {
        ProgressRules.isReviewed(ItemRecord(item: ItemReference(provider: .photoLibrary, localIdentifier: ""),
                                            disposition: s.disposition, dueDay: s.dueDay, bookmarked: s.bookmarked))
    }

    /// Laufende Serie rückwärts ab heute. Heute ohne Entscheidung beendet die Serie noch nicht. Je Woche (Montag bis
    /// Sonntag) darf ein Tag fehlen (Pausentag); ein zweiter fehlender Tag derselben Woche beendet die Serie. Ein Pausentag
    /// zählt nur, wenn davor wieder ein aktiver Tag liegt.
    static func currentStreak(active: Set<LocalDay>, today: LocalDay, first: LocalDay?) -> (count: Int, pauses: Set<LocalDay>) {
        guard let first else { return (0, []) }
        var day = active.contains(today) ? today : today.adding(days: -1)
        var count = 0
        var usedWeeks: Set<LocalDay> = []
        var pauses: Set<LocalDay> = []
        var pending: [LocalDay] = []
        while day >= first {
            if active.contains(day) {
                count += 1
                pauses.formUnion(pending)
                pending = []
            } else {
                let week = monday(of: day)
                if usedWeeks.contains(week) { break }
                usedWeeks.insert(week)
                pending.append(day)
            }
            day = day.adding(days: -1)
        }
        return (count, count > 0 ? pauses : [])
    }

    /// Längste Serie über die ganze Zeit (gleiche Regel) und der Tag, an dem welche Länge erstmals erreicht wurde.
    static func longest(active: [LocalDay], today: LocalDay) -> (longest: Int, reached: [Int: LocalDay]) {
        guard let first = active.first else { return (0, [:]) }
        let set = Set(active)
        var run = 0, best = 0
        var usedWeeks: Set<LocalDay> = []
        var reached: [Int: LocalDay] = [:]
        var day = first
        while day <= today {
            if set.contains(day) {
                run += 1
                best = max(best, run)
                for t in streakThresholds where run == t && reached[t] == nil { reached[t] = day }
            } else {
                let week = monday(of: day)
                if usedWeeks.contains(week) {
                    run = 0
                    usedWeeks = []
                } else {
                    usedWeeks.insert(week)
                }
            }
            day = day.adding(days: 1)
        }
        return (best, reached)
    }

    /// Montag der Woche (ISO 8601) eines Tages.
    public static func monday(of day: LocalDay) -> LocalDay {
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let weekday = cal.component(.weekday, from: day.startOfDay(in: utc)) // 1 = Sonntag
        return day.adding(days: -((weekday + 5) % 7))
    }
}

/// Ein Tag mit der Anzahl durchgesehener Medien.
public struct ReviewDay: Hashable, Sendable {
    public let day: LocalDay
    public let reviewed: Int
    public init(day: LocalDay, reviewed: Int) { self.day = day; self.reviewed = reviewed }
}

/// Level nach Anzahl durchgesehener Medien (nur Zahlen, keine Wertung).
public struct ReviewLevel: Hashable, Sendable {
    public static let thresholds = [50, 250, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000]
    public let total: Int

    public init(total: Int) { self.total = max(0, total) }

    /// 1 bis 10.
    public var number: Int { ReviewLevel.thresholds.filter { $0 <= total }.count + 1 }
    public var floor: Int { number == 1 ? 0 : ReviewLevel.thresholds[number - 2] }
    /// Schwelle des nächsten Levels; nil im höchsten Level.
    public var next: Int? { number <= ReviewLevel.thresholds.count ? ReviewLevel.thresholds[number - 1] : nil }
    public var remaining: Int? { next.map { $0 - total } }
    public var fraction: Double {
        guard let next else { return 1 }
        return Double(total - floor) / Double(max(1, next - floor))
    }
}
