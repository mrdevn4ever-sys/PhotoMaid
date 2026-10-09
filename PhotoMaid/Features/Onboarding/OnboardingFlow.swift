import StoreKit
import SwiftUI

struct OnboardingFlow: View {
    static let version = 1
    @Environment(AppModel.self) private var app
    @Environment(\.purchase) private var purchase
    @State private var page = 0

    private let pages = [("onb_story_title", "onb_story_text", "photo.stack"),
                         ("onb_try_title", "onb_try_text", "hand.draw"),
                         ("onb_safe_title", "onb_safe_text", "lock.shield"),
                         ("onb_offer_title", "onb_offer_text", "sparkles"),
                         ("onb_access_title", "onb_access_text", "photo.on.rectangle")]
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: AppSpacing.l) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(spacing: AppSpacing.l) {
                            Image(systemName: pages[index].2).font(.system(size: 64)).foregroundStyle(AppColors.accent)
                            Text(key: pages[index].0).font(AppTypography.largeTitle).multilineTextAlignment(.center)
                            Text(key: pages[index].1).multilineTextAlignment(.center).foregroundStyle(AppColors.textSecondary)
                        }.padding(AppSpacing.pageMargin).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .always))
                if page == 3, !app.capabilities.hasProToolsAccess {
                    Button {
                        Task { _ = await app.purchases.purchasePro(using: purchase) }
                    } label: {
                        Text(verbatim: offerLabel)
                    }
                    .buttonStyle(.glass)
                    .disabled(!app.purchases.isConfigured || app.purchases.isBusy)
                }
                Button(action: next) { Text(key: page == pages.count - 1 ? "privacy_allow" : "onb_next") }
                    .buttonStyle(.glassProminent).padding()
            }
        }
        .task { await app.purchases.refresh() }
    }
    private func next() {
        if page < pages.count - 1 { page += 1; return }
        Task { await app.library.requestAccess(); app.updateSettings { $0.onboardingVersion = Self.version } }
    }

    private var offerLabel: String {
        guard let product = app.purchases.product else { return L("onb_buy_noprice") }
        return L("onb_buy", product.displayPrice)
    }
}
