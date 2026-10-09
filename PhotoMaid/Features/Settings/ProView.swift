import StoreKit
import SwiftUI

struct ProView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.purchase) private var purchase
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                Image(systemName: "sparkles").font(.system(size: 54)).foregroundStyle(AppColors.accent)
                Text(key: app.capabilities.hasProToolsAccess ? "pro_active_title" : "pro_title").font(AppTypography.largeTitle)
                Text(key: app.capabilities.hasProToolsAccess ? "pro_active_sub" : "pro_subtitle").multilineTextAlignment(.center)
                ForEach([("pro_f1", "pro_f1d"), ("pro_f2", "pro_f2d"), ("pro_f3", "pro_f3d"), ("pro_f5", "pro_f5d")], id: \.0) { pair in
                    SurfaceCard { Text(key: pair.0).font(AppTypography.headline); Text(key: pair.1).foregroundStyle(AppColors.textSecondary) }
                }
                if !app.capabilities.hasProToolsAccess {
                    Button { Task { await buy() } } label: {
                        Text(verbatim: app.purchases.product.map { L("pro_unlock") + " · " + $0.displayPrice } ?? L("pro_price_loading"))
                    }.buttonStyle(.glassProminent).disabled(app.purchases.isBusy || !app.purchases.isConfigured)
                    Button(L("pro_restore")) { Task { await restore() } }.buttonStyle(.glass)
                }
                if let message { Text(verbatim: message).foregroundStyle(AppColors.textSecondary) }
                Text(key: "pro_privacy_no_ads").font(AppTypography.caption)
            }.padding(AppSpacing.pageMargin)
        }.appPage().navigationTitle(L("pro_title")).task { await app.purchases.refresh() }
    }

    private func buy() async { message = text(await app.purchases.purchasePro(using: purchase)) }
    private func restore() async { message = text(await app.purchases.restore()) }
    private func text(_ result: PurchaseResult) -> String {
        switch result {
        case .purchased: L("pro_msg_active")
        case .pending: L("pro_msg_pending")
        case .cancelled: ""
        case .failed: L("pro_msg_failed")
        case .notConfigured: L("pro_unavailable")
        case .restored: L("pro_msg_restored")
        case .nothingToRestore: L("pro_msg_nothing")
        }
    }
}
