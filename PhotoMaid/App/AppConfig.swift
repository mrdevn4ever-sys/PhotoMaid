import Foundation

/// Build-Konfiguration aus der Info.plist (Werte kommen aus Build-Einstellungen bzw. CI-Secrets, nie aus dem Repo).
enum AppConfig {
    /// Produkt-ID des Einmalkaufs „PhotoMaid Pro“ (Non-Consumable). Leer = Käufe in diesem Build nicht verfügbar.
    static var proProductID: String? { nonEmpty("PMProProductID") }

    /// Datenschutzerklärung (öffentliche Seite des Inhabers). Leer = Link wird nicht gezeigt.
    static var privacyPolicyURL: URL? { nonEmpty("PMPrivacyPolicyURL").flatMap(URL.init(string:)) }

    /// Werbung/Rewarded: aus, bis Entscheidung E1 getroffen ist (`docs/IOS_ENTSCHEIDUNGEN.md`). Kein Werbe-SDK im Build.
    static let adsEnabled = false

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
