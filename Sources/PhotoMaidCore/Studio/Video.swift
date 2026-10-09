import Foundation

/// Zeitbereich in Millisekunden (Quellzeit eines Clips).
public struct TimeRange: Hashable, Codable, Sendable {
    public var startMs: Int64
    public var endMs: Int64
    public init(startMs: Int64, endMs: Int64) { self.startMs = startMs; self.endMs = endMs }
    public var durationMs: Int64 { max(0, endMs - startMs) }
    public func overlaps(_ o: TimeRange) -> Bool { startMs < o.endMs && o.startMs < endMs }
}

public enum Transition: String, Hashable, Codable, Sendable, CaseIterable { case none = "NONE", fadeBlack = "FADE_BLACK" }

/// Exportprofil: verständliche Stufen.
public enum ExportProfile: String, Hashable, Codable, Sendable, CaseIterable {
    /// Original-Auflösung, hohe Bitrate.
    case high = "HIGH"
    case balanced = "BALANCED"
    case small = "SMALL"

    public var height: Int {
        switch self {
        case .high: 0
        case .balanced: 1080
        case .small: 720
        }
    }

    public var bitsPerPixel: Float {
        switch self {
        case .high: 0.14
        case .balanced: 0.09
        case .small: 0.06
        }
    }
}

/// Ein Clip (Video oder Foto als Standbild). Alle Bearbeitungen sind Angaben – geschrieben wird erst beim Export.
/// `cuts` = entfernte Bereiche innerhalb von `trimStartMs…trimEndMs` (werden wirklich entfernt, nicht versteckt).
public struct VideoClip: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public var mediaId: String
    public var isPhoto = false
    public var sourceDurationMs: Int64
    public var trimStartMs: Int64 = 0
    public var trimEndMs: Int64
    public var cuts: [TimeRange] = []
    public var speed: Float = 1
    public var volume: Float = 1
    public var muted = false
    public var fadeInMs: Int64 = 0
    public var fadeOutMs: Int64 = 0
    public var quarterTurns = 0
    public var flipH = false
    public var crop = NormRect.full
    public var adjust = Adjustments()
    public var filter = FilterId.none
    public var filterIntensity: Float = 1
    public var colorMix = ColorMix()
    /// Foto-Clip: sanfter Zoom.
    public var kenBurns = true

    public init(id: String, mediaId: String, isPhoto: Bool = false, sourceDurationMs: Int64, trimStartMs: Int64 = 0,
                trimEndMs: Int64? = nil, kenBurns: Bool = true) {
        self.id = id
        self.mediaId = mediaId
        self.isPhoto = isPhoto
        self.sourceDurationMs = sourceDurationMs
        self.trimStartMs = trimStartMs
        self.trimEndMs = trimEndMs ?? sourceDurationMs
        self.kenBurns = kenBurns
    }

    /// Behaltene Abschnitte (Quellzeit), aufsteigend, ohne Schnitte.
    public func keptSegments() -> [TimeRange] {
        let base = TimeRange(startMs: trimStartMs, endMs: trimEndMs)
        if isPhoto { return [base] }
        var parts = [base]
        for c in cuts.sorted(by: { $0.startMs < $1.startMs }) {
            parts = parts.flatMap { p -> [TimeRange] in
                guard p.overlaps(c) else { return [p] }
                return [TimeRange(startMs: p.startMs, endMs: c.startMs), TimeRange(startMs: c.endMs, endMs: p.endMs)]
                    .filter { $0.durationMs >= VideoRules.minSegmentMs }
            }
        }
        return parts
    }

    /// Dauer im Ergebnis (nach Schnitten und Tempo).
    public var outputDurationMs: Int64 {
        let kept = keptSegments().reduce(Int64(0)) { $0 + $1.durationMs }
        return Int64((Double(kept) / Double(min(max(speed, 0.25), 4))).rounded())
    }

    /// Farbteil des Clips als Rezept (für `PointOps`).
    public var colorRecipe: EditRecipe {
        var r = EditRecipe()
        r.adjust = adjust
        r.filter = filter
        r.filterIntensity = filterIntensity
        r.colorMix = colorMix
        return r
    }
}

