import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import PhotoMaidCore
import UIKit

/// Ein Weg für Vorschau und Export: `AVMutableComposition` (Schnitte und Tempo als Zeitachse) + eigener Compositor
/// (`PMCompositor`), der jedes Bild mit derselben Pipeline rechnet wie der Foto-Editor: Drehung der Aufnahme →
/// Vierteldrehung/Spiegeln/Ausschnitt → Farbe (Farbtabelle aus `PointOps`) → einpassen oder füllen (nie verzerrt) →
/// Text/Sticker mit Zeitfenster → Schwarzblende an Nähten. Ton: Lautstärke mit Blenden über `AVAudioMix`.
enum VideoEdit {
    /// Farb- und Formteil eines Clips als Foto-Rezept (Detail/Effekte wie auf Android ausgenommen).
    static func recipe(_ clip: VideoClip) -> EditRecipe {
        var r = clip.colorRecipe
        r.adjust.vignette = 0
        r.adjust.grain = 0
        r.adjust.sharpness = 0
        r.adjust.clarity = 0
        r.adjust.noiseReduction = 0
        r.adjust.sharpenRadius = 0
        r.adjust.sharpenThreshold = 0
        r.quarterTurns = clip.quarterTurns
        r.flipH = clip.flipH
        r.crop = clip.crop
        return r
    }

    static func colorNeutral(_ clip: VideoClip) -> Bool {
        var r = recipe(clip)
        r.quarterTurns = 0
        r.flipH = false
        r.crop = .full
        return PointOps(recipe: r).isNeutral
    }

    /// Nur Anfang/Ende gekürzt, sonst nichts geändert → schneller Weg ohne Neuberechnung (gleiche Qualität, HDR bleibt).
    static func isTrimOnly(_ p: VideoProject) -> Bool {
        guard p.clips.count == 1, let c = p.clips.first else { return false }
        return c.cuts.isEmpty && c.speed == 1 && c.volume == 1 && !c.muted && c.fadeInMs == 0 && c.fadeOutMs == 0
            && ((c.quarterTurns % 4) + 4) % 4 == 0 && !c.flipH && c.crop.isFull && colorNeutral(c) && p.aspect == nil
            && p.layers.isEmpty && !p.removeAudio && p.profile == .high && p.targetBitrate == nil && p.targetShortSide == nil
    }
}

/// Alles, was der Compositor für ein Bild braucht. Nach dem Bauen unverändert (Fotos werden nur nachgeladen und
/// zwischengespeichert) – deshalb `@unchecked Sendable`.
final class RenderPlan: @unchecked Sendable {
    struct Clip {
        let clip: VideoClip
        let recipe: EditRecipe
        let orientation: CGImagePropertyOrientation
        let startMs: Int64
    }

    struct Overlay {
        let layer: TimedLayer
        let image: CIImage
    }

    let project: VideoProject
    let size: CGSize
    let clips: [Clip]
    let background: CIImage
    let overlays: [Overlay]
    let allowNetwork: Bool
    private let lock = NSLock()
    private var photos: [String: CIImage] = [:]
    private var loading: Set<String> = []
    /// Farbe/Form je Clip – in der Vorschau ohne Neuaufbau änderbar (Regler wirken sofort).
    private var recipes: [EditRecipe]

    init(project: VideoProject, size: CGSize, clips: [Clip], includeLayers: Bool, allowNetwork: Bool) {
        self.project = project
        self.size = size
        self.clips = clips
        self.allowNetwork = allowNetwork
        recipes = clips.map(\.recipe)
        let rect = CGRect(origin: .zero, size: size)
        background = CIImage(color: CIColor(color: LayerRenderer.color(project.background))).cropped(to: rect)
        let px = PxSize(Int(size.width), Int(size.height))
        overlays = includeLayers ? project.layers.map { tl in
            Overlay(layer: tl, image: LayerRenderer.draw([tl.layer], over: CIImage(color: .clear).cropped(to: rect), size: px))
        } : []
    }

    func recipe(_ index: Int) -> EditRecipe { lock.withLock { recipes[index] } }
    func setRecipe(_ r: EditRecipe, at index: Int) { lock.withLock { if recipes.indices.contains(index) { recipes[index] = r } } }

