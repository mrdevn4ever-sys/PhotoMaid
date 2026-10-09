import PhotoMaidCore
import SwiftUI

/// „Zu Album hinzufügen“ (E5: Alben der Fotos-App). Nie eine Entscheidung. Angepinnte und zuletzt verwendete oben,
/// Suche, neues Album. Die Änderung ist in der Fotos-App sichtbar (und wird mit iCloud-Fotos synchronisiert).
struct AlbumPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let assetIDs: [String]
    let pick: (String, String) -> Void

    @State private var albums: [PhotoAlbum]?
    @State private var query = ""
    @State private var newName = ""
    @State private var askName = false

    private var flat: [PhotoAlbum] {
        func walk(_ list: [PhotoAlbum]) -> [PhotoAlbum] { list.flatMap { $0.isFolder ? walk($0.children) : [$0] } }
        return walk(albums ?? []).filter(\.canAddAssets)
    }

    private var filtered: [PhotoAlbum] {
        let tokens = SearchText.tokens(query)
        guard !tokens.isEmpty else { return flat }
        return flat.filter { SearchText.matches(tokens, fields: [$0.title]) }
    }

    var body: some View {
        NavigationStack {
            List {
                if albums == nil {
                    LoadingState(message: L("folder_loading")).listRowBackground(Color.clear)
                } else {
                    let pinned = flat.filter { app.settings.pinnedAlbums.contains($0.id) }
                    let recent = app.settings.recentAlbums.compactMap { id in flat.first { $0.id == id } }
                        .filter { !app.settings.pinnedAlbums.contains($0.id) }
                    if query.isEmpty && !pinned.isEmpty {
                        Section(L("folder_pinned")) { ForEach(pinned) { row($0) } }
                    }
                    if query.isEmpty && !recent.isEmpty {
                        Section(L("folder_recent")) { ForEach(recent) { row($0) } }
                    }
                    Section(L("folder_all")) {
                        ForEach(filtered) { row($0) }
                        Button { askName = true } label: { Label(L("folder_new"), systemImage: "plus") }
                            .frame(minHeight: AppSpacing.minTouch)
                    }
                    Section {
                        Text(key: "folder_note").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .searchable(text: $query, prompt: Text(key: "folder_search"))
            .appPage()
            .navigationTitle(L("folder_action"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } } }
            .alert(L("folder_new"), isPresented: $askName) {
                TextField(L("folder_name"), text: $newName)
                Button(L("folder_create_move")) { Task { await create() } }
                Button(L("cancel"), role: .cancel) { newName = "" }
            }
        }
        .task { albums = await PhotoLibraryService.loadAlbums() }
    }

    private func row(_ a: PhotoAlbum) -> some View {
        Button {
            pick(a.id, a.title)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "rectangle.stack").foregroundStyle(AppColors.accent).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(verbatim: a.title).foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: LP("items_count", a.count)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
            }
            .frame(minHeight: AppSpacing.minTouch)
            .contentShape(.rect)
        }
        .swipeActions {
            Button { app.togglePinnedAlbum(a.id) } label: {
                Label(L(app.settings.pinnedAlbums.contains(a.id) ? "folder_unpin" : "folder_pin"),
                      systemImage: app.settings.pinnedAlbums.contains(a.id) ? "pin.slash" : "pin")
            }
            .tint(AppColors.accentFill)
        }
    }

    private func create() async {
        guard let name = AlbumRules.normalizeName(newName) else { app.showError(L("folder_invalid")); return }
        newName = ""
        let existing = flat.map(\.title)
        let unique = AlbumRules.uniqueName(existing: existing, wanted: name)
        guard let id = await app.library.createAlbum(named: unique) else { app.showError(L("album_failed")); return }
        pick(id, unique)
        dismiss()
    }
}
