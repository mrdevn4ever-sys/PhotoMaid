import PhotoMaidCore
import SwiftUI

/// Heute – „Was kann ich jetzt tun?“: Hero zum Feed mit den nächsten echten Medien, Weitermachen/Neu seit,
/// Papierkorb/Später/Wieder dran, Schnellzugriffe, ein leiser Pro-Hinweis und zuletzt der Gerätespeicher.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var tourStep = 0
    @State private var continueOpen = 0
    @State private var newSince = 0
    @State private var showGames = false

    private var access: PhotoAccess { app.library.access }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    WorkspaceColumns(accessibility: dynamicType.isAccessibilitySize) {
                        VStack(alignment: .leading, spacing: AppSpacing.m) {
                            if !access.canRead { accessCard }
                            if access.canRead {
                                ReviewHero(pending: app.snapshot.loaded && app.readReady ? app.pending : nil,
                                           hasHistory: !app.read.events.isEmpty, showGestures: !app.settings.gestureHintSeen) {
                                    app.open(FeedRequest(.allMedia))
                                }
                                .tourTarget("today.hero")
                                .id("today.hero")
                            }
                            progressRows
                            if access == .limited {
                                InfoBanner(symbol: "photo.badge.checkmark", title: L("today_limited_title"), text: L("today_limited_text"),
                                           actionTitle: L("today_limited_action")) { app.library.presentLimitedLibraryPicker() }
                            }
                            if !app.read.reconciliationNeeded.isEmpty {
                                InfoBanner(symbol: "arrow.triangle.2.circlepath", tint: AppColors.warning, text: L("today_reconciliation"))
                            }
                        }
                        VStack(alignment: .leading, spacing: AppSpacing.m) {
                            statusGroup.tourTarget("today.status").id("today.status")
                            PMCardRow(icon: .cup, tint: AppColors.later, tile: AppColors.pauseStroke, title: L("memory_break"),
                                      subtitle: L("art_pause_sub"), subtitleColor: AppColors.pauseText,
                                      background: AppColors.pauseSurface, stroke: AppColors.pauseStroke, radius: AppRadii.card) {
                                showGames = true
                            }
                            .accessibilityIdentifier("today.games")
                            if access.canRead && app.readReady { QuickAccessSection().tourTarget("today.quick").id("today.quick") }
                            if app.capabilities.tier == .free, let first = app.settings.firstSeenDay, app.today > first {
                                PMCardRow(icon: .crown, tint: AppColors.accent, title: L("pro_title"), subtitle: L("pro_subtitle")) {
                                    app.navigate(.pro)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xxl)
            }
            .appPage()
            // Kopf bleibt wie eine Navigationsleiste unter der Statusleiste stehen; Inhalte scrollen darunter.
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, AppSpacing.pageMargin)
                    .padding(.bottom, AppSpacing.s)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.background.ignoresSafeArea(edges: .top))
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(app.pending.count)-\(app.cleanupMedia.count)-\(app.settings.continueMonth ?? "")-\(app.settings.lastSessionEnd?.timeIntervalSince1970 ?? 0)") {
                await countProgress()
            }
            .tourOverlay(step: activeTourStep, isLast: tourStep == tourSteps.count - 1) {
                if tourStep >= tourSteps.count - 1 { app.updateSettings { $0.todayTourSeen = true } } else { tourStep += 1 }
            } skip: {
                app.updateSettings { $0.todayTourSeen = true }
            }
            .onChange(of: activeTourStep, initial: true) { _, step in scrollToTourTarget(step, scroller) }
            .onChange(of: app.settings.todayTourSeen) { _, seen in if !seen { tourStep = 0 } }
            .gamesCover(isPresented: $showGames)
        }
    }

    /// Begrüßung nach Tageszeit über „PhotoMaid“ (Nutzerwunsch 21.10.2026): Morgen 5–11, Mittag 12–13,
    /// Nachmittag 14–17, Abend 18–4 Uhr, nach der Ortszeit; aktualisiert sich mit der App-Uhr.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: app.now)
        return switch hour {
        case 5...11: L("today_greeting_morning")
        case 12...13: L("today_greeting_noon")
        case 14...17: L("today_greeting_afternoon")
        default: L("today_greeting_evening")
        }
    }

    /// Kopf wie im Artefakt: Begrüßung, „PhotoMaid“ (mit Tresor-Rad) und der runde Einstellungen-Knopf.
    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: greeting).font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
                    .foregroundStyle(AppColors.textSecondary)
                // Geheimer Eingang zum Tresor (E16): „PhotoMaid“ 2 Sekunden halten, das „o“ ist ein Tresor-Rad.
                // Ohne eingerichteten Tresor passiert nichts.
                VaultDialWordmark()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            Spacer()
            Button { app.navigate(.settings) } label: {
                PMIcon(.gear, size: 20)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppColors.surface, in: .circle)
                    .overlay(Circle().strokeBorder(AppColors.control, lineWidth: 1))
                    .contentShape(.circle)
            }
            .buttonStyle(PMPressStyle())
            .accessibilityLabel(Text(key: "settings"))
            .tourTarget("today.settings")
            .accessibilityIdentifier("today.settings")
        }
        .padding(.top, AppSpacing.xs)
    }

    private var accessCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Label {
                    Text(key: access == .denied || access == .restricted ? "today_access_denied_title" : "today_access_title")
                        .font(AppTypography.headline)
                } icon: {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(AppColors.accent)
                }
                Text(key: access == .denied || access == .restricted ? "today_access_denied" : "today_access_default")
                    .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                PrimaryButton(title: L(access == .notDetermined ? "privacy_allow" : "today_limited_action")) {
                    if access == .notDetermined {
                        Task { await app.library.requestAccess(); app.reloadLibraryIfNeeded(force: true) }
                    } else {
                        app.navigate(.privacy)
                    }
                }
            }
        }
    }

    /// „Weitermachen“ und „Neu seit dem letzten Aufräumen“ – echte offene Zahlen, abseits des Main-Threads.
    private func countProgress() async {
        let month = MonthKey.parse(app.settings.continueMonth)
        let pendingSet = Set(app.pending.map(\.localIdentifier))
        let media = app.cleanupMedia
        let settings = app.settings
        let (c, n) = await Task.detached(priority: .utility) { () -> (Int, Int) in
            let tz = TimeZone.autoupdatingCurrent
            let c = month.map { m in
                media.filter { pendingSet.contains($0.id) && $0.creationDate.map { MonthKey($0, timeZone: tz) } == m }.count
            } ?? 0
            let n = settings.lastSessionEnd == nil ? 0
                : NewSinceQuery.assets(in: media, settings: settings).filter { pendingSet.contains($0.id) }.count
            return (c, n)
        }.value
        continueOpen = c
        newSince = n
    }

    @ViewBuilder
    private var progressRows: some View {
        let month = MonthKey.parse(app.settings.continueMonth)
        if access.canRead {
            if let month, continueOpen > 0 {
                PMCardRow(icon: .calendar, tint: AppColors.accent, title: L("today_continue_month", MonthText.title(month)),
                          subtitle: LP("hub_pending", continueOpen)) {
                    app.open(FeedRequest(.month(month, again: false)))
                }
            }
            if newSince > 0 {
                PMCardRow(icon: .sparkles, tint: AppColors.accent, title: LP("today_new_since", newSince),
                          subtitle: L("today_new_since_sub")) {
                    app.open(FeedRequest(.newSince))
                }
            }
        }
    }

    /// Papierkorb und Später als zwei Kacheln (Artefakt), darüber ggf. „Wieder dran“.
    private var statusGroup: some View {
        VStack(spacing: AppSpacing.s) {
            if app.dueCount > 0 {
                PMCardRow(icon: .calendar, tint: AppColors.later, title: LP("today_due", app.dueCount)) {
                    app.open(FeedRequest(.due))
                }
            }
            HStack(spacing: AppSpacing.s) {
                PMStackTile(icon: .trash, tint: AppColors.cleanup, value: CountText.number(app.read.basket.count),
                            title: L("basket")) { app.navigate(.trash) }
                    .accessibilityLabel(Text(verbatim: L("basket") + ", " + LP("items_count", app.read.basket.count)))
                    .accessibilityIdentifier("today.trash")
                PMStackTile(icon: .clock, tint: AppColors.later, value: CountText.number(app.read.laterRecords.count),
                            title: L("later")) { app.navigate(.later) }
                    .accessibilityLabel(Text(verbatim: L("later") + ", " + LP("items_count", app.read.laterRecords.count)))
                    .accessibilityIdentifier("today.later")
            }
        }
    }

    // MARK: Rundgang (einmal: Heute, Status, Schnellzugriffe, Tabs)

    /// Ziel sichtbar machen, bevor Spotlight und Karte darauf zeigen.
    private func scrollToTourTarget(_ step: TourStep?, _ scroller: ScrollViewProxy) {
        // Der Kopf (Einstellungen) steht immer sichtbar oben und muss nicht gescrollt werden.
        guard let step, case .anchor(let anchor) = step.target, anchor != "today.settings" else { return }
        withAnimation(.snappy) { scroller.scrollTo(anchor, anchor: .center) }
    }

    private var tourSteps: [TourStep] {
        [TourStep(titleKey: "tour_today_hero_title", textKey: "tour_today_hero_text", target: .anchor("today.hero")),
         TourStep(titleKey: "tour_today_status_title", textKey: "tour_today_status_text", target: .anchor("today.status")),
         TourStep(titleKey: "tour_today_quick_title", textKey: "tour_today_quick_text", target: .anchor("today.quick")),
         TourStep(titleKey: "tour_today_tab_title", textKey: "tour_today_tab_text",
                  target: .tab(2, titleKey: "tab_cleanup", symbol: "square.stack.3d.up")),
         TourStep(titleKey: "tour_lib_title", textKey: "tour_lib_text",
                  target: .tab(1, titleKey: "tab_library", symbol: "photo.on.rectangle.angled")),
         TourStep(titleKey: "tour_studio_title", textKey: "tour_studio_text",
                  target: .tab(3, titleKey: "tab_studio", symbol: "paintpalette")),
         TourStep(titleKey: "tour_history_title", textKey: "tour_history_text",
                  target: .tab(4, titleKey: "tab_history", symbol: "clock.arrow.circlepath")),
         TourStep(titleKey: "tour_settings_title", textKey: "tour_settings_text", target: .anchor("today.settings"))]
    }

    private var activeTourStep: TourStep? {
        guard !app.settings.todayTourSeen && access.canRead && app.feed == nil && tourStep < tourSteps.count else { return nil }
        return tourSteps[tourStep]
    }
}

