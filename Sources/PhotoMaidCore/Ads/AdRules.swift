import Foundation

/// Werbung beim App-Start (E19, Nutzerentscheidung 14.10.2026): bei jedem Kaltstart – außer den ersten drei Starts nach
/// der Installation. Nie mit Pro, nie ohne Einwilligung/Werbeerlaubnis. Gezählt wird lokal (nur eine Zahl).
public enum AppOpenAdPolicy {
    public static let freeStarts = 3

    /// `launchNumber`: 1 = erster Start nach der Installation.
    public static func shouldShow(launchNumber: Int, adsAllowed: Bool) -> Bool {
        adsAllowed && launchNumber > freeStarts
    }
}

/// Neuer Ordner im Tresor (E19): mit Pro frei, sonst je Ordner ein Belohnungsvideo. Ist Werbung in diesem Build gar
/// nicht eingerichtet, wird nichts gesperrt (kein toter Knopf); kann gerade keine Werbung geladen werden, bleibt Pro.
public enum VaultFolderAccess: Equatable, Sendable {
    /// Ordner sofort anlegen.
    case free
    /// Erst ein Belohnungsvideo, dann den Ordner anlegen.
    case watchAd
    /// Gerade keine Werbung möglich (z. B. Kaufstatus noch unklar, Einwilligung fehlt): Pro anbieten, später erneut.
    case unavailable

    public static func resolve(_ caps: Capabilities, adsConfigured: Bool, canRequestAds: Bool) -> VaultFolderAccess {
        if caps.vaultFoldersWithoutAd || !adsConfigured { return .free }
        return caps.adsAllowed && canRequestAds ? .watchAd : .unavailable
    }
}

/// Angebot „+100 für heute“ im Papierkorb: nur Free, nur wenn das heutige Limit erreicht/knapp ist und der Bonus heute
/// noch nicht genutzt wurde. Freigeschaltet wird nur nach dem Belohnungs-Callback des SDK (`RewardLedger.grantBonus`).
public enum LimitBonusOffer {
    public static func available(_ caps: Capabilities, rewards: RewardLedger, now: Date, timeZone: TimeZone,
                                 adsConfigured: Bool) -> Bool {
        adsConfigured && caps.adsAllowed && !caps.isLifetimePro
            && !rewards.bonusUsedToday(now: now, timeZone: timeZone)
    }
}
