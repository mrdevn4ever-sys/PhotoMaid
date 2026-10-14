import GoogleMobileAds
import PhotoMaidCore
import SwiftUI
import UIKit

/// Werbekarte im Feed (nur Gratis, E19: nach jeder 50. Entscheidung). Nie eine Entscheidung, zählt nicht fürs Limit,
/// kein Ledger-Eintrag. Nach 1,5 s lässt sie sich in jede Richtung wegwischen oder mit „Weiter“ schließen; „runter“
/// schließt sofort. Die Anfrage enthält nie Medien oder Kennungen aus der Mediathek.
struct FeedAdCard: Identifiable {
    let id = UUID()
    let ad: NativeAd
}

struct FeedAdCardView: View {
    let card: FeedAdCard
    let dismiss: () -> Void
    let removeAds: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var canSkip = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: AppSpacing.s) {
                HStack(spacing: AppSpacing.s) {
                    Text(key: "ad_label")
                        .font(AppTypography.caption.weight(.semibold))
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, 4)
                        .background(AppColors.surface, in: .capsule)
                    Spacer(minLength: 0)
                    if canSkip {
                        Button(L("ad_skip")) { leave(direction: CGSize(width: 0, height: -1), size: geo.size) }
                            .buttonStyle(.glass)
                    } else {
                        Text(key: "ad_wait").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }
                }
                NativeAdContainer(ad: card.ad)
                    .clipShape(.rect(cornerRadius: AppRadii.small))
                Button(L("ad_remove"), action: removeAds)
                    .font(AppTypography.footnote.weight(.semibold))
                    .frame(minHeight: AppSpacing.minTouch)
            }
            .padding(AppSpacing.s)
            .background(AppColors.stage, in: .rect(cornerRadius: AppRadii.card))
            .offset(offset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        // Vor Ablauf der 1,5 s nur ein leichtes Nachgeben (außer „runter“: schließt sofort).
                        offset = canSkip ? v.translation : CGSize(width: v.translation.width / 6, height: v.translation.height / 6)
                    }
                    .onEnded { v in
                        let t = v.translation
                        let down = t.height > 80 && abs(t.height) > abs(t.width)
                        if (canSkip && hypot(t.width, t.height) > 80) || down {
                            leave(direction: t, size: geo.size)
                        } else {
                            withAnimation(AppMotion.standard(reduceMotion)) { offset = .zero }
                        }
                    }
            )
        }
        .task {
            do { try await Task.sleep(for: .milliseconds(Int(FeedAdPolicy.minVisibleMs))) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { canSkip = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(key: "ad_skip")) { if canSkip { dismiss() } }
    }

    /// Hinaus in Wischrichtung, dann schließen (keine Entscheidung).
    private func leave(direction t: CGSize, size: CGSize) {
        let length = max(1, hypot(t.width, t.height))
        let target = CGSize(width: t.width / length * size.width * 1.3, height: t.height / length * size.height * 1.3)
        if reduceMotion {
            dismiss()
        } else {
            withAnimation(.easeOut(duration: 0.18)) { offset = target }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                dismiss()
            }
        }
    }
}

/// Googles Vorlage für native Anzeigen (`NativeAdView`): Symbol, Titel, Werbetreibender, Medien (eingepasst, nie
/// verzerrt), Text, Aktionsknopf. Klicks verarbeitet das SDK selbst.
struct NativeAdContainer: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> NativeAdView { NativeAdLayout.make() }

    func updateUIView(_ view: NativeAdView, context: Context) { NativeAdLayout.bind(ad, to: view) }
}

@MainActor
enum NativeAdLayout {
    static func make() -> NativeAdView {
        let view = NativeAdView()
        view.backgroundColor = .secondarySystemBackground

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 8
        icon.clipsToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 44),
                                     icon.heightAnchor.constraint(equalToConstant: 44)])

        let headline = UILabel()
        headline.font = .preferredFont(forTextStyle: .headline)
        headline.adjustsFontForContentSizeCategory = true
        headline.numberOfLines = 2
        headline.textColor = .label

        let advertiser = UILabel()
        advertiser.font = .preferredFont(forTextStyle: .footnote)
        advertiser.adjustsFontForContentSizeCategory = true
        advertiser.textColor = .secondaryLabel

        let titles = UIStackView(arrangedSubviews: [headline, advertiser])
        titles.axis = .vertical
        titles.spacing = 2
        let header = UIStackView(arrangedSubviews: [icon, titles])
        header.axis = .horizontal
        header.spacing = 10
        header.alignment = .center

        let media = MediaView()
        media.contentMode = .scaleAspectFit
        media.setContentHuggingPriority(.defaultLow, for: .vertical)
        media.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.adjustsFontForContentSizeCategory = true
        body.numberOfLines = 3
        body.textColor = .secondaryLabel

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        let action = UIButton(configuration: config)
        // Klicks verarbeitet das SDK über die ganze Anzeige; der Knopf selbst nimmt keine Berührungen an.
        action.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [header, media, body, action])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            media.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        view.iconView = icon
        view.headlineView = headline
        view.advertiserView = advertiser
        view.mediaView = media
        view.bodyView = body
        view.callToActionView = action
        return view
    }

    static func bind(_ ad: NativeAd, to view: NativeAdView) {
        guard view.nativeAd !== ad else { return }
        (view.headlineView as? UILabel)?.text = ad.headline
        (view.advertiserView as? UILabel)?.text = ad.advertiser
        view.advertiserView?.isHidden = ad.advertiser == nil
        (view.bodyView as? UILabel)?.text = ad.body
        view.bodyView?.isHidden = ad.body == nil
        (view.iconView as? UIImageView)?.image = ad.icon?.image
        view.iconView?.isHidden = ad.icon == nil
        if let button = view.callToActionView as? UIButton {
            button.configuration?.title = ad.callToAction
            button.isHidden = ad.callToAction == nil
        }
        view.mediaView?.mediaContent = ad.mediaContent
        // Zuletzt zuweisen: erst dann registriert das SDK die Ansichten für Klicks und Messung.
        view.nativeAd = ad
    }
}