/// Gruppe von Zeilen auf einer Fläche (wie eine Einstellungsgruppe).
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.xxs)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }
}

/// Hero wie im Artefakt: Etikett „Noch durchzusehen“, große Zahl, Satz, Bernstein-Knopf; oben rechts ein Fächer aus
/// den nächsten echten Medien, der alle paar Sekunden einen Wisch andeutet (links, rechts, hoch).
struct ReviewHero: View {
    let pending: [ItemReference]?
    let hasHistory: Bool
    let showGestures: Bool
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let pending {
                if pending.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key: "today_done_title").font(PMFont.display(34)).tracking(-0.7)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(key: "today_done_subtitle").font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key: "art_today_left").eyebrow()
                        Text(verbatim: CountText.number(pending.count))
                            .font(AppTypography.display).tracking(-1.74)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(verbatim: L("art_today_media") + " " + L(hasHistory ? "today_continue_sub" : "today_start_sub"))
                            .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: 200, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    PrimaryButton(title: L(hasHistory ? "today_continue_cta" : "today_start_cta"), trailingArrow: true,
                                  action: start)
                        .accessibilityHint(Text(key: "today_review_hint"))
                        .accessibilityIdentifier("today.review")
                    if showGestures {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: AppSpacing.m) { gestureChips }
                            VStack(alignment: .leading, spacing: AppSpacing.xs) { gestureChips }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: 6).fill(AppColors.control).frame(width: 140, height: 14)
                    RoundedRectangle(cornerRadius: 8).fill(AppColors.control).frame(width: 180, height: 52)
                    RoundedRectangle(cornerRadius: 6).fill(AppColors.control).frame(width: 200, height: 14)
                }
                .padding(.top, 4)
                RoundedRectangle(cornerRadius: AppRadii.button).fill(AppColors.control).frame(height: 56)
                    .accessibilityHidden(true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let pending, !pending.isEmpty {
                HeroFan(ids: pending.prefix(3).map(\.localIdentifier))
                    .padding(.top, 18).padding(.trailing, 18)
                    .accessibilityHidden(true)
            }
        }
        .background(AppColors.surface)
        .clipShape(.rect(cornerRadius: AppRadii.sheet))
        .overlay(RoundedRectangle(cornerRadius: AppRadii.sheet).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }

    @ViewBuilder private var gestureChips: some View {
        chip(.up, "dir_keep", AppColors.keep)
        chip(.left, "dir_trash", AppColors.cleanup)
        chip(.right, "dir_later", AppColors.later)
    }

    private func chip(_ d: SwipeDirection, _ key: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            GestureArrow(direction: d).font(.footnote.weight(.bold)).foregroundStyle(tint)
            Text(key: key).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
        }
    }
}

