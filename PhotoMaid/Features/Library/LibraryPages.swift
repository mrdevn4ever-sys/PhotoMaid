import PhotoMaidCore
import SwiftUI

/// Auswahlkorb: dauerhafter Arbeitsvorrat (≠ Papierkorb). Leeren ändert nie eine Datei, ist nie eine Entscheidung.
struct SelectionBasketView: View {
    @Environment(AppModel.self) private var app
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var confirmClear = false

    var body: some View {
        let assets = app.organize.basket.compactMap { app.snapshot.byID[$0] }
        let missing = app.organize.basket.count - assets.count
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(key: "org_basket_intro").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.pageMargin)
                if missing > 0 && app.snapshot.loaded {
                    InfoBanner(symbol: "questionmark.circle", text: LP("org_missing", missing), actionTitle: L("org_missing_remove")) {
                        let present = Set(assets.map(\.id))
                        app.organize.removeFromBasket(app.organize.basket.filter { !present.contains($0) })
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                if assets.isEmpty {
                    EmptyState(symbol: "basket", title: L("org_basket_empty_title"), message: L("org_basket_empty_text"))
                } else {
                    MediaGrid(sections: [TimelineSection(key: TimelineKey(year: 0), items: assets)], columns: 4,
                              selecting: selecting, selection: $selection, open: { a in
                                  let ids = assets.map(\.id)
                                  app.fullScreen = .viewer(ids: ids, index: ids.firstIndex(of: a.id) ?? 0)
                              })
                }
            }
        }
        .appPage()
        .navigationTitle(L("org_basket"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(L(selecting ? "done" : "grid_select")) { selecting.toggle(); if !selecting { selection = [] } }
                Menu {
                    Button { selection = Set(assets.map(\.id)); selecting = true } label: { Label(L("grid_select_all"), systemImage: "checkmark.circle") }
                    if selecting && !selection.isEmpty {
                        Button { app.organize.removeFromBasket(Array(selection)); selection = [] } label: {
                            Label(L("org_basket_remove"), systemImage: "minus.circle")
                        }
                    }
                    Button(role: .destructive) { confirmClear = true } label: { Label(L("org_basket_clear"), systemImage: "trash.slash") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(Text(key: "more_actions"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { SelectionBar(ids: Array(selection)) { selection = []; selecting = false }.padding(.bottom, AppSpacing.xs) }
        }
        .alert(L("org_basket_clear_title"), isPresented: $confirmClear) {
            Button(L("org_basket_clear"), role: .destructive) { app.organize.clearBasket() }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(key: "org_basket_clear_text")
        }
    }
}

/// Eigene Schlagwörter mit Anzahl; Antippen zeigt die Medien. „Überall entfernen“ ändert keine Datei.
struct TagsView: View {
    @Environment(AppModel.self) private var app
    @State private var deleting: String?

    var body: some View {
        List {
            let tags = app.organize.allTags
            if tags.isEmpty {
                Text(key: "org_tags_none").foregroundStyle(AppColors.textSecondary)
            }
            ForEach(tags, id: \.tag) { t in
                Button {
                    app.navigate(.grid(.items(app.organize.ids(withTag: t.tag), titleKey: "org_tags")))
                } label: {
                    HStack {
                        Label(t.tag, systemImage: "tag")
                        Spacer()
                        Text(verbatim: CountText.number(t.count)).foregroundStyle(AppColors.textSecondary)
                    }
                }
                .swipeActions { Button(L("org_tag_delete"), role: .destructive) { deleting = t.tag } }
            }
        }
        .appPage()
        .navigationTitle(L("org_tags"))
        .alert(L("org_tag_delete_title", deleting ?? ""), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("org_tag_delete"), role: .destructive) {
                if let t = deleting { app.organize.removeTag(t, from: app.organize.ids(withTag: t)) }
                deleting = nil
            }
            Button(L("cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(key: "org_tag_delete_text")
        }
    }
}

/// „In PhotoMaid ausgeblendet“: Medien und Alben, die PhotoMaid nirgends zeigt. Dateien unverändert, kein Tresor.
struct HiddenView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                Text(key: "lib_hidden_intro").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
            if app.settings.hiddenMedia.isEmpty && app.settings.hiddenAlbums.isEmpty {
                EmptyState(symbol: "eye", title: L("lib_hidden_none_title"), message: L("lib_hidden_none_text"))
                    .listRowBackground(Color.clear)
            }
            if !app.settings.hiddenAlbums.isEmpty {
                Section(L("lib_mode_albums")) {
                    ForEach(app.settings.hiddenAlbums, id: \.self) { id in
                        HStack {
                            Label(AlbumNames.title(id) ?? "—", systemImage: "rectangle.stack")
                            Spacer()
                            Button(L("lib_unhide")) {
                                app.updateSettings { $0.hiddenAlbums.removeAll { $0 == id } }
                            }
                        }
                    }
                }
            }
            if !app.settings.hiddenMedia.isEmpty {
                Section(LP("lib_hidden_media", app.settings.hiddenMedia.count)) {
                    ForEach(app.settings.hiddenMedia, id: \.self) { id in
                        HStack {
                            AssetThumbnail(assetID: id, side: 48)
                            Spacer()
                            Button(L("lib_unhide")) {
                                app.unhide([id])
                                app.showToast(LP("lib_unhidden", 1))
                            }
                        }
                    }
                }
            }
        }
        .appPage()
        .navigationTitle(L("lib_hidden_title"))
    }
}

/// Raster mit Mehrfachauswahl aus einer Quelle (Sammlung, Monat, Liste). Auswahl ist nie eine Entscheidung.
struct MediaGridView: View {
    @Environment(AppModel.self) private var app
    let source: GridSource
    @State private var assets: [MediaAsset]?
    @State private var selecting = true
    @State private var selection: Set<String> = []

    var body: some View {
        ScrollView {
            if let assets {
                if assets.isEmpty {
                    EmptyState(symbol: "photo", title: L("grid_empty_title"), message: L("grid_empty_text"))
                } else {
                    if !app.settings.gridTourSeen {
                        InfoBanner(symbol: "hand.tap", title: L("tour_grid_note_title"), text: L("grid_note"),
                                   actionTitle: L("tour_done")) { app.updateSettings { $0.gridTourSeen = true } }
                            .padding(.horizontal, AppSpacing.pageMargin)
                    }
                    MediaGrid(sections: Timeline.sections(assets, date: \.creationDate, level: .day, timeZone: .autoupdatingCurrent),
                              columns: 3, selecting: selecting, selection: $selection, open: { a in
                                  let ids = assets.map(\.id)
                                  app.fullScreen = .viewer(ids: ids, index: ids.firstIndex(of: a.id) ?? 0)
                              }, header: { TimelineText.header($0, level: .day) })
                }
            } else {
                LoadingState().frame(minHeight: 300)
            }
        }
        .appPage()
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L(selecting ? "done" : "grid_select")) { selecting.toggle(); if !selecting { selection = [] } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !selection.isEmpty {
                SelectionBar(ids: Array(selection)) { selection = [] }.padding(.bottom, AppSpacing.xs)
            }
        }
        .task { await load() }
    }

    private var title: String {
        switch source {
        case .collection(let c): CollectionText.title(c)
        case .items(_, let key): L(key)
        case .month(let m): MonthText.title(m)
        case .category(let c): L(c == .videos ? "cat_videos" : (c == .screenshots ? "cat_screenshots" : "cat_photos"))
        }
    }

    private func load() async {
        switch source {
        case .collection(let c):
            let r = await CollectionEvaluator.evaluate(c, app: app)
            assets = app.assets(r.items)
        case .items(let ids, _):
            assets = app.assets(ids.map(ItemReference.photo))
        case .month(let m):
            let tz = TimeZone.autoupdatingCurrent
            assets = app.cleanupMedia.filter { $0.creationDate.map { MonthKey($0, timeZone: tz) } == m }
        case .category(let c):
            assets = app.cleanupMedia.filter { FeedViewModel.matches($0, c) }
        }
    }
}
