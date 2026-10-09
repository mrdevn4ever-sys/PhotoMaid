import PhotoMaidCore
import SwiftUI

struct ToolsView: View {
    @Environment(AppModel.self) private var app
    let kind: ToolKind
    @State private var ids: [String] = []
    @State private var picker = false
    @State private var longEdge = 2048
    @State private var quality = 85
    @State private var format = EditFormat.jpeg
    @State private var gifDelay = 0.5
    @State private var exposure: Float = 0
    @State private var summary: BatchSummary?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Button { picker = true } label: { Label(L("tools_pick"), systemImage: "photo.on.rectangle.angled") }
                Text(verbatim: LP("tools_selected", ids.count)).foregroundStyle(AppColors.textSecondary)
            }
            if kind == .resize || kind == .convert || kind == .batchEdit {
                Section {
                    Picker(L("tools_long_edge"), selection: $longEdge) {
                        ForEach(BatchRules.longEdges, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                    Picker(L("tools_quality"), selection: $quality) {
                        ForEach(BatchRules.qualities, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                    if kind == .convert {
                        Picker(L("tools_target_format"), selection: $format) {
                            Text(verbatim: "JPEG").tag(EditFormat.jpeg)
                            Text(verbatim: "PNG").tag(EditFormat.png)
                            Text(verbatim: "HEIC").tag(EditFormat.heic)
                        }
                    }
                    if kind == .batchEdit {
                        Slider(value: $exposure, in: -100...100) { Text(key: "edit_adj_exposure") }
                    }
                }
            }
            if kind == .gif {
                Section {
                    Picker(L("tools_gif_size"), selection: $longEdge) {
                        ForEach(GifPlan.sizes, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                    Slider(value: $gifDelay, in: 0.1...2, step: 0.1) { Text(key: "tools_gif_delay") }
                }
            }
            Section {
                Button { Task { await run() } } label: { Label(L("tools_start"), systemImage: "play.fill") }
                    .buttonStyle(.glassProminent).disabled(ids.isEmpty || busy)
            }
            if let summary {
                Section(L("done")) {
                    Text(verbatim: LP("tools_done", summary.done))
                    Text(verbatim: LP("tools_skipped", summary.skipped))
                    Text(verbatim: LP("tools_failed_n", summary.failed))
                    if summary.unknownSizes > 0 { Text(verbatim: LP("tools_unknown", summary.unknownSizes)) }
                }
            }
        }
        .appPage()
        .navigationTitle(title)
        .overlay { if busy { LoadingState(message: L("tools_running")).background(.ultraThinMaterial) } }
        .sheet(isPresented: $picker) {
            StudioMediaPicker(allowsVideos: false, limit: selectionLimit, initial: Set(ids)) { ids = $0 }
        }
    }

    private var selectionLimit: Int {
        if kind == .gif { return GifPlan.maxFrames }
        return app.capabilities.batchLimit ?? 500
    }

    private var title: String {
        switch kind {
        case .resize: L("tools_resize")
        case .convert: L("tools_convert")
        case .removeLocation: L("tools_location")
        case .stitch: L("tools_stitch")
        case .gif: L("tools_gif")
        case .batchEdit: L("tools_header")
        }
    }

    private func run() async {
        if (kind == .gif || kind == .batchEdit) && !app.capabilities.hasProToolsAccess { app.navigate(.pro); return }
        busy = true
        defer { busy = false }
        do {
            if kind == .stitch {
                let data = try await BatchProcessor.stitch(ids: ids)
                try await save(data, fileExtension: "jpg", type: false)
                app.showToast(L("tools_stitch_saved"))
                return
            }
            if kind == .gif {
                let data = try await BatchProcessor.gif(ids: ids, maxEdge: longEdge, delay: gifDelay)
                try await save(data, fileExtension: "gif", type: false)
                app.showToast(L("tools_gif_saved"))
                return
            }
            let tool: BatchTool
            switch kind {
            case .resize, .batchEdit: tool = .resize
            case .convert: tool = .convert
            case .removeLocation: tool = .stripLocation
            default: tool = .resize
            }
            var options = BatchOptions(tool: tool)
            options.longEdge = kind == .removeLocation ? nil : longEdge
            options.quality = quality
            options.format = format
            var recipe: EditRecipe?
            if kind == .batchEdit {
                var value = EditRecipe()
                value.adjust.exposure = exposure
                recipe = value
            }
            summary = await BatchProcessor.process(app: app, ids: ids, options: options, recipe: recipe)
        } catch {
            app.showError(L("tools_failed"))
        }
    }

    private func save(_ data: Data, fileExtension: String, type: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("PhotoMaid." + fileExtension)
        try data.write(to: url, options: .atomic)
        let request = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: type, creationDate: Date(), latitude: nil,
                                                      longitude: nil, filename: url.lastPathComponent)
        guard case .saved(let newID) = await app.library.save(request) else { throw BatchProcessor.Failure.write }
        _ = await app.decide(.photo(newID), .keep)
    }
}