/// Text/Sticker über dem Video mit Ein- und Ausblendzeit (Zeit im Ergebnis).
public struct TimedLayer: Hashable, Codable, Sendable {
    public var layer: Layer
    public var startMs: Int64 = 0
    public var endMs: Int64 = .max
    public init(layer: Layer, startMs: Int64 = 0, endMs: Int64 = .max) {
        self.layer = layer
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// Hintergrundmusik: eigene Datei (Bookmark über die Dateiauswahl), Startpunkt in der Musik, Lautstärke.
public struct MusicTrack: Hashable, Codable, Sendable {
    public var uri: String
    public var name: String
    public var offsetMs: Int64 = 0
    public var volume: Float = 0.8
    public var fadeMs: Int64 = 1500
    public init(uri: String, name: String, offsetMs: Int64 = 0, volume: Float = 0.8, fadeMs: Int64 = 1500) {
        self.uri = uri
        self.name = name
        self.offsetMs = offsetMs
        self.volume = volume
        self.fadeMs = fadeMs
    }
}

public struct VideoProject: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public private(set) var clips: [VideoClip]
    /// Übergang je Naht (Größe = clips − 1).
    public var transitions: [Transition]
    public var transitionMs: Int64 = 500
    /// Ausgabe-Seitenverhältnis (Breite/Höhe); `nil` = wie der erste Clip.
    public var aspect: Float?
    /// Ausfüllen (zuschneiden) statt ganzes Bild zeigen (mit Hintergrund).
    public var fill = false
    public var background: ARGB = ARGB(Int32(bitPattern: 0xFF00_0000))
    public var music: MusicTrack?
    /// Originalton aller Clips entfernen (Tonspur wird nicht geschrieben).
    public var removeAudio = false
    public var layers: [TimedLayer] = []
    public var profile = ExportProfile.high
    /// Zielgröße (Arbeitsabläufe): feste Video-Bitrate und höchstens diese kurze Seite; `nil` = aus dem Profil.
    public var targetBitrate: Int?
    public var targetShortSide: Int?

    public init(id: String, clips: [VideoClip], transitions: [Transition]? = nil, transitionMs: Int64 = 500) {
        self.id = id
        self.clips = clips
        self.transitions = transitions ?? Array(repeating: .none, count: max(0, clips.count - 1))
        self.transitionMs = transitionMs
    }

    public var durationMs: Int64 { clips.reduce(0) { $0 + $1.outputDurationMs } }

    public func transition(at i: Int) -> Transition { transitions.indices.contains(i) ? transitions[i] : .none }

    public func withClips(_ next: [VideoClip]) -> VideoProject {
        var p = self
        p.clips = next
        p.transitions = (0..<max(0, next.count - 1)).map { transition(at: $0) }
        return p
    }

    public mutating func updateClip(_ i: Int, _ f: (inout VideoClip) -> Void) {
        guard clips.indices.contains(i) else { return }
        f(&clips[i])
    }

    public func move(from: Int, to: Int) -> VideoProject {
        guard clips.indices.contains(from), clips.indices.contains(to) else { return self }
        var l = clips
        let c = l.remove(at: from)
        l.insert(c, at: to)
        return withClips(l)
    }
}

public enum VideoRules {
    public static let minSegmentMs: Int64 = 300
    public static let minClipMs: Int64 = 500
    public static let photoDefaultMs: Int64 = 3000
    public static let maxClips = 50
    public static let maxTotalMs: Int64 = 30 * 60_000

    /// Geschätzte Größe in Bytes (Bitrate × Dauer + Ton). In der Oberfläche ausdrücklich als „ca.“ gezeigt.
    public static func estimateBytes(width: Int, height: Int, fps: Float, durationMs: Int64, profile: ExportProfile,
                                     audio: Bool) -> Int64 {
        let videoBps = Double(width) * Double(height) * Double(fps) * Double(profile.bitsPerPixel)
        let audioBps: Double = audio ? 128_000 : 0
        return Int64(((videoBps + audioBps) * Double(durationMs) / 8_000).rounded())
    }

