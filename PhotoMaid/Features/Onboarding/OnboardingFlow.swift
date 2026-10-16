import StoreKit
import SwiftUI

struct OnboardingFlow: View {
    static let version = 2 // 2: neue Einführung mit Bildern und Übungskarten (wird nach dem Update einmal gezeigt)
    @Environment(AppModel.self) private var app
    @Environment(\.purchase) private var purchase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let pages = [("onb_story_title", "onb_story_text"), ("onb_try_title", "onb_try_text"),
                         ("onb_safe_title", "onb_safe_text"), ("onb_offer_title", "onb_offer_text"),
                         ("onb_access_title", "onb_access_text")]

    // Eigene Seitenführung statt TabView(.page): Wischen auf den Übungskarten darf nicht die Seite wechseln.
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: AppSpacing.m) {
                ScrollView {
                    VStack(spacing: AppSpacing.l) {
                        visual
                        Text(key: pages[page].0).font(AppTypography.largeTitle).multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(key: pages[page].1).multilineTextAlignment(.center).foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(AppSpacing.pageMargin)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .id(page)
                    .transition(.opacity)
                }
                .scrollDisabled(page == 1) // Übungskarten: senkrechte Wische gehören dem Stapel
                .scrollBounceBehavior(.basedOnSize)
                pageDots
                // Kaufknopf nur mit echtem Preis aus dem App Store; sonst kein toter Knopf.
                if page == 3, !app.capabilities.isLifetimePro, case .ready = app.purchases.offer {
                    Button {
                        Task { _ = await app.purchases.purchasePro(using: purchase) }
                    } label: {
                        Text(verbatim: offerLabel)
                    }
                    .buttonStyle(.glass)
                    .disabled(app.purchases.isBusy)
                }
                HStack {
                    if page > 0 {
                        Button { page -= 1 } label: { Text(key: "back") }
                            .frame(minHeight: AppSpacing.minTouch)
                    }
                    Spacer()
                    Button(action: next) { Text(key: page == pages.count - 1 ? "privacy_allow" : "onb_next") }
                        .accessibilityIdentifier("onboarding.next")
                        .buttonStyle(.glassProminent)
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.bottom, AppSpacing.m)
            }
        }
        .animation(AppMotion.standard(reduceMotion), value: page)
        .task { await app.purchases.refresh() }
    }

    @ViewBuilder
    private var visual: some View {
        switch page {
        case 0: OnboardingPhotoStack()
        case 1: OnboardingDemoStack()
        case 2: OnboardingSafeFlow()
        case 3: OnboardingSymbol(symbol: "sparkles")
        default: OnboardingSymbol(symbol: "photo.on.rectangle")
        }
    }

    private var pageDots: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(pages.indices, id: \.self) { i in
                Circle()
                    .fill(i == page ? AppColors.accent : AppColors.textSecondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L("onb_progress", page + 1, pages.count)))
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
