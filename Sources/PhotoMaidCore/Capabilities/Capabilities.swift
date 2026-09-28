import Foundation

/// Kaufstatus aus dem einzigen Kauf-Gateway (RevenueCat über Apple-IAP).
public enum PurchaseState: Hashable, Codable, Sendable {
    case unknown
    case notPurchased
    case pending
    case purchased
    /// Erstattet/widerrufen.
    case revoked
}

/// Freiwillig freigeschaltete Rewarded-Vorschau: 30 reale Minuten Pro-Werkzeuge.
public struct RewardWindow: Hashable, Codable, Sendable {
    public let rewardID: String
    public let grantedAt: Date
    public let grantedDay: LocalDay
    public static let duration: TimeInterval = 30 * 60

    public var endsAt: Date { grantedAt.addingTimeInterval(Self.duration) }

    /// Restzeit. Läuft im Hintergrund weiter. Uhr zurückgestellt → konservativ abgelaufen.
    public func remaining(at now: Date) -> TimeInterval {
        guard now >= grantedAt else { return 0 }
        return max(0, min(Self.duration, endsAt.timeIntervalSince(now)))
    }
}

public enum RewardError: Error, Hashable, Sendable {
    case alreadyPurchased
    case dailyUnlockUsed
}

/// Lokale, persistierte Reward-Buchführung (idempotent).
public struct RewardLedger: Hashable, Codable, Sendable {
    public private(set) var windows: [RewardWindow] = []
    public init() {}

    /// Nur nach tatsächlichem SDK-Reward-Callback aufrufen.
    /// Gleiche `rewardID` erneut → keine zweite Freischaltung.
    public mutating func grant(rewardID: String, now: Date, timeZone: TimeZone,
                               purchase: PurchaseState) throws -> RewardWindow {
        if let existing = windows.first(where: { $0.rewardID == rewardID }) { return existing }
        guard purchase != .purchased else { throw RewardError.alreadyPurchased }
        let day = LocalDay(now, timeZone: timeZone)
        guard !windows.contains(where: { $0.grantedDay == day }) else { throw RewardError.dailyUnlockUsed }
        let w = RewardWindow(rewardID: rewardID, grantedAt: now, grantedDay: day)
        windows.append(w)
        return w
    }

    public func active(at now: Date) -> RewardWindow? {
        windows.last.flatMap { $0.remaining(at: now) > 0 ? $0 : nil }
    }

    public func canOfferReward(now: Date, timeZone: TimeZone, purchase: PurchaseState) -> Bool {
        guard purchase != .purchased else { return false }
        let day = LocalDay(now, timeZone: timeZone)
        return !windows.contains { $0.grantedDay == day }
    }
}

/// Zentrale Capability-Auflösung. Einzige Stelle, die Free/Pro/Rewarded unterscheidet.
public struct Capabilities: Hashable, Sendable {
    public static let freeDailyCleanupLimit = 15

    public enum Tier: Hashable, Sendable { case free, rewardedPreview, pro }

    public let tier: Tier
    /// `nil` = unbegrenzt.
    public let dailyCleanupLimit: Int?
    public let exactDuplicates: Bool
    public let advancedFileTools: Bool
    /// Dauerhaft aktive Regeln/Routinen (Rewarded: nur einmaliger Testscan).
    public let persistentRoutines: Bool
    public let oneTimeRuleTestScan: Bool
    /// Werbung darf angeboten/angefragt werden (nie für Pro).
    public let adsAllowed: Bool
    public let rewardRemaining: TimeInterval?

    public static func resolve(purchase: PurchaseState, rewards: RewardLedger, now: Date) -> Capabilities {
        if purchase == .purchased {
            return Capabilities(tier: .pro, dailyCleanupLimit: nil, exactDuplicates: true,
                                advancedFileTools: true, persistentRoutines: true,
                                oneTimeRuleTestScan: true, adsAllowed: false, rewardRemaining: nil)
        }
        if let w = rewards.active(at: now) {
            return Capabilities(tier: .rewardedPreview, dailyCleanupLimit: freeDailyCleanupLimit,
                                exactDuplicates: true, advancedFileTools: true, persistentRoutines: false,
                                oneTimeRuleTestScan: true, adsAllowed: true,
                                rewardRemaining: w.remaining(at: now))
        }
        return Capabilities(tier: .free, dailyCleanupLimit: freeDailyCleanupLimit, exactDuplicates: false,
                            advancedFileTools: false, persistentRoutines: false, oneTimeRuleTestScan: false,
                            // Bei unbekanntem Kaufstatus keine Ad-Requests, bis der Status geklärt ist.
                            adsAllowed: purchase != .unknown, rewardRemaining: nil)
    }
}

/// Begrenzte Arbeitseinheit (z. B. ein Duplikat-Scan), die bei Ablauf der Vorschau
/// noch abgeschlossen wird. Gespeicherte Entscheidungen bleiben immer erhalten.
public struct WorkUnitGrant: Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date

    /// Startet nur, wenn die Fähigkeit jetzt vorhanden ist.
    public static func begin(requires keyPath: KeyPath<Capabilities, Bool>, in caps: Capabilities,
                             now: Date) -> WorkUnitGrant? {
        caps[keyPath: keyPath] ? WorkUnitGrant(id: UUID(), startedAt: now) : nil
    }
}
