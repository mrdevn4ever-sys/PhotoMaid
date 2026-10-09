import PhotoMaidCore
import SwiftUI

struct SmartReviewView: View {
    @Environment(AppModel.self) private var app
    let kind: SmartReviewKind
    @State private var running = false
    @State private var cache: [String: AnalysisCacheEntry] = [:]
    @State private var groups: [[String]] = []

    private var matchingIDs: [String] {
        switch kind {
        case .blurry:
            return app.visibleMedia.filter { BlurryPhotos.verdict(cache[$0.id]?.sharpness) == .possiblyBlurry }.map(\.id)
        case .documents:
            return app.visibleMedia.filter { entry($0.id).category == .documents || !(entry($0.id).text ?? "").isEmpty }.map(\.id)
        case .categories:
            return app.visibleMedia.filter { entry($0.id).category != nil }.map(\.id)
        case .similar:
            return groups.flatMap { $0 }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.m) {
                InfoBanner(symbol: "iphone", text: L("ana_footer"))
                Button { Task { await analyze() } } label: { Label(L("tools_start"), systemImage: "viewfinder") }
                    .buttonStyle(.glassProminent).disabled(running)
                if running {
                    LoadingState(message: L("feed_loading")).frame(height: 220)
                } else if matchingIDs.isEmpty {
                    EmptyState(symbol: "sparkles", title: title, message: subtitle)
                } else {
                    let assets = matchingIDs.compactMap(app.asset)
                    MediaGrid(sections: Timeline.sections(assets, date: \.creationDate, level: .month,
                                                          timeZone: .autoupdatingCurrent), columns: 3,
                              selection: .constant([])) { asset in
                        app.fullScreen = .viewer(ids: matchingIDs, index: matchingIDs.firstIndex(of: asset.id) ?? 0)
                    }
                }
            }.padding(AppSpacing.pageMargin)
        }
        .appPage().navigationTitle(title)
        .onAppear { cache = app.kv?.get(StoreKeys.analysisCache) ?? [:] }
    }

    private func entry(_ id: String) -> AnalysisCacheEntry { cache[id] ?? AnalysisCacheEntry() }
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
    private func analyze() async {
        guard app.settings.analysisEnabled else { return }
        guard app.capabilities.smartReview else { app.navigate(.pro); return }
        running = true
        let result = await LocalPhotoAnalyzer.analyze(app.visibleMedia)
        cache.merge(result.cache) { _, new in new }
        groups = result.similarGroups
        try? app.kv?.set(StoreKeys.analysisCache, cache)
        running = false
    }
}
