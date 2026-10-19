import CoreImage
import PhotoMaidCore
import SwiftUI

struct WorkflowsView: View {
    @Environment(AppModel.self) private var app
    @State private var workflows: [Workflow] = []
    @State private var editing: Workflow?
    @State private var pickerWorkflow: Workflow?
    @State private var results: [WorkflowRunResult] = []
    @State private var running = false

    var body: some View {
        List {
            if workflows.isEmpty {
                EmptyState(symbol: "arrow.triangle.branch", title: L("wf_empty"), actionTitle: L("wf_new")) {
                    editing = Workflow(name: L("wf_new"))
                }
            }
            ForEach(workflows) { workflow in
                Section {
                    ForEach(WorkflowRules.steps(workflow), id: \.self) { step in Text(verbatim: stepText(step)) }
                    HStack {
                        Button(L("wf_edit")) { editing = workflow }
                        Spacer()
                        Button(L("wf_run")) { pickerWorkflow = workflow }
                    }
                } header: { Text(verbatim: workflow.name) }
            }
            if !results.isEmpty {
                Section(L("wf_result_title")) {
                    ForEach(results) { result in
                        HStack { Text(verbatim: result.name); Spacer(); Text(verbatim: result.status) }
                    }
                }
            }
        }
        .appPage()
        .navigationTitle(L("wf_title"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editing = Workflow(name: L("wf_new")) } label: { Image(systemName: "plus") } } }
        .overlay { if running { LoadingState(message: L("wf_running")).background(.ultraThinMaterial) } }
        .sheet(item: $editing) { workflow in WorkflowEditor(workflow: workflow) { save($0) } }
        .sheet(item: $pickerWorkflow) { workflow in
            StudioMediaPicker(allowsVideos: false, limit: app.capabilities.batchLimit ?? 500) { ids in
                Task { await run(workflow, ids: ids) }
            }
        }
        .onAppear { workflows = app.kv?.get(StoreKeys.workflows) ?? [] }
    }

    private func save(_ workflow: Workflow) {
        guard WorkflowRules.isValid(workflow) else { app.showError(L("wf_reason_error")); return }
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) { workflows[index] = workflow } else { workflows.append(workflow) }
        try? app.kv?.set(StoreKeys.workflows, workflows)
    }

    private func run(_ workflow: Workflow, ids: [String]) async {
        running = true
        defer { running = false }
        results = await WorkflowProcessor.run(app: app, workflow: workflow, ids: ids)
    }

    private func stepText(_ step: WorkflowStep) -> String {
        switch step {
        case .format: L("wf_step_format")
        case .resize: L("wf_step_resize")
        case .targetSize: L("wf_step_target")
        case .quality: L("wf_step_quality")
        case .location: L("tools_remove_location")
        case .videoTarget: L("wf_step_video")
        case .rename: L("wf_step_rename")
        case .album: L("wf_step_folder")
        case .save: L("wf_step_save")
        case .share: L("wf_step_share")
        }
    }
}

private struct WorkflowEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var workflow: Workflow
    let save: (Workflow) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("wf_name"), text: $workflow.name)
                Picker(L("wf_format"), selection: $workflow.format) {
                    Text(key: "wf_format_keep").tag(WorkflowFormat.keep)
                    Text(verbatim: "JPEG").tag(WorkflowFormat.jpeg)
                    Text(verbatim: "PNG").tag(WorkflowFormat.png)
                    Text(verbatim: "HEIC").tag(WorkflowFormat.heic)
                }
                Picker(L("wf_long_edge"), selection: $workflow.longEdge) {
                    Text(key: "wf_off").tag(Int?.none)
                    ForEach(WorkflowRules.longEdges, id: \.self) { Text(verbatim: String($0)).tag(Int?.some($0)) }
                }
                Stepper(L("wf_quality") + " · " + String(workflow.quality), value: $workflow.quality, in: 30...100, step: 5)
                Toggle(L("wf_location"), isOn: $workflow.removeLocation)
                Picker(L("wf_target"), selection: $workflow.photoMaxBytes) {
                    Text(key: "wf_off").tag(Int64?.none)
                    ForEach(WorkflowRules.photoTargets, id: \.self) { Text(verbatim: SizeText.bytes($0)).tag(Int64?.some($0)) }
                }
                Picker(L("wf_finish"), selection: $workflow.finish) {
                    Text(key: "wf_finish_save").tag(WorkflowFinish.save)
                    Text(key: "wf_finish_share").tag(WorkflowFinish.share)
                    Text(key: "wf_finish_both").tag(WorkflowFinish.saveAndShare)
                }
                TextField(L("wf_name_base"), text: Binding(get: { workflow.nameBase ?? "" }, set: { value in
                    workflow.nameBase = value.isEmpty ? nil : value
                }))
            }
            .navigationTitle(L("wf_edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("save")) { save(workflow); dismiss() } }
            }
        }
    }
}

