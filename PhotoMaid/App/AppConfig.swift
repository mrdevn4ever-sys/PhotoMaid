import Foundation

/// Build-Konfiguration aus der Info.plist (Werte kommen aus Build-Einstellungen bzw. CI-Secrets, nie aus dem Repo).
enum AppConfig {
    /// Sichtbarer Produktname (seit 23.10.2026 „Arrumo“, vorher „PhotoMaid“ – Markenkonflikt mit „photoAiD“). Gilt für
    /// Dateinamen, Ordner und Metadaten, die Nutzer sehen. Texte kommen aus dem Katalog (`scripts/…xcstrings.py`
    /// ersetzt den Namen dort). Interne Namen – Projekt, Module, Datenbank, Schlüsselbund, Warteschlangen – bleiben
    /// „PhotoMaid“, damit vorhandene Daten und der Tresor erhalten bleiben.
    static let brandName = "Arrumo"

    /// Produkt-ID des Einmalkaufs „PhotoMaid Pro“ (Non-Consumable). Leer = Käufe in diesem Build nicht verfügbar.
    static var proProductID: String? { nonEmpty("PMProProductID") }

    /// Datenschutzerklärung (öffentliche Seite des Inhabers). Leer = Link wird nicht gezeigt.
    static var privacyPolicyURL: URL? { nonEmpty("PMPrivacyPolicyURL").flatMap(URL.init(string:)) }

    /// Werbung (E1/E19, Nutzerentscheidung 14.10.2026): Google Mobile Ads nur in der Gratis-Version. An, sobald alle
    /// Anzeigenblöcke eingetragen sind (Build-Einstellungen `PM_ADMOB_*`; ohne eigene IDs Googles öffentliche Test-IDs).
    static var adsEnabled: Bool { adMob != nil }

    /// Anzeigenblöcke aus der Info.plist. Echte IDs nur über CI (Secrets/Variablen), nie im Repo.
    static var adMob: AdMobUnits? {
        guard nonEmpty("GADApplicationIdentifier") != nil, let appOpen = nonEmpty("PMAdMobAppOpenID"),
              let native = nonEmpty("PMAdMobNativeID"), let rewarded = nonEmpty("PMAdMobRewardedID") else { return nil }
        return AdMobUnits(appOpen: appOpen, native: native, rewarded: rewarded)
    }

    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    static var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }

    private static func nonEmpty(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nicht ersetzte Build-Variable („$(PM_…)“) zählt als leer.
        return t.isEmpty || t.hasPrefix("$(") ? nil : t
    }
}

/// Anzeigenblöcke (AdMob). `isTest`: Googles öffentliche Test-Anzeigen (keine Einnahmen, für Entwicklung/TestFlight).
struct AdMobUnits: Equatable, Sendable {
    let appOpen: String
    let native: String
    let rewarded: String
    var isTest: Bool { [appOpen, native, rewarded].allSatisfy { $0.hasPrefix(Self.googleTestPublisher) } }
    static let googleTestPublisher = "ca-app-pub-3940256099942544/"
}
