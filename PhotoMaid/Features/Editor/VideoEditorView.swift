import AVFoundation
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

/// Video-Editor (immer dunkel): Kürzen und Bereiche entfernen, Farbe, Filter, Text/Sticker mit Zeitfenster, Tempo, Ton,
/// Format. Vorschau = Export (eigener Compositor). Speichern nur als neue Datei, mit Pro. Tippen auf das Video =
/// Pause/Play – nie eine Entscheidung. Mediensteuerung wird in RTL nicht gespiegelt.
struct VideoEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: VideoEditorModel
    @State private var zoom: CGFloat = 1
    @State private var confirmDiscard = false
    @State private var saveSheet = false
    @State private var proSheet = false
    @State private var audioFile: ExportedFile?
    @State private var showAudioExporter = false
    @State private var dragLayer: Layer?
    @GestureState private var stageGestureActive = false
    @State private var askText = false
    @State private var text = ""
    /// Kurzer Hinweis im Tresor (z. B. Standbild gespeichert); die App-Pillen liegen unter dem Tresor.
    @State private var vaultNotice: String?

    /// `inVault`: `assetID` ist eine Kennung im Tresor; Quelle und Ergebnis bleiben im Tresor.
    init(assetID: String, inVault: Bool = false) {
        _model = State(initialValue: VideoEditorModel(assetID: assetID, inVault: inVault))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: AppSpacing.s) {
                header
                stage
                if model.loadState == .ready {
                    transport
                    toolZone
                }
            }
            ExportProgressOverlay(coordinator: ExportCoordinator.shared)
        }
        .preferredColorScheme(.dark)
        .task { await model.load(app: app) }
        .onDisappear { finishLayerDrag(); model.stop() }
        .onChange(of: stageGestureActive) { _, active in if !active { finishLayerDrag() } }
        .onChange(of: model.tool) { _, _ in finishLayerDrag() }
        .onChange(of: VaultStore.shared.phase) { _, phase in
            // Tresor gesperrt: Bearbeitung sofort schließen (die entschlüsselte Quelle wird gelöscht).
            if model.inVault && phase != .unlocked { dismiss() }
        }
        .overlay(alignment: .top) {
            if let vaultNotice {
                Text(verbatim: vaultNotice)
                    .font(AppTypography.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.m).padding(.vertical, AppSpacing.xs)
                    .glassCapsule()
                    .padding(.top, 64)
                    .transition(.opacity)
                    .task(id: vaultNotice) {
                        try? await Task.sleep(for: .seconds(2.5))
                        self.vaultNotice = nil
                    }
            }
        }
        .alert(L("vault_title"), isPresented: Binding(get: { model.vaultFailure != nil },
                                                      set: { if !$0 { model.vaultFailure = nil } })) {
            Button(L("ok")) { model.vaultFailure = nil }
        } message: {
            Text(verbatim: model.vaultFailure ?? "")
        }
        .confirmationDialog(L("edit_discard_title"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L("edit_discard"), role: .destructive) { dismiss() }
            Button(L("edit_keep_editing"), role: .cancel) {}
        } message: {
            Text(key: "edit_discard_text")
        }
        .sheet(isPresented: $saveSheet) { VideoSaveSheet(model: model) { dismiss() } }
        .sheet(isPresented: $proSheet) {
            VStack(spacing: AppSpacing.m) {
                Text(key: "edit_pro_title").font(AppTypography.headline)
                Text(key: "vid_pro_needed").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: L("pro_view"), symbol: "crown") {
                    proSheet = false
                    dismiss()
                    app.navigate(.pro)
                }
                SecondaryButton(title: L("edit_keep_editing")) { proSheet = false }
            }
            .padding(AppSpacing.pageMargin)
            .presentationDetents([.medium])
        }
        .fileExporter(isPresented: $showAudioExporter, document: audioFile, contentType: .mpeg4Audio,
                      defaultFilename: audioFile?.url.lastPathComponent) { result in
            if case .success = result, let name = audioFile?.url.lastPathComponent {
                app.showToast(L("vid_audio_saved", name))
            }
            if let dir = audioFile?.url.deletingLastPathComponent() { try? FileManager.default.removeItem(at: dir) }
            audioFile = nil
        }
        .alert(L("edit_mk_text"), isPresented: $askText) {
            TextField(L("edit_mk_text"), text: $text)
            Button(L("done")) {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                var layer = TextLayer(text: t)
                layer.color = MarkupStyle.shared.color
                model.addLayer(.text(layer))
            }
            Button(L("cancel"), role: .cancel) {}
        }
    }

    // MARK: Kopf

    private var header: some View {
        EditorHeader(cancel: {
            if model.hasChanges { confirmDiscard = true } else { dismiss() }
        }, confirm: {
            guard model.hasChanges else { dismiss(); return }
            if app.capabilities.hasProToolsAccess { saveSheet = true } else { proSheet = true }
        }, confirmEnabled: model.loadState == .ready && !model.saving && !ExportCoordinator.shared.isBusy) {
            HStack(spacing: AppSpacing.s) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo).accessibilityLabel(Text(key: "undo"))
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo).accessibilityLabel(Text(key: "redo"))
                Menu {
                    Button(L("edit_reset_all"), role: .destructive) { model.resetAll() }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel(Text(key: "more_actions"))
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(height: AppSpacing.touch)
            .padding(.horizontal, AppSpacing.m)
            .glassCapsule()
        }
    }

    // MARK: Bühne

    @ViewBuilder
    private var stage: some View {
        switch model.loadState {
        case .loading:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ErrorState(message: L("edit_err_load")).frame(maxHeight: .infinity)
        case .iCloud:
            VStack(spacing: AppSpacing.m) {
                Text(key: "feed_icloud_only").foregroundStyle(.white)
                Button(L("feed_icloud_load")) { Task { await model.load(app: app, allowNetwork: true) } }.buttonStyle(.pmProminent)
            }
            .frame(maxHeight: .infinity)
        case .ready:
            GeometryReader { geo in
                let rect = fitRect(model.frameAspect, in: geo.size)
                ZoomableStage(zoom: $zoom) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        stageContent
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        if model.tool == .text { layerOverlay(rect) }
                    }
                    .contentShape(.rect)
                    .gesture(stageGesture(rect), including: model.tool == .text ? .all : .subviews)
                }
                .onTapGesture { if model.tool != .text { model.togglePlay() } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(key: model.playing ? "pause" : "play"))
                .accessibilityHint(Text(key: "edit_stage_gestures"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.togglePlay() }
            }
            .padding(.horizontal, AppSpacing.xs)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        ZStack {
            Color.black
            if model.tool == .text, let poster = model.poster {
                Image(uiImage: poster).resizable().scaledToFit()
            } else {
                PlayerLayerView(player: model.player)
                if let scrub = model.scrubImage {
                    Image(uiImage: scrub).resizable().scaledToFit()
                }
            }
            if model.previewFailed {
                Text(key: "vid_preview_failed").font(AppTypography.footnote).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func fitRect(_ aspect: CGFloat, in box: CGSize) -> CGRect {
        guard aspect > 0, box.width > 0, box.height > 0 else { return .zero }
        let w = min(box.width, box.height * aspect), h = w / aspect
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    /// Texte/Sticker auf dem Standbild (gleicher `LayerRenderer` wie im Export), ausgewählter mit Rahmen.
    private func layerOverlay(_ rect: CGRect) -> some View {
        let visible = model.project.layers.filter { tl in
            tl.layer.id == model.selectedLayer || VideoPlan.layerAlpha(tl, outMs: model.outMs, fadeMs: 0) > 0
        }.map(\.layer)
        return LayerPreviewImage(layers: visible, size: rect.size)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .overlay(alignment: .topLeading) {
                if let id = model.selectedLayer, let l = model.project.layers.first(where: { $0.layer.id == id })?.layer,
                   let c = Self.center(l) {
                    Circle().strokeBorder(Color.yellow, lineWidth: 2).frame(width: 44, height: 44)
                        .position(x: rect.minX + CGFloat(c.x) * rect.width, y: rect.minY + CGFloat(c.y) * rect.height)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
    }

    private static func center(_ l: Layer) -> NormPoint? {
        switch l {
        case .text(let t): t.center
        case .sticker(let s): s.center
        default: nil
        }
    }

    /// Text/Sticker auswählen und verschieben (nur im Werkzeug „Markieren“; nie eine Entscheidung).
    private func stageGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($stageGestureActive) { _, active, _ in active = true }
            .onChanged { v in
                guard model.tool == .text, hypot(v.translation.width, v.translation.height) > 4 else { return }
                if dragLayer == nil {
                    let start = norm(v.startLocation, rect)
                    guard let l = hit(start) ?? model.project.layers.first(where: { $0.layer.id == model.selectedLayer })?.layer
                    else { return }
                    model.selectedLayer = l.id
                    dragLayer = l
                    model.beginChange()
                }
                if let base = dragLayer {
                    model.replaceLayer(base.moved(dx: Float(v.translation.width / max(1, rect.width)),
                                                  dy: Float(v.translation.height / max(1, rect.height))))
                }
            }
            .onEnded { v in
                guard model.tool == .text else { return }
                if dragLayer != nil {
                    finishLayerDrag()
                } else if hypot(v.translation.width, v.translation.height) < 6 {
                    model.selectedLayer = hit(norm(v.location, rect))?.id
                }
            }
    }

    private func finishLayerDrag() {
        guard dragLayer != nil else { return }
        dragLayer = nil
        model.endChange()
    }

    private func norm(_ p: CGPoint, _ rect: CGRect) -> NormPoint {
        NormPoint(Float((p.x - rect.minX) / max(1, rect.width)), Float((p.y - rect.minY) / max(1, rect.height)))
    }

    private func hit(_ p: NormPoint) -> Layer? {
        model.project.layers.reversed().map(\.layer)
            .compactMap { l -> (Layer, Double)? in
                guard let c = Self.center(l) else { return nil }
                return (l, hypot(Double(c.x - p.x), Double(c.y - p.y)))
            }
            .filter { $0.1 < 0.12 }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: Wiedergabe

    private var transport: some View {
        HStack(spacing: AppSpacing.s) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill").frame(width: AppSpacing.touch, height: AppSpacing.touch)
            }
            .disabled(model.tool == .text)
            .accessibilityLabel(Text(key: model.playing ? "pause" : "play"))
            Text(verbatim: "\(DateText.duration(Double(model.outMs) / 1000)) / \(DateText.duration(Double(model.outputDurationMs) / 1000))")
                .font(AppTypography.footnote.weight(.semibold).monospacedDigit())
            Spacer()
            Button { model.previewMuted.toggle() } label: {
                Image(systemName: model.previewMuted ? "speaker.slash" : "speaker.wave.2")
                    .frame(width: AppSpacing.touch, height: AppSpacing.touch)
            }
            .accessibilityLabel(Text(key: model.previewMuted ? "unmute" : "mute"))
            Button { Task { await saveFrame() } } label: {
                Image(systemName: "camera").frame(width: AppSpacing.touch, height: AppSpacing.touch)
            }
            .accessibilityLabel(Text(key: "vid_frame"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.pageMargin)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func saveFrame() async {
        guard app.capabilities.hasProToolsAccess else { proSheet = true; return }
        guard let av = model.avAsset, let info = model.info, !model.saving else { return }
        model.saving = true
        defer { model.saving = false }
        if model.inVault {
            do {
                _ = try await VaultEditSaver.saveFrame(itemID: model.assetID, sourceName: model.sourceName, avAsset: av,
                                                       info: info, project: model.project, sourceMs: model.playheadSourceMs,
                                                       unlimited: app.capabilities.hasProToolsAccess)
                Haptics.success()
                vaultNotice = L("vault_edit_frame_saved")
            } catch {
                model.vaultFailure = VaultEditSaver.message(for: error)
            }
            return
        }
        do {
            try await VideoSaver.saveFrame(app: app, assetID: model.assetID, avAsset: av, info: info, project: model.project,
                                           sourceMs: model.playheadSourceMs)
            Haptics.success()
            app.showToast(L("vid_frame_saved"))
        } catch {
            app.showError(L("edit_err_save"))
        }
    }

    // MARK: Werkzeugzone

    private var toolZone: some View {
        VStack(spacing: AppSpacing.s) {
            Group {
                switch model.tool {
                case .trim: VideoTrimPanel(model: model)
                case .adjust: VideoAdjustPanel(model: model)
                case .filter: VideoFilterPanel(model: model)
                case .text: VideoLayerPanel(model: model) { text = L("edit_text_default"); askText = true }
                case .speed: VideoSpeedPanel(model: model)
                // Ton als Datei verlässt den Tresor – dort nicht angeboten.
                case .audio: VideoAudioPanel(model: model, exportAudio: model.inVault ? nil : { Task { await exportAudio() } })
                case .format: VideoFormatPanel(model: model)
                }
            }
            .frame(minHeight: 120)
            if !app.capabilities.hasProToolsAccess {
                Text(key: "edit_pro_hint").font(AppTypography.caption).foregroundStyle(.yellow)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(VideoTool.allCases) { t in
                            Button { model.tool = t } label: {
                                Label(L(t.titleKey), systemImage: t.symbol)
                                    .font(AppTypography.footnote.weight(.semibold))
                                    .padding(.horizontal, AppSpacing.s)
                                    .frame(minHeight: AppSpacing.minTouch)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(model.tool == t ? .black : .white)
                            .background(model.tool == t ? Color.white : Color.white.opacity(0.1), in: .capsule)
                            .accessibilityAddTraits(model.tool == t ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
            }
        }
        .padding(.bottom, AppSpacing.xs)
    }

    private func exportAudio() async {
        guard app.capabilities.hasProToolsAccess else { proSheet = true; return }
        guard let av = model.avAsset, let info = model.info else { return }
        do {
            let url = try await VideoSaver.exportAudio(app: app, assetID: model.assetID, avAsset: av, info: info,
                                                       project: model.project)
            audioFile = ExportedFile(url: url)
            showAudioExporter = true
        } catch is CancellationError {
            app.showToast(L("export_cancelled"))
        } catch ExportCoordinator.Failure.expired {
            app.showError(L("export_expired"))
        } catch {
            app.showError(L("vid_audio_failed"))
        }
    }
}

/// Ebenen als Bild (derselbe `LayerRenderer` wie im Export).
private struct LayerPreviewImage: View {
    let layers: [Layer]
    let size: CGSize

    var body: some View {
        if let img = render() { Image(uiImage: img).resizable() } else { Color.clear }
    }

    private func render() -> UIImage? {
        guard !layers.isEmpty, size.width >= 2, size.height >= 2 else { return nil }
        let scale: CGFloat = 2
        let px = PxSize(Int(size.width * scale), Int(size.height * scale))
        let out = LayerRenderer.draw(layers, over: CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: px.width, height: px.height)),
                                     size: px)
        return EditRenderer.shared.cgImage(out).map { UIImage(cgImage: $0) }
    }
}

// MARK: - Kürzen & Schneiden

/// Zeitleiste in Quellzeit: Griffe für Anfang/Ende, entfernte Bereiche rot, „Bereich entfernen“ mit eigenen Griffen.
struct VideoTrimPanel: View {
    @Bindable var model: VideoEditorModel
    @State private var active: Int?
    @State private var startRange: TimeRange?
    @State private var moved = false

    var body: some View {
        let c = model.clip
        VStack(spacing: AppSpacing.s) {
            Text(verbatim: L("edit_trim_range", DateText.duration(Double(c.trimStartMs) / 1000), DateText.duration(Double(c.trimEndMs) / 1000),
                             (Double(c.outputDurationMs) / 1000).formatted(.number.precision(.fractionLength(1)))))
                .font(AppTypography.headline).foregroundStyle(.white)
            timeline
                .frame(height: 64)
                .padding(.horizontal, AppSpacing.pageMargin)
            if let d = model.cutDraft {
                Text(verbatim: L("vid_cut_draft", DateText.duration(Double(d.startMs) / 1000), DateText.duration(Double(d.endMs) / 1000)))
                    .font(AppTypography.subheadline).foregroundStyle(.white)
                HStack(spacing: AppSpacing.s) {
                    Button(L("vid_cut_confirm"), systemImage: "scissors") {
                        if !model.confirmCut() { model.cutDraft = nil }
                    }
                    .buttonStyle(.pmProminent).tint(.red)
                    Button(L("cancel")) { model.cutDraft = nil }.buttonStyle(.pmBordered)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        Button(L("vid_cut_start"), systemImage: "scissors") { model.startCut() }.buttonStyle(.pmBordered)
                        ForEach(c.cuts.indices, id: \.self) { i in
                            let cut = c.cuts[i]
                            Button {
                                model.removeCut(i)
                            } label: {
                                Label("\(DateText.duration(Double(cut.startMs) / 1000))–\(DateText.duration(Double(cut.endMs) / 1000))",
                                      systemImage: "xmark")
                            }
                            .buttonStyle(.pmBordered)
                        }
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                Text(verbatim: c.cuts.isEmpty ? L("vid_trim_hint_short")
                     : L("vid_cut_hint_restore", DateText.duration(Double(c.outputDurationMs) / 1000)))
                    .font(AppTypography.footnote).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center).padding(.horizontal, AppSpacing.pageMargin)
            }
        }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let total = max(1, model.durationMs)
            let handle: CGFloat = 16
            let track = max(1, geo.size.width - 2 * handle)
            let h = geo.size.height
            let c = model.clip
            let x = { (ms: Int64) -> CGFloat in handle + track * CGFloat(ms) / CGFloat(total) }
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(model.thumbnails.indices, id: \.self) { i in
                        Image(uiImage: model.thumbnails[i]).resizable().scaledToFill().frame(width: track / CGFloat(max(1, model.thumbnails.count)), height: h - 8)
                            .clipped()
                    }
                }
                .frame(width: track, height: h - 8)
                .background(Color.white.opacity(0.08))
                .clipShape(.rect(cornerRadius: 6))
                .offset(x: handle, y: 4)
                Canvas { ctx, size in
                    let sx = x(c.trimStartMs), ex = x(c.trimEndMs)
                    ctx.fill(Path(CGRect(x: handle, y: 4, width: max(0, sx - handle), height: size.height - 8)), with: .color(.black.opacity(0.55)))
                    ctx.fill(Path(CGRect(x: ex, y: 4, width: max(0, size.width - handle - ex), height: size.height - 8)), with: .color(.black.opacity(0.55)))
                    for cut in c.cuts {
                        let a = x(cut.startMs), b = x(cut.endMs)
                        ctx.fill(Path(CGRect(x: a, y: 4, width: b - a, height: size.height - 8)), with: .color(.red.opacity(0.55)))
                    }
                    ctx.stroke(Path(roundedRect: CGRect(x: sx, y: 1, width: ex - sx, height: size.height - 2), cornerRadius: 6),
                               with: .color(.yellow), lineWidth: 3)
                    ctx.fill(Path(roundedRect: CGRect(x: sx - handle, y: 0, width: handle, height: size.height), cornerRadius: 5), with: .color(.yellow))
                    ctx.fill(Path(roundedRect: CGRect(x: ex, y: 0, width: handle, height: size.height), cornerRadius: 5), with: .color(.yellow))
                    for hx in [sx - handle / 2, ex + handle / 2] {
                        ctx.stroke(Path { p in p.move(to: CGPoint(x: hx, y: size.height * 0.35)); p.addLine(to: CGPoint(x: hx, y: size.height * 0.65)) },
                                   with: .color(.black), lineWidth: 2)
                    }
                    if let d = model.cutDraft {
                        let a = x(d.startMs), b = x(d.endMs)
                        ctx.fill(Path(CGRect(x: a, y: 0, width: b - a, height: size.height)), with: .color(.red.opacity(0.35)))
                        ctx.stroke(Path(CGRect(x: a, y: 0, width: b - a, height: size.height)), with: .color(.red), lineWidth: 2)
                        for px in [a, b] {
                            ctx.fill(Path(roundedRect: CGRect(x: px - 5, y: size.height * 0.2, width: 10, height: size.height * 0.6), cornerRadius: 4),
                                     with: .color(.red))
                        }
                    }
                    let ph = model.playheadSourceMs
                    if ph >= c.trimStartMs && ph <= c.trimEndMs {
                        ctx.fill(Path(CGRect(x: x(ph) - 1, y: 2, width: 2, height: size.height - 4)), with: .color(.white))
                    }
                }
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in drag(v, x: x, track: track, total: total) }
                .onEnded { v in end(v, handle: handle, track: track, total: total) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(key: "edit_trim_start"))
            .accessibilityValue(Text(verbatim: DateText.duration(Double(c.trimStartMs) / 1000)))
            .accessibilityAdjustableAction { dir in
                let step: Int64 = dir == .increment ? 1000 : -1000
                model.checkpoint()
                model.setTrim(start: c.trimStartMs + step, end: c.trimEndMs)
                model.schedulePreview()
            }
            .overlay(alignment: .topTrailing) {
                // VoiceOver: Ende getrennt einstellbar.
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(Text(key: "edit_trim_end"))
                    .accessibilityValue(Text(verbatim: DateText.duration(Double(c.trimEndMs) / 1000)))
                    .accessibilityAdjustableAction { dir in
                        let step: Int64 = dir == .increment ? 1000 : -1000
                        model.checkpoint()
                        model.setTrim(start: c.trimStartMs, end: c.trimEndMs + step)
                        model.schedulePreview()
                    }
            }
        }
    }

    private func drag(_ v: DragGesture.Value, x: (Int64) -> CGFloat, track: CGFloat, total: Int64) {
        let c = model.clip
        if active == nil {
            let px = v.startLocation.x
            if let d = model.cutDraft {
                active = abs(px - x(d.startMs)) <= abs(px - x(d.endMs)) ? 3 : 4
                startRange = d
            } else {
                active = abs(px - x(c.trimStartMs)) <= abs(px - x(c.trimEndMs)) ? 1 : 2
                startRange = TimeRange(startMs: c.trimStartMs, endMs: c.trimEndMs)
                model.beginChange()
            }
            moved = false
        }
        guard abs(v.translation.width) > 2 || moved, let base = startRange, let a = active else { return }
        moved = true
        let dms = Int64((v.translation.width / track * CGFloat(total)).rounded())
        switch a {
        case 1: model.setTrim(start: base.startMs + dms, end: base.endMs); model.scrub(sourceMs: model.clip.trimStartMs)
        case 2: model.setTrim(start: base.startMs, end: base.endMs + dms); model.scrub(sourceMs: model.clip.trimEndMs)
        case 3: model.moveCutDraft(start: base.startMs + dms, end: base.endMs); model.scrub(sourceMs: model.cutDraft?.startMs ?? 0)
        default: model.moveCutDraft(start: base.startMs, end: base.endMs + dms); model.scrub(sourceMs: model.cutDraft?.endMs ?? 0)
        }
    }

    private func end(_ v: DragGesture.Value, handle: CGFloat, track: CGFloat, total: Int64) {
        defer { active = nil; startRange = nil; moved = false }
        let c = model.clip
        if !moved {
            if active == 1 || active == 2 { model.endChange() }
            let ms = Int64(((v.location.x - handle) / track * CGFloat(total)).rounded())
            model.endScrub(seekSourceMs: min(max(ms, c.trimStartMs), c.trimEndMs))
            return
        }
        switch active {
        case 1: model.endChange(); model.endScrub(seekSourceMs: c.trimStartMs)
        case 2: model.endChange(); model.endScrub(seekSourceMs: max(c.trimStartMs, c.trimEndMs - 300))
        default: model.endScrub(seekSourceMs: nil)
        }
    }
}

// MARK: - Farbe & Filter

struct VideoAdjustPanel: View {
    @Bindable var model: VideoEditorModel
    @State private var mix = false
    @State private var band: ColorBand = .red
    private let params = AdjustParam.allCases.filter { $0.group == "edit_grp_light" || $0.group == "edit_grp_color" }

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            if mix {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(ColorBand.allCases, id: \.self) { b in
                            Button { band = b } label: {
                                Circle().fill(Color(hue: Double(b.centerDeg) / 360, saturation: 0.85, brightness: 0.95))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: band == b ? 3 : 0))
                                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(key: "edit_band_\(b.rawValue.lowercased())"))
                        }
                        Button(L("done")) { mix = false }.foregroundStyle(.yellow).padding(.leading, AppSpacing.s)
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                mixRuler(L("edit_mix_hue"), \.hue)
                mixRuler(L("edit_mix_saturation"), \.saturation)
                mixRuler(L("edit_mix_luminance"), \.luminance)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(params) { p in
                            RoundToolButton(symbol: p.symbol, title: L(p.titleKey), active: model.param == p,
                                            changed: abs(model.clip.adjust[keyPath: p.keyPath]) >= 0.5) { model.param = p }
                        }
                        RoundToolButton(symbol: "swatchpalette", title: L("edit_grp_mix"), changed: !model.clip.colorMix.isNeutral) { mix = true }
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                EditorRuler(title: L(model.param.titleKey),
                            value: Binding(get: { model.clip.adjust[keyPath: model.param.keyPath] },
                                           set: { v in model.project.updateClip(0) { $0.adjust[keyPath: model.param.keyPath] = v } }),
                            range: model.param.range, onBegin: model.beginChange, onEnd: model.endChange)
                    .padding(.horizontal, AppSpacing.pageMargin)
            }
        }
    }

    private func mixRuler(_ title: String, _ kp: WritableKeyPath<HslShift, Float>) -> some View {
        EditorRuler(title: title, value: Binding(get: { model.clip.colorMix[band][keyPath: kp] }, set: { v in
            var s = model.clip.colorMix[band]
            s[keyPath: kp] = v
            let next = model.clip.colorMix.with(band, s)
            model.project.updateClip(0) { $0.colorMix = next }
        }), range: -100...100, onBegin: model.beginChange, onEnd: model.endChange)
        .padding(.horizontal, AppSpacing.pageMargin)
    }
}