/// Fächer aus drei echten Medien (66 × 88, weißer Rand 3, gedreht −12°/10°/−2°). Die vordere Karte deutet alle 4,8 s
/// einen Wisch an: links (Papierkorb), rechts (Später), hoch (Behalten); die hinteren schaukeln leicht.
/// „Bewegung reduzieren“: ruhig. Nur Anzeige – nie eine Entscheidung.
struct HeroFan: View {
    let ids: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Wiggle {
        var x: Double = 0
        var y: Double = 0
        var angle: Double = 0
    }

    private struct Slot { let left: CGFloat; let rotation: Double }
    private let slots = [Slot(left: 0, rotation: -12), Slot(left: 50, rotation: 10), Slot(left: 24, rotation: -2)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                let slot = slots[min(index, slots.count - 1)]
                card(id)
                    .modifier(FanWiggle(slot: index, base: slot.rotation, animate: !reduceMotion))
                    .offset(x: slot.left, y: 4)
            }
        }
        .frame(width: 120, height: 110, alignment: .topLeading)
    }

    private func card(_ id: String) -> some View {
        AssetCell(assetID: id)
            .frame(width: 66, height: 88)
            .clipShape(.rect(cornerRadius: 9))
            .padding(3)
            .background(AppColors.textPrimary, in: .rect(cornerRadius: 12))
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 10, y: 8)
    }
}

