import Foundation
import Observation
import PhotoMaidCore
import RevenueCat

/// Einzige Entitlement-Wahrheit: RevenueCat über Apple-IAP. Kein paralleles StoreKit-System.
/// Es werden keine Medien, Hashes, Dateinamen, Pfade oder Review-Daten übertragen.
struct StoreProductInfo: Equatable, Sendable {
    /// Lokalisierter Preis aus dem echten Storeprodukt.
    let localizedPrice: String
    let title: String
}

enum PurchaseResult: Equatable, Sendable {
    case purchased
    case pending
    case cancelled
    case failed(String)
    case notConfigured
}

@MainActor
protocol PurchaseGateway: AnyObject {
    var state: PurchaseState { get }
    var product: StoreProductInfo? { get }
    var isConfigured: Bool { get }
    func refresh() async
    func purchasePro() async -> PurchaseResult
    func restore() async -> PurchaseResult
}

/// Solange API-Key und Entitlement nicht konfiguriert sind: ehrlich „nicht verfügbar“.
@MainActor
@Observable
final class UnconfiguredPurchaseGateway: PurchaseGateway {
    private(set) var state: PurchaseState = .notPurchased
    let product: StoreProductInfo? = nil
    let isConfigured = false
    func refresh() async {}
    func purchasePro() async -> PurchaseResult { .notConfigured }
    func restore() async -> PurchaseResult { .notConfigured }
}

@MainActor
@Observable
final class RevenueCatPurchaseGateway: PurchaseGateway {
    private(set) var state: PurchaseState = .unknown
    private(set) var product: StoreProductInfo?
    let isConfigured = true
    @ObservationIgnored private let entitlementID: String
    @ObservationIgnored private var package: Package?
    @ObservationIgnored private let cache: CoreDataStore
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    private static let cacheKey = "purchase.cachedState"

    init(apiKey: String, entitlementID: String, cache: CoreDataStore) {
        self.entitlementID = entitlementID
        self.cache = cache
        // Offline-Cache: letzter bekannter Status bis zur nächsten Bestätigung.
        if let cached = cache.value(PurchaseState.self, forKey: Self.cacheKey) { state = cached }
        Purchases.logLevel = .warn
        Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey).build())
        updatesTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await self?.apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        let active = info.entitlements[entitlementID]?.isActive == true
        let hadPurchase = info.entitlements[entitlementID] != nil
        // Refund/Revocation: Entitlement vorhanden, aber nicht mehr aktiv.
        let new: PurchaseState = active ? .purchased : (hadPurchase ? .revoked : .notPurchased)
        if new != state {
            state = new
            try? cache.setValue(new, forKey: Self.cacheKey)
        }
    }

    func refresh() async {
        if let info = try? await Purchases.shared.customerInfo() { apply(info) }
        if let offerings = try? await Purchases.shared.offerings(),
           let pkg = offerings.current?.availablePackages.first(where: { $0.packageType == .lifetime })
            ?? offerings.current?.availablePackages.first {
            package = pkg
            product = StoreProductInfo(localizedPrice: pkg.storeProduct.localizedPriceString,
                                       title: pkg.storeProduct.localizedTitle)
        }
    }

    func purchasePro() async -> PurchaseResult {
        if package == nil { await refresh() }
        guard let package else { return .failed("no-product") }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            apply(result.customerInfo)
            return state == .purchased ? .purchased : .pending
        } catch let error as ErrorCode where error == .paymentPendingError {
            state = .pending
            return .pending // Ask-to-Buy / ausstehend
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
    }

    func restore() async -> PurchaseResult {
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            return state == .purchased ? .purchased : .failed("nothing-to-restore")
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
    }
}

enum PurchaseGatewayFactory {
    @MainActor
    static func make(store: CoreDataStore) -> any PurchaseGateway {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["PMRevenueCatAPIKey"] as? String) ?? ""
        let entitlement = (info["PMProEntitlementID"] as? String) ?? ""
        #if QA_FIXTURES
        if QAFixtures.isActive { return QAPurchaseGateway(pro: QAFixtures.proEnabled) }
        #endif
        guard !key.isEmpty, !entitlement.isEmpty else { return UnconfiguredPurchaseGateway() }
        return RevenueCatPurchaseGateway(apiKey: key, entitlementID: entitlement, cache: store)
    }
}