struct VideoFilterPanel: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.s) {
                    ForEach(FilterId.allCases, id: \.self) { f in
                        Button {
                            model.updateClip { $0.filter = f; if f != .none && $0.filterIntensity <= 0.01 { $0.filterIntensity = 1 } }
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    if let t = model.filterThumbs[f] { Image(uiImage: t).resizable().scaledToFill() } else { Color.white.opacity(0.1) }
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow, lineWidth: model.clip.filter == f ? 2 : 0))
                                Text(verbatim: FilterNames.name(f)).font(.caption2).foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.clip.filter == f ? .isSelected : [])
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
            }
            if model.clip.filter != .none {
                EditorRuler(title: L("edit_filter_strength"),
                            value: Binding(get: { model.clip.filterIntensity * 100 },
                                           set: { v in model.project.updateClip(0) { $0.filterIntensity = v / 100 } }),
                            range: 0...100, onBegin: model.beginChange, onEnd: model.endChange)
                    .padding(.horizontal, AppSpacing.pageMargin)
            }
        }
    }
}

enum FilterNames {
    static func name(_ f: FilterId) -> String {
        switch f {
        case .none: L("edit_filter_none")
        case .mono: L("edit_filter_mono")
        case .monoContrast: L("edit_filter_mono_contrast")
        case .warm: L("edit_filter_warm")
        case .cool: L("edit_filter_cool")
        case .sepia: L("edit_filter_sepia")
        case .fade: L("edit_filter_fade")
        case .vivid: L("edit_filter_vivid")
        }
    }
}

