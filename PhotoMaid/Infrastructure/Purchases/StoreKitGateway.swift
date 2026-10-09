import Foundation
import Observation
import PhotoMaidCore
import StoreKit
import SwiftUI

/// Preis und Name kommen ausschließlich aus dem echten Store-Produkt (`Product.displayPrice`). Nie ein fester Preis.
struct StoreProductInfo: Equatable, Sendable {
    let displayPrice: String
    let displayName: String
}

enum PurchaseResult: Equatable, Sendable {
    case purchased
    case pending
    case cancelled
    case failed
    case notConfigured
    case restored
    case nothingToRestore
}

/// Einziges Kauf-Gateway: StoreKit 2, Einmalkauf (Non-Consumable). Kein Abo, kein Konto, kein Server, kein
/// Drittanbieter. Es werden keine Medien, Namen, Pfade oder IDs übertragen – StoreKit kennt nur die Produkt-ID.
@MainActor
@Observable
final class StoreKitGateway {
    private(set) var state: PurchaseState
    private(set) var product: StoreProductInfo?
    private(set) var isBusy = false
    /// Laden des Produkts gescheitert (offline, Produkt nicht freigegeben). Kein erfundener Preis.
    private(set) var productUnavailable = false
    let productID: String?
    var isConfigured: Bool { productID != nil }

    @ObservationIgnored private var storeProduct: Product?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let kv: KeyValueStore?

    init(productID: String?, kv: KeyValueStore?) {
        self.productID = productID
        self.kv = kv
        // Offline-Cache: letzter bestätigter Status, bis StoreKit ihn erneut bestätigt.
        state = productID == nil ? .notPurchased : (kv?.get(StoreKeys.purchaseCache) ?? .unknown)
        guard productID != nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let t) = result else { continue }
                await t.finish()
                await self?.refresh()
            }
        }
    }

    /// Produkt laden und Berechtigung aus `Transaction.currentEntitlements` prüfen (funktioniert auch offline).
    func refresh() async {
        guard let productID else { set(.notPurchased); return }
        if storeProduct == nil {
            do {
                storeProduct = try await Product.products(for: [productID]).first
                productUnavailable = storeProduct == nil
            } catch {
                productUnavailable = true
                Diagnostics.log(.purchase, "product-load-failed")
            }
            if let p = storeProduct { product = StoreProductInfo(displayPrice: p.displayPrice, displayName: p.displayName) }
        }
        var found: PurchaseState = .notPurchased
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.productID == productID else { continue }
            if t.revocationDate == nil { found = .purchased }
        }
        if found != .purchased, let latest = await Transaction.latest(for: productID),
           case .verified(let t) = latest, t.revocationDate != nil {
            found = .revoked
        }
        // Ein laufender „Kaufen fragen“-Vorgang bleibt sichtbar, bis StoreKit ein Ergebnis liefert.
        if found == .notPurchased && state == .pending { return }
        set(found)
    }

    /// Kauf über die SwiftUI-Aktion `@Environment(\.purchase)` (zeigt das System-Kaufblatt).
    func purchasePro(using purchase: PurchaseAction) async -> PurchaseResult {
        guard isConfigured else { return .notConfigured }
        if storeProduct == nil { await refresh() }
        guard let p = storeProduct else { return .failed }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await purchase(p) {
            case .success(.verified(let t)):
                await t.finish()
                set(t.revocationDate == nil ? .purchased : .revoked)
                return t.revocationDate == nil ? .purchased : .failed
            case .success(.unverified):
                Diagnostics.log(.purchase, "unverified-transaction")
                return .failed
            case .pending:
                if state != .purchased { set(.pending) }
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            Diagnostics.log(.purchase, "purchase-error")
            return .failed
        }
    }

    /// „Käufe wiederherstellen“: `AppStore.sync()` (kann eine Anmeldung beim App Store verlangen).
    func restore() async -> PurchaseResult {
        guard isConfigured else { return .notConfigured }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            Diagnostics.log(.purchase, "restore-error")
            return .failed
        }
        await refresh()
        return state == .purchased ? .restored : .nothingToRestore
    }

    private func set(_ new: PurchaseState) {
        guard new != state else { return }
        state = new
        try? kv?.set(StoreKeys.purchaseCache, new)
    }

    #if QA_FIXTURES
    /// Nur QA-Builds: Status für Bildschirmprüfungen setzen (nie in Release).
    func qaOverride(_ s: PurchaseState) { state = s }
    #endif
}