    /// Foto eines Foto-Clips (verkleinert auf die Ausgabegröße mit Reserve für den sanften Zoom). Höchstens zwei im
    /// Speicher; das nächste wird im Voraus geladen.
    func photo(_ index: Int) -> CIImage? {
        guard clips.indices.contains(index) else { return nil }
        let id = clips[index].clip.mediaId
        lock.lock()
        if let hit = photos[id] { lock.unlock(); prefetch(index + 1); return hit }
        lock.unlock()
        let img = load(id)
        lock.lock()
        if photos.count >= 2 { photos.removeAll() }
        if let img { photos[id] = img }
        lock.unlock()
        prefetch(index + 1)
        return img
    }

    private func prefetch(_ index: Int) {
        guard clips.indices.contains(index), clips[index].clip.isPhoto else { return }
        let id = clips[index].clip.mediaId
        lock.lock()
        let skip = photos[id] != nil || loading.contains(id)
        if !skip { loading.insert(id) }
        lock.unlock()
        guard !skip else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let img = load(id)
            lock.lock()
            loading.remove(id)
            if let img {
                if photos.count >= 2, let other = photos.keys.first(where: { $0 != clips[max(0, index - 1)].clip.mediaId }) {
                    photos[other] = nil
                }
                photos[id] = img
            }
            lock.unlock()
        }
    }

    private func load(_ id: String) -> CIImage? {
        guard let ph = PhotoLibraryService.phAsset(id) else { return nil }
        let edge = max(size.width, size.height) * 1.12
        let o = PHImageRequestOptions()
        o.isSynchronous = true
        o.isNetworkAccessAllowed = allowNetwork
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .exact
        o.version = .current
        let holder = ImageHolder()
        PHImageManager.default().requestImage(for: ph, targetSize: CGSize(width: edge, height: edge), contentMode: .aspectFit,
                                              options: o) { @Sendable image, _ in holder.image = image }
        guard let ui = holder.image, let cg = ui.cgImage else { return nil }
        let img = EditRenderer.normalized(CIImage(cgImage: cg).oriented(CGImagePropertyOrientation(ui.imageOrientation)))
        // Einmal dekodieren, dann nur noch abtasten.
        guard let baked = EditRenderer.shared.cgImage(img) else { return img }
        return CIImage(cgImage: baked)
    }
}

private final class ImageHolder: @unchecked Sendable { var image: UIImage? }

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Ein Ergebnisbild aus einem Quellbild – derselbe Code für Compositor, Vorschau-Standbild und „Standbild speichern“.
enum FrameComposer {
    /// - Parameters:
    ///   - frame: Quellbild schon in Anzeigedrehung (Ursprung 0,0), `nil` = Hintergrund.
    ///   - outMs: Zeit im Ergebnis (für Zoom, Ebenen, Blenden).
    static func compose(_ frame: CIImage?, clip c: RenderPlan.Clip, plan: RenderPlan, outMs t: Int64,
                        recipe: EditRecipe? = nil, layers: Bool = true, fadeLayers: Bool = true) -> CIImage {
        let W = plan.size.width, H = plan.size.height
        let rect = CGRect(x: 0, y: 0, width: W, height: H)
        var img = plan.background
        if let frame, frame.extent.width > 0, frame.extent.height > 0 {
            let edited = EditRenderer.shared.render(frame, recipe: recipe ?? c.recipe, includeLayers: false)
            let ew = edited.extent.width, eh = edited.extent.height
            var s = plan.project.fill ? max(W / ew, H / eh) : min(W / ew, H / eh)
            if c.clip.isPhoto && c.clip.kenBurns {
                let f = Float(t - c.startMs) / Float(max(1, c.clip.outputDurationMs))
                s *= CGFloat(MoviePlan.kenBurnsScale(f))
            }
            let placed = edited
                .transformed(by: CGAffineTransform(scaleX: s, y: s))
                .transformed(by: CGAffineTransform(translationX: (W - ew * s) / 2, y: (H - eh * s) / 2))
            img = placed.cropped(to: rect).composited(over: img)
        }
        if layers {
            for o in plan.overlays {
                let a = VideoPlan.layerAlpha(o.layer, outMs: t, fadeMs: fadeLayers ? 200 : 0)
                guard a > 0 else { continue }
                img = (a >= 0.999 ? o.image : faded(o.image, a)).composited(over: img)
            }
        }
        let black = MoviePlan.blackAlpha(plan.project, outMs: t)
        if black > 0 {
            img = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(black))).cropped(to: rect).composited(over: img)
        }
        return img.cropped(to: rect)
    }

    private static func faded(_ img: CIImage, _ a: Float) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = img
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(a))
        return f.outputImage ?? img
    }
}

