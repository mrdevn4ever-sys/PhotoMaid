import Foundation
import PhotoMaidCore

/// Ehrliche Größen: dezimal wie die Fotos-App/Einstellungen (`ByteCountFormatter`, Stil `.file`).
/// Unbekannt bleibt unbekannt, nie „0 KB“.
enum SizeText {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, b), countStyle: .file)
    }

    static func size(_ s: KnownSize) -> String {
        switch s {
        case .known(let b): bytes(b)
        case .unknown: L("size_unknown")
        }
    }

    /// „mind. 1,2 GB“, wenn unbekannte Größen enthalten sind.
    static func tally(_ t: SizeTally) -> String {
        if t.knownCount == 0 && t.unknownCount > 0 { return L("size_unknown") }
        return t.isLowerBound ? L("size_at_least", bytes(t.knownBytes)) : bytes(t.knownBytes)
    }

    static func savings(_ s: SavingsTotal) -> String {
        s.lowerBound ? L("size_at_least", bytes(s.bytes)) : bytes(s.bytes)
    }
}

enum DayText {
    /// „Mi., 7. Okt.“ / „Wed, Oct 7“.
    static func string(_ day: LocalDay) -> String {
        let date = day.startOfDay(in: .autoupdatingCurrent)
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func long(_ day: LocalDay) -> String {
        day.startOfDay(in: .autoupdatingCurrent).formatted(date: .long, time: .omitted)
    }
}

enum MonthText {
    /// „September 2026“ – Monatsname in der Nominativform der Sprache (`LLLL`).
    static func title(_ m: MonthKey) -> String {
        let date = m.firstDay.startOfDay(in: .autoupdatingCurrent)
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        let s = f.string(from: date)
        return s.prefix(1).uppercased(with: Locale.current) + s.dropFirst()
    }
}

enum DateText {
    static func abbreviated(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .omitted) }
    static func long(_ d: Date) -> String { d.formatted(date: .long, time: .omitted) }
    static func longWithTime(_ d: Date) -> String { d.formatted(date: .long, time: .shortened) }
    static func complete(_ d: Date) -> String { d.formatted(date: .complete, time: .omitted) }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// „1:05“ – Videolänge.
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Texte zu Später-Intervallen (wie Android `LaterText`).
enum LaterText {
    static func inInterval(_ i: LaterInterval) -> String {
        switch i.unit {
        case .days: i.value == 1 ? L("later_tomorrow_again") : LP("later_in_days_again", i.value)
        case .weeks: i.value == 1 ? L("later_in_one_week_again") : LP("later_in_weeks_again", i.value)
        case .months: i.value == 1 ? L("later_in_one_month_again") : LP("later_in_months_again", i.value)
        }
    }

    static func unit(_ u: LaterInterval.Unit, _ n: Int) -> String {
        switch u {
        case .days: LP("unit_days", n)
        case .weeks: LP("unit_weeks", n)
        case .months: LP("unit_months", n)
        }
    }
}

enum CountText {
    /// Zahl in der Schreibweise der App-Sprache (z. B. arabische Ziffern bleiben Systemsache).
    static func number(_ n: Int) -> String { n.formatted(.number) }
    /// Anteil 0…1 als ganze Prozent in der Schreibweise der App-Sprache.
    static func percent(_ p: Double) -> String { min(1, max(0, p)).formatted(.percent.precision(.fractionLength(0))) }
}