    /// Zielgröße für ein Profil (nie hochskalieren, gerade Werte für Encoder).
    public static func targetSize(srcW: Int, srcH: Int, profile: ExportProfile, maxShortSide: Int? = nil) -> (Int, Int) {
        let short = min(srcW, srcH)
        let byProfile = profile.height == 0 || profile.height >= short ? short : profile.height
        let h = min(byProfile, maxShortSide ?? byProfile)
        let scale = Double(h) / Double(short)
        func even(_ v: Double) -> Int { (Int(v.rounded()) / 2) * 2 }
        return (even(Double(srcW) * scale), even(Double(srcH) * scale))
    }

    /// Schnitt `r` (Quellzeit) zum Clip hinzufügen: überlappende Schnitte werden zusammengelegt.
    public static func addCut(_ clip: VideoClip, _ r: TimeRange) -> VideoClip {
        let clipped = TimeRange(startMs: max(clip.trimStartMs, r.startMs), endMs: min(clip.trimEndMs, r.endMs))
        guard clipped.durationMs >= minSegmentMs else { return clip }
        let all = (clip.cuts + [clipped]).sorted { $0.startMs < $1.startMs }
        var merged: [TimeRange] = []
        for c in all {
            if let last = merged.last, c.startMs <= last.endMs {
                merged[merged.count - 1] = TimeRange(startMs: last.startMs, endMs: max(last.endMs, c.endMs))
            } else {
                merged.append(c)
            }
        }
        var next = clip
        next.cuts = merged
        // Nie alles wegschneiden.
        return next.keptSegments().reduce(0) { $0 + $1.durationMs } < minClipMs ? clip : next
    }
}

/// Pixelgröße (Breite × Höhe).
public struct VSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
    public var aspect: Float { Float(width) / Float(max(1, height)) }
}

/// Ergebnis-Layout eines Clips: Ausschnitt nach Drehen, Ausgabegröße, Füllen/Einpassen.
public struct VideoLayout: Hashable, Sendable {
    public let rotated: VSize
    public let cropped: VSize
    public let output: VSize
    public let fill: Bool
}

/// Reine Rechnung für den Video-Editor – gleiche Werte für Vorschau, Export und Tests.
public enum VideoPlan {
    public struct Segment: Hashable, Sendable {
        public let source: TimeRange
        public let outStartMs: Int64
        public let outEndMs: Int64
    }

    public static func speed(of clip: VideoClip) -> Double { Double(min(max(clip.speed, 0.25), 4)) }

    public static func segments(_ clip: VideoClip) -> [Segment] {
        let sp = speed(of: clip)
        var t = 0.0
        return clip.keptSegments().map { r in
            let start = t
            t += Double(r.durationMs) / sp
            return Segment(source: r, outStartMs: Int64(start.rounded()), outEndMs: Int64(t.rounded()))
        }
    }

    /// Ergebniszeit eines Quellzeitpunkts; `nil`, wenn er weggeschnitten ist.
    public static func toOutputMs(_ clip: VideoClip, sourceMs: Int64) -> Int64? {
        let sp = speed(of: clip)
        for s in segments(clip) where sourceMs >= s.source.startMs && sourceMs <= s.source.endMs {
            return s.outStartMs + Int64((Double(sourceMs - s.source.startMs) / sp).rounded())
        }
        return nil
    }

    /// Quellzeit zu einer Ergebniszeit (am Ende geklemmt).
    public static func toSourceMs(_ clip: VideoClip, outMs: Int64) -> Int64 {
        let sp = speed(of: clip)
        let segs = segments(clip)
        guard let last = segs.last else { return clip.trimStartMs }
        for s in segs where outMs < s.outEndMs {
            return s.source.startMs + Int64((Double(max(0, outMs - s.outStartMs)) * sp).rounded())
        }
        return last.source.endMs
    }

    /// Lautstärke (0…2) zur Ergebniszeit: Grundlautstärke × Einblenden × Ausblenden; stumm = 0.
    public static func gain(_ clip: VideoClip, outMs: Int64) -> Float {
        if clip.muted { return 0 }
        let total = clip.outputDurationMs
        var g = min(max(clip.volume, 0), 2)
        if clip.fadeInMs > 0 && outMs < clip.fadeInMs { g *= clamp01(Float(outMs) / Float(clip.fadeInMs)) }
        if clip.fadeOutMs > 0 && outMs > total - clip.fadeOutMs { g *= clamp01(Float(total - outMs) / Float(clip.fadeOutMs)) }
        return g
    }

