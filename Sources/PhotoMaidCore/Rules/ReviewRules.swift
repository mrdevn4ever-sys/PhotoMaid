import Foundation

/// Quelle einer Regel.
public enum RuleSource: Hashable, Codable, Sendable {
    case screenshots
    case photos
    case videos
    case connectedSource(ConnectedSourceID)
}

/// Deklarativer Filter. Keine Skripte, keine KI.
public enum RuleFilter: Hashable, Codable, Sendable {
    case olderThan(days: Int)
    case knownSizeAtLeast(bytes: Int64)
    case all
}

public enum RuleTrigger: Hashable, Codable, Sendable {
    /// Bei jedem Start/Resume geprüft, höchstens eine Aufgabe pro lokalem Tag.
    case daily
    /// An einem Wochentag (1 = Sonntag … 7 = Samstag, gregorianisch), eine Aufgabe pro Woche.
    case weekly(weekday: Int)
    /// Sobald mindestens `count` neu **entdeckte** (nicht: neu heruntergeladene) Items warten.
    case newlyDiscovered(count: Int)
}

public struct ReviewRuleID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Quelle + Filter + Auslöser → Review-Aufgabe. Niemals Löschung.
public struct ReviewRule: Hashable, Codable, Sendable, Identifiable {
    public let id: ReviewRuleID
    public var source: RuleSource
    public var filter: RuleFilter
    public var trigger: RuleTrigger
    public var isEnabled: Bool
    public var notify: Bool

    public init(id: ReviewRuleID = ReviewRuleID(), source: RuleSource, filter: RuleFilter,
                trigger: RuleTrigger, isEnabled: Bool = true, notify: Bool = false) {
        self.id = id
        self.source = source
        self.filter = filter
        self.trigger = trigger
        self.isEnabled = isEnabled
        self.notify = notify
    }
}

/// Inventar-Eintrag, wie er bei einem tatsächlichen Scan erfasst wurde.
public struct InventoryItem: Hashable, Sendable {
    public let item: ItemReference
    public let source: RuleSource
    public let createdAt: Date?
    public let size: KnownSize
    /// Zeitpunkt, zu dem PhotoMaid das Item zum ersten Mal gesehen hat.
    public let firstSeenAt: Date

    public init(item: ItemReference, source: RuleSource, createdAt: Date?, size: KnownSize, firstSeenAt: Date) {
        self.item = item
        self.source = source
        self.createdAt = createdAt
        self.size = size
        self.firstSeenAt = firstSeenAt
    }
}

/// Ergebnis einer Regel: eine Review-Aufgabe. Enthält ausdrücklich keine Löschfreigabe.
public struct ReviewTask: Hashable, Codable, Sendable, Identifiable {
    /// Idempotenzschlüssel: gleiche Regel + gleicher Zeitraum → dieselbe Aufgabe.
    public let id: String
    public let ruleID: ReviewRuleID
    public let items: [ItemReference]
    public let createdAt: Date
}

public enum RuleEvaluator {
    /// Wertet eine Regel gegen ein tatsächlich gescanntes Inventar aus.
    /// - Parameter existingTaskIDs: bereits erzeugte Aufgaben (Idempotenz).
    /// - Parameter lastEvaluatedAt: Zeitpunkt der letzten Auswertung dieser Regel (für „neu entdeckt“).
    public static func evaluate(_ rule: ReviewRule, inventory: [InventoryItem],
                                records: [ItemReference: ItemRecord],
                                existingTaskIDs: Set<String>, lastEvaluatedAt: Date?,
                                now: Date, timeZone: TimeZone) -> ReviewTask? {
        guard rule.isEnabled else { return nil }
        let today = LocalDay(now, timeZone: timeZone)
        let periodKey: String
        switch rule.trigger {
        case .daily:
            periodKey = "d\(today)"
        case .weekly(let weekday):
            let cal = LocalDay.gregorian(timeZone)
            guard cal.component(.weekday, from: now) == weekday else { return nil }
            periodKey = "w\(today)"
        case .newlyDiscovered:
            periodKey = "n\(today)"
        }
        let taskID = "\(rule.id.rawValue.uuidString)|\(periodKey)"
        guard !existingTaskIDs.contains(taskID) else { return nil }

        let matching = inventory.filter { inv in
            guard inv.source == rule.source else { return false }
            if let r = records[inv.item], r.disposition != .undecided { return false }
            switch rule.filter {
            case .all: return true
            case .olderThan(let days):
                guard let created = inv.createdAt else { return false }
                return LocalDay(created, timeZone: timeZone).adding(days: days) <= today
            case .knownSizeAtLeast(let bytes):
                guard let b = inv.size.bytes else { return false } // unbekannt ≠ 0, aber auch nicht ≥ x
                return b >= bytes
            }
        }
        let selected: [InventoryItem]
        if case .newlyDiscovered(let count) = rule.trigger {
            let fresh = matching.filter { inv in lastEvaluatedAt.map { inv.firstSeenAt > $0 } ?? true }
            guard fresh.count >= count else { return nil }
            selected = fresh
        } else {
            selected = matching
        }
        guard !selected.isEmpty else { return nil }
        return ReviewTask(id: taskID, ruleID: rule.id,
                          items: selected.map(\.item).sorted { $0.description < $1.description },
                          createdAt: now)
    }
}
