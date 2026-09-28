import PhotoMaidCore
import SwiftUI

/// Screen 14 – PhotoMaid Pro. Einmalkauf, echter Storepreis, Wiederherstellen,
/// freiwillige Rewarded-Vorschau (30 Minuten, 1× pro Tag, Tageslimit bleibt 15).
struct ProView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var message: String?

    private var purchases: any PurchaseGateway { app.entitlements.purchases }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                Image(systemName: "crown.fill").font(.system(size: 48)).foregroundStyle(AppColors.accent)
                    .padding(AppSpacing.l).glassEffect(.regular, in: .rect(cornerRadius: AppRadii.card))
                    .accessibilityHidden(true)
                Text("PhotoMaid Pro").font(AppTypography.largeTitle)
                Text("Mehr Werkzeuge für das, was zählt.").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        feature("infinity", "Einmaliger Kauf", "Kein Abo.")
                        feature("trash", "Unbegrenzt bereinigen", "Statt 15 bestätigten Bereinigungen pro Tag.")
                        feature("magnifyingglass", "Exakte Duplikate finden", "Byte-identische Kopien per SHA-256.")
                        feature("square.grid.2x2", "Erweiterte Datei- und Speicherwerkzeuge", "Für verbundene Ordner.")
                        feature("gearshape.2", "Dauerhaft aktive Regeln & Routinen", "Prüfaufgaben automatisch vorbereiten.")
                        feature("nosign", "Keine Werbung", "Auch keine freiwillige Werbung mehr.")
                    }
                }

                purchaseSection
                rewardSection

                Text("Analyse und Sortierung erfolgen auf deinem Gerät. Für Kauf und Werbung werden technische Daten an Apple, RevenueCat bzw. den Werbeanbieter übertragen – keine Fotos, Dateinamen oder Hashes.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
            }
            .padding(AppSpacing.pageMargin)
        }
        .background(AppBackground())
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        .task { await purchases.refresh() }
        .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        switch purchases.state {
        case .purchased:
            Label("Pro ist aktiv. Danke!", systemImage: "checkmark.seal.fill").foregroundStyle(AppColors.success)
        case .pending:
            Label("Kauf ausstehend (z. B. Genehmigung durch Familie).", systemImage: "hourglass")
        default:
            VStack(spacing: AppSpacing.s) {
                if purchases.isConfigured, let product = purchases.product {
                    Button {
                        Task { await buy() }
                    } label: {
                        VStack {
                            Text("PhotoMaid Pro freischalten").font(AppTypography.headline)
                            Text("\(product.localizedPrice) · Einmalkauf").font(AppTypography.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large).disabled(busy)
                } else {
                    // Ohne echte Storekonfiguration kein erfundener Preis und kein toter Button.
                    Text(purchases.isConfigured ? "Preis wird geladen …" : "Käufe sind in dieser Version noch nicht verfügbar.")
                        .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                if purchases.isConfigured {
                    Button("Käufe wiederherstellen") { Task { await restore() } }.buttonStyle(.glass).disabled(busy)
                }
                if purchases.state == .revoked {
                    Text("Ein früherer Kauf wurde erstattet oder widerrufen.").font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var rewardSection: some View {
        let caps = app.capabilities
        if caps.tier == .rewardedPreview, let remaining = caps.rewardRemaining {
            SurfaceCard {
                Label("Pro-Vorschau aktiv: noch \(Int(remaining / 60) + 1) Min.", systemImage: "timer")
            }
        } else if purchases.state != .purchased {
            VStack(spacing: AppSpacing.xs) {
                Button {
                    Task { await watchAd() }
                } label: {
                    VStack {
                        Text("Pro mit einer Werbe-Vorschau testen").font(AppTypography.subheadline.weight(.semibold))
                        Text("Freiwillig: 30 Minuten Pro-Werkzeuge, einmal pro Tag.").font(AppTypography.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(!app.entitlements.canOfferReward || busy)
                if !app.entitlements.ads.isConfigured {
                    Text("Die Werbe-Vorschau ist in dieser Version noch nicht verfügbar.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
                Text("Das Tageslimit von 15 Bereinigungen bleibt auch in der Vorschau bestehen.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            Image(systemName: symbol).foregroundStyle(AppColors.accent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTypography.subheadline.weight(.semibold))
                Text(detail).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func buy() async {
        busy = true; defer { busy = false }
        app.player.stop()
        switch await purchases.purchasePro() {
        case .purchased: message = String(localized: "PhotoMaid Pro ist jetzt aktiv.")
        case .pending: message = String(localized: "Der Kauf ist ausstehend. Pro wird aktiv, sobald er genehmigt ist.")
        case .cancelled: break
        case .failed: message = String(localized: "Der Kauf konnte nicht abgeschlossen werden.")
        case .notConfigured: message = String(localized: "Käufe sind in dieser Version noch nicht verfügbar.")
        }
        await app.reload()
    }

    private func restore() async {
        busy = true; defer { busy = false }
        switch await purchases.restore() {
        case .purchased: message = String(localized: "Dein Kauf wurde wiederhergestellt.")
        default: message = String(localized: "Es wurde kein Kauf zum Wiederherstellen gefunden.")
        }
        await app.reload()
    }

    private func watchAd() async {
        busy = true; defer { busy = false }
        let result = await app.entitlements.watchRewardedAd(pausePlayback: { app.player.stop() })
        switch result {
        case .rewarded: message = String(localized: "Pro-Vorschau für 30 Minuten aktiv.")
        case .dismissedWithoutReward: message = String(localized: "Die Anzeige wurde vorzeitig geschlossen. Es wurde nichts freigeschaltet.")
        case .noFill: message = String(localized: "Gerade ist keine Anzeige verfügbar.")
        case .failed, .notConfigured: message = String(localized: "Die Werbe-Vorschau ist gerade nicht verfügbar.")
        }
    }
}
