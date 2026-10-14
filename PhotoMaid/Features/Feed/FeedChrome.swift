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

/// Bezeichnung, Farbe und Symbol einer belegbaren Aktion (Wischen & Tasten, E18).
enum FeedActionText {
    /// Kurz (Pille beim Wischen, Gestenhilfe, Einstellungen).
    static func title(_ a: FeedAction) -> String {
        switch a {
        case .keep: L("dir_keep")
        case .trash: L("dir_trash")
        case .later: L("dir_later")
        case .laterPickDate: L("fc_action_pick_date")
        case .album(_, let title): L("fc_action_album", title)
        case .previous: L("dir_back")
        case .nothing: L("fc_action_none")
        }
    }

    /// Für VoiceOver und Tasten-Beschriftung.
    static func accessibility(_ a: FeedAction) -> String {
        switch a {
        case .keep: L("act_keep_next")
        case .trash: L("act_trash")
        case .later: L("act_later")
        case .laterPickDate: L("act_later_custom")
        case .album(_, let title): L("fc_action_album", title)
        case .previous: L("act_previous")
        case .nothing: L("fc_action_none")
        }
    }

    static func color(_ a: FeedAction) -> Color {
        switch a {
        case .keep, .album: AppColors.keep
        case .trash: AppColors.cleanup
        case .later, .laterPickDate: AppColors.later
        case .previous, .nothing: AppColors.textSecondary
        }
    }

    /// Symbol für Tasten ohne eigene Wischrichtung.
    static func symbol(_ a: FeedAction) -> String {
        switch a {
        case .keep: "checkmark"
        case .trash: "trash"
        case .later: "clock"
        case .laterPickDate: "calendar"
        case .album: "rectangle.stack.badge.plus"
        case .previous: "arrow.uturn.backward"
        case .nothing: "nosign"
        }
    }
}

/// Dezente Pille während des Wischens mit der belegten Aktion („↑ Behalten“, „→ In „Urlaub“ legen“ …).
/// Keine Pille für „Zurück“ und „Nichts“.
struct DirectionPill: View {
    let direction: SwipeDirection?
    let action: FeedAction?
    let ready: Bool

    var body: some View {
        if let direction, let action, action.isDecision {
            HStack(spacing: 6) {
                GestureArrow(direction: direction)
                Text(verbatim: FeedActionText.title(action)).font(AppTypography.footnote.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(FeedActionText.color(action))
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, 6)
            .glassCapsule()
            .opacity(ready ? 1 : 0.8)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }
}

/// Gestenhilfe beim Öffnen – zeigt die eigene Belegung. Jede Richtung steht an ihrem Rand des Fotos (oben, unten,
/// links, rechts), damit sie klar auseinanderliegen; bleibt `duration` Sekunden, Antippen oder Wischen blendet sie aus.
struct GestureHintOverlay: View {
    /// So lange bleibt die Hilfe stehen (Sekunden), wenn nichts passiert.
    static let duration: Double = 6
    /// Frühestens nach dieser Zeit blendet Tippen/Wischen sie aus.
    static let minimumVisible: TimeInterval = 1
    /// Ab dieser Fingerstrecke (pt) gilt eine Bewegung als Wisch.
    static let dismissDistance: CGFloat = 24
    let controls: FeedControls

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().accessibilityHidden(true)
            hint(.up, "hint_up").frame(maxHeight: .infinity, alignment: .top)
            hint(.down, "hint_down").frame(maxHeight: .infinity, alignment: .bottom)
            HStack(spacing: AppSpacing.m) {
                hint(.left, "hint_left")
                Spacer(minLength: AppSpacing.m)
                hint(.right, "hint_right")
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(AppSpacing.l)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func hint(_ d: SwipeDirection, _ title: String) -> some View {
        let action = controls.action(for: d)
        return VStack(spacing: 4) {
            GestureArrow(direction: d).font(.title.weight(.bold)).foregroundStyle(FeedActionText.color(action))
            Text(key: title).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            Text(verbatim: FeedActionText.title(action)).font(AppTypography.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(minWidth: 84, maxWidth: 132)
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.s)
        .glassPanel()
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
    let controls: FeedControls
    let act: (FeedAction) -> Void

    var body: some View {
        GlassEffectContainer(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(controls.buttons, id: \.self) { action in button(action) }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Liegt die Aktion auf einer Wischrichtung, zeigt die Taste deren Pfeil (physische Richtung, nie gespiegelt),
    /// sonst ein eigenes Symbol.
    private func button(_ action: FeedAction) -> some View {
        Button { act(action) } label: {
            Group {
                if let d = controls.direction(of: action) {
                    GestureArrow(direction: d)
                } else {
                    Image(systemName: FeedActionText.symbol(action)).accessibilityHidden(true)
                }
            }
            .foregroundStyle(FeedActionText.color(action))
            .frame(maxWidth: .infinity, minHeight: AppSpacing.touch)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text(verbatim: FeedActionText.accessibility(action)))
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
                        SwiftUI.Divider()
                        row(.left, "summary_trash", summary.marked, AppColors.cleanup)
                        SwiftUI.Divider()
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
