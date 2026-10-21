import PhotoMaidCore
import SwiftUI

/// PhotoMaid-Papierkorb: bisher ist nichts gelöscht. Echte Kandidaten, Vorschau, Abwahl, genaue Beschreibung.
/// Fotos/Videos und Dateien werden getrennt bestätigt. Tageslimit wird VOR der Systembestätigung erklärt.
struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var inSheet = false

    @State private var selection: Set<ItemReference> = []
    @State private var known: Set<ItemReference> = []
    @State private var sizes: [String: KnownSize] = [:]
    @State private var confirmPhotos: [ItemReference]?
    @State private var confirmFiles: [ItemReference]?
    @State private var limitFor: LimitRequest?
    @State private var bonusBusy = false
    @State private var running = false
    @State private var result: ResultMessage?
    @State private var done: CleanupDone?
    @State private var preview: MediaAsset?

    struct LimitRequest: Identifiable { let id = UUID(); let items: [ItemReference]; let kind: CleanupOperationKind }
    struct ResultMessage: Identifiable { let id = UUID(); let title: String; let text: String; let openPro: Bool }

    private var basket: [ItemRecord] { app.read.basket }

    /// Zeitpunkt des Hineinlegens = letzte Entscheidung „Papierkorb“ im Verlauf (nichts zusätzlich gespeichert).
    private var placedAt: [ItemReference: Date] {
        var out: [ItemReference: Date] = [:]
        for e in app.read.events where e.to.disposition == .markedForCleanup {
            if let d = out[e.item] { out[e.item] = max(d, e.at) } else { out[e.item] = e.at }
        }
        return out
    }

    private var photoItems: [ItemRecord] {
        let p = basket.filter { $0.item.provider == .photoLibrary }
        switch app.settings.basketSort {
        case .added:
            let placed = placedAt
            return p.sorted { (placed[$0.item] ?? .distantPast) > (placed[$1.item] ?? .distantPast) }
        case .taken:
            return p.sorted { a, b in
                switch (app.asset(a.item.localIdentifier)?.creationDate, app.asset(b.item.localIdentifier)?.creationDate) {
                case let (x?, y?): x > y
                case (nil, _): false
                case (_, nil): true
                }
            }
        case .largest:
            // Gemessen oder geschätzt („ca.“): jede Zeile hat eine Zahl, also auch eine Position.
            let bytes = Dictionary(p.map { ($0.item, value($0.item).bytes) }, uniquingKeysWith: { a, _ in a })
            return p.sorted { (bytes[$0.item] ?? 0) > (bytes[$1.item] ?? 0) }
        }
    }

    /// Größe für die Anzeige beim Löschen: gemessen, sonst geschätzt („ca.“) – nie ohne Zahl (E17).
    private func value(_ ref: ItemReference) -> SizeValue {
        if ref.provider == .photoLibrary {
            let measured = sizes[ref.localIdentifier] ?? .unknown
            guard let a = app.asset(ref.localIdentifier) else {
                return SizeValue.of(measured, estimate: app.estimator.estimate(EstimateInput(kind: .photo)))
            }
            return app.sizeValue(a, measured: measured)
        }
        let entry = app.files.entries.first { $0.reference == ref }
        return SizeValue.of(entry?.size ?? .unknown,
                            estimate: app.estimator.estimate(entry?.estimateInput ?? EstimateInput(kind: .file)))
    }

    private func total(_ refs: [ItemReference]) -> String {
        SizeText.value(SizeSum(refs.map(value)).value)
    }

    private var fileItems: [ItemRecord] { basket.filter { $0.item.provider != .photoLibrary } }
    private var selectedPhotos: [ItemReference] { photoItems.map(\.item).filter { selection.contains($0) } }
    private var selectedFiles: [ItemReference] { fileItems.map(\.item).filter { selection.contains($0) } }

    var body: some View {
        Group {
            if basket.isEmpty {
                EmptyState(symbol: "tray", title: L("basket_empty_title"), message: L("basket_empty_message"))
            } else {
                list
            }
        }
        .appPage()
        .navigationTitle(L("basket"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            if inSheet { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task(id: basket.map(\.item)) { await syncSelection() }
        .confirmationDialog(L("basket_confirm_media_title"), isPresented: Binding(get: { confirmPhotos != nil }, set: { if !$0 { confirmPhotos = nil } }),
                            titleVisibility: .visible) {
            if let items = confirmPhotos {
                Button(L("basket_confirm_media_action", items.count), role: .destructive) { run(items, .photoLibraryDelete) }
            }
            Button(L("cancel"), role: .cancel) { confirmPhotos = nil }
        } message: {
            Text(verbatim: L("basket_confirm_media_message") + "\n\n" + L("basket_selection_size", total(confirmPhotos ?? [])))
        }
        .confirmationDialog(L("basket_confirm_files_title"), isPresented: Binding(get: { confirmFiles != nil }, set: { if !$0 { confirmFiles = nil } }),
                            titleVisibility: .visible) {
            if let items = confirmFiles {
                Button(L("basket_confirm_files_action", items.count), role: .destructive) { run(items, .fileDeletePermanently) }
            }
            Button(L("cancel"), role: .cancel) { confirmFiles = nil }
        } message: {
            Text(verbatim: L("basket_confirm_files_message") + "\n\n" + L("basket_selection_size", total(confirmFiles ?? [])))
        }
        .sheet(item: $limitFor) { req in
            LimitSheet(available: app.read.allowance?.available ?? 0, limit: app.read.allowance?.limit ?? 0, selected: req.items.count,
                       bonus: bonusAvailable ? LimitBonus.amount : nil, bonusBusy: bonusBusy) {
                limitFor = nil
                request(Array(req.items.prefix(app.read.allowance?.available ?? 0)), kind: req.kind)
            } openPro: {
                limitFor = nil
                openPro()
            } watchBonus: {
                Task { await watchBonus(retry: req) }
            }
            .onAppear { if bonusAvailable { AdsService.shared.preloadRewarded(app: app) } }
        }
        .sheet(item: $preview) { a in TrashPreview(asset: a) }
        .fullScreenCover(item: $done) { d in
            CleanupDoneView(done: d) { done = nil; if inSheet { dismiss() } }
        }
        .alert(result?.title ?? "", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button(L("ok"), role: .cancel) {
                if result?.openPro == true { openPro() }
                result = nil
            }
        } message: {
            Text(verbatim: result?.text ?? "")
        }
    }

    /// „+100 für heute“ (nur Gratis, einmal täglich): erst nach dem Belohnungs-Callback freigeschaltet.
    private var bonusAvailable: Bool {
        LimitBonusOffer.available(app.capabilities, rewards: app.rewards, now: app.now, timeZone: .autoupdatingCurrent,
                                  adsConfigured: AdsService.shared.configured(app))
    }

    private func watchBonus(retry: LimitRequest?) async {
        guard !bonusBusy else { return }
        bonusBusy = true
        defer { bonusBusy = false }
        switch await AdsService.shared.showRewarded(app: app) {
        case .earned(let rewardID):
            guard await app.grantLimitBonus(rewardID: rewardID) else {
                app.showToast(L("limit_bonus_unavailable"))
                return
            }
            Haptics.success()
            if let retry {
                limitFor = nil
                request(retry.items, kind: retry.kind)
            }
        case .dismissed:
            app.showToast(L("limit_bonus_dismissed"))
        case .unavailable:
            app.showToast(L("limit_bonus_unavailable"))
        }
    }

    private func openPro() {
        if inSheet { dismiss(); app.closeFeed(reviewed: 0) }
        app.navigate(.pro, in: .cleanup)
    }

    /// Artefakt: oranger Titel, Tageslimit als Karte, Fotos und Videos als Raster (3 Spalten) mit Zurückholen.
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(key: "basket").font(AppTypography.largeTitle).tracking(-0.8).foregroundStyle(AppColors.cleanup)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: L("basket_count", basket.count)).font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Text(key: "basket_intro").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let a = app.read.allowance, let available = a.available { allowanceCard(available: available, limit: a.limit ?? 0) }
                if photoItems.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xs) {
                            sortChip(.added, "basket_sort_added")
                            sortChip(.taken, "basket_sort_taken")
                            sortChip(.largest, "lib_sort_largest")
                        }
                    }
                }
                if !photoItems.isEmpty {
                    Text(key: "basket_media_header").font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader).padding(.top, 4).padding(.horizontal, 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(photoItems, id: \.item) { r in photoTile(r) }
                    }
                    Text(key: "basket_media_footer").font(AppTypography.footnote).foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !fileItems.isEmpty {
                    Text(key: "basket_files_header").font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader).padding(.top, 4).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(fileItems, id: \.item) { r in fileRow(r).padding(.horizontal, AppSpacing.s) }
                    }
                    .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
                    .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
                    Text(key: "basket_files_footer").font(AppTypography.footnote).foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.l)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
    }

    private func sortChip(_ sort: BasketSort, _ key: String) -> some View {
        PMChip(title: L(key), selected: app.settings.basketSort == sort) {
            app.updateSettings { $0.basketSort = sort }
        }
    }

    /// „Heute noch 100 von 100 möglich“ mit Balken; darunter Bonus-Video (Gratis) und Pro.
    private func allowanceCard(available: Int, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: L("basket_allowance", available, limit))
                .font(PMFont.text(.semibold, 15, relativeTo: .subheadline)).foregroundStyle(AppColors.textPrimary)
            if limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.surfaceStroke)
                        Capsule().fill(available == 0 ? AppColors.cleanup : AppColors.success)
                            .frame(width: geo.size.width * min(1, Double(available) / Double(limit)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            HStack(spacing: AppSpacing.xs) {
                if bonusAvailable {
                    Button(L("limit_bonus", LimitBonus.amount)) { Task { await watchBonus(retry: nil) } }
                        .buttonStyle(.pmBordered)
                        .disabled(bonusBusy)
                }
                Button { openPro() } label: {
                    Text(key: "limit_soon_pro").foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.pmBordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }

    /// Kachel 3:4 (Radius 14): Antippen zeigt die Vorschau, Kreis oben rechts (de)aktiviert die Auswahl,
    /// Pfeil unten rechts holt zurück. Größe oben links (gemessen oder „ca.“).
    private func photoTile(_ r: ItemRecord) -> some View {
        let a = app.asset(r.item.localIdentifier)
        let selected = selection.contains(r.item)
        let title = switch a?.kind {
        case .video: L("video")
        case .screenshot: L("screenshot")
        default: L("photo")
        }
        return Button { preview = a } label: {
            AssetCell(assetID: r.item.localIdentifier)
                .aspectRatio(3 / 4, contentMode: .fit)
                .opacity(selected ? 1 : 0.45)
                .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(a == nil)
        .accessibilityLabel(Text(verbatim: L("basket_preview_open", title)))
        .overlay(alignment: .topLeading) {
            Text(verbatim: SizeText.value(value(r.item)))
                .font(PMFont.text(.bold, 11, relativeTo: .caption2)).foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(AppColors.background.opacity(0.7), in: .rect(cornerRadius: 8))
                .padding(6)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                if selected { selection.remove(r.item) } else { selection.insert(r.item) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? AppColors.cleanup : AppColors.textPrimary)
                    .background(Circle().fill(AppColors.background.opacity(0.6)))
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: L(selected ? "selected" : "not_selected") + ": " + title))
        }
        .overlay(alignment: .bottomTrailing) {
            Button { Task { await app.decide(r.item, .unmark) } } label: {
                PMIcon(.undo, size: 14, lineWidth: 2.4)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(AppColors.background.opacity(0.75), in: .circle)
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: L("put_back") + ": " + title))
        }
        .contextMenu {
            Button { Task { await app.decide(r.item, .keep) } } label: { Label(L("keep"), systemImage: "checkmark") }
            Button { Task { await app.decide(r.item, .unmark) } } label: { Label(L("put_back"), systemImage: "arrow.uturn.backward") }
        }
    }

    private func photoRow(_ r: ItemRecord) -> some View {
        let a = app.asset(r.item.localIdentifier)
        let title = switch a?.kind {
        case .video: L("video")
        case .screenshot: L("screenshot")
        default: L("photo")
        }
        let sub = [a?.creationDate.map(DateText.abbreviated), SizeText.value(value(r.item))]
            .compactMap { $0 }.joined(separator: " · ")
        return row(r, title: title, subtitle: sub) {
            Button { preview = a } label: { AssetThumbnail(assetID: r.item.localIdentifier, side: 56) }
                .buttonStyle(.plain)
                .disabled(a == nil)
                .accessibilityLabel(Text(verbatim: L("basket_preview_open", title)))
        }
    }

    private func fileRow(_ r: ItemRecord) -> some View {
        let entry = app.files.entries.first { $0.reference == r.item }
        let name = entry?.name ?? (r.item.localIdentifier as NSString).lastPathComponent
        return row(r, title: name, subtitle: SizeText.value(value(r.item))) {
            Image(systemName: "doc").font(.title2).foregroundStyle(AppColors.textSecondary).frame(width: 56, height: 56)
        }
    }

    private func row<Thumb: View>(_ r: ItemRecord, title: String, subtitle: String, @ViewBuilder thumb: () -> Thumb) -> some View {
        let selected = selection.contains(r.item)
        return HStack(spacing: AppSpacing.s) {
            Button {
                if selected { selection.remove(r.item) } else { selection.insert(r.item) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AppColors.cleanup : AppColors.textSecondary)
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: L(selected ? "selected" : "not_selected") + ": " + title))
            thumb()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(AppTypography.subheadline.weight(.semibold)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 64)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { Task { await app.decide(r.item, .unmark) } } label: { Label(L("put_back"), systemImage: "arrow.uturn.backward") }
                .tint(AppColors.accentFill)
            Button { Task { await app.decide(r.item, .keep) } } label: { Label(L("keep"), systemImage: "checkmark") }
                .tint(AppColors.success)
        }
        .contextMenu {
            Button { Task { await app.decide(r.item, .keep) } } label: { Label(L("keep"), systemImage: "checkmark") }
            Button { Task { await app.decide(r.item, .unmark) } } label: { Label(L("put_back"), systemImage: "arrow.uturn.backward") }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !basket.isEmpty {
            VStack(spacing: AppSpacing.xs) {
                if !selectedPhotos.isEmpty || !selectedFiles.isEmpty {
                    Text(verbatim: L("basket_selection_size", total(selectedPhotos + selectedFiles)))
                        .font(PMFont.text(.semibold, 13, relativeTo: .footnote)).foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }
                if !selectedPhotos.isEmpty {
                    PrimaryButton(title: LP("basket_empty_media", selectedPhotos.count), role: .destructive) {
                        request(selectedPhotos, kind: .photoLibraryDelete)
                    }
                    .disabled(running)
                }
                if !selectedFiles.isEmpty {
                    SecondaryButton(title: LP("basket_delete_files", selectedFiles.count)) {
                        request(selectedFiles, kind: .fileDeletePermanently)
                    }
                    .disabled(running)
                }
                if running { ProgressView() }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.top, AppSpacing.s)
            .padding(.bottom, AppSpacing.xs)
            .background(AppColors.background)
        }
    }

    private func syncSelection() async {
        let all = Set(basket.map(\.item))
        // Abwahl bleibt erhalten; neu hinzugekommene sind ausgewählt.
        selection = selection.intersection(all).union(all.subtracting(known))
        known = all
        let assets = app.assets(photoItems.map(\.item))
        sizes = await app.sizer.cachedSizes(assets)
        await app.refreshSizeEstimator()
        let measured = await app.sizes(assets)
        sizes = measured
    }

    private func request(_ items: [ItemReference], kind: CleanupOperationKind) {
        guard !items.isEmpty else { return }
        if let available = app.read.allowance?.available, items.count > available {
            limitFor = LimitRequest(items: items, kind: kind)
        } else if kind == .photoLibraryDelete {
            confirmPhotos = items
        } else {
            confirmFiles = items
        }
    }

    private func run(_ items: [ItemReference], _ kind: CleanupOperationKind) {
        confirmPhotos = nil
        confirmFiles = nil
        running = true
        Task {
            defer { running = false }
            // Größen VOR dem Löschen festhalten (danach gibt es sie nicht mehr). Fehlende = unbekannt, nie 0.
            var before: [ItemReference: KnownSize] = [:]
            // Ohne Messung (z. B. nur in iCloud): die angezeigte Schätzung, im Ergebnis als „ca.“.
            var estimates: [ItemReference: Int64] = [:]
            for ref in items {
                if ref.provider == .photoLibrary {
                    before[ref] = sizes[ref.localIdentifier] ?? .unknown
                } else {
                    before[ref] = app.files.entries.first { $0.reference == ref }?.size ?? .unknown
                }
                if case .approximate(let b) = value(ref) { estimates[ref] = b }
            }
            let r = await app.runCleanup(items, kind: kind)
            switch r {
            case .finished(let intent):
                let removed = intent.confirmedRemoved
                if !removed.isEmpty && (intent.state == .succeeded || intent.state == .partiallySucceeded) {
                    Haptics.success()
                    let saving = app.recordSavings(removed, sizes: before, estimates: estimates)
                    done = CleanupDone(savings: saving, kind: kind, partial: intent.state == .partiallySucceeded,
                                       keptToday: keptToday(), totalBytes: app.settings.savedTotalBytes,
                                       totalLowerBound: app.settings.savedTotalLowerBound,
                                       totalApproximate: app.settings.savedTotalApproximate)
                } else if intent.state == .cancelled {
                    result = ResultMessage(title: L("result_title_not_done"), text: L("result_cancelled"), openPro: false)
                } else {
                    // Show only a safe error category/domain/code, never file names or paths.
                    // The exact provider error is additionally available in "Diagnose teilen".
                    let code = kind == .photoLibraryDelete ? nil : app.lastFileCleanupFailureCode
                    let message = L("result_nothing") + (code.map { "\n[\($0)]" } ?? "")
                    result = ResultMessage(title: L("result_title_not_done"), text: message, openPro: false)
                }
            case .rejected(let e):
                if case .allowanceExceeded(let requested, let available) = e {
                    result = ResultMessage(title: L("result_title_limit"),
                                           text: LP("result_allowance", available, available, requested), openPro: available == 0)
                } else {
                    result = ResultMessage(title: L("notice"), text: L("result_changed"), openPro: false)
                }
            case .needsReconciliation:
                result = ResultMessage(title: L("notice"), text: L("result_reconcile"), openPro: false)
            }
        }
    }

    private func keptToday() -> Int {
        let cal = Calendar.current
        return app.read.events.filter { $0.to.disposition == .kept && $0.kind != .undo && cal.isDateInToday($0.at) }.count
    }
}

