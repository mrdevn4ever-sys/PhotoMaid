import Photos
import PhotoMaidCore
import SwiftUI

/// Werkzeuge für viele Fotos auf einmal (Verkleinern, Umwandeln, Standort entfernen, Screenshots zusammenfügen, GIF).
/// Jede Zahl trägt Einheit und Bedeutung; Ergebnisse sind immer neue Kopien, Originale bleiben unverändert.
struct ToolsView: View {
    @Environment(AppModel.self) private var app
    @State private var kind: ToolKind
    @State private var ids: [String] = []
    @State private var picker = false
    /// Längste Seite in Pixeln; `nil` = Originalgröße (nur beim Umwandeln angeboten).
    @State private var longEdge: Int?
    @State private var quality = 80
    @State private var format = EditFormat.jpeg
    @State private var gifEdge = GifPlan.sizes.first ?? 480
    @State private var gifDelay = 0.5
    @State private var exposure: Float = 0
    @State private var summary: BatchSummary?
    @State private var busy = false
    @State private var noWorkMessage: String?

    init(kind: ToolKind) {
        _kind = State(initialValue: kind)
        _longEdge = State(initialValue: kind == .convert ? nil : 2048)
    }

    var body: some View {
        form
            .appPage()
            .navigationTitle(title(kind))
            .safeAreaInset(edge: .bottom) { startBar }
            .overlay { if busy { LoadingState(message: L("tools_running")).background(.ultraThinMaterial) } }
            .sheet(isPresented: $picker) {
                StudioMediaPicker(allowsVideos: false, limit: selectionLimit, initial: Set(ids)) { ids = $0 }
            }
            .alert(L("notice"), isPresented: Binding(get: { noWorkMessage != nil },
                                                     set: { if !$0 { noWorkMessage = nil } })) {
                Button(L("ok"), role: .cancel) { noWorkMessage = nil }
            } message: {
                Text(verbatim: noWorkMessage ?? "")
            }
            .onChange(of: kind) { _, newKind in
                summary = nil
                if newKind == .convert { longEdge = nil } else if longEdge == nil { longEdge = 2048 }
            }
    }

    private var form: some View {
        Form {
            introSection
            if kind == .resize || kind == .convert || kind == .batchEdit { sizeSection }
            if kind == .convert { formatSection }
            if showsQuality { qualitySection }
            if kind == .batchEdit { exposureSection }
            if kind == .gif {
                gifSizeSection
                gifTimingSection
            }
            if let summary { resultSection(summary) }
        }
    }

    // MARK: Werkzeug und Auswahl

    private var introSection: some View {
        Section {
            if kind != .batchEdit {
                Picker(L("tools_tool_label"), selection: $kind) {
                    ForEach(Self.switchable, id: \.self) { tool in Text(verbatim: title(tool)).tag(tool) }
                }
            }
            Text(verbatim: intro(kind)).font(AppTypography.subheadline).fixedSize(horizontal: false, vertical: true)
            Button { picker = true } label: {
                Label(L("tools_pick"), systemImage: "photo.on.rectangle.angled").frame(minHeight: AppSpacing.minTouch)
            }
            Text(verbatim: ids.isEmpty ? L("tools_none_selected") : LP("tools_selected", ids.count))
                .foregroundStyle(AppColors.textSecondary)
        } footer: {
            Text(key: "tools_copies_note")
        }
    }

    private static let switchable: [ToolKind] = [.resize, .convert, .removeLocation, .stitch, .gif]

    private func title(_ tool: ToolKind) -> String {
        switch tool {
        case .resize: L("tools_resize")
        case .convert: L("tools_convert")
        case .removeLocation: L("tools_location")
        case .stitch: L("tools_stitch")
        case .gif: L("tools_gif")
        case .batchEdit: L("tools_batch")
        }
    }

    private func intro(_ tool: ToolKind) -> String {
        switch tool {
        case .resize: L("tools_resize_intro")
        case .convert: L("tools_convert_intro")
        case .removeLocation: L("tools_location_note")
        case .stitch: L("tools_stitch_note")
        case .gif: L("tools_gif_intro")
        case .batchEdit: L("tools_batch_intro")
        }
    }

    // MARK: Größe

