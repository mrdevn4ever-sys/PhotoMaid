import Foundation

/// Kaufstatus aus dem einzigen Kauf-Gateway (StoreKit 2).
public enum PurchaseState: String, Hashable, Codable, Sendable {
    case unknown
    case notPurchased
    case pending
    case purchased
    /// Erstattet/widerrufen.
    case revoked
}

/// Freiwillig freigeschaltete Rewarded-Vorschau: 30 reale Minuten Pro-Werkzeuge.
/// Auf iOS nur aktiv, wenn ein Werbeanbieter entschieden ist (`docs/IOS_ENTSCHEIDUNGEN.md`, E1).
public struct RewardWindow: Hashable, Codable, Sendable {
    public let rewardID: String
    public let grantedAt: Date
    public let grantedDay: LocalDay
    public static let duration: TimeInterval = 30 * 60

    public init(rewardID: String, grantedAt: Date, grantedDay: LocalDay) {
        self.rewardID = rewardID
        self.grantedAt = grantedAt
        self.grantedDay = grantedDay
    }

    public var endsAt: Date { grantedAt.addingTimeInterval(Self.duration) }

    /// Restzeit. Läuft im Hintergrund weiter. Uhr zurückgestellt → konservativ abgelaufen.
    public func remaining(at now: Date) -> TimeInterval {
        guard now >= grantedAt else { return 0 }
        return max(0, min(Self.duration, endsAt.timeIntervalSince(now)))
    }
}

/// Freiwilliger Video-Bonus „+100 heute“: hebt das Limit zum Entfernen für EINEN lokalen Tag an.
public struct LimitBonus: Hashable, Codable, Sendable {
    public let rewardID: String
    public let grantedAt: Date
    public let grantedDay: LocalDay
    /// E19 (Nutzerentscheidung 14.10.2026): +100, einmal je lokalem Tag (vorher Android: +20).
    public static let amount = 100

    public init(rewardID: String, grantedAt: Date, grantedDay: LocalDay) {
        self.rewardID = rewardID
        self.grantedAt = grantedAt
        self.grantedDay = grantedDay
    }
}

public enum RewardError: Error, Hashable, Sendable {
    case alreadyPurchased
    case dailyUnlockUsed
    case dailyBonusUsed
}

/// Lokale, persistierte Reward-Buchführung (idempotent).
public struct RewardLedger: Hashable, Codable, Sendable {
    public private(set) var windows: [RewardWindow]
    public private(set) var bonuses: [LimitBonus]

    public init(windows: [RewardWindow] = [], bonuses: [LimitBonus] = []) {
        self.windows = windows
        self.bonuses = bonuses
    }

