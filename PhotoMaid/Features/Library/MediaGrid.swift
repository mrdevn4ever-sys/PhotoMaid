import PhotoMaidCore
import SwiftUI

/// Raster mit Abschnitten (Zeitachse) und optionaler Mehrfachauswahl. Ansehen und Auswählen sind NIE eine Entscheidung.
struct MediaGrid: View {
    let sections: [TimelineSection<MediaAsset>]
    let columns: Int
    var selecting = false
    @Binding var selection: Set<String>
    let open: (MediaAsset) -> Void
    var header: ((TimelineKey) -> String)?

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: max(1, columns))
        LazyVGrid(columns: cols, spacing: 2, pinnedViews: [.sectionHeaders]) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { a in cell(a) }
                } header: {
                    if let header {
                        HStack {
                            Text(verbatim: header(section.key)).font(AppTypography.headline)
                            Spacer()
                            if selecting {
                                let ids = Set(section.items.map(\.id))
                                Button(L(ids.isSubset(of: selection) ? "grid_select_none" : "grid_select_all")) {
                                    if ids.isSubset(of: selection) { selection.subtract(ids) } else { selection.formUnion(ids) }
                                }
                                .font(AppTypography.footnote.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, AppSpacing.pageMargin)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.background.opacity(0.95))
                    }
                }
            }
        }
    }

    private func cell(_ a: MediaAsset) -> some View {
        let selected = selection.contains(a.id)
        return Button {
            if selecting {
                if selected { selection.remove(a.id) } else { selection.insert(a.id) }
            } else {
                open(a)
            }
        } label: {
            AssetCell(assetID: a.id)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 2) {
                        if a.isFavorite { Image(systemName: "heart.fill") }
                        if a.isVideo { Text(verbatim: DateText.duration(a.duration)).monospacedDigit() }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(4)
                }
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected ? AppColors.accentFill : .white)
                            .background(Circle().fill(.black.opacity(0.25)))
                            .padding(4)
                    }
                }
                .overlay { if selected { Rectangle().fill(.white.opacity(0.18)) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: MediaInfoLine.describe(a)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum TimelineText {
    static func header(_ key: TimelineKey, level: TimelineLevel) -> String {
        if key.unknown { return L("lib_no_date") }
        switch level {
        case .day:
            if let d = key.localDay { return DayText.long(d) }
            return String(key.year)
        case .month:
            return MonthText.title(MonthKey(year: key.year, month: key.month))
        case .year:
            return String(key.year)
        }
    }
}

/// Leiste für eine Auswahl im Raster (nie eine Entscheidung – außer „In den Papierkorb“, das über den Ledger geht).
struct SelectionBar: View {
    @Environment(AppModel.self) private var app
    let ids: [String]
    let clear: () -> Void
    @State private var albumSheet = false
    @State private var tagSheet = false
    @State private var confirmTrash = false
    @State private var confirmHide = false
    @State private var shareItem: MediaShareItem?

    private var assets: [MediaAsset] { ids.compactMap { app.asset($0) } }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(verbatim: LP("grid_selected", ids.count)).font(AppTypography.subheadline.weight(.semibold))
            Spacer()
            Button {
                Task { if let s = await MediaShare.prepare(ids) { shareItem = s } else { app.showError(L("share_failed")) } }
            } label: { Image(systemName: "square.and.arrow.up").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch) }
                .accessibilityLabel(Text(key: "share"))
            Button { albumSheet = true } label: {
                Image(systemName: "rectangle.stack.badge.plus").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: "org_add_to_album"))
            Button { confirmTrash = true } label: {
                Image(systemName: "trash").foregroundStyle(AppColors.cleanup).frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: "lib_trash_action"))
            Menu {
                Button { Task { await setFavorite(true) } } label: { Label(L("fav_add"), systemImage: "heart") }
                Button { Task { await setFavorite(false) } } label: { Label(L("fav_remove"), systemImage: "heart.slash") }
                Button { tagSheet = true } label: { Label(L("org_tags"), systemImage: "tag") }
                Button {
                    let n = app.organize.addToBasket(assets)
                    app.showToast(n > 0 ? LP("org_basket_added", n) : L("org_basket_already"))
                } label: { Label(L("org_basket_add"), systemImage: "basket") }
                Divider()
                Button { app.navigate(.collage(draftID: nil), in: .studio); StudioHandoff.shared.ids = ids } label: {
                    Label(L("grid_collage"), systemImage: "rectangle.3.group")
                }
                Button { app.navigate(.pdfFromPhotos(ids: ids), in: .studio) } label: { Label(L("pdf_from_selection"), systemImage: "doc.richtext") }
                Button { app.navigate(.movie(ids: ids), in: .studio) } label: { Label(L("movie_title"), systemImage: "film.stack") }
                Button { app.fullScreen = .slideshow(ids: ids) } label: { Label(L("slideshow_start"), systemImage: "play.rectangle") }
                Button { app.navigate(.archive(ids: ids), in: .studio) } label: { Label(L("archive_title"), systemImage: "externaldrive") }
                Button { StudioHandoff.shared.ids = ids; app.navigate(.workflows, in: .studio) } label: {
                    Label(L("wf_apply"), systemImage: "wand.and.stars")
                }
                Divider()
                Button { app.open(FeedRequest(.items(ids.map(ItemReference.photo), titleKey: "lib_feed_title"))) } label: {
                    Label(L("lib_review_from_here"), systemImage: "rectangle.stack")
                }
                Button(role: .destructive) { confirmHide = true } label: { Label(L("lib_hide"), systemImage: "eye.slash") }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: "more_actions"))
        }
        .disabled(ids.isEmpty)
        .padding(.horizontal, AppSpacing.m)
        .glassCapsule()
        .padding(.horizontal, AppSpacing.pageMargin)
        .sheet(isPresented: $albumSheet) {
            AlbumPickerSheet(assetIDs: ids) { albumID, title in
                Task {
                    switch await app.library.add(ids, toAlbum: albumID) {
                    case .done:
                        app.rememberRecentAlbum(albumID)
                        app.showToast(LP("org_added_to_album", ids.count, ids.count, title))
                    case .cancelled: break
                    case .failed: app.showError(L("album_failed"))
                    }
                }
            }
        }
        .sheet(isPresented: $tagSheet) { TagEditorSheet(assets: assets) }
        .sheet(item: $shareItem) { ShareSheet(items: $0.items) }
        .alert(LP("lib_trash_title", ids.count), isPresented: $confirmTrash) {
            Button(L("lib_trash_action"), role: .destructive) { Task { await trash() } }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(key: app.settings.protectFavorites && assets.contains(where: \.isFavorite) ? "lib_trash_text_fav" : "lib_trash_text")
        }
        .alert(LP("lib_hide_title", ids.count), isPresented: $confirmHide) {
            Button(L("lib_hide")) {
                app.hide(ids)
                app.showToast(LP("lib_hidden_done", ids.count), actionTitle: L("undo")) { app.unhide(ids) }
                clear()
            }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(key: "lib_hide_text")
        }
    }

    private func setFavorite(_ value: Bool) async {
        if await app.library.setFavorite(ids, value) == .failed { app.showError(L("fav_failed")) }
        app.reloadLibraryIfNeeded(force: true)
    }

    /// In den PhotoMaid-Papierkorb (Ledger, mit Rückgängig). Favoriten bleiben, wenn „Favoriten schützen“ an ist.
    private func trash() async {
        let list = assets.filter { !(app.settings.protectFavorites && $0.isFavorite) }
        guard !list.isEmpty else { app.showError(L("lib_trash_fav_protected")); return }
        let n = await app.decideMany(list.map(\.reference), .markForCleanup)
        app.showToast(LP("lib_trashed", n), actionTitle: L("feed_view_basket")) { app.navigate(.trash, in: .cleanup) }
        clear()
    }
}

/// Übergabe einer Auswahl an Studio-Seiten, deren Route keine Medienliste trägt (Collage, Abläufe). Nur im Speicher.
@MainActor
final class StudioHandoff {
    static let shared = StudioHandoff()
    var ids: [String] = []

    func take() -> [String] {
        defer { ids = [] }
        return ids
    }
}