/// Bewegung einer Fächerkarte (Zeiten wie die CSS-Keyframes des Artefakts, Zyklus 4,8 s).
private struct FanWiggle: ViewModifier {
    let slot: Int
    let base: Double
    let animate: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !animate {
            content.rotationEffect(.degrees(base))
        } else if slot == 0 {
            // 0–55 % Ruhe, 70 % (−3, −15°), 85 % (−11°), 100 % (−12°)
            content.keyframeAnimator(initialValue: HeroFan.Wiggle(angle: base), repeating: true) { view, v in
                view.rotationEffect(.degrees(v.angle)).offset(x: v.x, y: v.y)
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    LinearKeyframe(base, duration: 2.64)
                    CubicKeyframe(base - 3, duration: 0.72)
                    CubicKeyframe(base + 1, duration: 0.72)
                    CubicKeyframe(base, duration: 0.72)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: 2.64)
                    CubicKeyframe(-3, duration: 0.72)
                    CubicKeyframe(0, duration: 0.72)
                    CubicKeyframe(0, duration: 0.72)
                }
            }
        } else if slot == 1 {
            // 0–55 % Ruhe, 72 % (+3, 13°), 87 % (9°), 100 % (10°)
            content.keyframeAnimator(initialValue: HeroFan.Wiggle(angle: base), repeating: true) { view, v in
                view.rotationEffect(.degrees(v.angle)).offset(x: v.x, y: v.y)
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    LinearKeyframe(base, duration: 2.64)
                    CubicKeyframe(base + 3, duration: 0.816)
                    CubicKeyframe(base - 1, duration: 0.72)
                    CubicKeyframe(base, duration: 0.624)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: 2.64)
                    CubicKeyframe(3, duration: 0.816)
                    CubicKeyframe(0, duration: 0.72)
                    CubicKeyframe(0, duration: 0.624)
                }
            }
        } else {
            // 0–50 % Ruhe, 58 % links (Papierkorb), 66 %, 74 % rechts (Später), 82 %, 90 % hoch (Behalten), 100 %
            content.keyframeAnimator(initialValue: HeroFan.Wiggle(angle: base), repeating: true) { view, v in
                view.rotationEffect(.degrees(v.angle)).offset(x: v.x, y: v.y)
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    LinearKeyframe(base, duration: 2.4)
                    CubicKeyframe(base - 5, duration: 0.384)
                    CubicKeyframe(base, duration: 0.384)
                    CubicKeyframe(base + 5, duration: 0.384)
                    CubicKeyframe(base, duration: 0.384)
                    CubicKeyframe(base, duration: 0.384)
                    CubicKeyframe(base, duration: 0.48)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: 2.4)
                    CubicKeyframe(-9, duration: 0.384)
                    CubicKeyframe(0, duration: 0.384)
                    CubicKeyframe(9, duration: 0.384)
                    CubicKeyframe(0, duration: 0.384)
                    CubicKeyframe(0, duration: 0.384)
                    CubicKeyframe(0, duration: 0.48)
                }
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: 3.936)
                    CubicKeyframe(-7, duration: 0.384)
                    CubicKeyframe(0, duration: 0.48)
                }
            }
        }
    }
}