    /// Layout: `display` = Anzeigegröße (Quelldrehung schon berücksichtigt). Vierteldrehungen, Ausschnitt,
    /// Seitenverhältnis des Projekts und Profil.
    public static func layout(display: VSize, clip: VideoClip, project: VideoProject) -> VideoLayout {
        let rotated = ((clip.quarterTurns % 4) + 4) % 2 == 1 ? VSize(display.height, display.width) : display
        let c = clip.crop
        let cropped = VSize(max(2, Int((c.width * Float(rotated.width)).rounded())),
                            max(2, Int((c.height * Float(rotated.height)).rounded())))
        let aspect = project.aspect ?? cropped.aspect
        let frame: VSize
        if project.fill {
            frame = cropped.aspect > aspect ? VSize(Int((Float(cropped.height) * aspect).rounded()), cropped.height)
                : VSize(cropped.width, Int((Float(cropped.width) / aspect).rounded()))
        } else {
            frame = cropped.aspect > aspect ? VSize(cropped.width, Int((Float(cropped.width) / aspect).rounded()))
                : VSize(Int((Float(cropped.height) * aspect).rounded()), cropped.height)
        }
        let (w, h) = VideoRules.targetSize(srcW: max(2, frame.width), srcH: max(2, frame.height), profile: project.profile,
                                           maxShortSide: project.targetShortSide)
        return VideoLayout(rotated: rotated, cropped: cropped, output: VSize(max(2, w), max(2, h)), fill: project.fill)
    }

    /// Geschätzte Dateigröße in Bytes – in der Oberfläche immer als „ca.“ beschriftet.
    public static func estimateBytes(_ project: VideoProject, layout: VideoLayout, fps: Float) -> Int64 {
        guard let clip = project.clips.first else { return 0 }
        let audio = !project.removeAudio && !clip.muted
        return VideoRules.estimateBytes(width: layout.output.width, height: layout.output.height,
                                        fps: min(max(fps, 1), 120), durationMs: clip.outputDurationMs,
                                        profile: project.profile, audio: audio)
    }

    /// Video-Bitrate für den Encoder (Bit/s) aus Profil, Größe und Bildrate.
    public static func videoBitrate(_ layout: VideoLayout, fps: Float, profile: ExportProfile) -> Int {
        let v = Double(layout.output.width) * Double(layout.output.height) * Double(min(max(fps, 1), 120))
            * Double(profile.bitsPerPixel)
        return Int(min(max(v, 500_000), 120_000_000))
    }

    /// Sichtbar zur Ergebniszeit (mit Einblenden 200 ms an den Rändern): Deckkraft 0…1.
    public static func layerAlpha(_ l: TimedLayer, outMs: Int64, fadeMs: Int64 = 200) -> Float {
        if outMs < l.startMs || outMs > l.endMs { return 0 }
        let inA: Float = fadeMs <= 0 ? 1 : min(1, Float(outMs - l.startMs) / Float(fadeMs))
        let outA: Float = fadeMs <= 0 || l.endMs == .max ? 1 : min(1, Float(l.endMs - outMs) / Float(fadeMs))
        return clamp01(min(inA, outA))
    }
}

/// „Video zusammenfügen“ und „Diashow als Video“: Übergang je Naht „keiner“ oder „über Schwarz“ (mittig auf der Naht,
/// Gesamtdauer bleibt gleich). Alle Clips werden in eine gemeinsame Ausgabegröße eingepasst oder füllen sie – nie verzerrt.
public enum MoviePlan {
    public static func starts(_ project: VideoProject) -> [Int64] {
        var t: Int64 = 0
        return project.clips.map { c in defer { t += c.outputDurationMs }; return t }
    }

    public static func totalMs(_ project: VideoProject) -> Int64 { project.durationMs }

    public static func blackSeams(_ project: VideoProject) -> [Int64] {
        let s = starts(project)
        return (1..<max(1, project.clips.count)).filter { project.transition(at: $0 - 1) == .fadeBlack }.map { s[$0] }
    }

