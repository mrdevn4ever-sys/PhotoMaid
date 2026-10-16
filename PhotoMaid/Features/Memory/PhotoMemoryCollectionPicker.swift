import PhotoMaidCore
import SwiftUI

/// Read-only source choice. Folders include their subalbums; picking never adds photos or creates an album.
struct PhotoMemoryCollectionPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pick: (String, String) -> Void
    @State private var albums: [PhotoAlbum]?
    @State private var query = ""

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let isFolder: Bool
    }

    private var entries: [Entry] {
        func walk(_ albums: [PhotoAlbum], path: [String]) -> [Entry] {
            albums.filter { !app.settings.hiddenAlbums.contains($0.id) }.flatMap { album in
                let names = path + [album.title]
                let entry = Entry(id: album.id, title: names.joined(separator: " / "), isFolder: album.isFolder)
                return [entry] + walk(album.children, path: names)
            }
        }
        let tokens = SearchText.tokens(query)
        return walk(albums ?? [], path: []).filter { tokens.isEmpty || SearchText.matches(tokens, fields: [$0.title]) }
    }

    var body: some View {
        NavigationStack {
            List {
                if albums == nil {
                    LoadingState(message: L("folder_loading"))
                } else if entries.isEmpty {
                    EmptyState(symbol: "folder", title: L("grid_empty_title"))
                } else {
                    ForEach(entries) { entry in
                        Button {
                            pick(entry.id, entry.title)
                            dismiss()
                        } label: {
                            Label(entry.title, systemImage: entry.isFolder ? "folder" : "rectangle.stack")
                                .frame(minHeight: AppSpacing.minTouch)
                        }
                        .accessibilityIdentifier("memory.collection")
                    }
                }
            }
            .appPage()
            .navigationTitle(L("memory_pick_collection"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text(key: "lib_folders_search_hint"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
            }
            .task(id: app.library.changeToken) { albums = await PhotoLibraryService.loadAlbums() }
        }
    }
}