// MARK: - Text & Sticker

struct VideoLayerPanel: View {
    @Bindable var model: VideoEditorModel
    let addText: () -> Void
    @State private var askEmoji = false
    @State private var emoji = "😀"
    private let palette: [ARGB] = [0xFFFF_FFFF, 0xFF00_0000, 0xFFFF_3B30, 0xFFFF_9500, 0xFFFF_CC00, 0xFF34_C759, 0xFF00_7AFF, 0xFFAF_52DE]

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.xs) {
                RoundToolButton(symbol: "textformat", title: L("edit_mk_text"), action: addText)
                Menu {
                    ForEach(StickerKind.allCases, id: \.self) { k in
                        Button(StickerNames.name(k)) { addSticker(k) }
                    }
                } label: {
                    RoundToolButton(symbol: "face.smiling", title: L("edit_mk_sticker")) {}.allowsHitTesting(false)
                }
                if model.selectedLayer != nil {
                    RoundToolButton(symbol: "minus.magnifyingglass", title: L("edit_mk_smaller")) { resize(0.85) }
                    RoundToolButton(symbol: "plus.magnifyingglass", title: L("edit_mk_larger")) { resize(1.18) }
                    RoundToolButton(symbol: "trash", title: L("edit_mk_delete")) { model.removeSelectedLayer() }
                }
            }
            HStack(spacing: 6) {
                ForEach(palette, id: \.self) { c in
                    Button {
                        MarkupStyle.shared.color = c
                        recolor(c)
                    } label: {
                        Circle().fill(Color(uiColor: LayerRenderer.color(c))).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                            .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(key: "edit_mk_color"))
                }
            }
            if let id = model.selectedLayer, let tl = model.project.layers.first(where: { $0.layer.id == id }) {
                timeWindow(tl)
            } else {
                Text(key: "edit_mk_hint_ios").font(AppTypography.caption).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center).padding(.horizontal, AppSpacing.pageMargin)
            }
        }
        .alert(L("edit_mk_emoji"), isPresented: $askEmoji) {
            TextField(L("edit_mk_emoji"), text: $emoji)
            Button(L("done")) {
                var s = StickerLayer(kind: .emoji, value: String(emoji.prefix(2)))
                s.size = 0.18
                model.addLayer(.sticker(s))
            }
            Button(L("cancel"), role: .cancel) {}
        }
    }

    /// Zeitfenster im Ergebnis (Anfang/Ende), weich ein- und ausgeblendet wie im Export.
    private func timeWindow(_ tl: TimedLayer) -> some View {
        let total = Double(max(1, model.outputDurationMs))
        let end = tl.endMs == .max ? Int64(total) : tl.endMs
        return VStack(spacing: 2) {
            Text(verbatim: L("vid_layer_time", DateText.duration(Double(tl.startMs) / 1000), DateText.duration(Double(end) / 1000)))
                .font(AppTypography.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            HStack {
                Text(key: "edit_trim_start").font(.caption2).frame(width: 56, alignment: .leading)
                Slider(value: Binding(get: { Double(tl.startMs) }, set: { model.setLayerTime(start: Int64($0), end: end) }),
                       in: 0...total, onEditingChanged: { editing in editing ? model.beginChange() : model.endChange() })
            }
            HStack {
                Text(key: "edit_trim_end").font(.caption2).frame(width: 56, alignment: .leading)
                Slider(value: Binding(get: { Double(end) }, set: { model.setLayerTime(start: tl.startMs, end: Int64($0)) }),
                       in: 0...total, onEditingChanged: { editing in editing ? model.beginChange() : model.endChange() })
            }
        }
        .tint(.yellow)
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.pageMargin)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func addSticker(_ k: StickerKind) {
        if k == .emoji { emoji = "😀"; askEmoji = true; return }
        var s = StickerLayer(kind: k, value: k == .date ? Date().formatted(date: .numeric, time: .omitted) : "")
        s.color = MarkupStyle.shared.color
        model.addLayer(.sticker(s))
    }

    private func selected() -> Layer? {
        guard let id = model.selectedLayer else { return nil }
        return model.project.layers.first { $0.layer.id == id }?.layer
    }

    private func recolor(_ c: ARGB) {
        guard let l = selected() else { return }
        model.checkpoint()
        switch l {
        case .text(var t): t.color = c; model.replaceLayer(.text(t))
        case .sticker(var s): s.color = c; model.replaceLayer(.sticker(s))
        default: break
        }
    }

    private func resize(_ f: Float) {
        guard let l = selected() else { return }
        model.checkpoint()
        switch l {
        case .text(var t): t.size = min(0.4, max(0.02, t.size * f)); model.replaceLayer(.text(t))
        case .sticker(var s): s.size = min(0.8, max(0.04, s.size * f)); model.replaceLayer(.sticker(s))
        default: break
        }
    }
}

