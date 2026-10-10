import PhotoMaidCore
import SwiftUI

/// Tab „Fotos“: Zeitachse Tag/Monat/Jahr (zwei Finger), Alben der Fotos-App, Favoriten, Suche, Auswahl.
/// Ansehen ist NIE eine Entscheidung. Zeigt alles außer „In PhotoMaid ausgeblendet“.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var mode = 0
    @State private var level: TimelineLevel = .day
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var filter = 0
    @State private var pinchBase: CGFloat = 1

    var body: some View {
        Group {
            if !app.library.access.canRead {
                EmptyState(symbol: "photo.on.rectangle", title: L("today_access_title"), message: L("today_access_default"),
                           actionTitle: L("privacy_allow")) {
                    Task { await app.library.requestAccess(); app.reloadLibraryIfNeeded(force: true) }
                }
            } else {
                switch mode {
                case 1: AlbumsContent()
                case 2: FavoritesContent()
                default: timeline
                }
            }
        }
        .appPage()
        .navigationTitle(L("tab_library"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $mode) {
                    Text(key: "lib_mode_timeline").tag(0)
                    Text(key: "lib_mode_albums").tag(1)
                    Text(key: "lib_filter_favorites").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if mode == 0 {
                    Button(L(selecting ? "done" : "grid_select")) {
                        selecting.toggle()
                        if !selecting { selection = [] }
                    }
                }
                Menu {
                    Button { app.navigate(.search) } label: { Label(L("lib_search"), systemImage: "magnifyingglass") }
                    Button { app.navigate(.selectionBasket) } label: { Label(L("org_basket"), systemImage: "basket") }
                    Button { app.navigate(.tags) } label: { Label(L("org_tags"), systemImage: "tag") }
                    Button { app.navigate(.hidden) } label: { Label(L("lib_hidden_title"), systemImage: "eye.slash") }
                    Button { app.fullScreen = .slideshow(ids: visible.map(\.id)) } label: {
                        Label(L("slideshow_start"), systemImage: "play.rectangle")
                    }
                    SwiftUI.Divider()
                    Button { app.navigate(.settings) } label: { Label(L("settings"), systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text(key: "more_actions"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && mode == 0 {
                SelectionBar(ids: Array(selection)) { selection = []; selecting = false }
                    .padding(.bottom, AppSpacing.xs)
            }
        }
    }

    private var visible: [MediaAsset] {
        filter == 1 ? app.visibleMedia.filter(\.isFavorite) : app.visibleMedia
    }

    private var timeline: some View {
        let sections = Timeline.sections(visible, date: \.creationDate, level: level, timeZone: .autoupdatingCurrent)
        return ScrollView {
            if app.visibleMedia.isEmpty && app.snapshot.loaded {
                EmptyState(symbol: "photo", title: L("grid_empty_title"), message: L("lib_empty_text"))
            } else if !app.snapshot.loaded {
                LoadingState(message: L("feed_loading")).frame(minHeight: 300)
            } else {
                Picker(L("lib_sort"), selection: $level) {
                    Text(key: "lib_level_day").tag(TimelineLevel.day)
                    Text(key: "lib_level_month").tag(TimelineLevel.month)
                    Text(key: "lib_level_year").tag(TimelineLevel.year)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.pageMargin)
                MediaGrid(sections: sections, columns: level.columns, selecting: selecting, selection: $selection,
                          open: { a in open(a, in: visible) }, header: { TimelineText.header($0, level: level) })
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onEnded { v in
                    withAnimation(.snappy) { level = v.magnification > 1.15 ? level.finer : (v.magnification < 0.85 ? level.coarser : level) }
                }
        )
        .accessibilityAction(named: Text(key: "lib_level_finer")) { level = level.finer }
        .accessibilityAction(named: Text(key: "lib_level_coarser")) { level = level.coarser }
    }

    private func open(_ a: MediaAsset, in list: [MediaAsset]) {
        let ids = list.map(\.id)
        app.fullScreen = .viewer(ids: ids, index: ids.firstIndex(of: a.id) ?? 0)
    }
}

/// Alben und Ordner der Fotos-App als Baum (E5). Antippen öffnet das Album (Raster); Ordner klappen auf.
struct AlbumsContent: View {
    @Environment(AppModel.self) private var app
    @State private var albums: [PhotoAlbum]?
    @State private var expanded: Set<String> = []
    @State private var query = ""
    @State private var askName = false
    @State private var newName = ""

    var body: some View {
        List {
            if let albums {
                let nodes = AlbumTree.order(albums.map(Self.node), sort: app.settings.albumListSort)
                let rows = query.isEmpty ? AlbumTree.rows(nodes, expanded: expanded) : AlbumTree.search(nodes, query: query)
                if rows.isEmpty {
                    Text(verbatim: query.isEmpty ? L("org_albums_empty_title") : L("lib_folders_none_query", query))
                        .foregroundStyle(AppColors.textSecondary)
                }
                ForEach(rows) { n in row(n) }
            } else {
                ProgressView()
            }
            Section {
                Button { askName = true } label: { Label(L("org_new_album"), systemImage: "plus") }
            } footer: {
                Text(key: "albums_footer_ios")
            }
        }
        .searchable(text: $query, prompt: Text(key: "lib_folders_search_hint"))
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Picker(L("lib_sort"), selection: Binding(get: { app.settings.albumListSort },
                                                          set: { s in app.updateSettings { $0.albumListSort = s } })) {
                    Text(key: "lib_folders_sort_recent").tag(AlbumListSort.recent)
                    Text(key: "lib_sort_name").tag(AlbumListSort.name)
                    Text(key: "lib_folders_sort_count").tag(AlbumListSort.count)
                }
            }
        }
        .task(id: app.library.changeToken) { albums = await PhotoLibraryService.loadAlbums() }
        .alert(L("org_new_album"), isPresented: $askName) {
            TextField(L("org_album_name"), text: $newName)
            Button(L("org_create")) {
                Task {
                    guard let name = AlbumRules.normalizeName(newName) else { app.showError(L("folder_invalid")); return }
                    newName = ""
                    if await app.library.createAlbum(named: name) == nil { app.showError(L("album_failed")) }
                    albums = await PhotoLibraryService.loadAlbums()
                }
            }
            Button(L("cancel"), role: .cancel) { newName = "" }
        }
    }

    static func node(_ a: PhotoAlbum) -> AlbumNode {
        AlbumNode(id: a.id, title: a.title, isFolder: a.isFolder, own: a.isFolder ? 0 : a.count, latest: a.latest,
                  children: a.children.map(node))
    }

    private func row(_ n: AlbumNode) -> some View {
        HStack(spacing: AppSpacing.s) {
            if n.isFolder {
                Button {
                    if expanded.contains(n.id) { expanded.remove(n.id) } else { expanded.insert(n.id) }
                } label: {
                    Image(systemName: expanded.contains(n.id) ? "chevron.down" : "chevron.forward")
                        .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(key: expanded.contains(n.id) ? "lib_collapse" : "lib_expand"))
                Image(systemName: "folder").foregroundStyle(AppColors.amber)
                Text(verbatim: n.title)
                Spacer()
                Text(verbatim: LP("lib_subfolders", n.children.count)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            } else {
                Button { app.navigate(.album(id: n.id, title: n.title)) } label: {
                    HStack {
                        Image(systemName: "rectangle.stack").foregroundStyle(AppColors.accent)
                        Text(verbatim: n.title)
                        Spacer()
                        if app.settings.excludedAlbums.contains(n.id) {
                            Image(systemName: "eye.slash").foregroundStyle(AppColors.textSecondary)
                                .accessibilityLabel(Text(key: "lib_folder_excluded"))
                        }
                        Text(verbatim: CountText.number(n.total)).foregroundStyle(AppColors.textSecondary).monospacedDigit()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, CGFloat(n.depth) * AppSpacing.m)
        .frame(minHeight: AppSpacing.minTouch)
    }
}

/// Favoriten (dieselben wie in der Fotos-App).
struct FavoritesContent: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Set<String> = []

    var body: some View {
        let favs = app.visibleMedia.filter(\.isFavorite)
        ScrollView {
            if favs.isEmpty {
                EmptyState(symbol: "heart", title: L("lib_fav_empty_title"), message: L("lib_fav_empty_text"))
            } else {
                MediaGrid(sections: Timeline.sections(favs, date: \.creationDate, level: .month, timeZone: .autoupdatingCurrent),
                          columns: 4, selection: $selection, open: { a in
                              let ids = favs.map(\.id)
                              app.fullScreen = .viewer(ids: ids, index: ids.firstIndex(of: a.id) ?? 0)
                          }, header: { TimelineText.header($0, level: .month) })
            }
        }
    }
}

/// Favoriten als eigene Seite (Route).
struct FavoritesView: View {
    var body: some View {
        FavoritesContent().appPage().navigationTitle(L("lib_filter_favorites"))
    }
}

/// Alben als eigene Seite (Route).
struct AlbumsView: View {
    var body: some View {
        AlbumsContent().appPage().navigationTitle(L("lib_mode_albums"))
    }
}

/// Ein Album der Fotos-App: Raster, Sortierung je Album, aufräumen, vom Aufräumen ausnehmen, ausblenden.
struct AlbumView: View {
    @Environment(AppModel.self) private var app
    let albumID: String
    let title: String
    @State private var ids: [String]?
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var sizes: [String: KnownSize] = [:]

    var body: some View {
        let sort = app.settings.albumSorts[albumID] ?? app.settings.defaultAlbumSort
        let assets = (ids ?? []).compactMap { app.snapshot.byID[$0] }.filter { !app.settings.hiddenMedia.contains($0.id) }
        let sorted = sort.sort(assets, date: \.creationDate, added: { _ in nil }, name: { _ in nil }, size: { sizes[$0.id]?.bytes })
        ScrollView {
            if ids == nil {
                LoadingState().frame(minHeight: 300)
            } else if sorted.isEmpty {
                EmptyState(symbol: "rectangle.stack", title: L("grid_empty_title"), message: L("lib_folder_empty"))
            } else {
                MediaGrid(sections: [TimelineSection(key: TimelineKey(year: 0), items: sorted)], columns: 4,
                          selecting: selecting, selection: $selection, open: { a in
                              let list = sorted.map(\.id)
                              app.fullScreen = .viewer(ids: list, index: list.firstIndex(of: a.id) ?? 0)
                          })
            }
        }
        .appPage()
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(L(selecting ? "done" : "grid_select")) { selecting.toggle(); if !selecting { selection = [] } }
                Menu {
                    Button { app.open(FeedRequest(.album(id: albumID, title: title))) } label: {
                        Label(L("lib_folder_cleanup"), systemImage: "rectangle.stack")
                    }
                    Picker(L("lib_sort"), selection: Binding(get: { sort }, set: { s in app.updateSettings { $0.albumSorts[albumID] = s } })) {
                        Text(key: "lib_sort_newest").tag(MediaSort.newest)
                        Text(key: "lib_sort_oldest").tag(MediaSort.oldest)
                        Text(key: "lib_sort_largest").tag(MediaSort.largest)
                    }
                    let excluded = app.settings.excludedAlbums.contains(albumID)
                    Button { app.setExcluded(album: albumID, !excluded) } label: {
                        Label(L(excluded ? "lib_folder_include" : "lib_folder_exclude"), systemImage: excluded ? "eye" : "eye.slash")
                    }
                    Button { app.fullScreen = .slideshow(ids: sorted.map(\.id)) } label: {
                        Label(L("slideshow_start"), systemImage: "play.rectangle")
                    }
                    Button(role: .destructive) {
                        app.updateSettings { $0.hiddenAlbums = Array(Set($0.hiddenAlbums).union([albumID])) }
                    } label: { Label(L("lib_hide"), systemImage: "eye.slash") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(Text(key: "more_actions"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { SelectionBar(ids: Array(selection)) { selection = []; selecting = false }.padding(.bottom, AppSpacing.xs) }
        }
        .task(id: app.library.changeToken) {
            let id = albumID
            ids = await Task.detached { PhotoLibraryService.orderedAssetIDs(inAlbum: id) }.value
            if sort == .largest { sizes = await app.sizer.cachedSizes(assets) }
        }
    }
}
