import PhotoMaidCore
import SwiftUI
import UIKit

/// Intelligente Prüfung: schrittweise, fortsetzbare Analyse auf diesem iPhone (Apple Vision, nur verkleinerte
/// Vorschauen). Ergebnisse sind Vorschläge und Filter, nie eine Entscheidung oder Löschung. iCloud-Fotos nur nach
/// ausdrücklicher Wahl und nur im WLAN; Fortschritt bleibt beim Anhalten und beim Verlassen der App erhalten.
/// Entschieden wird nur im Feed („Durchwischen“, Tipp auf ein Foto) oder beim Vergleich ähnlicher Aufnahmen –
/// derselbe Weg wie überall (Ledger). Gezeigt werden nur noch offene Fotos, außer „Auch entschiedene zeigen“ ist an.
struct SmartReviewView: View {
    @Environment(AppModel.self) private var app
    let kind: SmartReviewKind
    @State private var analysis = AnalysisController.shared
    @State private var compare: SimilarSelection?

    struct SimilarSelection: Identifiable {
        let members: [MediaAsset]
        var id: String { members.map(\.id).joined(separator: ",") }
    }

    private var analysisKind: AnalysisKind {
        switch kind {
        case .blurry: .blurry
        case .similar: .similar
        case .documents: .documents
        case .categories: .categories
        }
    }

