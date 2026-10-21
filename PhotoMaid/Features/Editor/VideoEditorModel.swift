import AVFoundation
import Observation
import PhotoMaidCore
import UIKit

enum VideoTool: String, CaseIterable, Identifiable, Hashable {
    case trim, adjust, filter, text, speed, audio, format
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .trim: "edit_tab_trim"
        case .adjust: "edit_tab_adjust"
        case .filter: "edit_tab_filter"
        case .text: "edit_tab_markup"
        case .speed: "vid_tab_speed"
        case .audio: "vid_tab_audio"
        case .format: "vid_tab_format"
        }
    }

    var symbol: String {
        switch self {
        case .trim: "scissors"
        case .adjust: "slider.horizontal.3"
        case .filter: "camera.filters"
        case .text: "textformat"
        case .speed: "speedometer"
        case .audio: "speaker.wave.2"
        case .format: "aspectratio"
        }
    }
}

/// Zustand des Video-Editors: ein Projekt mit einem Clip (nicht destruktiv, Rückgängig/Wiederholen). Die Vorschau
/// spielt dieselbe Komposition wie der Export (eigener Compositor) in kleiner Auflösung; Farbe wirkt sofort, Schnitte,
/// Tempo, Ton und Format bauen die Vorschau neu auf. Tippen auf das Video = Pause/Play, nie eine Entscheidung.
@MainActor
@Observable
final class VideoEditorModel {
    enum LoadState: Equatable { case loading, ready, failed, iCloud }

    let assetID: String
    /// Bearbeitung im Tresor: `assetID` ist dann die Kennung im Tresor; Quelle und Ergebnis bleiben im Tresor.
    let inVault: Bool
    /// Dateiname des Originals im Tresor (für den Namen der Kopie).
    private(set) var sourceName: String?
    /// Fehler beim Speichern im Tresor (der Editor zeigt ihn selbst – die App-Pillen liegen unter dem Tresor).
    var vaultFailure: String?
    private(set) var loadState: LoadState = .loading
    private(set) var asset: MediaAsset?
    private(set) var avAsset: AVAsset?
    private(set) var info: VideoInfo?
    private(set) var initial: VideoProject?
    var project = VideoProject(id: "pending", clips: [MoviePlan.videoClip(id: "c0", mediaId: "", durationMs: 1000)]) {
        didSet { projectChanged(oldValue) }
    }
    var tool: VideoTool = .trim { didSet { if tool != oldValue { toolChanged() } } }
    var param: AdjustParam = .exposure
    let player = AVPlayer()
    private(set) var playing = false
    private(set) var outMs: Int64 = 0
    var previewMuted = true { didSet { player.isMuted = previewMuted } }
    var cutDraft: TimeRange?
    /// Bild an der Griffposition beim Ziehen (statt Neuaufbau bei jedem Schritt).
    private(set) var scrubImage: UIImage?
    private(set) var thumbnails: [UIImage] = []
    /// Ergebnisbild ohne Ebenen an der aktuellen Stelle (Werkzeug „Markieren“).
    private(set) var poster: UIImage?
    private(set) var filterThumbs: [FilterId: UIImage] = [:]
    private(set) var previewFailed = false
    var selectedLayer: String?
    var saving = false

    @ObservationIgnored private var history: [VideoProject] = []
    @ObservationIgnored private var future: [VideoProject] = []
    @ObservationIgnored private var gestureStart: VideoProject?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var scrubTask: Task<Void, Never>?
    @ObservationIgnored private var pendingScrub: Int64?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var built: BuiltComposition?
    /// Entschlüsselte Quelle in der Temp-Ablage der Sitzung (beim Schließen gelöscht, spätestens beim Sperren).
    @ObservationIgnored private var vaultSourceURL: URL?
    /// Tresor-Sitzung beim Öffnen: gespeichert wird nur in genau diese Sitzung.
    @ObservationIgnored private(set) var vaultLease: VaultSessionLease?
    /// Editor schon geschlossen: eine noch laufende Entschlüsselung räumt ihre Datei selbst weg.
    @ObservationIgnored private var stopped = false

    init(assetID: String, inVault: Bool = false) {
        self.assetID = assetID
        self.inVault = inVault
        player.isMuted = true
        player.actionAtItemEnd = .pause
    }

