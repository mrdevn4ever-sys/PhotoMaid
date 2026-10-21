import Photos
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

/// Collage: oben die bearbeitbare Vorschau (gleiche Geometrie wie der Export), darunter Bereiche für Layout, Abstand,
/// Hintergrund, Foto sowie Text & Sticker, unten (über der Tableiste) Fotos hinzufügen und Speichern.
/// Gespeichert wird immer eine neue Datei – die Originalfotos bleiben unverändert.
struct CollageView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicType
    let draftID: UUID?

    @State private var model = CollageModel()
    @State private var started = false
    @State private var picker = false
    @State private var replaceIndex: Int?
    /// Keep the editing canvas large; advanced settings stay one tap away.
    @State private var showTools = false
    @State private var saveSheet = false
    @State private var options = CollageSaveOptions()
    @State private var pendingSave: CollageSaveOptions?
    @State private var busy = false
    @State private var exportFile: ExportedFile?
    @State private var exportFolder: URL?
    @State private var exportName = ""
    @State private var exportType: UTType = .jpeg
    @State private var exporting = false
    @State private var shareItem: CollageShareItem?
    @State private var persistTask: Task<Void, Never>?

    var body: some View {
        lifecycle(sheets(framed))
    }

    private var framed: some View {
        page
            .safeAreaInset(edge: .bottom) {
                if model.project != nil { bottomBar }
            }
            .overlay { if busy { LoadingState(message: L("export_running")).background(.ultraThinMaterial) } }
    }

    private func sheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $picker) { addPicker }
            .sheet(isPresented: replaceBinding) { replacePicker }
            .sheet(isPresented: $saveSheet, onDismiss: runPendingSave) { saveSheetContent }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.urls) { cleanupShare() }
            }
            .fileExporter(isPresented: $exporting, document: exportFile, contentType: exportType,
                          defaultFilename: exportName) { result in exported(result) }
    }

    private func lifecycle(_ content: some View) -> some View {
        content
            .task { start() }
            .task(id: model.project?.items.map(\.mediaId) ?? []) { await loadSources() }
            .onChange(of: model.project) { old, _ in
                if old != nil { schedulePersist() }
            }
            .onDisappear {
                persistTask?.cancel()
                persistDraft()
            }
    }

    // MARK: Seite

    @ViewBuilder
    private var page: some View {
        Group {
            if model.project != nil {
                GeometryReader { geo in editor(geo.size) }
            } else if started {
                EmptyState(symbol: "rectangle.3.group", title: L("studio_pick_collage"),
                           actionTitle: L("collage_add")) { picker = true }
            } else {
                Color.clear
            }
        }
        .appPage()
        .navigationTitle(L("studio_collage"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func editor(_ size: CGSize) -> some View {
        let wide = AppWorkspace.isWide(size, accessibility: dynamicType.isAccessibilitySize)
        let stageWidth = size.width - (wide ? 320 : 0)
        let boxWidth = max(0, stageWidth - 2 * AppSpacing.pageMargin)
        // In the default editing mode the actual photo canvas owns most of the
        // screen. Advanced controls are expandable, not permanently stacked below it.
        let boxHeight = max(150, min(size.height * (wide ? 0.96 : (showTools ? 0.46 : 0.82)), boxWidth * 1.55))
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.l)) : AnyLayout(VStackLayout(spacing: AppSpacing.s))
        return layout {
            CollageStage(model: model, box: CGSize(width: boxWidth, height: boxHeight))
                .frame(width: stageWidth, height: boxHeight)
            VStack(spacing: AppSpacing.s) {
                if showTools || wide {
                    Text(verbatim: hint)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, AppSpacing.pageMargin)
                }
                if !wide {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showTools.toggle() }
                    } label: {
                        HStack(spacing: AppSpacing.s) {
                            Label(L("tools_header"), systemImage: "slider.horizontal.3")
                            Spacer()
                            Image(systemName: showTools ? "chevron.down" : "chevron.up")
                        }
                        .font(AppTypography.subheadline.weight(.semibold))
                        .frame(minHeight: AppSpacing.minTouch)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                if showTools || wide {
                    kindPicker
                    tabStrip
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.m) {
                            panel
                            if !model.missing.isEmpty {
                                InfoBanner(symbol: "exclamationmark.triangle", tint: AppColors.warning, text: L("col_missing"))
                            }
                        }
                        .padding(.horizontal, AppSpacing.pageMargin)
                        .padding(.top, AppSpacing.xxs)
                        .padding(.bottom, AppSpacing.l)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: wide ? 300 : nil)
        }
        .padding(.top, AppSpacing.xs)
    }

    private var hint: String {
        guard let p = model.project else { return "" }
        if model.tab == .decor || model.selectedLayer != nil { return L("edit_mk_hint") }
        switch p.kind {
        case .grid: return model.selected != nil ? L("collage_hint_crop") : L("col_layout_hint")
        case .free: return L("collage_hint_free")
        case .strip: return L("col_photo_hint")
        }
    }

    private var kindPicker: some View {
        Picker(L("studio_collage"), selection: Binding(get: { model.project?.kind ?? .grid }, set: { kind in
            model.update { $0 = $0.withKind(kind) }
            model.selected = nil
        })) {
            Text(key: "col_kind_grid").tag(CollageKind.grid)
            Text(key: "col_kind_free").tag(CollageKind.free)
            Text(key: "col_kind_strip").tag(CollageKind.strip)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppSpacing.pageMargin)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(CollageTab.tabs(for: model.project?.kind ?? .grid)) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
        }
    }

    private func tabButton(_ tab: CollageTab) -> some View {
        let on = model.tab == tab
        return Button { model.tab = tab } label: {
            Label(L(tab.titleKey), systemImage: tab.symbol)
                .font(AppTypography.footnote.weight(.semibold))
                .padding(.horizontal, AppSpacing.s)
                .frame(minHeight: AppSpacing.minTouch)
                .foregroundStyle(on ? Color.white : AppColors.textPrimary)
                .background(on ? AppColors.accentFill : AppColors.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(on ? Color.clear : AppColors.surfaceStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }

    @ViewBuilder
    private var panel: some View {
        switch model.tab {
        case .layout: CollageLayoutPanel(model: model)
        case .spacing: CollageSpacingPanel(model: model)
        case .background: CollageBackgroundPanel(model: model)
        case .photo: CollagePhotoPanel(model: model) { index in replaceIndex = index }
        case .decor: CollageDecorPanel(model: model)
        }
    }

    /// Liegt über der Tableiste (`safeAreaInset`), damit nichts verdeckt wird.
    private var bottomBar: some View {
        HStack(spacing: AppSpacing.s) {
            Button { picker = true } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                    .contentShape(.circle)
            }
            .buttonStyle(.pmBordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(key: "collage_add"))
            PrimaryButton(title: L("save"), symbol: "square.and.arrow.down", overMedia: true) { openSave() }
                .disabled(busy || !model.allLoaded)
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: Blätter

    private var addPicker: some View {
        StudioMediaPicker(allowsVideos: false, limit: CollageProject.max,
                          initial: Set(model.project?.items.map(\.mediaId) ?? [])) { ids in
            applySelection(ids)
        }
    }

    private var replaceBinding: Binding<Bool> {
        Binding(get: { replaceIndex != nil }, set: { if !$0 { replaceIndex = nil } })
    }

    private var replacePicker: some View {
        StudioMediaPicker(allowsVideos: false, limit: 1) { ids in
            guard let i = replaceIndex, let id = ids.first, let p = model.project else { return }
            model.replace(p.replacingItem(i, with: id))
        }
    }

    @ViewBuilder
    private var saveSheetContent: some View {
        if let p = model.project, let scene = model.scene {
            CollageSaveSheet(options: $options, project: p, aspect: scene.aspect) { pendingSave = options }
        }
    }

    // MARK: Laden

    private func start() {
        guard !started else { return }
        defer { started = true }
        let drafts = app.kv?.get(StoreKeys.collageDrafts) ?? []
        if let draftID, let draft = drafts.first(where: { $0.id == draftID.uuidString }) {
            model.replace(draft)
        } else {
            let ids = StudioHandoff.shared.take()
            if !ids.isEmpty { model.replace(CollageProject.create(id: UUID().uuidString, ids: ids)) }
        }
    }

    /// Vorschaubilder (aufrecht) – Größe passend zur Zahl der Fotos, nie die Originale im Speicher.
    private func loadSources() async {
        guard let p = model.project else { return }
        let n = p.items.count
        let edge: CGFloat = n <= 4 ? 1400 : (n <= 9 ? 1000 : 700)
        for id in p.items.map(\.mediaId) where model.sources[id] == nil && !model.missing.contains(id) {
            let result = await app.previews.image(for: id, targetSize: CGSize(width: edge, height: edge), allowNetwork: true)
            if Task.isCancelled { return }
            if case .image(let image) = result, let cg = CollageRenderer.upright(image) {
                model.setSource(cg, for: id)
            } else {
                model.setSource(nil, for: id)
            }
        }
    }

    /// Auswahl aus dem Picker übernehmen: vorhandene Fotos behalten ihre Lage, neue kommen dazu, abgewählte gehen.
    private func applySelection(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        guard var p = model.project else {
            model.replace(CollageProject.create(id: UUID().uuidString, ids: ids))
            persistDraft()
            return
        }
        let keep = Set(ids)
        let existing = Set(p.items.map(\.mediaId))
        let added = ids.filter { !existing.contains($0) }
        if !added.isEmpty { p = p.addItems(added) }
        while p.items.count > 1, let i = p.items.firstIndex(where: { !keep.contains($0.mediaId) }) {
            p = p.removeItem(i)
        }
        model.replace(p)
        model.selected = nil
        persistDraft()
    }

    // MARK: Entwurf

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            persistDraft()
        }
    }

    private func persistDraft() {
        guard let project = model.project, let kv = app.kv else { return }
        var drafts = kv.get(StoreKeys.collageDrafts)
        if let index = drafts.firstIndex(where: { $0.id == project.id }) { drafts[index] = project } else { drafts.append(project) }
        let limit = app.capabilities.hasProToolsAccess ? 50 : 3
        if drafts.count > limit { drafts = Array(drafts.suffix(limit)) }
        try? kv.set(StoreKeys.collageDrafts, drafts)
    }

    // MARK: Speichern

    private func openSave() {
        guard let p = model.project else { return }
        let others = (app.kv?.get(StoreKeys.collageDrafts) ?? []).filter { $0.id != p.id }
        guard app.capabilities.hasProToolsAccess || others.count < 3 else { app.navigate(.pro); return }
        // Vorauswahl immer „als Kopie in Fotos“; Auflösung und Dateityp bleiben wie zuletzt gewählt.
        options.destination = .photos
        saveSheet = true
    }

    private func runPendingSave() {
        guard let o = pendingSave else { return }
        pendingSave = nil
        Task { await export(o) }
    }

    private func export(_ o: CollageSaveOptions) async {
        guard let p = model.project, let scene = model.scene, !busy else { return }
        busy = true
        defer { busy = false }
        cleanupExport()
        let size = CollageGeometry.outputSize(p, aspect: scene.aspect, resolution: o.resolution)
        let images = await exportImages(p, scene: scene, size: size)
        guard !images.isEmpty else { app.showError(L("collage_err_save")); return }
        let box = UncheckedBox(images)
        let format = o.format
        let data: Data? = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let cg = try? CollageRenderer.shared.render(project: p, scene: scene, size: size, images: box.value) else {
                return nil
            }
            return try? CollageRenderer.shared.encode(cg, format: format)
        }.value
        guard let data else { app.showError(L("studio_err_memory")); return }
        let name = Self.fileName(format)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            app.showError(L("collage_err_save"))
            return
        }
        switch o.destination {
        case .photos:
            await saveToLibrary(url: url, name: name, albumID: nil, albumTitle: nil, bytes: data.count, count: p.items.count,
                                sources: p.items.map(\.mediaId))
            try? FileManager.default.removeItem(at: folder)
        case .album(let id, let title):
            await saveToLibrary(url: url, name: name, albumID: id, albumTitle: title, bytes: data.count, count: p.items.count,
                                sources: p.items.map(\.mediaId))
            try? FileManager.default.removeItem(at: folder)
        case .files:
            exportFolder = folder
            exportFile = ExportedFile(url: url)
            exportName = name
            exportType = format == .png ? .png : .jpeg
            exporting = true
        case .share:
            shareItem = CollageShareItem(urls: [url], folder: folder)
        }
    }

    /// Jedes Foto nur so groß laden, wie es in der Ausgabe gebraucht wird (Speicher), höchstens 4096 px.
    private func exportImages(_ p: CollageProject, scene: CollageScene, size: PxSize) async -> [String: CGImage] {
        var images: [String: CGImage] = [:]
        for pl in scene.placements where p.items.indices.contains(pl.index) {
            let id = p.items[pl.index].mediaId
            let edge = CollageGeometry.neededSourceEdge(pl, output: size, cap: 4096)
            if let have = images[id], max(have.width, have.height) >= edge { continue }
            if let preview = model.sources[id], max(preview.width, preview.height) >= edge {
                images[id] = preview
                continue
            }
            let result = await app.previews.image(for: id, targetSize: CGSize(width: edge, height: edge), allowNetwork: true)
            if case .image(let image) = result, let cg = CollageRenderer.upright(image) {
                images[id] = cg
            } else if let preview = model.sources[id] {
                images[id] = preview
            }
        }
        return images
    }

    private func saveToLibrary(url: URL, name: String, albumID: String?, albumTitle: String?, bytes: Int, count: Int,
                               sources: [String]) async {
        let request = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: false, creationDate: Date(), latitude: nil,
                                                      longitude: nil, albumID: albumID, filename: name)
        guard case .saved(let newID) = await app.library.save(request) else {
            app.showError(L("collage_err_save"))
            return
        }
        // Gespeicherte Collage = behalten und in „Bearbeitet“ (sonst erschiene sie als neues offenes Medium).
        _ = await EditSaver.finish(app: app, original: nil, newID: newID, mode: .copy, video: false, kind: .collage,
                                   count: count, sources: sources, bytes: Int64(bytes))
        persistDraft()
        Haptics.success()
        if let albumTitle {
            app.showToast(L("collage_saved_album", albumTitle))
        } else {
            app.showToast(L("collage_saved_photos"))
        }
    }

    private func exported(_ result: Result<URL, any Error>) {
        defer { cleanupExport() }
        switch result {
        case .success:
            persistDraft()
            app.showToast(L("collage_saved_files"))
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            app.showError(L("collage_err_save"))
        }
    }

    private func cleanupExport() {
        if let exportFolder { try? FileManager.default.removeItem(at: exportFolder) }
        exportFolder = nil
        exportFile = nil
    }

    private func cleanupShare() {
        if let folder = shareItem?.folder { try? FileManager.default.removeItem(at: folder) }
        shareItem = nil
    }

    private static func fileName(_ format: EditFormat) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(L("studio_collage_file")) \(f.string(from: Date())).\(format.fileExtension)"
    }
}

/// Fertige Collage zum Teilen (Datei im Zwischenspeicher, wird danach entfernt).
struct CollageShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
    let folder: URL
}