/// Tageslimit reicht nicht für die Auswahl: erklären, Teilmenge oder Pro anbieten – bevor iOS fragt.
struct LimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let available: Int
    let limit: Int
    let selected: Int
    /// Gratis: „+n für heute“ per Werbevideo (einmal täglich); `nil` = nicht verfügbar.
    var bonus: Int? = nil
    var bonusBusy = false
    let takePartial: () -> Void
    let openPro: () -> Void
    var watchBonus: () -> Void = {}

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Text(verbatim: available > 0 ? L("limit_title_partial", available) : L("limit_title_none"))
                .font(AppTypography.headline).multilineTextAlignment(.center)
            Text(verbatim: L("limit_message", limit, selected))
                .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
            if available == 0 {
                Text(key: "limit_tomorrow").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let bonus {
                PrimaryButton(title: L("limit_bonus", bonus), action: watchBonus)
                    .disabled(bonusBusy)
                Text(key: "limit_bonus_note").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                SecondaryButton(title: L("limit_all_with_pro", selected), action: openPro)
            } else {
                PrimaryButton(title: L("limit_all_with_pro", selected), action: openPro)
            }
            if available > 0 {
                SecondaryButton(title: L("limit_take_partial", available), action: takePartial)
            }
            Button(L("cancel")) { dismiss() }.frame(minHeight: AppSpacing.minTouch)
        }
        .padding(AppSpacing.pageMargin)
        .presentationDetents([.medium])
    }
}