    var clip: VideoClip { project.clips[0] }
    var durationMs: Int64 { info?.durationMs ?? clip.sourceDurationMs }
    var hasChanges: Bool { initial.map { $0 != project } ?? false }
    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var outputDurationMs: Int64 { clip.outputDurationMs }
    var layout: VideoLayout? { info.map { VideoPlan.layout(display: $0.display, clip: clip, project: project) } }
    var playheadSourceMs: Int64 { VideoPlan.toSourceMs(clip, outMs: outMs) }
    var isTrimOnly: Bool { VideoEdit.isTrimOnly(project) }
    /// HDR wird beim Neuberechnen mit normalen Farben gespeichert (der schnelle Weg behält HDR).
    var hdrWillConvert: Bool { info?.hdr == true && !isTrimOnly }

    // MARK: Laden

    func load(app: AppModel, allowNetwork: Bool = true) async {
        loadState = .loading
        app.player.stop()
        let av: AVAsset
        if inVault {
            guard let lease = VaultStore.shared.editSession(),
                  let source = await VaultStore.shared.editVideoSource(assetID, lease: lease) else { loadState = .failed; return }
            if stopped || Task.isCancelled {
                VaultStore.shared.removeTempFiles([source.url])
                return
            }
            vaultLease = lease
            vaultSourceURL = source.url
            sourceName = source.name
            av = AVURLAsset(url: source.url)
        } else {
            guard let a = app.library.asset(assetID), a.isVideo else { loadState = .failed; return }
            asset = a
            guard let loaded = await VideoSource.asset(assetID, allowNetwork: allowNetwork) else {
                loadState = allowNetwork ? .failed : .iCloud
                return
            }
            av = loaded
        }
        guard let i = await VideoSource.info(av), i.durationMs > VideoRules.minClipMs else { loadState = .failed; return }
        avAsset = av
        info = i
        let p = VideoProject(id: UUID().uuidString, clips: [MoviePlan.videoClip(id: "c0", mediaId: assetID, durationMs: i.durationMs)])
        initial = p
        project = p
        history = []
        future = []
        loadState = .ready
        installObserver()
        await rebuild()
        thumbnails = await VideoSource.thumbnails(UncheckedBox(av), durationMs: i.durationMs, count: 10, height: 56)
    }

    func stop() {
        stopped = true
        previewTask?.cancel()
        scrubTask?.cancel()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
        if let vaultSourceURL {
            VaultStore.shared.removeTempFiles([vaultSourceURL])
            self.vaultSourceURL = nil
        }
    }

