import Photos
import PhotoMaidCore
import SwiftUI

/// Tab „Fotos“: Zeitachse Tag/Monat/Jahr (zwei Finger), Alben der Fotos-App, Favoriten, Suche, Auswahl.
/// Filter wie in der Fotos-App (Alle · Favoriten · Bearbeitet · Fotos · Videos · Bildschirmfotos, dazu Medienarten),
/// Sortierung nach Aufnahmedatum oder „Zuletzt hinzugefügt“ und Ansicht quadratisch/Seitenverhältnis – alles bleibt
/// gespeichert und gilt auch für Betrachter, Auswahl, Diashow.
/// Ansehen ist NIE eine Entscheidung. Zeigt alles außer „In PhotoMaid ausgeblendet“.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var mode = 0
    @State private var level: TimelineLevel = .day
    @State private var selecting = false
    @State private var selection: Set<String> = []
    /// Mitglieder des Smart-Albums für „Selfies“/„RAW“ (`nil` = wird geladen).
    @State private var members: Set<String>?
    /// Hinzufüge-Reihenfolge der Fotos-App für „Zuletzt hinzugefügt“ (`nil` = wird geladen).
    @State private var addedRank: [String: Int]?
    @State private var pinchBase: CGFloat = 1

    private var filter: LibraryFilter { app.settings.libraryFilter }
    private var order: LibraryOrder { app.settings.libraryOrder }

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
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                modePicker
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.s)
            .frame(maxWidth: .infinity)
            .background(AppColors.background)
        }
        .navigationTitle(L("tab_library"))
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if selecting && mode == 0 {
                SelectionBar(ids: Array(selection)) { selection = []; selecting = false }
                    .padding(.bottom, AppSpacing.xs)
            }
        }
    }

    /// Kopf wie im Artefakt: „Fotos“, rechts Suche, Auswählen/Fertig und Mehr.
    private var header: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            Text(key: "tab_library").pageTitle().accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            circleButton(.search, L("lib_search")) { app.navigate(.search) }
            if mode == 0 {
                Button {
                    selecting.toggle()
                    if !selecting { selection = [] }
                } label: {
                    Text(key: selecting ? "done" : "grid_select")
                        .font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
                        .foregroundStyle(selecting ? AppColors.onAccent : AppColors.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(selecting ? AppColors.accentFill : AppColors.surface, in: .capsule)
                        .overlay(Capsule().strokeBorder(selecting ? Color.clear : AppColors.control, lineWidth: 1))
                        .contentShape(.capsule)
                }
                .buttonStyle(PMPressStyle())
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
                circleLabel(.more)
            }
            .accessibilityLabel(Text(key: "more_actions"))
        }
    }

    private func circleLabel(_ icon: PMIconName) -> some View {
        PMIcon(icon, size: 19, lineWidth: 2.2)
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: 44, height: 44)
            .background(AppColors.surface, in: .circle)
            .overlay(Circle().strokeBorder(AppColors.control, lineWidth: 1))
            .contentShape(.circle)
    }

    private func circleButton(_ icon: PMIconName, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(icon) }
            .buttonStyle(PMPressStyle())
            .accessibilityLabel(Text(verbatim: label))
    }

    @ViewBuilder private var modePicker: some View {
        if dynamicType.isAccessibilitySize {
            libraryModes.pickerStyle(.menu)
                .frame(minHeight: AppSpacing.minTouch)
        } else {
            libraryModes.pickerStyle(.segmented).frame(maxWidth: 620)
        }
    }

    private var libraryModes: some View {
        Picker(L("tab_library"), selection: $mode) {
            Text(key: "lib_mode_timeline").tag(0)
            Text(key: "lib_mode_albums").tag(1)
            Text(key: "lib_filter_favorites").tag(2)
        }
        .accessibilityIdentifier("library.mode")
    }

    private var visible: [MediaAsset] {
        LibraryFilter.apply(filter, to: app.visibleMedia, facts: { $0.libraryFacts }, members: members)
    }

    /// Filter und Ansicht wie in der Fotos-App (Menü oben rechts).
    private var filterMenu: some View {
        let filterBinding = Binding<LibraryFilter>(get: { app.settings.libraryFilter },
                                                   set: { f in app.updateSettings { $0.libraryFilter = f } })
        let fitBinding = Binding<Bool>(get: { app.settings.libraryAspectFit },
                                       set: { v in app.updateSettings { $0.libraryAspectFit = v } })
        let orderBinding = Binding<LibraryOrder>(get: { app.settings.libraryOrder },
                                                 set: { o in app.updateSettings { $0.libraryOrder = o } })
        return Menu {
            Picker(L("lib_filter_title"), selection: filterBinding) {
                ForEach(LibraryFilter.main, id: \.self) { f in
                    Label(LibraryFilterText.title(f), systemImage: LibraryFilterText.symbol(f)).tag(f)
                }
            }
            Menu {
                Picker(L("lib_media_types"), selection: filterBinding) {
                    ForEach(LibraryFilter.mediaTypes, id: \.self) { f in
                        Label(LibraryFilterText.title(f), systemImage: LibraryFilterText.symbol(f)).tag(f)
                    }
                }
            } label: {
                Label(L("lib_media_types"), systemImage: "square.stack.3d.down.right")
            }
            SwiftUI.Divider()
            Picker(L("lib_sort"), selection: orderBinding) {
                Label(L("basket_sort_taken"), systemImage: "calendar").tag(LibraryOrder.captured)
                Label(L("lib_sort_added"), systemImage: "clock.arrow.circlepath").tag(LibraryOrder.added)
            }
            Picker(L("lib_view_options"), selection: fitBinding) {
                Label(L("lib_view_square"), systemImage: "square.grid.3x3").tag(false)
                Label(L("lib_view_aspect"), systemImage: "rectangle.grid.3x2").tag(true)
            }
        } label: {
            HStack(spacing: 6) {
                PMIcon(.filter, size: 14, lineWidth: 2.2)
                Text(key: "lib_filter_title").font(PMFont.text(.semibold, 13, relativeTo: .footnote))
            }
            .foregroundStyle(filter == .all ? AppColors.textPrimary : AppColors.onAccent)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(filter == .all ? AppColors.surface : AppColors.accentFill, in: .capsule)
            .overlay(Capsule().strokeBorder(filter == .all ? AppColors.control : Color.clear, lineWidth: 1))
            .frame(minHeight: AppSpacing.minTouch)
            .contentShape(.rect)
        }
        .accessibilityLabel(Text(key: "lib_filter_title"))
        .accessibilityValue(Text(verbatim: LibraryFilterText.title(filter)))
        .accessibilityIdentifier("library.filter")
    }

    /// Aktiver Filter als Chip mit Anzahl und ✕ (damit nie vergessen wird, dass gefiltert ist).
    private func filterChip(count: Int) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Label(LibraryFilterText.title(filter), systemImage: LibraryFilterText.symbol(filter))
                .font(AppTypography.subheadline.weight(.semibold))
            Text(verbatim: CountText.number(count))
                .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary).monospacedDigit()
            Spacer()
            Button { app.updateSettings { $0.libraryFilter = .all } } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(AppColors.textSecondary)
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: "lib_filter_clear"))
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }

    private var timeline: some View {
        let byAdded = order == .added
        let list = byAdded ? LibraryOrder.addedFirst(visible, id: \.id, rank: addedRank ?? [:]) : visible
        // Zuletzt hinzugefügt: eine durchgehende Fläche ohne Datumsüberschriften (wie in der Fotos-App).
        let sections = byAdded
            ? [TimelineSection(key: TimelineKey(year: 0, unknown: true), items: list)]
            : Timeline.sections(list, date: \.creationDate, level: level, timeZone: .autoupdatingCurrent)
        let header: ((TimelineKey) -> String)? = byAdded ? nil : { TimelineText.header($0, level: level) }
        return ScrollView {
            if app.visibleMedia.isEmpty && app.snapshot.loaded {
                EmptyState(symbol: "photo", title: L("grid_empty_title"), message: L("lib_empty_text"))
            } else if !app.snapshot.loaded || (filter.readsCollection && members == nil) || (byAdded && addedRank == nil) {
                LoadingState(message: L("feed_loading")).frame(minHeight: 300)
            } else {
                if byAdded {
                    HStack(alignment: .center) {
                        Text(key: "lib_order_added_note")
                            .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                        Spacer(minLength: AppSpacing.xs)
                        filterMenu
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                } else {
                    HStack(spacing: AppSpacing.xs) {
                        PMChip(title: L("lib_level_day"), selected: level == .day) { level = .day }
                        PMChip(title: L("lib_level_month"), selected: level == .month) { level = .month }
                        PMChip(title: L("lib_level_year"), selected: level == .year) { level = .year }
                        Spacer(minLength: 0)
                        filterMenu
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("library.level")
                }
                if filter != .all { filterChip(count: list.count) }
                if list.isEmpty {
                    EmptyState(symbol: LibraryFilterText.symbol(filter), title: L("grid_empty_title"),
                               message: L("lib_filter_empty", LibraryFilterText.title(filter)))
                } else {
                    MediaGrid(sections: sections, columns: level.columns, selecting: selecting, selection: $selection,
                              open: { a in open(a, in: list) }, header: header,
                              fit: app.settings.libraryAspectFit)
                }
            }
        }
        .task(id: "\(filter.rawValue)-\(app.library.changeToken)") { await loadMembers() }
        .task(id: "\(order.rawValue)-\(app.library.changeToken)") { await loadAddedRank() }
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

    /// „Zuletzt hinzugefügt“: Reihenfolge des Systemalbums der Fotos-App (vorheriger Stand bleibt beim Neuladen sichtbar).
    private func loadAddedRank() async {
        guard order == .added else { return }
        let rank = await Task.detached(priority: .userInitiated) { PhotoLibraryService.addedRank() }.value
        guard !Task.isCancelled else { return }
        addedRank = rank
    }

    /// Selfies und RAW kennt nur das Smart-Album der Fotos-App (keine Bildanalyse).
    private func loadMembers() async {
        guard filter.readsCollection else { members = nil; return }
        members = nil
        let selfies = filter == .selfies
        let ids = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.smartAlbumIDs(selfies ? .smartAlbumSelfPortraits : .smartAlbumRAW)
        }.value
        guard !Task.isCancelled else { return }
        members = ids
    }
}

enum LibraryFilterText {
    static func title(_ f: LibraryFilter) -> String {
        switch f {
        case .all: L("lib_filter_all")
        case .favorites: L("lib_filter_favorites")
        case .edited: L("lib_filter_edited")
        case .photos: L("cat_photos")
        case .videos: L("cat_videos")
        case .screenshots: L("cat_screenshots")
        case .selfies: L("qa_selfies")
        case .livePhotos: L("qa_live_photos")
        case .portraits: L("qa_portraits")
        case .panoramas: L("lib_filter_panoramas")
        case .slowMotion: L("lib_filter_slowmo")
        case .timelapse: L("lib_filter_timelapse")
        case .cinematic: L("lib_filter_cinematic")
        case .screenRecordings: L("lib_filter_screenrec")
        case .raw: L("lib_filter_raw")
        }
    }

    static func symbol(_ f: LibraryFilter) -> String {
        switch f {
        case .all: "photo.on.rectangle"
        case .favorites: "heart"
        case .edited: "slider.horizontal.3"
        case .photos: "photo"
        case .videos: "video"
        case .screenshots: "camera.viewfinder"
        case .selfies: "person.crop.square"
        case .livePhotos: "livephoto"
        case .portraits: "cube"
        case .panoramas: "pano"
        case .slowMotion: "slowmo"
        case .timelapse: "timelapse"
        case .cinematic: "film"
        case .screenRecordings: "record.circle"
        case .raw: "r.square"
        }
    }
}

extension MediaAsset {
    /// Was der Mediathek-Filter wissen darf (nur Metadaten der Fotos-App).
    var libraryFacts: LibraryMediaFacts {
        LibraryMediaFacts(id: id, kind: kind, isFavorite: isFavorite, isEdited: isEdited, isLivePhoto: isLivePhoto,
                          isPortrait: isPortrait, isPanorama: isPanorama, isSlowMotion: isSlowMotion,
                          isTimelapse: isTimelapse, isCinematic: isCinematic, isScreenRecording: isScreenRecording)
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
