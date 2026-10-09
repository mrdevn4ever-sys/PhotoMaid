import Foundation

/// Ein Kalendermonat (lokale Zeitzone), z. B. `2026-09`. Monate sind nur Filter – nichts wird je Monat gespeichert.
public struct MonthKey: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(_ date: Date, timeZone: TimeZone) {
        let d = LocalDay(date, timeZone: timeZone)
        self.init(year: d.year, month: d.month)
    }

    public static func < (a: MonthKey, b: MonthKey) -> Bool { (a.year, a.month) < (b.year, b.month) }

    /// `2026-09`, immer mit ASCII-Ziffern (wird gespeichert, z. B. „Weitermachen“).
    public var description: String {
        let y = String(year), m = String(month)
        return String(repeating: "0", count: max(0, 4 - y.count)) + y + "-" + (m.count < 2 ? "0" + m : m)
    }

    /// Liest `yyyy-MM`; andere Ziffernsysteme (z. B. arabisch-indisch) werden auf ASCII abgebildet.
    public static func parse(_ s: String?) -> MonthKey? {
        guard let s else { return nil }
        let ascii = String(s.unicodeScalars.map { u -> Character in
            if let v = u.properties.numericType == .decimal ? u.properties.numericValue : nil, v >= 0, v <= 9 {
                return Character(String(Int(v)))
            }
            return Character(u)
        })
        let parts = ascii.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m), parts[1].count == 2
        else { return nil }
        return MonthKey(year: y, month: m)
    }

    public var firstDay: LocalDay { LocalDay(year: year, month: month, day: 1) }
}

public enum MonthState: Hashable, Sendable { case notStarted, inProgress, done }

/// Echter Fortschritt eines Monats aus dem Ledger. „Durchgesehen“ = Behalten, Papierkorb, entfernt oder Später mit
/// Termin / ohne Termin beiseitegelegt; `later` davon getrennt sichtbar. Nur in einer Sitzung übersprungen = offen.
public struct MonthProgress: Hashable, Sendable, Identifiable {
    public let month: MonthKey
    public let total: Int
    public let reviewed: Int
    public let later: Int

    public init(month: MonthKey, total: Int, reviewed: Int, later: Int) {
        self.month = month
        self.total = total
        self.reviewed = reviewed
        self.later = later
    }

    public var id: MonthKey { month }
    public var open: Int { total - reviewed }
    public var state: MonthState {
        if total == 0 || reviewed >= total { return .done }
        return reviewed == 0 ? .notStarted : .inProgress
    }
    public var fraction: Double { total == 0 ? 1 : Double(reviewed) / Double(total) }
}

public enum ProgressRules {
    public static func isReviewed(_ r: ItemRecord?) -> Bool {
        guard let r else { return false }
        switch r.disposition {
        case .undecided: return false
        case .kept, .markedForCleanup, .removed: return true
        case .later: return r.dueDay != nil || r.bookmarked
        }
    }

    public static func isLater(_ r: ItemRecord?) -> Bool { r?.disposition == .later && isReviewed(r) }

    /// Monate (neueste zuerst) aus Medien mit Datum; Medien ohne Datum bilden keinen Monat.
    /// `.removed` zählt nur, solange das Medium noch in der Liste ist (wiederhergestellt) – dann ist es wieder offen.
    public static func months<T>(_ items: [T], date: (T) -> Date?, record: (T) -> ItemRecord?,
                                 timeZone: TimeZone) -> [MonthProgress] {
        var groups: [MonthKey: [ItemRecord?]] = [:]
        for a in items {
            guard let d = date(a) else { continue }
            groups[MonthKey(d, timeZone: timeZone), default: []].append(record(a))
        }
        return groups.map { m, recs in
            let reviewed = recs.filter { isReviewed($0) && $0?.disposition != .removed }.count
            return MonthProgress(month: m, total: recs.count, reviewed: reviewed, later: recs.filter(isLater).count)
        }.sorted { $0.month > $1.month }
    }
}