    private var sizeSection: some View {
        Section {
            Picker(L("tools_size_header"), selection: $longEdge) {
                if kind == .convert { sizeOption(nil) }
                ForEach(BatchRules.longEdges, id: \.self) { edge in sizeOption(edge) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(key: "tools_size_header")
        } footer: {
            Text(key: "tools_size_note")
        }
    }

    private func sizeOption(_ edge: Int?) -> some View {
        ToolOptionRow(title: edge.map { pixels($0) } ?? L("tools_size_original"), hint: sizeHint(edge))
            .tag(edge)
    }

    private func pixels(_ value: Int) -> String {
        L("tools_px", value.formatted(.number.grouping(.never)))
    }

    private func sizeHint(_ edge: Int?) -> String? {
        guard let edge else { return L("tools_size_original_hint") }
        return switch edge {
        case 4096: L("tools_size_4096_hint")
        case 2048: L("tools_size_2048_hint")
        case 1080: L("tools_size_1080_hint")
        default: nil
        }
    }

    // MARK: Format und Qualität

    private var formatSection: some View {
        Section {
            Picker(L("tools_target_format"), selection: $format) {
                ToolOptionRow(title: "JPEG", hint: L("tools_fmt_jpeg_hint")).tag(EditFormat.jpeg)
                ToolOptionRow(title: "HEIC", hint: L("tools_fmt_heic_hint")).tag(EditFormat.heic)
                ToolOptionRow(title: "PNG", hint: L("tools_fmt_png_hint")).tag(EditFormat.png)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(key: "tools_target_format")
        } footer: {
            Text(key: "tools_convert_note")
        }
    }

    /// PNG speichert ohne Verlust – dort gibt es keine Qualitätsstufe.
    private var showsQuality: Bool {
        switch kind {
        case .resize, .batchEdit: true
        case .convert: format != .png
        default: false
        }
    }

    private var qualitySection: some View {
        Section {
            Picker(L("tools_quality"), selection: $quality) {
                ForEach(BatchRules.qualities, id: \.self) { value in Text(verbatim: qualityLabel(value)).tag(value) }
            }
        } footer: {
            Text(key: "tools_quality_note")
        }
    }

    private func qualityLabel(_ value: Int) -> String {
        let name = value >= 90 ? L("tools_q_high") : value >= 80 ? L("tools_q_balanced") : L("tools_q_small")
        return L("tools_quality_value", name, CountText.percent(Double(value) / 100))
    }

    // MARK: Belichtung (mehrere Fotos bearbeiten)

    private var exposureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack {
                    Text(key: "edit_adj_exposure")
                    Spacer(minLength: AppSpacing.xs)
                    Text(verbatim: signed(exposure)).monospacedDigit().foregroundStyle(AppColors.textSecondary)
                }
                Slider(value: $exposure, in: -100...100, step: 1) { Text(key: "edit_adj_exposure") }
            }
        } footer: {
            Text(key: "tools_exposure_note")
        }
    }

