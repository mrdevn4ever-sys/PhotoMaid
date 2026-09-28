import Foundation
import Observation
import PhotoMaidCore

/// Freiwillige Rewarded-Werbung. Belohnung NUR nach tatsächlichem SDK-Reward-Callback.
/// Keine Banner, keine Interstitials, keine App-Open-Ads. Keine Requests für Pro-Nutzer.
enum RewardedAdResult: Equatable, Sendable {
    /// SDK hat die Belohnung bestätigt. `rewardID` ist für Idempotenz eindeutig.
    case rewarded(rewardID: String)
    case dismissedWithoutReward
    case noFill
    case failed(String)
    case notConfigured
}

@MainActor
protocol RewardedAdGateway: AnyObject {
    var isConfigured: Bool { get }
    /// Lädt und zeigt eine Anzeige. Aufrufer stellt sicher: kein Pro, Tageslimit frei.
    func presentRewardedAd() async -> RewardedAdResult
}

/// Werbeanbieter ist noch nicht festgelegt/konfiguriert (Release-Blocker).
/// Die Oberfläche zeigt die Vorschau dann als nicht verfügbar an – kein toter Button.
@MainActor
final class UnconfiguredRewardedAdGateway: RewardedAdGateway {
    let isConfigured = false
    func presentRewardedAd() async -> RewardedAdResult { .notConfigured }
}

/// Persistente Reward-Buchführung + Capability-Auflösung.
@MainActor
@Observable
final class EntitlementCenter {
    private(set) var rewards: RewardLedger
    /// Beobachtbarer Zeitstempel: `RootView` erhöht ihn alle 30 s und bei Resume,
    /// damit Restzeit und Ablauf in der UI sichtbar werden.
    private(set) var now = Date()
    @ObservationIgnored private let store: CoreDataStore
    @ObservationIgnored let purchases: any PurchaseGateway
    @ObservationIgnored let ads: any RewardedAdGateway
    private static let key = "rewards.ledger"

    init(store: CoreDataStore, purchases: any PurchaseGateway, ads: any RewardedAdGateway) {
        self.store = store
        self.purchases = purchases
        self.ads = ads
        rewards = store.value(RewardLedger.self, forKey: Self.key) ?? RewardLedger()
    }

    /// Wird immer mit der aktuellen Uhrzeit aufgelöst (Ablauf der Vorschau greift sofort).
    /// `now` wird gelesen, damit SwiftUI bei `tick()` neu rendert.
    var capabilities: Capabilities {
        _ = now
        return Capabilities.resolve(purchase: purchases.state, rewards: rewards, now: Date())
    }

    func tick() { now = Date() }

    var canOfferReward: Bool {
        ads.isConfigured && capabilities.adsAllowed
            && rewards.canOfferReward(now: Date(), timeZone: .autoupdatingCurrent, purchase: purchases.state)
    }

    /// Zeigt eine freiwillige Anzeige; schaltet nur nach Reward-Callback frei.
    func watchRewardedAd(pausePlayback: () -> Void) async -> RewardedAdResult {
        guard canOfferReward else { return .notConfigured }
        pausePlayback()
        let result = await ads.presentRewardedAd()
        if case .rewarded(let id) = result {
            var ledger = rewards
            if (try? ledger.grant(rewardID: id, now: Date(), timeZone: .autoupdatingCurrent,
                                  purchase: purchases.state)) != nil {
                try? store.setValue(ledger, forKey: Self.key)
                rewards = ledger
            }
        }
        tick()
        return result
    }
}
