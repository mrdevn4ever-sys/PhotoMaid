import PhotoMaidCore
import SwiftUI

/// Gestenpfeil – zeigt die physische Fingerrichtung, auch in RTL-Sprachen nie gespiegelt.
struct GestureArrow: View {
    let direction: SwipeDirection

    var body: some View {
        let name = switch direction {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
        Image(systemName: name)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }
}

/// Dezente Pille während des Wischens: „↑ Behalten“, „← Papierkorb“, „→ Später“. Keine bei „runter“.
struct DirectionPill: View {
    let direction: SwipeDirection?
    let ready: Bool

    var body: some View {
        let meaning: (String, Color)? = switch direction {
        case .up: ("dir_keep", AppColors.keep)
        case .left: ("dir_trash", AppColors.cleanup)
        case .right: ("dir_later", AppColors.later)
        default: nil
        }
        if let meaning, let direction {
            let (key, tint) = meaning
            HStack(spacing: 6) {
                GestureArrow(direction: direction)
                Text(key: key).font(AppTypography.footnote.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, 6)
            .glassCapsule()
            .opacity(ready ? 1 : 0.8)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }
}

/// Gestenhilfe beim Öffnen (blendet von selbst aus).
struct GestureHintOverlay: View {
    var body: some View {
        VStack(spacing: AppSpacing.l) {
            hint(.up, "hint_up", "dir_keep", AppColors.keep)
            HStack(spacing: AppSpacing.xl) {
                hint(.left, "hint_left", "dir_trash", AppColors.cleanup)
                hint(.right, "hint_right", "dir_later", AppColors.later)
            }
            .environment(\.layoutDirection, .leftToRight)
            hint(.down, "hint_down", "dir_back", AppColors.textSecondary)
        }
        .padding(AppSpacing.l)
        .glassPanel()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func hint(_ d: SwipeDirection, _ title: String, _ meaning: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            GestureArrow(direction: d).font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(key: title).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            Text(key: meaning).font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(AppColors.textPrimary)
        }
        .frame(minWidth: 88)
    }
}

/// „In 2 Tagen wieder · Ändern“ – der Termin ist bereits gespeichert.
struct LaterPillView: View {
    let pill: LaterPill
    let edit: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "clock").foregroundStyle(AppColors.later).accessibilityHidden(true)
            Text(verbatim: LaterText.inInterval(pill.interval))
                .font(AppTypography.subheadline).foregroundStyle(AppColors.textPrimary)
            Button(action: edit) {
                Text(key: "change").font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(AppColors.accent)
                    .frame(minHeight: AppSpacing.minTouch)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.m)
        .glassCapsule(interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(key: "change_date"), edit)
    }
}

struct NoticePill: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(AppTypography.subheadline)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .glassCapsule()
            .padding(.horizontal, AppSpacing.l)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Papierkorb-Zähler unten rechts im Feed.
struct TrashChip: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "trash").foregroundStyle(AppColors.cleanup)
                Text(verbatim: CountText.number(count)).font(AppTypography.subheadline.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.s)
            .frame(minHeight: AppSpacing.minTouch)
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .accessibilityLabel(Text(verbatim: L("dock_count", count)))
        .accessibilityHint(Text(key: "dock_hint"))
    }
}

/// Entscheidungs-Tasten nur für VoiceOver/Schaltersteuerung oder „Tasten zum Entscheiden“.
/// Rufen exakt denselben Weg wie die Geste (`FeedViewModel.perform`).
struct DecisionButtons: View {
    let act: (FeedIntent) -> Void

    var body: some View {
        GlassEffectContainer(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                button(.down, "act_previous", AppColors.textSecondary, .previous)
                button(.left, "act_trash", AppColors.cleanup, .markForCleanup)
                button(.up, "act_keep_next", AppColors.keep, .keep)
                button(.right, "act_later", AppColors.later, .later)
                Button { act(.laterCustom) } label: {
                    Image(systemName: "calendar").foregroundStyle(AppColors.later)
                        .frame(maxWidth: .infinity, minHeight: AppSpacing.touch)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text(key: "act_later_custom"))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func button(_ d: SwipeDirection, _ label: String, _ tint: Color, _ intent: FeedIntent) -> some View {
        Button { act(intent) } label: {
            GestureArrow(direction: d).foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: AppSpacing.touch)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text(key: label))
    }
}

/// „7. Oktober 2026 · Video · 0:35“ unter dem Medium.
struct MediaInfoLine: View {
    let asset: MediaAsset