    /// Deckkraft der Schwarzblende: 1 genau auf der Naht, linear auf 0 bis ±halbe Übergangsdauer (begrenzt durch die
    /// kürzere Nachbardauer, damit ein kurzer Clip nie ganz schwarz bleibt).
    public static func blackAlpha(_ project: VideoProject, outMs: Int64) -> Float {
        let starts = starts(project)
        var a: Float = 0
        guard project.clips.count > 1 else { return 0 }
        for i in 1..<project.clips.count where project.transition(at: i - 1) == .fadeBlack {
            let seam = starts[i]
            let half = max(1, min(project.transitionMs / 2,
                                  min(project.clips[i - 1].outputDurationMs, project.clips[i].outputDurationMs) / 3))
            let d = abs(outMs - seam)
            if d < half { a = max(a, 1 - Float(d) / Float(half)) }
        }
        return clamp01(a)
    }

    /// Lautstärke der Musik: Grundlautstärke × Ein-/Ausblenden am Anfang und Ende des Films.
    public static func musicGain(_ project: VideoProject, outMs: Int64) -> Float {
        guard let m = project.music else { return 0 }
        let total = totalMs(project)
        var g = clamp01(m.volume)
        if m.fadeMs > 0 {
            if outMs < m.fadeMs { g *= clamp01(Float(outMs) / Float(m.fadeMs)) }
            if outMs > total - m.fadeMs { g *= clamp01(Float(total - outMs) / Float(m.fadeMs)) }
        }
        return g
    }

    /// Gemeinsame Ausgabegröße: Seitenverhältnis des Projekts (`nil` = wie der erste Clip), kurze Kante nach Profil.
    public static func frame(_ project: VideoProject, first: VSize) -> VSize {
        let aspect = project.aspect ?? first.aspect
        let byProfile = project.profile == .small ? 720 : 1080
        let short = min(byProfile, max(480, max(2, min(first.width, first.height))))
        let (w, h) = aspect >= 1 ? (Int((Float(short) * aspect).rounded()), short) : (short, Int((Float(short) / aspect).rounded()))
        return VSize(even(w), even(h))
    }

    private static func even(_ v: Int) -> Int { max(2, v - v % 2) }

    /// Sanfter Zoom eines Foto-Clips: Faktor 1,00 → 1,08 über die Clipdauer (Anteil 0…1).
    public static func kenBurnsScale(_ fraction: Float) -> Float { 1 + 0.08 * clamp01(fraction) }

    public static func photoClip(id: String, mediaId: String, durationMs: Int64 = VideoRules.photoDefaultMs,
                                 kenBurns: Bool = true) -> VideoClip {
        VideoClip(id: id, mediaId: mediaId, isPhoto: true, sourceDurationMs: durationMs, trimStartMs: 0,
                  trimEndMs: durationMs, kenBurns: kenBurns)
    }

    public static func videoClip(id: String, mediaId: String, durationMs: Int64) -> VideoClip {
        VideoClip(id: id, mediaId: mediaId, sourceDurationMs: durationMs)
    }

    public static func withPhotoDuration(_ c: VideoClip, ms: Int64) -> VideoClip {
        guard c.isPhoto else { return c }
        let d = min(max(ms, VideoRules.minClipMs), 60_000)
        var n = c
        n.sourceDurationMs = d; n.trimStartMs = 0; n.trimEndMs = d
        return n
    }

    public enum Limit: Hashable, Sendable { case tooFew, tooMany, tooLong }

    /// Grenzen ehrlich: max. Clips und Gesamtdauer. `nil` = in Ordnung, sonst der Grund.
    public static func problem(_ project: VideoProject) -> Limit? {
        if project.clips.count < 2 { return .tooFew }
        if project.clips.count > VideoRules.maxClips { return .tooMany }
        if totalMs(project) > VideoRules.maxTotalMs { return .tooLong }
        return nil
    }

    /// Diashow aus Fotos: gleiche Dauer, sanfter Zoom, Übergang über Schwarz.
    public static func slideshow(id: String, photoIDs: [String], seconds: Int = 3) -> VideoProject {
        let clips = photoIDs.enumerated().map { photoClip(id: "\(id)-\($0.offset)", mediaId: $0.element, durationMs: Int64(seconds) * 1000) }
        return VideoProject(id: id, clips: clips, transitions: Array(repeating: .fadeBlack, count: max(0, clips.count - 1)),
                            transitionMs: 600)
    }
}