/// Karte mit Symbolkachel, Titel, Untertitel und Pfeil (Artefakt: „27 neue Fotos und Videos“, „Kurze Pause“, Pro).
struct PMCardRow: View {
    let icon: PMIconName
    var tint: Color = AppColors.accent
    var tile: Color?
    let title: String
    var subtitle: String?
    var subtitleColor: Color = AppColors.textSecondary
    var background: Color = AppColors.surface
    var stroke: Color = AppColors.surfaceStroke
    var radius: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                PMIcon(icon, size: 20)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tile ?? PMTile.background(for: tint), in: .rect(cornerRadius: AppRadii.small))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(verbatim: subtitle).font(AppTypography.footnote).foregroundStyle(subtitleColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: AppSpacing.xs)
                PMIcon(.chevronRight, size: 18).foregroundStyle(AppColors.textTertiary)
                    .flipsForRightToLeftLayoutDirection(true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(stroke, lineWidth: 1))
            .contentShape(.rect(cornerRadius: radius))
        }
        .buttonStyle(PMPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Kachel mit großer Zahl (Artefakt: Papierkorb 7 · Später 0).
struct PMStackTile: View {
    let icon: PMIconName
    let tint: Color
    let value: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                PMIcon(icon, size: 20)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(PMTile.background(for: tint), in: .rect(cornerRadius: AppRadii.small))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: value).font(AppTypography.metric).foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: title).font(PMFont.text(.medium, 14, relativeTo: .subheadline))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
            .contentShape(.rect(cornerRadius: AppRadii.card))
        }
        .buttonStyle(PMPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Gerätespeicher: bewusst leise – eine Zeile + dünner Balken.
struct StorageLine: View {
    let device: DeviceCapacity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(key: "today_storage_title").font(AppTypography.footnote.weight(.semibold))
                        Spacer()
                        Text(verbatim: L("today_storage_value", SizeText.bytes(device.usedBytes), SizeText.bytes(device.totalBytes)))
                            .font(AppTypography.footnote)
                    }
                    VStack(alignment: .leading) {
                        Text(key: "today_storage_title").font(AppTypography.footnote.weight(.semibold))
                        Text(verbatim: L("today_storage_value", SizeText.bytes(device.usedBytes), SizeText.bytes(device.totalBytes)))
                            .font(AppTypography.footnote)
                    }
                }
                .foregroundStyle(AppColors.textSecondary)
                if device.totalBytes > 0 {
                    ProgressView(value: min(1, Double(device.usedBytes) / Double(device.totalBytes)))
                        .tint(AppColors.textSecondary.opacity(0.6))
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Gerätespeicher über öffentliche Volumen-Werte (`volumeAvailableCapacityForImportantUsage`).
enum DeviceStorage {
    static func read() -> DeviceCapacity? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let available = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return DeviceCapacity(totalBytes: Int64(total), availableForImportantUsageBytes: available)
    }
}
