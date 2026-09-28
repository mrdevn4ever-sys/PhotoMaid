import PhotoMaidCore
import SwiftUI

/// Screen 6 – Aufräumen-Hub.
struct CleanUpHubView: View {
    @Environment(AppModel.self) private var app
    let openFeed: (FeedRequest) -> Void
    let openSettings: () -> Void
    @State private var filter: Filter = .all
    @State private var counts: [MediaCategory: Int] = [:]

    enum Filter: Hashable { case all, media, files }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Aufräumen").font(AppTypography.largeTitle).foregroundStyle(AppColors.textPrimary)
                        Text("Finde und entferne, was du nicht brauchst – auf deinem Gerät.")
                            .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    GlassIconButton(symbol: "gearshape", label: "Einstellungen", action: openSettings)
                }
                .padding(.top, AppSpacing.s)

                Picker("Filter", selection: $filter) {
                    Text("Alle").tag(Filter.all)
                    Text("Medien").tag(Filter.media)
                    Text("Dateien").tag(Filter.files)
                }
                .pickerStyle(.segmented)

                VStack(spacing: AppSpacing.s) {
                    if filter != .files {
                        media(.photos, "photo", "Fotos", "Ähnliches prüfst du selbst im Feed")
                        media(.videos, "video.fill", "Videos", "Große und unnötige Videos")
                        media(.screenshots, "camera.viewfinder", "Screenshots", "Schnappschüsse aufräumen")
                    }
                    if filter != .media {
                        link(symbol: "arrow.down.circle.fill", title: app.sources.downloadsSource == nil ? "Dateien" : "Downloads",
                             subtitle: app.sources.sources.isEmpty ? "Ordner auswählen" : "Dateien aus verbundenen Ordnern") {
                            FileBrowserView()
                        }
                    }
                    link(symbol: "doc.fill", title: "Große Dateien", subtitle: "Bekannte Größe ab einem Filterwert") {
                        LargeFilesView()
                    }
                    link(symbol: "square.on.square.fill", title: "Duplikate", subtitle: "Exakte Kopien (Hash-bestätigt)") {
                        DuplicatesView()
                    }
                    link(symbol: "chart.bar.fill", title: "Speicherübersicht", subtitle: "Was PhotoMaid sehen kann") {
                        StorageInsightsView()
                    }
                    link(symbol: "trash", title: "Auswahlkorb", subtitle: "\(app.basket.count) vorgemerkt") {
                        CleanupBasketView()
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: app.photos.changeToken) {
            var c: [MediaCategory: Int] = [:]
            for cat in MediaCategory.allCases { c[cat] = app.photos.count(cat) }
            counts = c
        }
    }

    private func media(_ c: MediaCategory, _ symbol: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        Button { openFeed(FeedRequest(source: .category(c))) } label: {
            SurfaceCard {
                SourceRow(symbol: symbol, tint: .blue, title: title, subtitle: Text(subtitle),
                          value: counts[c].map { Text("\($0)") }, detail: Text("Elemente"))
            }
        }
        .buttonStyle(.plain)
        .disabled(!app.photos.access.canRead)
    }

    private func link<D: View>(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey,
                               @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            SurfaceCard { SourceRow(symbol: symbol, tint: .blue, title: title, subtitle: Text(subtitle)) }
        }
        .buttonStyle(.plain)
    }
}

/// Ordnen: Später, Regeln/Routinen, verbundene Quellen.
struct OrganizeView: View {
    @Environment(AppModel.self) private var app
    let openFeed: (FeedRequest) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Ordnen").font(AppTypography.largeTitle).foregroundStyle(AppColors.textPrimary)
                    .padding(.top, AppSpacing.s)
                NavigationLink { LaterView(openFeed: openFeed) } label: {
                    SurfaceCard { SourceRow(symbol: "bookmark.fill", tint: .teal, title: "Später",
                                            subtitle: Text("Wiedervorlagen verwalten"),
                                            value: Text("\(app.laterRecords.count)")) }
                }.buttonStyle(.plain)
                NavigationLink { RulesView(openFeed: openFeed) } label: {
                    SurfaceCard { SourceRow(symbol: "gearshape.2.fill", tint: .blue, title: "Regeln & Routinen",
                                            subtitle: Text("Einrichten und vergessen – nur Review-Aufgaben")) }
                }.buttonStyle(.plain)
                NavigationLink { SourcesView() } label: {
                    SurfaceCard { SourceRow(symbol: "folder.fill", tint: .blue, title: "Verbundene Quellen",
                                            subtitle: Text("Ordner, die PhotoMaid sehen darf"),
                                            value: Text("\(app.sources.sources.count)")) }
                }.buttonStyle(.plain)
                if !app.rules.tasks.isEmpty {
                    Text("Offene Aufgaben").font(AppTypography.headline).padding(.top, AppSpacing.s)
                    ForEach(app.rules.tasks) { task in
                        Button { openFeed(FeedRequest(source: .task(task))) } label: {
                            SurfaceCard { SourceRow(symbol: "checklist", tint: .blue, title: "Prüfaufgabe",
                                                    subtitle: Text("\(task.items.count) Elemente"),
                                                    detail: Text(task.createdAt.formatted(date: .abbreviated, time: .omitted))) }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}
