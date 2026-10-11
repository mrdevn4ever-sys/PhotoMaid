import PhotoMaidCore
import SwiftUI

/// Intelligente Prüfung: schrittweise, fortsetzbare Analyse auf diesem iPhone (Apple Vision, nur verkleinerte
/// Vorschauen). Ergebnisse sind Vorschläge und Filter, nie eine Entscheidung oder Löschung. iCloud-Fotos nur nach
/// ausdrücklicher Wahl und nur im WLAN; Fortschritt bleibt beim Anhalten und beim Verlassen der App erhalten.
struct SmartReviewView: View {
    @Environment(AppModel.self) private var app
    let kind: SmartReviewKind
    @State private var analysis = AnalysisController.shared

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
                if analysis.includeCloud { detail(L("ana2_cloud_note")) }
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
        let ids = isCurrent ? analysis.visibleIDs : []
        if analysis.reading && ids.isEmpty {
            LoadingState(message: L("feed_loading")).frame(height: 220)
        } else if ids.isEmpty {
            EmptyState(symbol: "sparkles", title: title, message: subtitle)
        } else {
            let total = analysisKind == .similar ? analysis.groupCount : analysis.matchCount
            Text(verbatim: L("ana2_matches", total))
                .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            let assets = ids.compactMap(app.asset)
            MediaGrid(sections: Timeline.sections(assets, date: \.creationDate, level: .month,
                                                  timeZone: .autoupdatingCurrent), columns: 3,
                      selection: .constant([])) { asset in
                let order = assets.map(\.id)
                app.fullScreen = .viewer(ids: order, index: order.firstIndex(of: asset.id) ?? 0)
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

    private var title: String {
        switch kind {
        case .blurry: L("ana_blurry")
        case .similar: L("ana_similar")
        case .documents: L("ana_documents")
        case .categories: L("ana_categories")
        }
    }

    private var subtitle: String {
        switch kind {
        case .blurry: L("ana_blurry_sub")
        case .similar: L("ana_similar_sub")
        case .documents: L("ana_documents_sub")
        case .categories: L("ana_categories_sub")
        }
    }
}
