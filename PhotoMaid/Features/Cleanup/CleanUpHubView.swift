import PhotoMaidCore
import SwiftUI

/// Aufräumen: Reiter „Bereiche“ (Mediathek, Werkzeuge, lokale Analyse) und „Sammlungen“ (dauerhafte Filter).
struct CleanUpHubView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0
    @State private var counts: [MediaCategory: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                HStack(alignment: .bottom) {
                    Text(key: "tab_cleanup").font(AppTypography.largeTitle).accessibilityAddTraits(.isHeader)
                    Spacer()
                    GlassIconButton(symbol: "gearshape", label: L("settings")) { app.navigate(.settings) }
                }
                .padding(.top, AppSpacing.m)
                Picker("", selection: $tab) {
                    Text(key: "hub_tab_areas").tag(0)
                    Text(key: "hub_tab_collections").tag(1)
                }
                .pickerStyle(.segmented)
                if tab == 1 {
                    CollectionsContent()
                } else {
                    areas
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
        }
        .appPage()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(app.pending.count)-\(app.cleanupMedia.count)") { await recount() }
    }

    private var canRead: Bool { app.library.access.canRead }

    @ViewBuilder
    private var areas: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: L("hub_media_header"))
            RowGroup {
                media(.photos, "photo", "cat_photos", AppColors.accent)
                SwiftUI.Divider().padding(.leading, 52)
                media(.videos, "video", "cat_videos", AppColors.amber)
                SwiftUI.Divider().padding(.leading, 52)
                media(.screenshots, "camera.viewfinder", "cat_screenshots", AppColors.later)
                SwiftUI.Divider().padding(.leading, 52)
                link(.months, "calendar", AppColors.amber, L("months_title"), L("hub_months_sub"))
            }
        }
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: L("hub_tools_header"))
            RowGroup {
                link(.largeFiles, "doc.badge.arrow.up", AppColors.amber, L("large_files"),
                     L("hub_large_from", SizeText.bytes(Int64(app.settings.largeFileThresholdMB) * 1_000_000)))
                    .accessibilityIdentifier("hub.large")
                SwiftUI.Divider().padding(.leading, 52)
                link(.duplicates, "square.on.square", AppColors.success, L("duplicates"), L("hub_dup_sub"),
                     badge: app.capabilities.exactDuplicates ? nil : L("pro_badge"))
                    .accessibilityIdentifier("hub.duplicates")
                SwiftUI.Divider().padding(.leading, 52)
                link(.series, "square.stack.3d.forward.dottedline", AppColors.accent, L("series_title"), L("hub_series_sub"),
                     badge: app.capabilities.seriesCompare ? nil : L("pro_badge"))
                SwiftUI.Divider().padding(.leading, 52)
                link(.files, "folder", AppColors.amber, L("files"), L("hub_files_sub"))
                    .accessibilityIdentifier("hub.files")
                SwiftUI.Divider().padding(.leading, 52)
                link(.storage, "chart.bar", AppColors.accent, L("storage_overview"), nil)
                    .accessibilityIdentifier("hub.storage")
            }
        }
        if app.settings.analysisEnabled {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                SectionHeader(title: L("ana_header"))
                RowGroup {
                    ForEach(Array(SmartReviewKind.allCases.enumerated()), id: \.element) { i, kind in
                        if i > 0 { SwiftUI.Divider().padding(.leading, 52) }
                        link(.smartReview(kind), SmartReviewText.symbol(kind), AppColors.indigo, SmartReviewText.title(kind),
                             SmartReviewText.subtitle(kind), badge: app.capabilities.smartReview ? nil : L("pro_badge"))
                            .accessibilityIdentifier("hub.\(kind.rawValue)")
                    }
                }
                Text(key: "ana_footer").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func media(_ c: MediaCategory, _ symbol: String, _ title: String, _ tint: Color) -> some View {
        let n = counts[c]
        return Button { app.open(FeedRequest(.category(c))) } label: {
            NavRow(symbol: symbol, tint: tint, title: L(title),
                   value: n.map { $0 == 0 ? "✓" : CountText.number($0) })
        }
        .buttonStyle(.plain)
        .disabled(!canRead)
        .accessibilityValue(Text(verbatim: n.map { $0 == 0 ? L("hub_nothing_pending") : LP("hub_pending", $0) } ?? ""))
        .accessibilityIdentifier("hub.\(c.rawValue)")
    }

    private func link(_ route: Route, _ symbol: String, _ tint: Color, _ title: String, _ subtitle: String?,
                      badge: String? = nil) -> some View {
        Button { app.navigate(route, in: .cleanup) } label: {
            NavRow(symbol: symbol, tint: tint, title: title, subtitle: subtitle, badge: badge)
        }
        .buttonStyle(.plain)
    }

    private func recount() async {
        let open = Set(app.pending.map(\.localIdentifier))
        let media = app.cleanupMedia
        counts = await Task.detached(priority: .utility) { () -> [MediaCategory: Int] in
            var out: [MediaCategory: Int] = [:]
            for c in MediaCategory.allCases {
                out[c] = media.filter { FeedViewModel.matches($0, c) && open.contains($0.id) }.count
            }
            return out
        }.value
    }
}