    private func installObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t) }
        }
    }

    private func tick(_ t: CMTime) {
        outMs = t.milliseconds
        playing = player.timeControlStatus == .playing
        // Wiederholen wie auf Android (nur Vorschau, nur nach Tippen auf Play).
        if loopRequested, let built, player.timeControlStatus == .paused, outMs >= built.durationMs - 60 {
            player.seek(to: .zero)
            player.play()
        }
    }

    @ObservationIgnored private var loopRequested = false

    func togglePlay() {
        guard tool != .text else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            loopRequested = false
        } else {
            if let built, outMs >= built.durationMs - 60 { player.seek(to: .zero) }
            loopRequested = true
            player.play()
        }
        playing = player.timeControlStatus != .paused
    }

    // MARK: Verlauf

    func checkpoint() {
        history.append(project)
        if history.count > 60 { history.removeFirst() }
        future = []
    }

    func beginChange() { if gestureStart == nil { gestureStart = project } }

    func endChange() {
        guard let start = gestureStart else { return }
        gestureStart = nil
        if start != project {
            history.append(start)
            if history.count > 60 { history.removeFirst() }
            future = []
        }
        // Farbe wirkt schon live; alles andere baut die Vorschau einmal neu auf.
        if built == nil || !Self.onlyColor(start, project) { schedulePreview() }
    }

    func undo() {
        guard let last = history.popLast() else { return }
        future.append(project)
        project = last
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(project)
        project = next
    }

    func update(_ change: (inout VideoProject) -> Void) {
        var next = project
        change(&next)
        guard next != project else { return }
        checkpoint()
        project = next
    }

    func updateClip(_ change: (inout VideoClip) -> Void) {
        update { $0.updateClip(0, change) }
    }

    func resetAll() {
        guard let initial else { return }
        update { $0 = initial }
    }

    // MARK: Vorschau

    private func projectChanged(_ old: VideoProject) {
        guard project != old, loadState == .ready else { return }
        if tool == .text {
            var a = old
            a.layers = project.layers
            if a != project { renderPoster() }
        }
        if let built, Self.onlyColor(old, project) {
            built.plan.setRecipe(VideoEdit.recipe(clip), at: 0)
            refreshFrame()
            return
        }
        if gestureStart == nil { schedulePreview() }
    }

    private static func onlyColor(_ a: VideoProject, _ b: VideoProject) -> Bool {
        guard a.clips.count == 1, b.clips.count == 1 else { return false }
        var x = a
        let c = b.clips[0]
        x.updateClip(0) {
            $0.adjust = c.adjust
            $0.filter = c.filter
            $0.filterIntensity = c.filterIntensity
            $0.colorMix = c.colorMix
        }
        return x == b
    }

    private func refreshFrame() {
        guard player.timeControlStatus != .playing else { return }
        let t = player.currentTime()
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.rebuild()
        }
    }

    private func rebuild() async {
        guard let avAsset, let info else { return }
        let keep = outMs
        let wasPlaying = player.timeControlStatus == .playing
        var small = project
        small.profile = .small
        small.targetShortSide = nil
        let size = VideoPlan.layout(display: info.display, clip: small.clips[0], project: small).output
        let input = VideoBuilder.Input(project: project, assets: [assetID: avAsset], infos: [assetID: info], size: size,
                                       fps: min(info.fps, 30), forExport: false)
        do {
            let next = try await VideoBuilder.build(input)
            guard !Task.isCancelled else { return }
            built = next
            previewFailed = false
            player.replaceCurrentItem(with: next.playerItem())
            let target = min(keep, max(0, next.durationMs - 1))
            _ = await player.seek(to: .ms(target), toleranceBefore: .zero, toleranceAfter: .zero)
            if wasPlaying { player.play() }
        } catch {
            previewFailed = true
            Diagnostics.error(.video, "preview-build", error)
        }
    }

    // MARK: Kürzen

    func setTrim(start: Int64, end: Int64) {
        let total = durationMs
        let s = min(max(0, start), total - VideoRules.minClipMs)
        let e = max(min(total, end), s + VideoRules.minClipMs)
        var p = project
        p.updateClip(0) { $0.trimStartMs = s; $0.trimEndMs = e }
        project = p
    }

    func startCut() {
        let c = clip
        let len = min(Int64(2000), max(VideoRules.minSegmentMs, (c.trimEndMs - c.trimStartMs) / 4))
        let s = min(max(c.trimStartMs, playheadSourceMs), c.trimEndMs - len)
        cutDraft = TimeRange(startMs: s, endMs: s + len)
        player.pause()
    }

    func moveCutDraft(start: Int64, end: Int64) {
        let c = clip
        let s = max(c.trimStartMs, min(start, c.trimEndMs - VideoRules.minSegmentMs))
        let e = min(c.trimEndMs, max(end, s + VideoRules.minSegmentMs))
        cutDraft = TimeRange(startMs: s, endMs: e)
    }

    /// `false`, wenn danach zu wenig übrig bliebe (dann bleibt alles, wie es war).
    @discardableResult
    func confirmCut() -> Bool {
        guard let d = cutDraft else { return false }
        let next = VideoRules.addCut(clip, d)
        cutDraft = nil
        guard next != clip else { return false }
        updateClip { $0 = next }
        return true
    }

    func removeCut(_ i: Int) {
        updateClip { if $0.cuts.indices.contains(i) { $0.cuts.remove(at: i) } }
    }

    /// Bild an der Quellzeit beim Ziehen (immer nur eine Anfrage gleichzeitig; die letzte gewinnt).
    func scrub(sourceMs: Int64) {
        pendingScrub = sourceMs
        guard scrubTask == nil, let avAsset else { return }
        let source = UncheckedBox(avAsset)
        scrubTask = Task { [weak self] in
            while let self, let ms = self.pendingScrub {
                self.pendingScrub = nil
                if let cg = await VideoSource.frame(source, sourceMs: ms, maxEdge: 720) {
                    self.scrubImage = UIImage(cgImage: cg.value)
                }
            }
            self?.scrubTask = nil
        }
    }

    func endScrub(seekSourceMs: Int64?) {
        scrubImage = nil
        pendingScrub = nil
        if let ms = seekSourceMs { seek(sourceMs: ms) }
    }

    func seek(sourceMs: Int64) {
        let out = VideoPlan.toOutputMs(clip, sourceMs: sourceMs) ?? VideoPlan.toOutputMs(clip, sourceMs: clip.trimStartMs) ?? 0
        outMs = out
        player.seek(to: .ms(out), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Markieren (Text/Sticker)

    private func toolChanged() {
        if tool == .text {
            player.pause()
            loopRequested = false
            renderPoster()
        } else {
            poster = nil
        }
        if tool == .filter && filterThumbs.isEmpty { renderFilterThumbs() }
    }

    /// Ergebnisbild ohne Ebenen an der aktuellen Stelle (gleiche Pipeline wie der Export, kleine Größe).
    func renderPoster() {
        guard let avAsset, let info, let built else { return }
        let t = outMs
        let src = VideoPlan.toSourceMs(clip, outMs: t)
        let clipNow = clip
        let plan = built.plan
        let recipe = VideoEdit.recipe(clipNow)
        let source = UncheckedBox(avAsset)
        Task { [weak self] in
            guard let cg = await VideoSource.frame(source, sourceMs: src, maxEdge: min(CGFloat(max(info.display.width, info.display.height)), 1280)) else { return }
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                let c = RenderPlan.Clip(clip: clipNow, recipe: recipe, orientation: .up, startMs: 0)
                let img = FrameComposer.compose(EditRenderer.source(cg.value), clip: c, plan: plan, outMs: t, recipe: recipe,
                                                layers: false)
                return EditRenderer.shared.cgImage(img).map { UIImage(cgImage: $0) }
            }.value
            self?.poster = image
        }
    }

    /// Größe des Ergebnisbilds (Ebenen-Koordinaten 0…1 beziehen sich darauf).
    var frameAspect: CGFloat {
        guard let l = layout else { return 16 / 9 }
        return CGFloat(l.output.width) / CGFloat(max(1, l.output.height))
    }

    func addLayer(_ layer: Layer) {
        update { $0.layers.append(TimedLayer(layer: layer)) }
        selectedLayer = layer.id
    }

    func replaceLayer(_ layer: Layer) {
        guard let i = project.layers.firstIndex(where: { $0.layer.id == layer.id }) else { return }
        var p = project
        p.layers[i].layer = layer
        project = p
    }

    func removeSelectedLayer() {
        guard let id = selectedLayer else { return }
        update { $0.layers.removeAll { $0.layer.id == id } }
        selectedLayer = nil
    }

    func setLayerTime(start: Int64, end: Int64) {
        guard let id = selectedLayer, let i = project.layers.firstIndex(where: { $0.layer.id == id }) else { return }
        let total = max(1, outputDurationMs)
        let s = min(max(0, start), total - 200)
        let e = max(min(total, end), s + 200)
        var p = project
        p.layers[i].startMs = s
        p.layers[i].endMs = e >= total ? .max : e
        project = p
    }

    // MARK: Filter-Vorschaubilder

    private func renderFilterThumbs() {
        guard let avAsset else { return }
        let src = playheadSourceMs
        let source = UncheckedBox(avAsset)
        Task { [weak self] in
            guard let cg = await VideoSource.frame(source, sourceMs: src, maxEdge: 200) else { return }
            let thumbs = await Task.detached(priority: .utility) { () -> [FilterId: UIImage] in
                let base = EditRenderer.source(cg.value)
                var out: [FilterId: UIImage] = [:]
                for f in FilterId.allCases {
                    var r = EditRecipe()
                    r.filter = f
                    if let img = EditRenderer.shared.cgImage(EditRenderer.shared.render(base, recipe: r, forPreview: true)) {
                        out[f] = UIImage(cgImage: img)
                    }
                }
                return out
            }.value
            self?.filterThumbs = thumbs
        }
    }

    // MARK: Größe

    /// Geschätzte Dateigröße (immer als „ca.“ beschriftet).
    func estimate(_ profile: ExportProfile) -> Int64? {
        guard let info else { return nil }
        var p = project
        p.profile = profile
        let l = VideoPlan.layout(display: info.display, clip: p.clips[0], project: p)
        return VideoPlan.estimateBytes(p, layout: l, fps: info.fps)
    }
}