    private var isCurrent: Bool { analysis.kind == analysisKind && analysis.hasScope }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.m) {
                InfoBanner(symbol: "iphone", text: L("ana_footer"))
                if !app.settings.analysisEnabled {
                    InfoBanner(symbol: "eye.slash", tint: AppColors.warning, text: L("ana2_disabled"))
                } else {
                    statusCard
                    if isCurrent { filters }
                    results
                }
            }
            .padding(AppSpacing.pageMargin)
        }
        .appPage()
        .navigationTitle(title)
        .task(id: kind) { await analysis.select(analysisKind, app: app) }
        // Mediathek oder Verbergen-Liste geändert: Umfang neu bestimmen (bisherige Ergebnisse bleiben gespeichert).
        .onChange(of: analysis.scopeRevision) { _, _ in
            Task { await analysis.select(analysisKind, app: app) }
        }
        // Im Feed entschieden: entschiedene Fotos verschwinden aus der Liste.
        .onChange(of: app.pending.count) { _, _ in if isCurrent { analysis.reload() } }
        // Solange die Analyse hier sichtbar läuft, bleibt der Bildschirm an (sonst hält die Sperre sie an).
        .onAppear { UIApplication.shared.isIdleTimerDisabled = analysis.running }
        .onChange(of: analysis.running) { _, running in UIApplication.shared.isIdleTimerDisabled = running }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(item: $compare) { sel in
            SeriesCompareView(members: sel.members, title: L("ana_similar"),
                              subtitle: L("ana2_similar_compare_sub", sel.members.count)) { keep in
                Task { await confirm(sel.members, keep) }
            }
        }
    }

    // MARK: Status und Steuerung

    private var statusCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                let counts = isCurrent ? analysis.counts : AnalysisCounts()
                if let stage = stageText {
                    Text(verbatim: stage).font(AppTypography.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                if counts.total > 0 {
                    ProgressView(value: counts.fraction)
                    Text(verbatim: L("ana2_progress", counts.complete, counts.total))
                        .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary).monospacedDigit()
                    if counts.cloud > 0 { detail(L("ana2_cloud_waiting", counts.cloud)) }
                    if counts.quality > 0 { detail(L("ana2_quality", counts.quality)) }
                    if counts.failed > 0 { detail(L("ana2_failed", counts.failed)) }
                }
                if analysis.running, analysis.stage == .cloud, let fraction = analysis.downloadFraction {
                    ProgressView(value: fraction).tint(AppColors.accent)
                }
                Toggle(L("ana2_include_cloud"), isOn: $analysis.includeCloud)
                    .disabled(analysis.running)
                    .font(AppTypography.subheadline)
                    .onChange(of: analysis.includeCloud) { _, _ in analysis.optionsChanged() }
                if analysis.includeCloud { detail(L("ana2_cloud_note")) }
                Toggle(L("ana2_background"), isOn: $analysis.continueInBackground)
                    .font(AppTypography.subheadline)
                    .onChange(of: analysis.continueInBackground) { _, _ in analysis.optionsChanged() }
                if analysis.continueInBackground { detail(L("ana2_background_note")) }
                HStack(spacing: AppSpacing.s) {
                    if analysis.running {
                        Button { analysis.pause() } label: { Label(L("ana2_pause"), systemImage: "pause.fill") }
                            .buttonStyle(.glass)
                    } else {
                        Button { start(retry: false) } label: {
                            Label(L(counts.complete > 0 ? "ana2_resume" : "ana2_start"), systemImage: "viewfinder")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!isCurrent || analysis.reading)
                        if counts.failed > 0 {
                            Button { start(retry: true) } label: { Text(verbatim: L("ana2_retry_failed", counts.failed)) }
                                .buttonStyle(.glass)
                                .disabled(!isCurrent || analysis.reading)
                        }
                    }
                }
                .frame(minHeight: AppSpacing.minTouch)
            }
        }
    }

    private func detail(_ text: String) -> some View {
        Text(verbatim: text).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func start(retry: Bool) {
        guard app.capabilities.smartReview else { app.navigate(.pro); return }
        analysis.start(app: app, retryFailures: retry)
    }

    private var stageText: String? {
        guard isCurrent || analysis.stage == .privacy else { return nil }
        switch analysis.stage {
        case .idle: return nil
        case .preparing: return L("ana2_stage_preparing")
        case .local: return L("ana2_stage_local")
        case .cloud: return L("ana2_stage_cloud")
        case .comparing: return L("ana2_stage_comparing")
        case .paused: return L("ana2_stage_paused")
        case .waitingWiFi: return L("ana2_stage_wifi")
        case .cooling: return L("ana2_stage_cooling")
        case .thermal: return L("ana2_stage_thermal")
        case .storageError: return L("ana2_stage_storage")
        case .privacy: return L("ana2_stage_privacy")
        case .changed: return L("ana2_stage_changed")
        case .finished: return L("ana2_stage_finished")
        }
    }

    // MARK: Filter

    @ViewBuilder
    private var filters: some View {
        switch analysisKind {
        case .documents:
            TextField(L("ana2_search"), text: $analysis.query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: analysis.query) { _, _ in analysis.filterChanged() }
        case .categories:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    chip(L("ana2_all"), selected: analysis.category == nil) { analysis.category = nil }
                    ForEach(PhotoCategory.allCases, id: \.self) { c in
                        chip(Self.name(c), selected: analysis.category == c.rawValue) { analysis.category = c.rawValue }
                    }
                }
            }
            .onChange(of: analysis.category) { _, _ in analysis.filterChanged() }
        case .blurry, .similar:
            EmptyView()
        }
        Toggle(L("ana2_show_decided"), isOn: $analysis.showDecided)
            .font(AppTypography.subheadline)
            .onChange(of: analysis.showDecided) { _, _ in analysis.filterChanged() }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(AppTypography.subheadline.weight(.semibold))
                .padding(.horizontal, AppSpacing.s)
                .frame(minHeight: AppSpacing.minTouch)
        }
        .modifier(GlassButtonStyleModifier(prominent: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func name(_ category: PhotoCategory) -> String {
        switch category {
        case .documents: L("ana2_cat_documents")
        case .screenshotsText: L("ana2_cat_screenshotsText")
        case .food: L("ana2_cat_food")
        case .animals: L("ana2_cat_animals")
        case .nature: L("ana2_cat_nature")
        case .people: L("ana2_cat_people")
        case .vehicles: L("ana2_cat_vehicles")
        case .other: L("ana2_cat_other")
        }
    }

    // MARK: Ergebnisse

    @ViewBuilder
    private var results: some View {
        let ids = isCurrent ? analysis.results.ids : []
        let groups = isCurrent ? analysis.similar.groups : []
        let empty = analysisKind == .similar ? groups.isEmpty : ids.isEmpty
        if analysis.reading && empty {
            LoadingState(message: L("feed_loading")).frame(height: 220)
        } else if empty {
            EmptyState(symbol: "sparkles", title: title, message: subtitle)
        } else {
            resultsHeader
            if analysisKind == .similar {
                VStack(spacing: AppSpacing.s) {
                    ForEach(groups, id: \.self) { group in groupRow(group) }
                }
            } else {
                // Ein durchgehendes Raster (keine unsichtbaren Monatsgruppen): jede Reihe ist voll, nur die letzte
                // darf kürzer sein. Reihenfolge wie die Analyse (unscharf: am unschärfsten zuerst).
                let assets = ids.compactMap(app.asset)
                MediaGrid(sections: [TimelineSection(key: TimelineKey(year: 0, unknown: true), items: assets)],
                          columns: 3, selection: .constant([])) { asset in
                    openFeed(startingAt: asset.id)
                }
            }
            if analysis.page > 0 || analysis.canNext {
                HStack {
                    if analysis.page > 0 {
                        Button { analysis.previous() } label: { Label(L("ana2_previous"), systemImage: "chevron.left") }
                            .buttonStyle(.glass)
                    }
                    Spacer()
                    if analysis.canNext {
                        Button { analysis.next() } label: { Label(L("ana2_next"), systemImage: "chevron.right") }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    /// Anzahl und „Durchwischen“: alle Treffer (nicht nur diese Seite) im Feed – Behalten/Papierkorb/Später per Geste.
    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: analysisKind == .similar
                 ? L("ana2_groups_count", analysis.similar.total, analysis.similar.memberCount)
                 : L("ana2_matches", analysis.results.total))
                .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            Button { openFeed(startingAt: nil) } label: {
                Label(L("ana2_swipe_all", analysis.feedIDs.count), systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity, minHeight: AppSpacing.minTouch)
            }
            .buttonStyle(.glassProminent)
            Text(key: analysisKind == .similar ? "ana2_swipe_hint_similar" : "ana2_swipe_hint")
                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupRow(_ ids: [String]) -> some View {
        let members = ids.compactMap(app.asset)
        return Button {
            if members.count >= 2 { compare = SimilarSelection(members: members) }
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: 2) {
                    ForEach(members.prefix(5)) { AssetThumbnail(assetID: $0.id, side: 60, cornerRadius: 4) }
                    if members.count > 5 {
                        Text(verbatim: "+\(members.count - 5)")
                            .font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
                            .frame(width: 44, height: 60)
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: L("ana2_group_compare", members.count))
                    .font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppColors.accent)
            }
            .padding(AppSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.small))
        }
        .buttonStyle(.plain)
    }

    private func openFeed(startingAt id: String?) {
        let ids = analysisKind == .similar ? analysis.feedIDs : analysis.results.feedOrder(startingAt: id)
        guard !ids.isEmpty else { return }
        app.open(FeedRequest(.items(ids.map(ItemReference.photo), titleKey: titleKey)))
    }

    /// Vergleich ähnlicher Aufnahmen: erst „n behalten · m in den Papierkorb“ entscheidet (ein Befehl je Medium).
    private func confirm(_ members: [MediaAsset], _ keep: Set<String>) async {
        let kept = members.filter { keep.contains($0.id) }.map(\.reference)
        let trash = members.filter { !keep.contains($0.id) }.map(\.reference)
        _ = await app.decideMany(kept, .keep)
        _ = await app.decideMany(trash, .markForCleanup)
        Haptics.success()
        app.showToast(L("series_done", kept.count, trash.count))
        analysis.reload()
    }

    private var titleKey: String {
        switch kind {
        case .blurry: "ana_blurry"
        case .similar: "ana_similar"
        case .documents: "ana_documents"
        case .categories: "ana_categories"
        }
    }

    private var title: String { L(titleKey) }

    private var subtitle: String {
        switch kind {
        case .blurry: L("ana_blurry_sub")
        case .similar: L("ana_similar_sub")
        case .documents: L("ana_documents_sub")
        case .categories: L("ana_categories_sub")
        }
    }
}
