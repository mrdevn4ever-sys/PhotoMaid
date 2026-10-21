import Foundation

/// Abzeichen (Gamification, Nutzerentscheidung 21.10.2026). Jede Regel prüft nur vorhandene, echte Daten; nichts wird
/// geschätzt. Bewusst kein Abzeichen für gelöschte Mengen oder freigegebenen Speicher.
public enum AchievementGroup: String, CaseIterable, Sendable {
    case start, reviewed, streak, order, studio, games
}

public enum AchievementID: String, CaseIterable, Codable, Hashable, Sendable {
    // Erste Schritte
    case firstDecision, activeDays3, activeDays7
    // Durchgesehen
    case reviewed100, reviewed1000, reviewed5000, reviewed10000, libraryDone
    // Serien
    case streak3, streak7, streak30, streak100
    // Ordnung
    case firstMonthDone, twelveMonthsDone, laterCleared, goal10
    // Studio
    case firstCollage, firstPDF, firstFilm
    // Spiele
    case pairsUnder30, pairs12, snake50, blocks5000, allGames

    public var group: AchievementGroup {
        switch self {
        case .firstDecision, .activeDays3, .activeDays7: .start
        case .reviewed100, .reviewed1000, .reviewed5000, .reviewed10000, .libraryDone: .reviewed
        case .streak3, .streak7, .streak30, .streak100: .streak
        case .firstMonthDone, .twelveMonthsDone, .laterCleared, .goal10: .order
        case .firstCollage, .firstPDF, .firstFilm: .studio
        case .pairsUnder30, .pairs12, .snake50, .blocks5000, .allGames: .games
        }
    }
}

/// Alles, was die Regeln brauchen – vom Aufrufer aus Ledger, Mediathek, Spielen und „Bearbeitet“ zusammengestellt.
public struct AchievementInput: Sendable {
    public var progress: ReviewProgress
    public var timeZone: TimeZone
    /// Fertige Monate (alle Medien des Monats durchgesehen) und Monate insgesamt.
    public var monthsDone: Int
    public var monthsTotal: Int
    /// „Später“ wurde je benutzt und ist jetzt leer.
    public var laterEverUsed: Bool
    public var laterOpen: Int
    public var dailyGoal: Int
    /// Bestzeiten bei Paare: (Paare, Sekunden).
    public var pairsTimes: [(pairs: Int, seconds: Double)]
    public var snakeBest: Int?
    public var blocksBest: Int
    /// Früheste gespeicherte Ergebnisse je Art (aus „Bearbeitet“).
    public var firstCollage: Date?
    public var firstPDF: Date?
    public var firstFilm: Date?

    public init(progress: ReviewProgress, timeZone: TimeZone, monthsDone: Int = 0, monthsTotal: Int = 0,
                laterEverUsed: Bool = false, laterOpen: Int = 0, dailyGoal: Int = 0,
                pairsTimes: [(pairs: Int, seconds: Double)] = [], snakeBest: Int? = nil, blocksBest: Int = 0,
                firstCollage: Date? = nil, firstPDF: Date? = nil, firstFilm: Date? = nil) {
        self.progress = progress; self.timeZone = timeZone
        self.monthsDone = monthsDone; self.monthsTotal = monthsTotal
        self.laterEverUsed = laterEverUsed; self.laterOpen = laterOpen; self.dailyGoal = dailyGoal
        self.pairsTimes = pairsTimes; self.snakeBest = snakeBest; self.blocksBest = blocksBest
        self.firstCollage = firstCollage; self.firstPDF = firstPDF; self.firstFilm = firstFilm
    }
}

/// Ergebnis einer Regel: erreicht (mit Zeitpunkt, falls aus den Daten ableitbar) oder offen (mit Rest bis zum Ziel).
public enum AchievementState: Hashable, Sendable {
    case earned(Date?)
    case open(remaining: Int?)

    public var isEarned: Bool { if case .earned = self { true } else { false } }
}

public enum Achievements {
    public static let pairsUnderSeconds = 30.0
    public static let snakeTarget = 50
    public static let blocksTarget = 5_000
    public static let goalDaysTarget = 10