    private func signed(_ value: Float) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+" + rounded.formatted(.number) : rounded.formatted(.number)
    }

    // MARK: GIF

    private var gifSizeSection: some View {
        Section {
            Picker(L("tools_gif_size"), selection: $gifEdge) {
                ForEach(GifPlan.sizes, id: \.self) { edge in
                    ToolOptionRow(title: pixels(edge), hint: gifHint(edge)).tag(edge)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(key: "tools_gif_size")
        } footer: {
            Text(key: "tools_size_note")
        }
    }

    private func gifHint(_ edge: Int) -> String? {
        switch edge {
        case 480: L("tools_gif_480_hint")
        case 720: L("tools_gif_720_hint")
        default: nil
        }
    }

    private var gifTimingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack {
                    Text(key: "tools_gif_delay")
                    Spacer(minLength: AppSpacing.xs)
                    Text(verbatim: L("tools_seconds_value", gifDelay.formatted(.number.precision(.fractionLength(1)))))
                        .monospacedDigit().foregroundStyle(AppColors.textSecondary)
                }
                Slider(value: $gifDelay, in: 0.1...2, step: 0.1) { Text(key: "tools_gif_delay") }
            }
        } footer: {
            Text(key: "tools_gif_note")
        }
    }

    // MARK: Ergebnis

    private func resultSection(_ result: BatchSummary) -> some View {
        Section {
            Text(verbatim: LP("tools_done", result.done))
            if result.skipped > 0 { Text(verbatim: LP("tools_skipped", result.skipped)) }
            if result.failed > 0 { Text(verbatim: LP("tools_failed_n", result.failed)) }
            if result.beforeBytes > 0 {
                Text(verbatim: L("tools_sizes", SizeText.bytes(result.beforeBytes), SizeText.bytes(result.afterBytes)))
            }
            if result.unknownSizes > 0 { Text(verbatim: LP("tools_unknown", result.unknownSizes)) }
            if result.done > 0 {
                Text(key: "tools_originals_kept").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
        } header: {
            Text(key: "done")
        }
    }

    // MARK: Starten

    /// Hauptaktion fest über der Tableiste, mit Grund, solange sie nicht möglich ist.
    private var startBar: some View {
        VStack(spacing: AppSpacing.xs) {
            if let reason = blockedReason {
                Text(verbatim: reason)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            PrimaryButton(title: needsPro ? L("tools_pro_save") : L("tools_start"), symbol: needsPro ? "crown" : "play.fill") {
                Task { await run() }
            }
            .disabled(blockedReason != nil || busy)
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.vertical, AppSpacing.xs)
        .background(.bar)
    }

    private var needsPro: Bool { (kind == .gif || kind == .batchEdit) && !app.capabilities.hasProToolsAccess }

    private var blockedReason: String? {
        if ids.isEmpty { return L("tools_need_photos") }
        if (kind == .stitch || kind == .gif) && ids.count < 2 { return L("tools_need_two") }
        return nil
    }

    private var selectionLimit: Int {
        if kind == .gif { return GifPlan.maxFrames }
        return app.capabilities.batchLimit ?? 500
    }

    /// Screenshots und GIF-Bilder in der Reihenfolge der Aufnahme (ältestes zuerst), unabhängig von der Rasteransicht.
    private var chronological: [String] {
        Array(ids.prefix(selectionLimit)).sorted { a, b in
            (app.asset(a)?.creationDate ?? .distantFuture) < (app.asset(b)?.creationDate ?? .distantFuture)
        }
    }

    private func run() async {
        if needsPro { app.navigate(.pro); return }
        noWorkMessage = nil
        summary = nil
        busy = true
        defer { busy = false }
        do {
            if kind == .stitch {
                let sources = chronological
                let data = try await BatchProcessor.stitch(ids: sources)
                try await save(data, fileExtension: "jpg", editKind: .frame, sources: sources)
                app.showToast(L("tools_stitch_saved"))
                return
            }
            if kind == .gif {
                let sources = chronological
                let data = try await BatchProcessor.gif(ids: sources, maxEdge: gifEdge, delay: gifDelay)
                try await save(data, fileExtension: "gif", editKind: .gif, sources: sources)
                app.showToast(L("tools_gif_saved", SizeText.bytes(Int64(data.count))))
                return
            }
            let tool: BatchTool
            switch kind {
            case .convert: tool = .convert
            case .removeLocation: tool = .stripLocation
            default: tool = .resize
            }
            var options = BatchOptions(tool: tool)
            options.longEdge = kind == .removeLocation ? nil : longEdge
            // Standort entfernen ohne sichtbare Qualitätsstufe: höchste angebotene Stufe.
            options.quality = kind == .removeLocation ? (BatchRules.qualities.max() ?? quality) : quality
            options.format = format
            var recipe: EditRecipe?
            if kind == .batchEdit {
                var value = EditRecipe()
                value.adjust.exposure = exposure
                recipe = value
            }
            let selected = Array(ids.prefix(selectionLimit))
            let todo = kind == .batchEdit ? selected : selected.filter { needsWork($0, options) }
            if todo.isEmpty {
                var result = BatchSummary()
                result.skipped = selected.count
                summary = result
                // The result section may be far below the visible button. Explain
                // immediately that all images already meet the chosen settings.
                let hint = kind == .resize ? "\n" + L("tools_size_note") : ""
                noWorkMessage = LP("tools_skipped", selected.count) + hint
                return
            }
            var result = await BatchProcessor.process(app: app, ids: todo, options: options, recipe: recipe)
            result.skipped += selected.count - todo.count
            summary = result
            if result.done == 0 && result.failed == 0 {
                noWorkMessage = LP("tools_skipped", result.skipped)
            } else if result.failed > 0 {
                app.showError(LP("tools_failed_n", result.failed))
            } else {
                app.showToast(LP("tools_done", result.done))
            }
        } catch {
            app.showError(L("tools_failed"))
        }
    }

    /// Nichts zu tun → übersprungen statt sinnloser Kopie (wie Android): schon klein genug, schon im Zielformat,
    /// ohne Standort. Unbekanntes geht an die Verarbeitung, die es ehrlich zählt.
    private func needsWork(_ id: String, _ options: BatchOptions) -> Bool {
        guard let asset = app.asset(id), !asset.isVideo else { return true }
        let tooLarge = options.longEdge.map { max(asset.pixelWidth, asset.pixelHeight) > $0 } ?? false
        switch kind {
        case .resize: return tooLarge
        case .removeLocation: return asset.hasLocation
        case .convert:
            return tooLarge || BatchRules.needsWork(options, width: asset.pixelWidth, height: asset.pixelHeight,
                                                    uti: sourceUTI(id), hasLocation: asset.hasLocation)
        default: return true
        }
    }

    private func sourceUTI(_ id: String) -> String? {
        guard let asset = PhotoLibraryService.phAsset(id) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        return (resources.first { $0.type == .photo } ?? resources.first)?.uniformTypeIdentifier
    }

    private func save(_ data: Data, fileExtension: String, editKind: EditKind, sources: [String]) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(AppConfig.brandName + "." + fileExtension)
        try data.write(to: url, options: .atomic)
        let request = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: false, creationDate: Date(), latitude: nil,
                                                      longitude: nil, filename: url.lastPathComponent)
        guard case .saved(let newID) = await app.library.save(request) else { throw BatchProcessor.Failure.write }
        // Ergebnis erscheint unter „Gespeichert“; finish übernimmt auch das Behalten im Ledger.
        _ = await EditSaver.finish(app: app, original: nil, newID: newID, mode: .copy, video: false, kind: editKind,
                                   count: sources.count, sources: sources, bytes: Int64(data.count))
    }
}

/// Auswahlzeile mit Wert und kurzer Bedeutung (z. B. „2048 px“ · „Groß – scharf auf Handy und Tablet“).
private struct ToolOptionRow: View {
    let title: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
            if let hint {
                Text(verbatim: hint).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
