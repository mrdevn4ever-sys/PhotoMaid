import Foundation
import PhotoMaidCore
import SwiftUI

/// Texte aus `Localizable.xcstrings`. Kennungen wie in der Android-App (`res/values*/strings.xml`), erzeugt von
/// `scripts/android_strings_to_xcstrings.py`. Nie feste Texte in Views.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// Text mit Platzhaltern (`%1$@`, `%1$lld`). Zahlen als `Int`, Texte als `String` übergeben.
func L(_ key: String, _ args: any CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}

/// Mengenform nach CLDR (`PluralRules`): sucht `kennung#few`, sonst `kennung#other`. Wie Android
/// `getQuantityString(id, count, args…)` – `count` wählt die Form, `args` füllen die Platzhalter.
func LP(_ key: String, _ count: Int, _ args: any CVarArg...) -> String {
    let language = Strings.language
    for category in PluralRules.lookupOrder(count, language: language) {
        let k = "\(key)#\(category.rawValue)"
        let v = Bundle.main.localizedString(forKey: k, value: Strings.missing, table: nil)
        if v != Strings.missing {
            return String(format: v, locale: Locale.current, arguments: args.isEmpty ? [count] : args)
        }
    }
    return key
}

enum Strings {
    static let missing = "\u{0}missing"

    /// Tatsächlich verwendete Sprache der App (nicht nur die Gerätesprache).
    static var language: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// Leserichtung: Gestenpfeile werden in RTL nie gespiegelt (physische Fingerrichtung).
    static var isRightToLeft: Bool { Locale.Language(identifier: language).characterDirection == .rightToLeft }
}

extension Text {
    /// Kurzform: `Text(key: "today_title")`.
    init(key: String) { self.init(verbatim: L(key)) }
}
