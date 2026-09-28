import Foundation

/// Ein lokaler Kalendertag (gregorianisches Datum ohne Uhrzeit und ohne Zeitzone).
///
/// Wiedervorlagen und Tageslimits werden als lokaler Kalendertag gespeichert,
/// Audit-Zeitpunkte zusätzlich als UTC-`Date`. Arithmetik ausschließlich über `Calendar`,
/// nie über `n × 24 h`. Gespeichert wird immer das gregorianische Datum, auch wenn der
/// Nutzer einen anderen Anzeigekalender verwendet; die Anzeige formatiert separat.
public struct LocalDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Kalendertag eines Zeitpunkts in der übergebenen Zeitzone.
    public init(_ date: Date, timeZone: TimeZone) {
        let c = LocalDay.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Tagesbeginn dieses Tages in der Zeitzone. Existiert Mitternacht wegen
    /// Sommerzeitumstellung nicht, liefert `Calendar.startOfDay` den ersten gültigen Zeitpunkt.
    public func startOfDay(in timeZone: TimeZone) -> Date {
        let cal = LocalDay.gregorian(timeZone)
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return cal.startOfDay(for: cal.date(from: c)!)
    }

    /// Kalenderarithmetik: `n` Kalendertage später (früher bei negativem `n`).
    /// Unabhängig von Zeitzone und Sommerzeit, weil nur das Datum verschoben wird.
    public func adding(days n: Int) -> LocalDay {
        let utc = TimeZone(identifier: "UTC")!
        let cal = LocalDay.gregorian(utc)
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        let moved = cal.date(byAdding: .day, value: n, to: cal.date(from: c)!)!
        return LocalDay(moved, timeZone: utc)
    }

    /// `n` Kalendermonate später. Ein nicht existierender Tag wird auf das Monatsende gekürzt
    /// (31. Jan. + 1 Monat = 28./29. Feb.).
    public func adding(months n: Int) -> LocalDay {
        let utc = TimeZone(identifier: "UTC")!
        let cal = LocalDay.gregorian(utc)
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        let moved = cal.date(byAdding: .month, value: n, to: cal.date(from: c)!)!
        return LocalDay(moved, timeZone: utc)
    }

    /// Anzahl Kalendertage von `self` bis `other` (positiv, wenn `other` später liegt).
    public func days(until other: LocalDay) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        let cal = LocalDay.gregorian(utc)
        return cal.dateComponents([.day], from: startOfDay(in: utc), to: other.startOfDay(in: utc)).day!
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
}

/// Injizierbare Uhr. Produktion: `SystemClock`. Tests: `TestClock`.
public protocol Clock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

public extension Clock {
    var today: LocalDay { LocalDay(now, timeZone: timeZone) }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
    public var timeZone: TimeZone { TimeZone.autoupdatingCurrent }
}