    private enum CodingKeys: String, CodingKey { case windows, bonuses }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windows = try c.decodeIfPresent([RewardWindow].self, forKey: .windows) ?? []
        bonuses = try c.decodeIfPresent([LimitBonus].self, forKey: .bonuses) ?? []
    }

    /// Nur nach tatsächlichem SDK-Reward-Callback aufrufen. Gleiche `rewardID` → keine zweite Freischaltung.
    @discardableResult
    public mutating func grant(rewardID: String, now: Date, timeZone: TimeZone,
                               purchase: PurchaseState) throws -> RewardWindow {
        if let existing = windows.first(where: { $0.rewardID == rewardID }) { return existing }
        guard purchase != .purchased else { throw RewardError.alreadyPurchased }
        guard !usedToday(now: now, timeZone: timeZone) else { throw RewardError.dailyUnlockUsed }
        let w = RewardWindow(rewardID: rewardID, grantedAt: now, grantedDay: LocalDay(now, timeZone: timeZone))
        windows.append(w)
        return w
    }

    public func active(at now: Date) -> RewardWindow? {
        windows.last.flatMap { $0.remaining(at: now) > 0 ? $0 : nil }
    }

    /// Heute schon genutzt? Auch „ja“, wenn die Uhr vor den letzten Reward zurückgestellt wurde (konservativ).
    public func usedToday(now: Date, timeZone: TimeZone) -> Bool {
        let day = LocalDay(now, timeZone: timeZone)
        return windows.contains { $0.grantedDay == day } || windows.contains { now < $0.grantedAt }
    }

    public func canOfferReward(now: Date, timeZone: TimeZone, purchase: PurchaseState) -> Bool {
        purchase != .purchased && !usedToday(now: now, timeZone: timeZone)
    }

    /// „+100 heute“ – unabhängig vom Pro-Test, 1× pro lokalem Tag, nur nach SDK-Reward-Callback.
    @discardableResult
    public mutating func grantBonus(rewardID: String, now: Date, timeZone: TimeZone,
                                    purchase: PurchaseState) throws -> LimitBonus {
        if let existing = bonuses.first(where: { $0.rewardID == rewardID }) { return existing }
        guard purchase != .purchased else { throw RewardError.alreadyPurchased }
        guard !bonusUsedToday(now: now, timeZone: timeZone) else { throw RewardError.dailyBonusUsed }
        let b = LimitBonus(rewardID: rewardID, grantedAt: now, grantedDay: LocalDay(now, timeZone: timeZone))
        bonuses = Array((bonuses + [b]).suffix(14))
        return b
    }

    /// Heute schon genutzt? Auch „ja“ bei zurückgestellter Uhr (konservativ: kein zweiter Bonus).
    public func bonusUsedToday(now: Date, timeZone: TimeZone) -> Bool {
        let day = LocalDay(now, timeZone: timeZone)
        return bonuses.contains { $0.grantedDay == day } || bonuses.contains { now < $0.grantedAt }
    }

    /// Zusätzliche Löschungen für den heutigen Tag (nur der Bonus von genau heute zählt).
    public func cleanupBonus(now: Date, timeZone: TimeZone) -> Int {
        let day = LocalDay(now, timeZone: timeZone)
        return bonuses.contains { $0.grantedDay == day && now >= $0.grantedAt } ? LimitBonus.amount : 0
    }
}

/// Zentrale Capability-Auflösung. Einzige Stelle, die Free / Lifetime Pro unterscheidet.
///
/// E19 (Nutzerentscheidung 14.10.2026): Alle Werkzeuge sind für alle frei. Pro (Einmalkauf) heißt nur noch:
/// | Stufe          | Werkzeuge | Werbung | Entfernen je Tag              | Neuer Tresor-Ordner     |
/// |----------------|-----------|---------|-------------------------------|-------------------------|
/// | free           | alle      | ja      | 100 (+100 per Video, 1×/Tag)  | je Ordner ein Video     |
/// | lifetimePro    | alle      | nein    | unbegrenzt                    | frei                    |
/// `temporaryPro` (30-Minuten-Test) wird auf iOS nicht mehr angeboten; ein alter Eintrag zählt wie Free.
public struct Capabilities: Hashable, Sendable {
    public enum Tier: String, Hashable, Sendable { case free, temporaryPro, lifetimePro }

    /// E19 (Nutzerentscheidung 14.10.2026): 100 endgültige Entfernungen pro lokalem Tag (vorher 20 wie Android).
    public static let freeDailyCleanupLimit = 100
    /// Free-Grenze je Durchgang für Stapel-Werkzeuge, Abläufe, Auslagern, PDF (wie Android).
    public static let freeBatchLimit = 10

    public let tier: Tier
    /// Werbung darf angeboten/angefragt werden (nie für Lifetime Pro, nie bei unklarem Kaufstatus).
    /// Auf iOS zusätzlich nur, wenn `AppConfig.adsEnabled` (E1) – sonst nie.
    public let adsAllowed: Bool
    /// Restzeit des 30-Minuten-Pro-Tests, sonst `nil`.
    public let rewardRemaining: TimeInterval?
    /// Zusätzliche Löschungen heute aus dem Video-Bonus (0 oder `LimitBonus.amount`).
    public let cleanupBonus: Int