enum StickerNames {
    static func name(_ k: StickerKind) -> String {
        switch k {
        case .emoji: L("edit_mk_emoji")
        case .arrow: L("edit_st_arrow")
        case .heart: L("edit_st_heart")
        case .star: L("edit_st_star")
        case .check: L("edit_st_check")
        case .cross: L("edit_st_cross")
        case .bubble: L("edit_st_bubble")
        case .circle: L("edit_st_circle")
        case .sparkle: L("edit_st_sparkle")
        case .date: L("edit_st_date")
        }
    }
}

// MARK: - Tempo, Ton, Format

struct VideoSpeedPanel: View {
    @Bindable var model: VideoEditorModel
    private let speeds: [Float] = [0.5, 1, 1.5, 2, 0.25, 4]

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(speeds, id: \.self) { s in
                        editorChip(s.formatted(.number.precision(.fractionLength(0...2))) + "×", selected: model.clip.speed == s) {
                            model.updateClip { $0.speed = s }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
            }
            Text(verbatim: L("vid_speed_result", DateText.duration(Double(model.outputDurationMs) / 1000)))
                .font(AppTypography.subheadline).foregroundStyle(.white)
            Text(key: "vid_speed_hint").font(AppTypography.footnote).foregroundStyle(.white.opacity(0.75))
        }
    }
}