/// Großes Vorschaubild aus dem Papierkorb. Ansehen ändert nichts an der Auswahl.
struct TrashPreview: View {
    let asset: MediaAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.stage.ignoresSafeArea()
                LargePreview(assetID: asset.id)
            }
            .safeAreaInset(edge: .bottom) {
                Text(key: "basket_preview_note").font(AppTypography.footnote).foregroundStyle(.white.opacity(0.8))
                    .padding(AppSpacing.s)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct CleanupDone: Identifiable {
    let id = UUID()
    let savings: CleanupSavings
    let kind: CleanupOperationKind
    let partial: Bool
    let keptToday: Int
    let totalBytes: Int64
    let totalLowerBound: Bool
    let totalApproximate: Bool
}

/// „Papierkorb geleert“: gemessene Größen bestätigt entfernter Medien; ohne Messung die Schätzung – dann „ca.“ (E17).
struct CleanupDoneView: View {
    let done: CleanupDone
    let close: () -> Void

    var body: some View {
        let s = done.savings
        ZStack {
            AppBackground()
            VStack(spacing: AppSpacing.l) {
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 52)).foregroundStyle(AppColors.accent).accessibilityHidden(true)
                Text(key: "done_title").font(AppTypography.title).accessibilityAddTraits(.isHeader)
                VStack(spacing: 2) {
                    if s.display.isApproximate {
                        Text(verbatim: SizeText.value(s.display))
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    } else if s.hasKnownSizes {
                        if s.isLowerBound {
                            Text(verbatim: L("done_at_least", "").trimmingCharacters(in: .whitespaces))
                                .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                        }
                        Text(verbatim: SizeText.bytes(s.bytes))
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    } else {
                        // Bei ausschließlich unbekannten Größen nie "mind. 0 KB gespart" behaupten.
                        Text(key: "size_unknown")
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    }
                    Text(key: "done_saved").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: AppSpacing.s) {
                    tile(s.removedCount, "trash", L("done_removed"), AppColors.cleanup)
                    tile(done.keptToday, "arrow.up", L("done_kept"), AppColors.keep)
                }
                Text(verbatim: done.totalApproximate
                     ? L("done_total", SizeText.value(.approximate(done.totalBytes)))
                     : L(done.totalLowerBound ? "done_total_at_least" : "done_total", SizeText.bytes(done.totalBytes)))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                VStack(spacing: AppSpacing.xs) {
                    Text(key: done.kind == .photoLibraryDelete ? "done_note_media" : "done_note_files")
                    if s.display.isApproximate {
                        Text(verbatim: L("done_estimated", s.unknownCount))
                    } else if s.unknownCount > 0 {
                        Text(verbatim: LP("done_unknown", s.unknownCount))
                    }
                    if done.partial { Text(key: "done_partial") }
                }
                .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
                Spacer()
                PrimaryButton(title: L("done_button"), action: close)
            }
            .padding(AppSpacing.pageMargin)
        }
    }

    private func tile(_ n: Int, _ symbol: String, _ label: String, _ tint: Color) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
                Text(verbatim: CountText.number(n)).font(AppTypography.metric)
                Text(verbatim: label).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