struct WorkflowRunResult: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let status: String
}

@MainActor
enum WorkflowProcessor {
    static func run(app: AppModel, workflow: Workflow, ids: [String]) async -> [WorkflowRunResult] {
        var results: [WorkflowRunResult] = []
        for (index, id) in ids.enumerated() {
            guard let asset = app.asset(id), !asset.isVideo else {
                results.append(WorkflowRunResult(name: String(index + 1), status: L("wf_status_skipped")))
                continue
            }
            do {
                let input = try await BatchProcessor.imageData(id)
                guard let source = EditRenderer.source(input) else { throw BatchProcessor.Failure.render }
                let metadata = EditRenderer.metadata(input)
                let format = editFormat(workflow, uti: metadata?.uti)
                let startEdge = WorkflowRules.targetEdge(workflow, width: Int(source.extent.width), height: Int(source.extent.height))
                var encoded: Data?
                if let target = workflow.photoMaxBytes {
                    let outcome = try await TargetSize.search(maxBytes: target, startEdge: startEdge,
                                                              startQuality: workflow.quality, minEdge: workflow.minLongEdge,
                                                              minQuality: workflow.minQuality, lossless: format == .png) { attempt in
                        let value = encode(source, edge: attempt.longEdge, quality: attempt.quality, format: format,
                                           metadata: metadata?.props, removeLocation: workflow.removeLocation)
                        encoded = value
                        guard let value else { throw BatchProcessor.Failure.render }
                        return Int64(value.count)
                    }
                    guard case .met = outcome, let encoded else {
                        results.append(WorkflowRunResult(name: String(index + 1), status: L("wf_status_notmet")))
                        continue
                    }
                    try await save(app: app, workflow: workflow, asset: asset, data: encoded, format: format, index: index, total: ids.count)
                } else {
                    guard let data = encode(source, edge: startEdge, quality: workflow.quality, format: format,
                                            metadata: metadata?.props, removeLocation: workflow.removeLocation) else {
                        throw BatchProcessor.Failure.render
                    }
                    try await save(app: app, workflow: workflow, asset: asset, data: data, format: format, index: index, total: ids.count)
                }
                results.append(WorkflowRunResult(name: String(index + 1), status: L("wf_status_done")))
            } catch {
                results.append(WorkflowRunResult(name: String(index + 1), status: L("wf_status_failed")))
            }
        }
        return results
    }

    private static func encode(_ image: CIImage, edge: Int, quality: Int, format: EditFormat,
                               metadata: [String: Any]?, removeLocation: Bool) -> Data? {
        let current = max(image.extent.width, image.extent.height)
        var output = image
        if current > CGFloat(edge) {
            let scale = CGFloat(edge) / current
            output = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return EditRenderer.shared.encode(output, format: format, metadata: metadata, removeLocation: removeLocation,
                                          quality: Double(quality) / 100)
    }

    private static func editFormat(_ workflow: Workflow, uti: String?) -> EditFormat {
        switch WorkflowRules.outputFormat(workflow, uti: uti) {
        case .keep, .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        }
    }

    private static func save(app: AppModel, workflow: Workflow, asset: MediaAsset, data: Data, format: EditFormat,
                             index: Int, total: Int) async throws {
        guard workflow.saves else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stem = WorkflowRules.fileStem(workflow, index: index, total: total,
                                          originalName: PhotoLibraryService.originalFilename(asset.id), suffix: L("edit_copy_suffix"))
        let url = folder.appendingPathComponent(stem + "." + format.fileExtension)
        try data.write(to: url, options: .atomic)
        let request = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: false, creationDate: asset.creationDate,
                                                      latitude: workflow.removeLocation ? nil : asset.latitude,
                                                      longitude: workflow.removeLocation ? nil : asset.longitude,
                                                      albumID: workflow.album, filename: url.lastPathComponent)
        guard case .saved(let newID) = await app.library.save(request) else { throw BatchProcessor.Failure.write }
        _ = await app.decide(.photo(newID), .keep)
    }
}
