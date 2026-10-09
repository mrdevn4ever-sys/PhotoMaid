import Foundation

/// Stufe der Zeitachse: Tage (große Kacheln) · Monate · Jahre (kleine Kacheln). Zwei Finger wechseln die Stufe.
public enum TimelineLevel: Int, Hashable, Codable, Sendable, CaseIterable {
    case day, month, year

    public var columns: Int {
        switch self {
        case .day: 3
        case .month: 5
        case .year: 8
        }
    }

    public var finer: TimelineLevel { TimelineLevel(rawValue: max(0, rawValue - 1)) ?? .day }
    public var coarser: TimelineLevel { TimelineLevel(rawValue: min(2, rawValue + 1)) ?? .year }
}

/// Zeitlicher Schlüssel. Ohne Datum: `unknown`.
public struct TimelineKey: Hashable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let unknown: Bool

    public init(year: Int, month: Int = 0, day: Int = 0, unknown: Bool = false) {
        self.year = year
        self.month = month
        self.day = day
        self.unknown = unknown
    }

    public static func < (a: TimelineKey, b: TimelineKey) -> Bool {
        (a.unknown ? 0 : 1, a.year, a.month, a.day) < (b.unknown ? 0 : 1, b.year, b.month, b.day)
    }

    public var localDay: LocalDay? { unknown || day == 0 ? nil : LocalDay(year: year, month: month, day: day) }
}

/// Abschnitt der Zeitachse: Schlüssel (Tag, Monat oder Jahr) und die Medien darin (neueste zuerst).
public struct TimelineSection<T>: Identifiable {
    public let key: TimelineKey
    public let items: [T]
    public var id: TimelineKey { key }
}

extension TimelineSection: Sendable where T: Sendable {}

/// Zeitachse aus einer Momentaufnahme: reine Gruppierung, nichts gespeichert. Neueste Abschnitte zuerst; Medien ohne
/// Datum am Ende in einem eigenen Abschnitt (keine erfundenen Daten).
public enum Timeline {
    public static func sections<T>(_ items: [T], date: (T) -> Date?, level: TimelineLevel,
                                   timeZone: TimeZone) -> [TimelineSection<T>] {
        var order: [TimelineKey] = []
        var groups: [TimelineKey: [T]] = [:]
        for it in items {
            let k = key(date(it), level: level, timeZone: timeZone)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(it)
        }
        return order.sorted(by: >).map { k in
            TimelineSection(key: k, items: groups[k]!.sorted { (date($0) ?? .distantPast) > (date($1) ?? .distantPast) })
        }
    }

    public static func key(_ date: Date?, level: TimelineLevel, timeZone: TimeZone) -> TimelineKey {
        guard let date else { return TimelineKey(year: 0, unknown: true) }
        let d = LocalDay(date, timeZone: timeZone)
        switch level {
        case .day: return TimelineKey(year: d.year, month: d.month, day: d.day)
        case .month: return TimelineKey(year: d.year, month: d.month)
        case .year: return TimelineKey(year: d.year)
        }
    }
}

/// Suche ohne Akzente und Groß/klein: „é“ = „e“, „ß“ = „ss“, „Ø“ = „o“. Treffer = jedes Wort der Anfrage kommt in einem
/// der Felder vor (Teilwort genügt). Rein lokal.
public enum SearchText {
    private static let extra: [Character: String] = ["ß": "ss", "ø": "o", "đ": "d", "ł": "l", "æ": "ae", "œ": "oe", "ı": "i"]

    public static func normalize(_ s: String) -> String {
        var mapped = ""
        for ch in s.lowercased() { mapped += extra[ch] ?? String(ch) }
        let scalars = mapped.decomposedStringWithCanonicalMapping.unicodeScalars.filter { u in
            switch u.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: false
            default: true
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    public static func tokens(_ query: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;/_.-"))
        return normalize(query).components(separatedBy: separators).filter { !$0.isEmpty }
    }

    /// `fields` sollten schon normalisiert sein (einmal je Medium), `queryTokens` aus `tokens`.
    public static func matches(_ queryTokens: [String], fields: [String]) -> Bool {
        !queryTokens.isEmpty && queryTokens.allSatisfy { t in fields.contains { $0.contains(t) } }
    }
}

/// Natürliche Reihenfolge („IMG_2“ vor „IMG_10“), ohne Groß-/Kleinschreibung und Akzente.
public enum NaturalOrder {
    public static func compare(_ a: String, _ b: String) -> Int {
        let x = chunks(SearchText.normalize(a)), y = chunks(SearchText.normalize(b))
        for i in 0..<min(x.count, y.count) {
            let p = x[i], q = y[i]
            let r: Int
            if let pf = p.first, let qf = q.first, pf.isASCIIDigit, qf.isASCIIDigit {
                let pi = String(p.drop { $0 == "0" }), qi = String(q.drop { $0 == "0" })
                r = pi.count != qi.count ? pi.count - qi.count : (pi == qi ? 0 : (pi < qi ? -1 : 1))
            } else {
                r = p == q ? 0 : (p < q ? -1 : 1)
            }
            if r != 0 { return r }
        }
        return x.count - y.count
    }

    public static func less(_ a: String, _ b: String) -> Bool { compare(a, b) < 0 }

    private static func chunks(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var curDigit: Bool?
        for ch in s {
            let d = ch.isASCIIDigit
            if curDigit != nil && curDigit != d { out.append(cur); cur = "" }
            cur.append(ch)
            curDigit = d
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// Reihenfolge der Medien in einem Album (je Album gespeichert, sonst Standard). Nur Ansicht, nie eine Entscheidung.
public enum MediaSort: String, Hashable, Codable, Sendable, CaseIterable {
    case newest, oldest, added, name, largest

    /// Fehlende Werte (kein Datum, unbekannte Größe) kommen immer ans Ende – eine unbekannte Größe ist nie 0.
    /// Gleichstand: neueste zuerst, dann Name.
    public func sort<T>(_ items: [T], date: (T) -> Date?, added: (T) -> Date?, name: (T) -> String?,
                        size: (T) -> Int64?) -> [T] {
        func tie(_ a: T, _ b: T) -> Bool {
            let da = date(a) ?? .distantPast, db = date(b) ?? .distantPast
            if da != db { return da > db }
            return (name(a) ?? "").lowercased() < (name(b) ?? "").lowercased()
        }
        func optional<V: Comparable>(_ va: V?, _ vb: V?, descending: Bool, _ a: T, _ b: T) -> Bool {
            switch (va, vb) {
            case let (x?, y?): return x == y ? tie(a, b) : (descending ? x > y : x < y)
            case (nil, nil): return tie(a, b)
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        switch self {
        case .newest: return items.sorted { optional(date($0), date($1), descending: true, $0, $1) }
        case .oldest: return items.sorted { optional(date($0), date($1), descending: false, $0, $1) }
        case .added: return items.sorted { optional(added($0), added($1), descending: true, $0, $1) }
        case .largest: return items.sorted { optional(size($0), size($1), descending: true, $0, $1) }
        case .name:
            return items.sorted { a, b in
                let na = name(a).flatMap { $0.isEmpty ? nil : $0 }, nb = name(b).flatMap { $0.isEmpty ? nil : $0 }
                switch (na, nb) {
                case let (x?, y?):
                    let c = NaturalOrder.compare(x, y)
                    return c == 0 ? tie(a, b) : c < 0
                case (nil, nil): return tie(a, b)
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }
}