/// Anweisung je Clip (Zeitbereich im Ergebnis, Spur, Clip-Nummer).
final class PMInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let clipIndex: Int
    let plan: RenderPlan

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, clipIndex: Int, plan: RenderPlan) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.clipIndex = clipIndex
        self.plan = plan
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
        super.init()
    }
}

/// Eigener Compositor: rechnet jedes Bild mit `FrameComposer` (Core Image, GPU) in einen Puffer des Render-Kontexts.
final class PMCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.photomaid.compositor", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0

    private static let attributes: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
    ]

    var sourcePixelBufferAttributes: [String: any Sendable]? { Self.attributes }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.attributes }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let box = UncheckedBox(request)
        let gen = lock.withLock { generation }
        queue.async { [self] in
            let r = box.value
            guard lock.withLock({ generation }) == gen else { r.finishCancelledRequest(); return }
            let buffer: CVPixelBuffer? = autoreleasepool { render(r) }
            if let buffer { r.finish(withComposedVideoFrame: buffer) } else { r.finish(with: VideoError.render) }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        lock.withLock { generation += 1 }
    }

    private func render(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
        guard let ins = request.videoCompositionInstruction as? PMInstruction,
              let out = request.renderContext.newPixelBuffer() else { return nil }
        let plan = ins.plan
        let c = plan.clips[ins.clipIndex]
        let t = request.compositionTime.milliseconds
        var frame: CIImage?
        if c.clip.isPhoto {
            frame = plan.photo(ins.clipIndex)
        } else if let px = request.sourceFrame(byTrackID: ins.trackID) {
            frame = EditRenderer.normalized(CIImage(cvPixelBuffer: px).oriented(c.orientation))
        }
        let img = FrameComposer.compose(frame, clip: c, plan: plan, outMs: t, recipe: plan.recipe(ins.clipIndex))
        EditRenderer.shared.context.render(img, to: out, bounds: CGRect(origin: .zero, size: plan.size),
                                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return out
    }
}

/// Fertige Komposition (Vorschau oder Export). Nach dem Bauen unverändert.
final class BuiltComposition: @unchecked Sendable {
    let composition: AVComposition
    let videoComposition: AVVideoComposition
    let audioMix: AVAudioMix?
    let plan: RenderPlan
    let fps: Float
    let durationMs: Int64
    /// Verstärkung über 100 %, die der Schreiber auf die Tonproben rechnet (`AVAudioMix` kann nur 0…1).
    let audioBoost: Float
    let hasAudio: Bool

    init(composition: AVComposition, videoComposition: AVVideoComposition, audioMix: AVAudioMix?, plan: RenderPlan,
         fps: Float, durationMs: Int64, audioBoost: Float, hasAudio: Bool) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.plan = plan
        self.fps = fps
        self.durationMs = durationMs
        self.audioBoost = audioBoost
        self.hasAudio = hasAudio
    }

    @MainActor
    func playerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        item.audioTimePitchAlgorithm = .spectral
        return item
    }
}

/// Baut die Komposition aus einem Projekt. Fotos laufen über ein kurzes schwarzes Trägervideo (der Compositor zeichnet
/// das Foto darüber), damit Vorschau und Export dieselbe Zeitachse haben.
enum VideoBuilder {
    struct Input: @unchecked Sendable {
        var project: VideoProject
        /// Video-Clips: `mediaId` → AVAsset und Eckdaten.
        var assets: [String: AVAsset]
        var infos: [String: VideoInfo]
        var size: VSize
        var fps: Float
        var forExport: Bool
        var includeLayers = true
        var allowNetwork = false
        var musicURL: URL?
    }

