import Foundation

/// Voreinstellungen der Terminleiste: Morgen · 7 Tage · 30 Tage · … (eigenes Datum).
public enum LaterPreset: String, Hashable, Sendable, CaseIterable {
    case tomorrow
    case sevenDays
    case thirtyDays

    public var days: Int {
        switch self {
        case .tomorrow: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        }
    }

    /// Kalenderarithmetik auf dem lokalen Tag, nicht `n × 24 h`.
    public func dueDay(from today: LocalDay) -> LocalDay { today.adding(days: days) }
}

/// Selbst gewählter Abstand im Drehrad: „In [n] [Tagen | Wochen | Monaten]“.
public struct LaterInterval: Hashable, Codable, Sendable {
    public enum Unit: String, Hashable, Codable, Sendable, CaseIterable { case days, weeks, months }
    public var value: Int
    public var unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = max(1, value)
        self.unit = unit
    }

    /// Standard beim Wisch nach rechts (einstellbar, Vorgabe: 2 Tage).
    public static let defaultQuick = LaterInterval(value: 2, unit: .days)
    public static let allowedQuickDays = [1, 2, 3, 7]

    /// Wertebereich des Drehrads je Einheit.
    public static func range(for unit: Unit) -> ClosedRange<Int> {
        switch unit {
        case .days: 1...30
        case .weeks: 1...12
        case .months: 1...12
        }
    }

    /// Kalenderarithmetik auf dem lokalen Tag (nie `n × 24 h`).
    public func dueDay(from today: LocalDay) -> LocalDay {
        switch unit {
        case .days: today.adding(days: value)
        case .weeks: today.adding(days: 7 * value)
        case .months: today.adding(months: value)
        }
    }
}

public enum LaterStatus: Hashable, Sendable {
    /// Nur in einer Session übersprungen, kein Termin.
    case sessionOnly
    case upcoming(LocalDay)
    case due(LocalDay)
}

/// Aufbau der Review-Warteschlangen aus Kandidaten und gespeicherten Entscheidungen.
public enum ReviewQueues {
    public static func laterStatus(_ record: ItemRecord, today: LocalDay) -> LaterStatus? {
        guard record.disposition == .later else { return nil }
        guard let day = record.dueDay else { return .sessionOnly }
        return day <= today ? .due(day) : .upcoming(day)
    }

    /// Normale Warteschlange: unentschiedene Items sowie terminlos Zurückgestellte aus
    /// früheren Sessions. Vor Fälligkeit terminierte Items sind ausgeschlossen, fällige
    /// Items erscheinen nur im Wieder-fällig-Bereich.
    public static func normalQueue(candidates: [ItemReference], records: [ItemReference: ItemRecord],
                                   session: ReviewSessionID, today: LocalDay) -> [ItemReference] {
        candidates.filter { item in
            guard let r = records[item] else { return true }
            switch r.disposition {
            case .undecided: return true
            case .kept, .markedForCleanup, .removed: return false
            case .later:
                if r.dueDay != nil { return false }
                return r.skippedInSession != session
            }
        }
    }

    /// Wieder fällig: Termin erreicht und nicht in der aktuellen Session übersprungen.
    public static func dueQueue(records: [ItemRecord], session: ReviewSessionID, today: LocalDay) -> [ItemReference] {
        records
            .filter { r in
                guard case .due = laterStatus(r, today: today) else { return false }
                return r.skippedInSession != session
            }
            .sorted { ($0.dueDay!, $0.item.description) < ($1.dueDay!, $1.item.description) }
            .map(\.item)
    }

    /// Gruppierung für den Später-Screen nach echten Datumsgruppen.
    public static func laterGroups(records: [ItemRecord], today: LocalDay) -> [(key: LaterGroup, items: [ItemRecord])] {
        var groups: [LaterGroup: [ItemRecord]] = [:]
        for r in records {
            guard let status = laterStatus(r, today: today) else { continue }
            let key: LaterGroup
            switch status {
            case .sessionOnly: key = .noDate
            case .due: key = .due
            case .upcoming(let d):
                let n = today.days(until: d)
                key = n == 1 ? .tomorrow : (n <= 7 ? .withinSevenDays : .later(d))
            }
            groups[key, default: []].append(r)
        }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.item.description < $1.item.description }) }
    }
}

public enum LaterGroup: Hashable, Sendable, Comparable {
    case due
    case tomorrow
    case withinSevenDays
    case later(LocalDay)
    case noDate

    private var order: (Int, LocalDay?) {
        switch self {
        case .due: (0, nil)
        case .tomorrow: (1, nil)
        case .withinSevenDays: (2, nil)
        case .later(let d): (3, d)
        case .noDate: (4, nil)
        }
    }

    public static func < (a: LaterGroup, b: LaterGroup) -> Bool {
        let (ao, ad) = a.order, (bo, bd) = b.order
        if ao != bo { return ao < bo }
        if let ad, let bd { return ad < bd }
        return false
    }
}