    static func describe(_ a: MediaAsset) -> String {
        let kind = switch a.kind {
        case .video: L("video")
        case .screenshot: L("screenshot")
        default: L("photo")
        }
        var parts: [String] = []
        if let d = a.creationDate { parts.append(DateText.long(d)) }
        parts.append(kind)
        if a.isVideo { parts.append(DateText.duration(a.duration)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 6) {
            if asset.isFavorite {
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(AppColors.cleanup).accessibilityHidden(true)
            }
            Text(verbatim: Self.describe(asset))
                .font(AppTypography.footnote)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

/// Ende des Durchgangs: ehrliche Zahlen dieser Sitzung, Papierkorb ansehen, Pro-Hinweis nur bei echtem Aussortieren.
struct SessionSummaryView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    let basketCount: Int
    let openTrash: () -> Void
    let goBack: () -> Void
    let done: () -> Void
    @State private var strongOffer: Bool?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(AppColors.success)
                    .accessibilityHidden(true)
                Text(key: "summary_done").font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                SurfaceCard {
                    VStack(spacing: AppSpacing.s) {
                        row(.up, "summary_kept", summary.kept, AppColors.keep)
                        Divider()
                        row(.left, "summary_trash", summary.marked, AppColors.cleanup)
                        Divider()
                        row(.right, "summary_later", summary.later, AppColors.later)
                    }
                }
                if basketCount > 0 {
                    PrimaryButton(title: L("summary_view_basket", basketCount), symbol: "trash", action: openTrash)
                    Text(key: "summary_basket_hint").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if let allowance = app.read.allowance, let available = allowance.available, let limit = allowance.limit,
                   basketCount > 0, available < basketCount {
                    InfoBanner(symbol: "gauge.with.dots.needle.33percent", tint: AppColors.amber,
                               text: L("limit_soon", available, limit), actionTitle: L("limit_soon_pro")) {
                        done(); app.navigate(.pro, in: .cleanup)
                    }
                }
                offer
                SecondaryButton(title: L("summary_last"), symbol: "arrow.down", action: goBack)
                SecondaryButton(title: L("done"), action: done)
            }
            .padding(AppSpacing.pageMargin)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            guard strongOffer == nil else { return }
            let upsell = app.capabilities.tier != .lifetimePro && summary.marked > 0
            strongOffer = upsell && !app.settings.proOfferShown
            if strongOffer == true { app.updateSettings { $0.proOfferShown = true } }
        }
    }

    @ViewBuilder
    private var offer: some View {
        let upsell = app.capabilities.tier != .lifetimePro && summary.marked > 0
        if upsell && strongOffer == true {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    HStack {
                        Text(key: "summary_offer_title").font(AppTypography.headline)
                        Spacer()
                        BadgeText(text: L("pro_badge"))
                    }
                    Text(key: "summary_offer_text").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    SecondaryButton(title: L("pro_view")) { done(); app.navigate(.pro, in: .cleanup) }
                }
            }
        } else if upsell {
            VStack(spacing: AppSpacing.xxs) {
                Text(verbatim: LP("summary_upsell_count", summary.marked) + " " + L("summary_upsell"))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
                Button { done(); app.navigate(.pro, in: .cleanup) } label: { Text(key: "pro_view") }
                    .frame(minHeight: AppSpacing.minTouch)
            }
        }
    }

    private func row(_ d: SwipeDirection, _ key: String, _ n: Int, _ tint: Color) -> some View {
        HStack {
            GestureArrow(direction: d).foregroundStyle(tint).frame(width: 28)
            Text(key: key).font(AppTypography.body)
            Spacer()
            Text(verbatim: CountText.number(n)).font(AppTypography.metricSmall)
        }
        .frame(minHeight: AppSpacing.minTouch)
        .accessibilityElement(children: .combine)
    }
}

/// Hinweiskarte eines Rundgangs (einmal, abwählbar, kein Blockieren der Bedienung außerhalb der Karte).
struct CoachCard: View {
    let title: String
    let text: String
    let isLast: Bool
    let next: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(verbatim: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
            Text(verbatim: text).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if !isLast {
                    Button(action: skip) { Text(key: "tour_skip") }.frame(minHeight: AppSpacing.minTouch)
                }
                Spacer()
                Button(action: next) { Text(key: isLast ? "done" : "tour_next") }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(AppSpacing.m)
        .glassPanel()
        .padding(.horizontal, AppSpacing.pageMargin)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