    static func build(_ input: Input) async throws -> BuiltComposition {
        let project = input.project
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw VideoError.render }
        let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let withClipAudio = !project.removeAudio
        let gains = project.clips.filter { !$0.isPhoto && !$0.muted }.map { min(max($0.volume, 0), 2) }
        let boost: Float = input.forExport ? max(1, gains.max() ?? 1) : 1
        let audioParams = aTrack.map { AVMutableAudioMixInputParameters(track: $0) }
        var audioEnd = CMTime.zero
        var clips: [RenderPlan.Clip] = []
        var ranges: [CMTimeRange] = []
        var cursor = CMTime.zero
        var blankTrack: AVAssetTrack?

        for clip in project.clips {
            let start = cursor
            if clip.isPhoto {
                if blankTrack == nil {
                    let blankURL = try await BlankVideo.url()
                    let blank = AVURLAsset(url: blankURL)
                    blankTrack = try await blank.loadTracks(withMediaType: .video).first
                }
                guard let blankTrack else { throw VideoError.render }
                let one = CMTimeRange(start: .zero, duration: BlankVideo.duration)
                try vTrack.insertTimeRange(one, of: blankTrack, at: cursor)
                let d = CMTime.ms(max(1, clip.outputDurationMs))
                vTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: BlankVideo.duration), toDuration: d)
                cursor = cursor + d
                clips.append(RenderPlan.Clip(clip: clip, recipe: VideoEdit.recipe(clip), orientation: .up, startMs: start.milliseconds))
            } else {
                guard let asset = input.assets[clip.mediaId], let info = input.infos[clip.mediaId],
                      let sv = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.missing }
                var sa: AVAssetTrack?
                if withClipAudio && !clip.muted { sa = try await asset.loadTracks(withMediaType: .audio).first }
                let speed = VideoPlan.speed(of: clip)
                for seg in VideoPlan.segments(clip) {
                    let srcEnd = min(seg.source.endMs, info.durationMs)
                    guard srcEnd - seg.source.startMs >= 1 else { continue }
                    let range = CMTimeRange(start: .ms(seg.source.startMs), end: .ms(srcEnd))
                    try vTrack.insertTimeRange(range, of: sv, at: cursor)
                    let outDur = speed == 1 ? range.duration : CMTime.ms(max(1, seg.outEndMs - seg.outStartMs))
                    if speed != 1 { vTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: outDur) }
                    if let sa, let aTrack {
                        if audioEnd < cursor { aTrack.insertEmptyTimeRange(CMTimeRange(start: audioEnd, end: cursor)) }
                        if (try? aTrack.insertTimeRange(range, of: sa, at: cursor)) != nil {
                            if speed != 1 { aTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: outDur) }
                            audioEnd = cursor + outDur
                        }
                    }
                    cursor = cursor + outDur
                }
                if sa != nil, let p = audioParams {
                    ramp(p, clip: clip, start: start, end: cursor, boost: boost)
                }
                clips.append(RenderPlan.Clip(clip: clip, recipe: VideoEdit.recipe(clip), orientation: info.orientation,
                                             startMs: start.milliseconds))
            }
            ranges.append(CMTimeRange(start: start, end: cursor))
        }
        guard cursor > .zero else { throw VideoError.missing }

        var mixParams: [AVMutableAudioMixInputParameters] = []
        if let aTrack {
            if audioEnd == .zero { comp.removeTrack(aTrack) } else if let p = audioParams { mixParams.append(p) }
        }
        if let url = input.musicURL, let m = project.music,
           let p = try await addMusic(url, music: m, to: comp, total: cursor, boost: boost) {
            mixParams.append(p)
        }

        let size = CGSize(width: input.size.width, height: input.size.height)
        let plan = RenderPlan(project: project, size: size, clips: clips, includeLayers: input.includeLayers,
                              allowNetwork: input.allowNetwork)
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = PMCompositor.self
        vc.renderSize = size
        let fps = min(60, max(24, input.fps.rounded()))
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        vc.instructions = ranges.enumerated().map { i, r in
            PMInstruction(timeRange: r, trackID: vTrack.trackID, clipIndex: i, plan: plan)
        }
        var mix: AVAudioMix?
        if !mixParams.isEmpty {
            let m = AVMutableAudioMix()
            m.inputParameters = mixParams
            mix = m.copy() as? AVAudioMix
        }
        guard let frozen = comp.copy() as? AVComposition, let frozenVC = vc.copy() as? AVVideoComposition else {
            throw VideoError.render
        }
        return BuiltComposition(composition: frozen, videoComposition: frozenVC, audioMix: mix, plan: plan, fps: fps,
                                durationMs: cursor.milliseconds, audioBoost: boost, hasAudio: !mixParams.isEmpty)
    }

    /// Lautstärke mit Ein-/Ausblenden (wie `VideoPlan.gain`); Werte über 100 % rechnet der Schreiber dazu.
    private static func ramp(_ p: AVMutableAudioMixInputParameters, clip: VideoClip, start: CMTime, end: CMTime, boost: Float) {
        let v = min(1, min(max(clip.volume, 0), 2) / boost)
        let dur = (end - start).milliseconds
        let fi = min(clip.fadeInMs, dur / 2), fo = min(clip.fadeOutMs, dur / 2)
        if fi > 0 {
            p.setVolumeRamp(fromStartVolume: 0, toEndVolume: v, timeRange: CMTimeRange(start: start, duration: .ms(fi)))
        } else {
            p.setVolume(v, at: start)
        }
        if fo > 0 {
            p.setVolumeRamp(fromStartVolume: v, toEndVolume: 0, timeRange: CMTimeRange(start: end - .ms(fo), duration: .ms(fo)))
        }
    }

    /// Musik aus eigener Datei: ab Versatz, bei Bedarf wiederholt, mit Ein-/Ausblenden (wie `MoviePlan.musicGain`).
    private static func addMusic(_ url: URL, music m: MusicTrack, to comp: AVMutableComposition, total: CMTime,
                                 boost: Float) async throws -> AVMutableAudioMixInputParameters? {
        let asset = AVURLAsset(url: url)
        guard let src = try await asset.loadTracks(withMediaType: .audio).first,
              let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let length = try await asset.load(.duration)
        guard length.milliseconds > 100 else { comp.removeTrack(track); return nil }
        var t = CMTime.zero
        var from = CMTime.ms(min(max(0, m.offsetMs), max(0, length.milliseconds - 100)))
        while t < total {
            let len = CMTimeMinimum(length - from, total - t)
            guard len.milliseconds > 0 else { break }
            try track.insertTimeRange(CMTimeRange(start: from, duration: len), of: src, at: t)
            t = t + len
            from = .zero
        }
        let p = AVMutableAudioMixInputParameters(track: track)
        let v = min(1, max(0, m.volume)) / boost
        let fade = min(m.fadeMs, total.milliseconds / 2)
        if fade > 0 {
            p.setVolumeRamp(fromStartVolume: 0, toEndVolume: v, timeRange: CMTimeRange(start: .zero, duration: .ms(fade)))
            p.setVolumeRamp(fromStartVolume: v, toEndVolume: 0, timeRange: CMTimeRange(start: total - .ms(fade), duration: .ms(fade)))
        } else {
            p.setVolume(v, at: .zero)
        }
        return p
    }
}

/// Kurzes schwarzes Trägervideo (1 s, 30 Bilder) für Foto-Clips. Einmal erzeugt, im Zwischenspeicher.
enum BlankVideo {
    static let duration = CMTime(value: 1, timescale: 1)

    static func url() async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("photomaid-blank-v1.mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let tmp = dir.appendingPathComponent("blank-\(UUID().uuidString).mp4")
        let side = 128
        let writer = try AVAssetWriter(outputURL: tmp, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: side, kCVPixelBufferHeightKey as String: side,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw VideoError.write }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw VideoError.write }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for i in 0..<30 {
            var waited = 0
            while !input.isReadyForMoreMediaData && waited < 400 {
                try await Task.sleep(for: .milliseconds(5))
                waited += 1
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30)) else {
                throw VideoError.write
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoError.write }
        if !FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.moveItem(at: tmp, to: url) }
        try? FileManager.default.removeItem(at: tmp)
        return url
    }
}