struct VideoAudioPanel: View {
    @Bindable var model: VideoEditorModel
    let exportAudio: (() -> Void)?
    private let fades: [Int64] = [0, 500, 1000, 2000]

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            if model.info?.hasAudio == false {
                Text(key: "vid_no_audio").font(AppTypography.subheadline).foregroundStyle(.white.opacity(0.8))
            } else {
                Toggle(isOn: Binding(get: { model.project.removeAudio }, set: { v in model.update { $0.removeAudio = v } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key: "vid_remove_audio")
                        Text(key: "vid_remove_audio_text").font(AppTypography.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .tint(.yellow)
                .padding(.horizontal, AppSpacing.pageMargin)
                if !model.project.removeAudio {
                    EditorRuler(title: L("vid_volume"),
                                value: Binding(get: { model.clip.volume * 100 },
                                               set: { v in model.project.updateClip(0) { $0.volume = (v / 5).rounded() * 5 / 100 } }),
                                range: 0...200, onBegin: model.beginChange, onEnd: model.endChange)
                        .padding(.horizontal, AppSpacing.pageMargin)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(key: "vid_fade").font(AppTypography.footnote.weight(.semibold))
                            ForEach(fades, id: \.self) { ms in
                                editorChip(ms == 0 ? L("vid_fade_none") : (Double(ms) / 1000).formatted(.number.precision(.fractionLength(0...1))) + " s",
                                     selected: model.clip.fadeInMs == ms && model.clip.fadeOutMs == ms) {
                                    model.updateClip { $0.fadeInMs = ms; $0.fadeOutMs = ms }
                                }
                            }
                            if let exportAudio {
                                Button(L("vid_audio_export"), systemImage: "music.note", action: exportAudio).buttonStyle(.pmBordered)
                            }
                        }
                        .padding(.horizontal, AppSpacing.pageMargin)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

struct VideoFormatPanel: View {
    @Bindable var model: VideoEditorModel
    private let aspects: [Float?] = [nil, 1, 0.8, 0.5625, 1.7778]

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(aspects.indices, id: \.self) { i in
                        let a = aspects[i]
                        editorChip(label(a), selected: same(model.project.aspect, a)) { model.update { $0.aspect = a } }
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
            }
            if model.project.aspect != nil {
                HStack(spacing: AppSpacing.xs) {
                    editorChip(L("vid_fill"), selected: model.project.fill) { model.update { $0.fill = true } }
                    editorChip(L("vid_fit"), selected: !model.project.fill) { model.update { $0.fill = false } }
                }
                Text(key: model.project.fill ? "vid_fill_hint" : "vid_fit_hint").font(AppTypography.footnote)
                    .foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            }
            HStack(spacing: AppSpacing.s) {
                RoundToolButton(symbol: "rotate.right", title: L("edit_rotate")) {
                    model.updateClip { $0.quarterTurns = ((($0.quarterTurns + 1) % 4) + 4) % 4; $0.crop = $0.crop.rotatedClockwise() }
                }
                RoundToolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: L("edit_flip_h"),
                                active: model.clip.flipH) { model.updateClip { $0.flipH.toggle() } }
                RoundToolButton(symbol: "arrow.counterclockwise", title: L("edit_reset")) {
                    model.update {
                        $0.aspect = nil
                        $0.fill = false
                        $0.updateClip(0) { c in c.quarterTurns = 0; c.flipH = false; c.crop = .full }
                    }
                }
            }
            if let l = model.layout {
                Text(verbatim: "\(l.output.width) × \(l.output.height)").font(AppTypography.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func label(_ a: Float?) -> String {
        guard let a else { return L("edit_aspect_original") }
        switch a {
        case 1: return "1:1"
        case 0.8: return "4:5"
        case 0.5625: return "9:16"
        default: return "16:9"
        }
    }

    private func same(_ a: Float?, _ b: Float?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (let x?, let y?): abs(x - y) < 0.005
        default: false
        }
    }
}

/// Auswahlchip im Editor (dunkel, gelb ausgewählt).
@MainActor
func editorChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(verbatim: title)
            .font(AppTypography.footnote.weight(.semibold))
            .padding(.horizontal, AppSpacing.s)
            .frame(minHeight: AppSpacing.minTouch)
            .foregroundStyle(selected ? .black : .white)
            .background(selected ? Color.yellow : Color.white.opacity(0.12), in: .capsule)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
}

// MARK: - Speichern

/// Speichern-Blatt: Qualität mit „ca.“-Schätzung, Kopie (Vorauswahl) oder Ersetzen, ehrlicher Hinweis zum Weg.
struct VideoSaveSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VideoEditorModel
    let finished: () -> Void
    @State private var mode: SaveMode = .copy

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ExportProfile.allCases, id: \.self) { p in
                        Button { model.update { $0.profile = p } } label: {
                            HStack {
                                Image(systemName: model.project.profile == p ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(AppColors.accent)
                                Text(verbatim: L(profileKey(p))).foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if let est = model.estimate(p) {
                                    Text(verbatim: L("vid_estimate", SizeText.bytes(est))).font(AppTypography.footnote)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                        .accessibilityAddTraits(model.project.profile == p ? .isSelected : [])
                    }
                } header: {
                    Text(key: "vid_profile")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key: "vid_estimate_hint")
                        Text(verbatim: L(model.isTrimOnly ? "vid_export_info_fast" : "vid_export_info_reencode",
                                         DateText.duration(Double(model.outputDurationMs) / 1000)))
                        if model.hdrWillConvert { Text(key: "vid_hdr_hint_ios") }
                    }
                }
                if model.inVault {
                    Section {
                        option(.copy, L("vault_edit_copy"), L("edit_save_copy_text"))
                        option(.replace, L("vault_edit_replace"), L("vault_edit_replace_text"))
                    } footer: {
                        Text(key: "vault_edit_private_note")
                    }
                } else {
                    Section {
                        option(.copy, L("edit_save_copy"), L("edit_save_copy_text"))
                        option(.replace, L("edit_save_replace"), L("edit_save_replace_text"))
                    }
                }
            }
            .navigationTitle(L("edit_save_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(mode == .replace ? (model.inVault ? "vault_edit_replace_action" : "edit_save_replace_action")
                             : "edit_save_copy_action")) {
                        dismiss()
                        Task { await save() }
                    }
                    .accessibilityIdentifier("editor.save.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func profileKey(_ p: ExportProfile) -> String {
        switch p {
        case .high: "vid_profile_high"
        case .balanced: "vid_profile_balanced"
        case .small: "vid_profile_small"
        }
    }

    private func option(_ m: SaveMode, _ title: String, _ text: String) -> some View {
        Button { mode = m } label: {
            HStack(alignment: .top) {
                Image(systemName: mode == m ? "largecircle.fill.circle" : "circle").foregroundStyle(AppColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: text).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    private func save() async {
        guard let av = model.avAsset, let info = model.info else { return }
        model.saving = true
        defer { model.saving = false }
        if model.inVault {
            do {
                let result = try await VaultEditSaver.saveVideo(itemID: model.assetID, sourceName: model.sourceName,
                                                                avAsset: av, info: info, project: model.project, mode: mode,
                                                                unlimited: app.capabilities.hasProToolsAccess)
                VaultStore.shared.lastEdit = result
                Haptics.success()
                finished()
            } catch {
                model.vaultFailure = VaultEditSaver.message(for: error)
            }
            return
        }
        do {
            let outcome = try await VideoSaver.save(app: app, assetID: model.assetID, avAsset: av, info: info,
                                                    project: model.project, mode: mode)
            Haptics.success()
            switch outcome {
            case .copy(_, let bytes): app.showToast(bytes.map { L("edit_done_copy_size", SizeText.bytes($0)) } ?? L("edit_done_copy"))
            case .replaced: app.showToast(L("edit_done_replaced"))
            case .replaceDeclined: app.showToast(L("edit_done_declined"))
            case .editedOriginal: app.showToast(L("edit_done_original"))
            }
            finished()
        } catch is CancellationError {
            app.showToast(L("export_cancelled"))
        } catch ExportCoordinator.Failure.expired {
            app.showError(L("export_expired"))
        } catch ExportCoordinator.Failure.busy {
            app.showError(L("export_busy"))
        } catch EditSaveError.gone {
            app.showError(L("edit_err_gone"))
        } catch {
            app.showError(L("edit_err_save"))
        }
    }
}