    public init(tier: Tier, adsAllowed: Bool, rewardRemaining: TimeInterval?, cleanupBonus: Int = 0) {
        self.tier = tier
        self.adsAllowed = adsAllowed
        self.rewardRemaining = rewardRemaining
        self.cleanupBonus = cleanupBonus
    }

    /// Werkzeuge (Bearbeiten, Analyse, Duplikate, Sammlungen, Studio …): E19 – für alle frei.
    public var hasProToolsAccess: Bool { true }
    /// Gekauftes Pro (für Anzeige „Pro ist aktiv“ und alles, was nur der Kauf freischaltet).
    public var isLifetimePro: Bool { tier == .lifetimePro }
    /// Neuer Ordner im Tresor ohne Werbevideo (E19: nur mit Pro).
    public var vaultFoldersWithoutAd: Bool { tier == .lifetimePro }
    /// Nur der Kauf hebt das tägliche Papierkorb-Limit auf. Der Pro-Test ändert es NICHT.
    public var hasUnlimitedTrashAccess: Bool { tier == .lifetimePro }
    /// `nil` = unbegrenzt. Abgeleitet ausschließlich aus `hasUnlimitedTrashAccess`.
    public var dailyCleanupLimit: Int? { hasUnlimitedTrashAccess ? nil : Self.freeDailyCleanupLimit + cleanupBonus }

    public var exactDuplicates: Bool { hasProToolsAccess }
    /// Eigene Sammlungen anlegen und öffnen (fertige Sammlungen sind für alle).
    public var customCollections: Bool { hasProToolsAccess }
    /// Fotoserien vergleichen.
    public var seriesCompare: Bool { hasProToolsAccess }
    /// Stapel/Abläufe/Auslagern/PDF: `nil` = ohne Grenze.
    public var batchLimit: Int? { hasProToolsAccess ? nil : Self.freeBatchLimit }

    // iOS-eigene Funktionen (Entscheidung E10, vorläufig – nur hier ändern).
    /// Freistellen/Hintergrund entfernen.
    public var subjectLift: Bool { hasProToolsAccess }
    /// Ähnliche, unscharfe, doppelte Aufnahmen (lokale Bildanalyse).
    public var smartReview: Bool { hasProToolsAccess }
    /// Bearbeitungsrezept auf mehrere Fotos anwenden.
    public var batchEditing: Bool { hasProToolsAccess }
    /// Scannen, Texterkennung, PDF-Seiten bearbeiten, Unterschrift: für alle.
    public var documentTools: Bool { true }

    public static func resolve(purchase: PurchaseState, rewards: RewardLedger, now: Date,
                               timeZone: TimeZone = .autoupdatingCurrent) -> Capabilities {
        // Lifetime Pro gewinnt immer (auch während eines laufenden Tests).
        if purchase == .purchased {
            return Capabilities(tier: .lifetimePro, adsAllowed: false, rewardRemaining: nil)
        }
        let bonus = rewards.cleanupBonus(now: now, timeZone: timeZone)
        // Bei unbekanntem Kaufstatus keine Ad-Requests, bis der Status geklärt ist. Kein Pro-Test mehr (E19).
        return Capabilities(tier: .free, adsAllowed: purchase != .unknown, rewardRemaining: nil, cleanupBonus: bonus)
    }
}

/// Begrenzte Arbeitseinheit (z. B. ein Duplikat-Scan), die bei Ablauf der Vorschau noch abgeschlossen wird.
/// Gespeicherte Entscheidungen bleiben immer erhalten.
public struct WorkUnitGrant: Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date

    /// Startet nur, wenn die Fähigkeit jetzt vorhanden ist.
    public static func begin(requires keyPath: KeyPath<Capabilities, Bool>, in caps: Capabilities,
                             now: Date) -> WorkUnitGrant? {
        caps[keyPath: keyPath] ? WorkUnitGrant(id: UUID(), startedAt: now) : nil
    }
}
