import Foundation

/// CLDR-Mengenformen für ganze Zahlen in allen App-Sprachen (16 + Ausbau 11/2026) (wie Android `plurals`).
/// Die App wählt damit den Eintrag `kennung#form` aus `Localizable.xcstrings`; fehlt eine Form, gilt `other`.
public enum PluralCategory: String, Hashable, Sendable, CaseIterable {
    case zero, one, two, few, many, other
}

public enum PluralRules {
    /// Sprache aus einem Lokalisierungs-Kürzel („de“, „pt-PT“, „zh-Hans“, „ar“).
    public static func category(_ n: Int, language: String) -> PluralCategory {
        let lang = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
        let i = abs(n)
        switch lang {
        case "ja", "ko", "zh", "id", "ms", "th", "vi":
            return .other
        case "hi", "bn", "gu", "kn", "pa":
            return i == 0 || i == 1 ? .one : .other
        case "cs", "sk":
            if i == 1 { return .one }
            return (2...4).contains(i) ? .few : .other
        case "hr", "bs", "sr":
            if i % 10 == 1 && i % 100 != 11 { return .one }
            if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return .few }
            return .other
        case "sl":
            switch i % 100 {
            case 1: return .one
            case 2: return .two
            case 3, 4: return .few
            default: return .other
            }
        case "he":
            if i == 1 { return .one }
            return i == 2 ? .two : .other
        case "ca":
            if i == 1 { return .one }
            return i != 0 && i % 1_000_000 == 0 ? .many : .other
        case "fr":
            return i == 0 || i == 1 ? .one : (i != 0 && i % 1_000_000 == 0 ? .many : .other)
        case "es", "it", "pt":
            if i == 1 || (i == 0 && language.lowercased().replacingOccurrences(of: "_", with: "-") == "pt-br") { return .one }
            return i != 0 && i % 1_000_000 == 0 ? .many : .other
        case "ro":
            if i == 1 { return .one }
            if i == 0 || (1...19).contains(i % 100) { return .few }
            return .other
        case "ru", "uk":
            if i % 10 == 1 && i % 100 != 11 { return .one }
            if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return .few }
            return .many
        case "pl":
            if i == 1 { return .one }
            if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return .few }
            return .many
        case "ar":
            if i == 0 { return .zero }
            if i == 1 { return .one }
            if i == 2 { return .two }
            if (3...10).contains(i % 100) { return .few }
            if (11...99).contains(i % 100) { return .many }
            return .other
        default:
            // de, en, nl, tr, da, fi, el, hu, nb, sv, mr, or, ta, te, ml, ur und Rückfall.
            return i == 1 ? .one : .other
        }
    }

    /// Reihenfolge, in der Formen probiert werden (gewählte Form, dann `other`).
    public static func lookupOrder(_ n: Int, language: String) -> [PluralCategory] {
        let c = category(n, language: language)
        return c == .other ? [.other] : [c, .other]
    }
}