    public static func evaluate(_ input: AchievementInput) -> [AchievementID: AchievementState] {
        let p = input.progress
        func noon(_ day: LocalDay) -> Date { day.startOfDay(in: input.timeZone).addingTimeInterval(12 * 3600) }
        func activeDays(_ n: Int) -> AchievementState {
            p.activeDays.count >= n ? .earned(noon(p.activeDays[n - 1])) : .open(remaining: n - p.activeDays.count)
        }
        func reviewed(_ n: Int) -> AchievementState {
            if let at = p.reviewedMilestones[n] { return .earned(at) }
            return p.totalReviewed >= n ? .earned(nil) : .open(remaining: n - p.totalReviewed)
        }
        func streak(_ n: Int) -> AchievementState {
            if let day = p.streakMilestones[n] { return .earned(noon(day)) }
            return max(p.longestStreak, p.streak) >= n ? .earned(nil) : .open(remaining: n - p.streak)
        }
        func flag(_ done: Bool, _ at: Date? = nil) -> AchievementState { done ? .earned(at) : .open(remaining: nil) }
        let goalDays = p.goalDays(input.dailyGoal)
        let bestPairs = input.pairsTimes.filter { $0.pairs >= 6 }.map(\.seconds).min()

        var out: [AchievementID: AchievementState] = [:]
        for id in AchievementID.allCases {
            out[id] = switch id {
            case .firstDecision: flag(p.firstDecisionAt != nil, p.firstDecisionAt)
            case .activeDays3: activeDays(3)
            case .activeDays7: activeDays(7)
            case .reviewed100: reviewed(100)
            case .reviewed1000: reviewed(1_000)
            case .reviewed5000: reviewed(5_000)
            case .reviewed10000: reviewed(10_000)
            case .libraryDone: flag(input.monthsTotal > 0 && input.monthsDone == input.monthsTotal)
            case .streak3: streak(3)
            case .streak7: streak(7)
            case .streak30: streak(30)
            case .streak100: streak(100)
            case .firstMonthDone: input.monthsDone >= 1 ? .earned(nil) : .open(remaining: nil)
            case .twelveMonthsDone: input.monthsDone >= 12 ? .earned(nil) : .open(remaining: 12 - input.monthsDone)
            case .laterCleared: flag(input.laterEverUsed && input.laterOpen == 0)
            case .goal10:
                goalDays.count >= goalDaysTarget ? .earned(noon(goalDays[goalDaysTarget - 1]))
                    : .open(remaining: input.dailyGoal > 0 ? goalDaysTarget - goalDays.count : nil)
            case .firstCollage: flag(input.firstCollage != nil, input.firstCollage)
            case .firstPDF: flag(input.firstPDF != nil, input.firstPDF)
            case .firstFilm: flag(input.firstFilm != nil, input.firstFilm)
            case .pairsUnder30: flag((bestPairs ?? .infinity) < pairsUnderSeconds)
            case .pairs12: flag(input.pairsTimes.contains { $0.pairs >= 12 })
            case .snake50:
                (input.snakeBest ?? 0) >= snakeTarget ? .earned(nil) : .open(remaining: snakeTarget - (input.snakeBest ?? 0))
            case .blocks5000:
                input.blocksBest >= blocksTarget ? .earned(nil) : .open(remaining: blocksTarget - input.blocksBest)
            case .allGames: flag(!input.pairsTimes.isEmpty && (input.snakeBest ?? 0) > 0 && input.blocksBest > 0)
            }
        }
        return out
    }
}

/// Persönliche Medaillen je Spiel – gemessen nur an eigenen Werten, nie an anderen.
public enum GameMedal: Int, Comparable, Sendable {
    case none, bronze, silver, gold
    public static func < (a: GameMedal, b: GameMedal) -> Bool { a.rawValue < b.rawValue }

    /// Paare: Sekunden je Paar (≤ 9 Bronze, ≤ 6 Silber, ≤ 4 Gold).
    public static func pairs(seconds: Double, pairs: Int) -> GameMedal {
        guard pairs > 0, seconds.isFinite else { return .none }
        let perPair = seconds / Double(pairs)
        return perPair <= 4 ? .gold : perPair <= 6 ? .silver : perPair <= 9 ? .bronze : .none
    }

    public static let snakeSteps = [10, 25, 50]
    public static let blocksSteps = [1_000, 2_500, 5_000]

    public static func snake(_ eaten: Int) -> GameMedal { medal(eaten, snakeSteps) }
    public static func blocks(_ score: Int) -> GameMedal { medal(score, blocksSteps) }

    /// Nächste Stufe und ihr Schwellenwert (nil bei Gold).
    public static func next(after value: Int, steps: [Int]) -> (medal: GameMedal, at: Int)? {
        guard let i = steps.firstIndex(where: { value < $0 }) else { return nil }
        return (GameMedal(rawValue: i + 1) ?? .gold, steps[i])
    }

    private static func medal(_ value: Int, _ steps: [Int]) -> GameMedal {
        GameMedal(rawValue: steps.filter { value >= $0 }.count) ?? .none
    }
}
