import PhotoMaidCore
import PhotosUI
import SwiftUI

struct SnakeGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: PhotoSnakeModel
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        let images = model.gallery.images
        return NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $items,
                                 maxSelectionCount: max(1, PhotoSnakeGallery.maximumPhotos - model.gallery.selection.photos.count),
                                 selectionBehavior: .ordered, matching: .images) {
                        Label(L("snake_gallery_add"), systemImage: "photo.badge.plus")
                    }
                    .disabled(model.gallery.busy || model.gallery.selection.photos.count >= PhotoSnakeGallery.maximumPhotos)
                    .accessibilityIdentifier("snake.gallery.add")
                    Text(key: "snake_gallery_privacy").font(.footnote).foregroundStyle(.secondary)
                    if model.gallery.busy { ProgressView().accessibilityLabel(Text(key: "memory_loading")) }
                    if let error = model.gallery.error {
                        Text(verbatim: error).foregroundStyle(.red)
                        if !model.gallery.restored { Button(L("retry")) { Task { await model.gallery.restore() } } }
                    }
                }
                Section(L("snake_gallery_order")) {
                    if model.gallery.selection.photos.isEmpty { Text(key: "snake_gallery_empty").foregroundStyle(.secondary) }
                    ForEach(Array(model.gallery.selection.photos.enumerated()), id: \.element.id) { index, photo in
                        HStack(spacing: 12) {
                            Group {
                                if let image = images[photo.id.uuidString] {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Image(uiImage: SnakeArt.image("segment_placeholder")).resizable().scaledToFit()
                                }
                            }
                            .frame(width: 56, height: 56).clipShape(.circle)
                            .overlay(Circle().stroke(.green.opacity(0.5), lineWidth: 2))
                            .accessibilityHidden(true)
                            Text(verbatim: L("snake_gallery_photo", index + 1)).monospacedDigit()
                            Spacer(minLength: 0)
                            Button(role: .destructive) { Task { await model.gallery.remove(photo.id) } } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless).accessibilityLabel(Text(key: "remove"))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(named: Text(key: "snake_gallery_up")) {
                            guard index > 0 else { return }
                            Task { await model.gallery.move(from: IndexSet(integer: index), to: index - 1) }
                        }
                        .accessibilityAction(named: Text(key: "snake_gallery_down")) {
                            guard index + 1 < model.gallery.selection.photos.count else { return }
                            Task { await model.gallery.move(from: IndexSet(integer: index), to: index + 2) }
                        }
                    }
                    .onMove { offsets, destination in Task { await model.gallery.move(from: offsets, to: destination) } }
                    .onDelete { offsets in
                        let ids = offsets.map { model.gallery.selection.photos[$0].id }
                        Task { for id in ids { await model.gallery.remove(id) } }
                    }
                    .disabled(model.gallery.busy)
                }
            }
            .navigationTitle(L("snake_gallery_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("done")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(model.gallery.busy) }
            }
            .task { await model.gallery.restore() }
            .onChange(of: items) { _, chosen in
                guard !chosen.isEmpty else { return }
                Task {
                    let before = model.gallery.ids.count
                    await model.gallery.add(chosen)
                    if model.gallery.ids.count > before { model.audio.play(.photo_added, enabled: model.preferences.sound) }
                    items = []
                }
            }
            .onChange(of: model.gallery.revision) { _, _ in model.applyGalleryChanges() }
        }
    }
}