enum SmartReviewText {
    static func title(_ k: SmartReviewKind) -> String {
        switch k {
        case .blurry: L("ana_blurry")
        case .similar: L("ana_similar")
        case .documents: L("ana_documents")
        case .categories: L("ana_categories")
        }
    }

    static func subtitle(_ k: SmartReviewKind) -> String {
        switch k {
        case .blurry: L("ana_blurry_sub")
        case .similar: L("ana_similar_sub")
        case .documents: L("ana_documents_sub")
        case .categories: L("ana_categories_sub")
        }
    }

    static func symbol(_ k: SmartReviewKind) -> String {
        switch k {
        case .blurry: "camera.metering.unknown"
        case .similar: "square.on.square.dashed"
        case .documents: "doc.text.viewfinder"
        case .categories: "square.grid.2x2"
        }
    }
}

/// Sammlungen: dauerhafte, antippbare Filter mit aktuellem Stand. Fertige für alle, eigene mit Pro.
/// Kein Auslöser, keine Hintergrundarbeit, nie eine Löschung.
struct CollectionsContent: View {
    @Environment(AppModel.self) private var app
    @State private var results: [SmartCollectionID: CollectionResult] = [:]
    @State private var editing: SmartCollection?
    @State private var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            Text(key: "col_intro").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                SectionHeader(title: L("col_builtin_header"))
                RowGroup {
                    ForEach(Array(SmartCollections.builtIns.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { SwiftUI.Divider().padding(.leading, 52) }
                        row(c)
                    }
                }
            }
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                SectionHeader(title: L("col_custom_header"))
                RowGroup {
                    ForEach(Array(app.customCollections.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { SwiftUI.Divider().padding(.leading, 52) }
                        row(c)
                            .contextMenu {
                                Button { isNew = false; editing = c } label: { Label(L("col_edit"), systemImage: "pencil") }
                            }
                    }
                    if !app.customCollections.isEmpty { SwiftUI.Divider().padding(.leading, 52) }
                    Button {
                        if app.capabilities.customCollections {
                            isNew = true
                            editing = SmartCollection(source: .videos, filter: .largerThan(bytes: 500 * SmartCollections.mb))
                        } else {
                            app.navigate(.pro, in: .cleanup)
                        }
                    } label: {
                        NavRow(symbol: "plus", title: L("col_add"), badge: app.capabilities.customCollections ? nil : L("pro_badge"),
                               showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
                if !app.capabilities.customCollections {
                    Text(key: "col_custom_pro").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .task(id: "\(app.pending.count)-\(app.cleanupMedia.count)-\(app.customCollections.count)") { await evaluate() }
        .sheet(item: $editing) { c in
            CollectionEditor(initial: c, isNew: isNew) { saved in
                var list = app.customCollections
                if let i = list.firstIndex(where: { $0.id == saved.id }) { list[i] = saved } else { list.append(saved) }
                app.setCustomCollections(list)
            } delete: {
                app.setCustomCollections(app.customCollections.filter { $0.id != c.id })
            }
        }
    }

    private func row(_ c: SmartCollection) -> some View {
        let r = results[c.id]
        let locked = !c.builtIn && !app.capabilities.customCollections
        return Button {
            if locked { app.navigate(.pro, in: .cleanup) } else { app.open(FeedRequest(.collection(c))) }
        } label: {
            NavRow(symbol: CollectionText.symbol(c), tint: AppColors.accent, title: CollectionText.title(c),
                   subtitle: subtitle(c, r), value: r.map { $0.items.isEmpty ? "✓" : CountText.number($0.items.count) },
                   badge: locked ? L("pro_badge") : nil)
        }
        .buttonStyle(.plain)
        .disabled(r?.items.isEmpty == true && !locked)
    }

    private func subtitle(_ c: SmartCollection, _ r: CollectionResult?) -> String? {
        guard let r else { return L("col_counting") }
        if r.items.isEmpty { return L("col_nothing_open") }
        var parts: [String] = []
        if case .largerThan = c.filter {
            parts.append(r.unknownSizeCount > 0 ? L("size_at_least", SizeText.bytes(r.knownBytes)) : SizeText.bytes(r.knownBytes))
            if r.unknownSizeCount > 0 { parts.append(LP("col_unknown_hint", r.unknownSizeCount)) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func evaluate() async {
        var out: [SmartCollectionID: CollectionResult] = [:]
        for c in SmartCollections.builtIns + app.customCollections {
            if Task.isCancelled { return }
            out[c.id] = await CollectionEvaluator.evaluate(c, app: app)
            results = out
        }
    }
}

/// Wertet eine Sammlung aus: Kandidaten aus der Mediathek (ohne ausgenommene Alben), Größen nur gemessen.
@MainActor
enum CollectionEvaluator {
    static func evaluate(_ c: SmartCollection, app: AppModel) async -> CollectionResult {
        let media = app.cleanupMedia.filter { a in
            switch c.source {
            case .photos: a.kind == .photo
            case .videos: a.isVideo
            case .screenshots: a.kind == .screenshot
            }
        }
        var sizes: [String: KnownSize] = [:]
        if case .largerThan = c.filter {
            // Nur offene Kandidaten messen (entschiedene zählen ohnehin nicht).
            let open = Set(app.pending.map(\.localIdentifier))
            sizes = await app.sizes(media.filter { open.contains($0.id) })
        }
        let candidates = media.map { CollectionCandidate(item: $0.reference, createdAt: $0.creationDate, size: sizes[$0.id] ?? .unknown) }
        return SmartCollections.evaluate(c, candidates: candidates, records: app.read.records, now: app.now,
                                         timeZone: .autoupdatingCurrent)
    }
}

/// Eigene Sammlung bearbeiten: Was (Fotos/Videos/Screenshots) + Bedingung (größer als / älter als) als Schnellwahl.
struct CollectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initial: SmartCollection
    let isNew: Bool
    let save: (SmartCollection) -> Void
    let delete: () -> Void
    @State private var source: CollectionSource
    @State private var larger: Bool
    @State private var bytes: Int64
    @State private var days: Int

    init(initial: SmartCollection, isNew: Bool, save: @escaping (SmartCollection) -> Void, delete: @escaping () -> Void) {
        self.initial = initial
        self.isNew = isNew
        self.save = save
        self.delete = delete
        _source = State(initialValue: initial.source)
        switch initial.filter {
        case .largerThan(let b):
            _larger = State(initialValue: true); _bytes = State(initialValue: b); _days = State(initialValue: 365)
        case .olderThan(let d):
            _larger = State(initialValue: false); _bytes = State(initialValue: 100 * SmartCollections.mb); _days = State(initialValue: d)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("col_what")) {
                    Picker(L("col_what"), selection: $source) {
                        Text(key: "cat_photos").tag(CollectionSource.photos)
                        Text(key: "cat_videos").tag(CollectionSource.videos)
                        Text(key: "cat_screenshots").tag(CollectionSource.screenshots)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: source) { _, s in
                        if !SmartCollections.sizeChoices(s).contains(bytes) { bytes = SmartCollections.sizeChoices(s)[1] }
                    }
                }
                Section(L("col_condition")) {
                    Picker(L("col_condition"), selection: $larger) {
                        Text(key: "col_larger").tag(true)
                        Text(key: "col_older").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if larger {
                        Picker(L("col_larger"), selection: $bytes) {
                            ForEach(SmartCollections.sizeChoices(source), id: \.self) { Text(verbatim: SizeText.bytes($0)).tag($0) }
                        }
                    } else {
                        Picker(L("col_older"), selection: $days) {
                            ForEach(SmartCollections.ageChoices, id: \.self) { Text(verbatim: CollectionText.age($0)).tag($0) }
                        }
                    }
                }
                Section {
                    Text(verbatim: CollectionText.title(result)).font(AppTypography.headline)
                }
                if !isNew {
                    Section {
                        Button(L("col_delete"), role: .destructive) { delete(); dismiss() }
                    }
                }
            }
            .navigationTitle(L("col_editor_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("save")) { save(result); dismiss() } }
            }
        }
    }

    private var result: SmartCollection {
        SmartCollection(id: initial.id, source: source, filter: larger ? .largerThan(bytes: bytes) : .olderThan(days: days))
    }
}
