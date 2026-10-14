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
            LimitSheet(available: app.read.allowance?.available ?? 0, limit: app.read.allowance?.limit ?? 0, selected: req.items.count) {
                limitFor = nil
                request(Array(req.items.prefix(app.read.allowance?.available ?? 0)), kind: req.kind)
            } openPro: {
                limitFor = nil
                openPro()
            }
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

    private func openPro() {
        if inSheet { dismiss(); app.closeFeed(reviewed: 0) }
        app.navigate(.pro, in: .cleanup)
    }

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(verbatim: L("basket_count", basket.count)).font(AppTypography.title)
                    Text(key: "basket_intro").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    if photoItems.count > 1 {
                        Picker(L("order_title"), selection: Binding(get: { app.settings.basketSort },
                                                                     set: { s in app.updateSettings { $0.basketSort = s } })) {
                            Text(key: "basket_sort_added").tag(BasketSort.added)
                            Text(key: "basket_sort_taken").tag(BasketSort.taken)
                            Text(key: "lib_sort_largest").tag(BasketSort.largest)
                        }
                        .pickerStyle(.segmented)
                    }
                    if let a = app.read.allowance, let available = a.available {
                        Text(verbatim: L("basket_allowance", available, a.limit ?? 0))
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(available == 0 ? AppColors.textPrimary : AppColors.textSecondary)
                        if available < 5 {
                            Button(L("limit_soon_pro")) { openPro() }.font(AppTypography.footnote.weight(.semibold))
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            if !photoItems.isEmpty {
                Section {
                    ForEach(photoItems, id: \.item) { r in photoRow(r) }
                } header: {
                    Text(key: "basket_media_header")
                } footer: {
                    Text(key: "basket_media_footer")
                }
            }
            if !fileItems.isEmpty {
                Section {
                    ForEach(fileItems, id: \.item) { r in fileRow(r) }
                } header: {
                    Text(key: "basket_files_header")
                } footer: {
                    Text(key: "basket_files_footer")
                }
            }
        }
        .listStyle(.insetGrouped)
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
                        .font(AppTypography.subheadline.weight(.semibold)).monospacedDigit()
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
            .padding(.vertical, AppSpacing.xs)
            .background(.bar)
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
    let takePartial: () -> Void
    let openPro: () -> Void

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
            PrimaryButton(title: L("limit_all_with_pro", selected), action: openPro)
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
