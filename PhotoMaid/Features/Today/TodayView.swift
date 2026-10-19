import PhotoMaidCore
import SwiftUI

/// Heute – „Was kann ich jetzt tun?“: Hero zum Feed mit den nächsten echten Medien, Weitermachen/Neu seit,
/// Papierkorb/Später/Wieder dran, Schnellzugriffe, ein leiser Pro-Hinweis und zuletzt der Gerätespeicher.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @State private var device: DeviceCapacity?
    @State private var tourStep = 0
    @State private var continueOpen = 0
    @State private var newSince = 0

    private var access: PhotoAccess { app.library.access }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                header
                if !access.canRead { accessCard }
                if access.canRead {
                    ReviewHero(pending: app.snapshot.loaded ? app.pending : nil, hasHistory: !app.read.events.isEmpty,
                               showGestures: !app.settings.gestureHintSeen) {
                        app.open(FeedRequest(.allMedia))
                    }
                }
                progressRows
                if access == .limited {
                    InfoBanner(symbol: "photo.badge.checkmark", title: L("today_limited_title"), text: L("today_limited_text"),
                               actionTitle: L("today_limited_action")) { app.library.presentLimitedLibraryPicker() }
                }
                if !app.read.reconciliationNeeded.isEmpty {
                    InfoBanner(symbol: "arrow.triangle.2.circlepath", tint: AppColors.warning, text: L("today_reconciliation"))
                }
                statusGroup
                if !VaultStore.shared.hidesEntry {
                    Button { VaultStore.shared.present() } label: {
                        NavRow(symbol: "lock.shield", title: L("vault_title"), subtitle: L("vault_settings_row_hint"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.vault")
                }
                if access.canRead { QuickAccessSection() }
                if app.capabilities.tier == .free, let first = app.settings.firstSeenDay, app.today > first {
                    Button { app.navigate(.pro) } label: {
                        NavRow(symbol: "crown", title: L("today_pro_title"), subtitle: L("today_pro_text"))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.m)
                    .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
                }
                if let device { StorageLine(device: device) { app.navigate(.storage) } }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
        }
        .appPage()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: app.library.changeToken) { device = DeviceStorage.read() }
        .task(id: "\(app.pending.count)-\(app.cleanupMedia.count)-\(app.library.changeToken)-\(app.settings.continueMonth ?? "")-\(app.settings.lastSessionEnd?.timeIntervalSince1970 ?? 0)") {
            await countProgress()
        }
        .overlay(alignment: .bottom) { tour }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: app.now)
        return switch hour {
        case 5...10: L("today_greeting_morning")
        case 18...23, 0...4: L("today_greeting_evening")
        default: L("today_greeting_day")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: greeting).font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
                Text(key: "tab_today").font(AppTypography.largeTitle).foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    // Geheimer Eingang zum Tresor (E16): 2 Sekunden halten. Ohne eingerichteten Tresor passiert nichts.
                    .onLongPressGesture(minimumDuration: 2) {
                        if VaultStore.shared.openFromHiddenEntry() { Haptics.commit() }
                    }
            }
            Spacer()
            GlassIconButton(symbol: "gearshape", label: L("settings")) { app.navigate(.settings) }
        }
        .padding(.top, AppSpacing.m)
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
        guard !Task.isCancelled else { return }
        continueOpen = c
        newSince = n
    }

    @ViewBuilder
    private var progressRows: some View {
        let month = MonthKey.parse(app.settings.continueMonth)
        if access.canRead && ((month != nil && continueOpen > 0) || newSince > 0) {
            RowGroup {
                if let month, continueOpen > 0 {
                    Button { app.open(FeedRequest(.month(month, again: false))) } label: {
                        NavRow(symbol: "calendar", tint: AppColors.amber, title: L("today_continue_month", MonthText.title(month)),
                               subtitle: LP("hub_pending", continueOpen))
                    }
                    .buttonStyle(.plain)
                    if newSince > 0 { Divider().padding(.leading, 52) }
                }
                if newSince > 0 {
                    Button { app.open(FeedRequest(.newSince)) } label: {
                        NavRow(symbol: "sparkles", title: LP("today_new_since", newSince), subtitle: L("today_new_since_sub"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusGroup: some View {
        RowGroup {
            if app.dueCount > 0 {
                Button { app.open(FeedRequest(.due)) } label: {
                    NavRow(symbol: "calendar.badge.clock", tint: AppColors.later, title: LP("today_due", app.dueCount))
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
            }
            Button { app.navigate(.trash) } label: {
                NavRow(symbol: "trash", tint: AppColors.cleanup, title: L("basket"), value: CountText.number(app.read.basket.count))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: L("basket") + ", " + LP("items_count", app.read.basket.count)))
            Divider().padding(.leading, 52)
            Button { app.navigate(.later) } label: {
                NavRow(symbol: "clock", tint: AppColors.later, title: L("later"), value: CountText.number(app.read.laterRecords.count))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: L("later") + ", " + LP("items_count", app.read.laterRecords.count)))
        }
    }

    // MARK: Rundgang (einmal: Heute, Status, Schnellzugriffe, Tabs)

    private var tourSteps: [(String, String)] {
        [("tour_today_hero_title", "tour_today_hero_text"), ("tour_today_status_title", "tour_today_status_text"),
         ("tour_today_quick_title", "tour_today_quick_text"), ("tour_today_tab_title", "tour_today_tab_text"),
         ("tour_lib_title", "tour_lib_text"), ("tour_studio_title", "tour_studio_text"),
         ("tour_history_title", "tour_history_text"), ("tour_settings_title", "tour_settings_text")]
    }

    @ViewBuilder
    private var tour: some View {
        if !app.settings.todayTourSeen && access.canRead && app.feed == nil && tourStep < tourSteps.count {
            let step = tourSteps[tourStep]
            CoachCard(title: L(step.0), text: L(step.1), isLast: tourStep == tourSteps.count - 1) {
                if tourStep >= tourSteps.count - 1 { app.updateSettings { $0.todayTourSeen = true } } else { tourStep += 1 }
            } skip: {
                app.updateSettings { $0.todayTourSeen = true }
            }
            .padding(.bottom, 80)
        }
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

/// Hero: die nächsten echten Medien randlos oben, darunter die Zahl offener Medien und EIN großer Knopf.
struct ReviewHero: View {
    let pending: [ItemReference]?
    let hasHistory: Bool
    let showGestures: Bool
    let start: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let pending {
                if pending.isEmpty {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(AppColors.success)
                            .frame(width: 48, height: 48)
                            .background(AppColors.success.opacity(0.12), in: .rect(cornerRadius: AppRadii.small))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(key: "today_done_title").font(AppTypography.title)
                            Text(key: "today_done_subtitle").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(AppSpacing.m)
                    .accessibilityElement(children: .combine)
                } else {
                    HStack(spacing: 2) {
                        ForEach(Array(pending.prefix(3)), id: \.self) { ref in
                            AssetCell(assetID: ref.localIdentifier)
                        }
                    }
                    .frame(height: 168)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: LP("today_pending_count", pending.count)).font(AppTypography.title)
                            Text(key: hasHistory ? "today_continue_sub" : "today_start_sub")
                                .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        PrimaryButton(title: L(hasHistory ? "today_continue_cta" : "today_start_cta"), action: start)
                            .accessibilityHint(Text(key: "today_review_hint"))
                        if showGestures {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: AppSpacing.m) { gestureChips }
                                VStack(alignment: .leading, spacing: AppSpacing.xs) { gestureChips }
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        }
                    }
                    .padding(AppSpacing.m)
                }
            } else {
                Rectangle().fill(AppColors.backgroundTint).frame(height: 168)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    RoundedRectangle(cornerRadius: 6).fill(AppColors.backgroundTint).frame(width: 200, height: 22)
                    RoundedRectangle(cornerRadius: 6).fill(AppColors.backgroundTint).frame(width: 260, height: 14)
                    Capsule().fill(AppColors.backgroundTint).frame(height: AppSpacing.touch)
                }
                .padding(AppSpacing.m)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(.rect(cornerRadius: AppRadii.sheet))
        .overlay(RoundedRectangle(cornerRadius: AppRadii.sheet).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }

    @ViewBuilder
    private var gestureChips: some View {
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
