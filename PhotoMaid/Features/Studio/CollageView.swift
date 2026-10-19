import Photos
import PhotoMaidCore
import SwiftUI

struct CollageView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let draftID: UUID?
    @State private var project: CollageProject?
    @State private var preview: CGImage?
    @State private var picker = false
    @State private var busy = false
    @State private var longEdge = 2048
    private let renderer = CollageRenderer()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.m) {
                if let preview {
                    Image(decorative: preview, scale: 1).resizable().scaledToFit()
                        .background(Color.black.opacity(0.08)).clipShape(.rect(cornerRadius: AppRadii.card))
                } else if project == nil {
                    EmptyState(symbol: "rectangle.3.group", title: L("studio_pick_collage"),
                               actionTitle: L("collage_add")) { picker = true }
                } else {
                    LoadingState(message: L("feed_loading"))
                        .frame(height: 260)
                }
                if var value = project {
                    Picker(L("studio_collage"), selection: Binding(get: { value.kind }, set: { kind in
                        value.kind = kind
                        value.tree = CollageLayout.template(value.template, value.items.count)
                        project = value
                        Task { await rebuildPreview() }
                    })) {
                        Text(key: "col_kind_grid").tag(CollageKind.grid)
                        Text(key: "col_kind_free").tag(CollageKind.free)
                        Text(key: "col_kind_strip").tag(CollageKind.strip)
                    }
                    .pickerStyle(.segmented)
                    if value.kind == .grid {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(CollageLayout.templates(for: value.items.count), id: \.self) { template in
                                    Button(template) {
                                        project = value.withTemplate(template)
                                        Task { await rebuildPreview() }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    Picker(L("tools_sizes"), selection: $longEdge) {
                        Text("1080").tag(1080)
                        Text("2048").tag(2048)
                        Text("4096").tag(4096)
                    }
                    Button { picker = true } label: { Label(L("collage_add"), systemImage: "plus") }
                        .buttonStyle(.glass)
                    Button { Task { await save(value) } } label: { Label(L("edit_save_copy_action"), systemImage: "square.and.arrow.down") }
                        .buttonStyle(.glassProminent).disabled(busy)
                }
            }
            .padding(AppSpacing.pageMargin)
        }
        .appPage()
        .navigationTitle(L("studio_collage"))
        .overlay { if busy { LoadingState(message: L("col_save_action")).background(.ultraThinMaterial) } }
        .sheet(isPresented: $picker) {
            StudioMediaPicker(allowsVideos: false, limit: CollageProject.max,
                              initial: Set(project?.items.map(\.mediaId) ?? [])) { ids in
                project = CollageProject.create(id: project?.id ?? UUID().uuidString, ids: ids, kind: project?.kind ?? .grid)
                persistDraft()
                Task { await rebuildPreview() }
            }
        }
        .task { load(); await rebuildPreview() }
    }

    private func load() {
        let drafts = app.kv?.get(StoreKeys.collageDrafts) ?? []
        if let draftID, let draft = drafts.first(where: { $0.id == draftID.uuidString }) {
            project = draft
        } else {
            let ids = StudioHandoff.shared.take()
            if !ids.isEmpty { project = CollageProject.create(id: UUID().uuidString, ids: ids) }
        }
    }

    private func sourceImages(_ value: CollageProject, target: Int) async -> [String: CGImage] {
        var images: [String: CGImage] = [:]
        for item in value.items {
            let result = await app.previews.image(for: item.mediaId, targetSize: CGSize(width: target, height: target), allowNetwork: true)
            if case .image(let image) = result, let cg = image.cgImage { images[item.mediaId] = cg }
        }
        return images
    }

    private func rebuildPreview() async {
        guard let value = project else { return }
        let images = await sourceImages(value, target: 1200)
        preview = try? renderer.render(project: value, images: images, longEdge: 1200)
    }

    private func save(_ value: CollageProject) async {
        let allowed = app.capabilities.hasProToolsAccess || (app.kv?.get(StoreKeys.collageDrafts).count ?? 0) < 3
        guard allowed else { app.navigate(.pro); return }
        busy = true
        defer { busy = false }
        do {
            let images = await sourceImages(value, target: longEdge)
            let output = try renderer.render(project: value, images: images, longEdge: longEdge)
            let data = try renderer.jpeg(output)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("PhotoMaid.jpg")
            defer { try? FileManager.default.removeItem(at: folder) }
            try data.write(to: url, options: .atomic)
            let request = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: false, creationDate: Date(),
                                                          latitude: nil, longitude: nil, filename: "PhotoMaid.jpg")
            let result = await app.library.save(request)
            guard case .saved(let newID) = result else { app.showError(L("edit_err_save")); return }
            _ = await EditSaver.finish(app: app, original: nil, newID: newID, mode: .copy, video: false,
                                      kind: .collage, count: value.items.count, sources: value.items.map(\.mediaId),
                                      bytes: Int64(data.count))
            persistDraft()
            app.showToast(L("done_saved"))
        } catch {
            app.showError(L("studio_err_memory"))
        }
    }

    private func persistDraft() {
        guard let project, let kv = app.kv else { return }
        var drafts = kv.get(StoreKeys.collageDrafts)
        if let index = drafts.firstIndex(where: { $0.id == project.id }) { drafts[index] = project } else { drafts.append(project) }
        let limit = app.capabilities.hasProToolsAccess ? 50 : 3
        if drafts.count > limit { drafts = Array(drafts.suffix(limit)) }
        try? kv.set(StoreKeys.collageDrafts, drafts)
    }
}
