import Foundation

/// Normalisiertes Rechteck (0…1) im Bildrahmen nach Vierteldrehung/Spiegeln.
public struct NormRect: Hashable, Codable, Sendable {
    public var left: Float
    public var top: Float
    public var right: Float
    public var bottom: Float

    public init(left: Float = 0, top: Float = 0, right: Float = 1, bottom: Float = 1) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public static let eps: Float = 1e-4
    public static let full = NormRect()

    public var width: Float { right - left }
    public var height: Float { bottom - top }
    public var isFull: Bool {
        abs(left) < Self.eps && abs(top) < Self.eps && abs(right - 1) < Self.eps && abs(bottom - 1) < Self.eps
    }

    /// Ausschnitt nach einer Vierteldrehung im Uhrzeigersinn (der Rahmen dreht mit).
    public func rotatedClockwise() -> NormRect { NormRect(left: 1 - bottom, top: left, right: 1 - top, bottom: right) }
    public func flippedH() -> NormRect { NormRect(left: 1 - right, top: top, right: 1 - left, bottom: bottom) }
    public func flippedV() -> NormRect { NormRect(left: left, top: 1 - bottom, right: right, bottom: 1 - top) }
}

/// Regler −100…+100 (Schärfe, Körnung 0…100). 0 = keine Änderung.
public struct Adjustments: Hashable, Codable, Sendable {
    public var brightness: Float = 0
    public var contrast: Float = 0
    public var saturation: Float = 0
    public var warmth: Float = 0
    public var sharpness: Float = 0
    public var exposure: Float = 0
    public var highlights: Float = 0
    public var shadows: Float = 0
    public var whites: Float = 0
    public var blacks: Float = 0
    public var tint: Float = 0
    public var vibrance: Float = 0
    public var vignette: Float = 0
    public var grain: Float = 0
    public var clarity: Float = 0
    /// Schärfen: Radius 0…100 (0 = automatisch nach Bildgröße) und Schwelle 0…100.
    public var sharpenRadius: Float = 0
    public var sharpenThreshold: Float = 0
    /// Rauschreduzierung 0…100 (iOS-Ergänzung, Masterprompt §4).
    public var noiseReduction: Float = 0

    public init() {}

    private static func nz(_ v: Float) -> Bool { abs(v) >= 0.5 }

    /// Punktweise Tonwert-/Farbänderung (unabhängig von Nachbarpixeln und Position).
    public var pointNeutral: Bool {
        ![brightness, contrast, saturation, warmth, exposure, highlights, shadows, whites, blacks, tint, vibrance]
            .contains(where: Self.nz)
    }
    /// Positionsabhängig (Vignette, Körnung).
    public var spatialNeutral: Bool { !Self.nz(vignette) && grain < 0.5 }
    public var detailNeutral: Bool { sharpness < 0.5 && !Self.nz(clarity) && noiseReduction < 0.5 }
    public var isNeutral: Bool { pointNeutral && spatialNeutral && detailNeutral }
    public var colorNeutral: Bool { pointNeutral && spatialNeutral }

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, warmth, sharpness, exposure, highlights, shadows, whites, blacks, tint,
             vibrance, vignette, grain, clarity, sharpenRadius, sharpenThreshold, noiseReduction
    }

    /// Fehlende Felder (ältere Sicherungen, Android-Vorlagen) = 0.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ k: CodingKeys) throws -> Float { try c.decodeIfPresent(Float.self, forKey: k) ?? 0 }
        brightness = try f(.brightness); contrast = try f(.contrast); saturation = try f(.saturation)
        warmth = try f(.warmth); sharpness = try f(.sharpness); exposure = try f(.exposure)
        highlights = try f(.highlights); shadows = try f(.shadows); whites = try f(.whites); blacks = try f(.blacks)
        tint = try f(.tint); vibrance = try f(.vibrance); vignette = try f(.vignette); grain = try f(.grain)
        clarity = try f(.clarity); sharpenRadius = try f(.sharpenRadius); sharpenThreshold = try f(.sharpenThreshold)
        noiseReduction = try f(.noiseReduction)
    }
}

/// Ein Farbbereich des Farbmischers: Farbton ±100 (= ±30°), Sättigung, Helligkeit −100…+100.
public struct HslShift: Hashable, Codable, Sendable {
    public var hue: Float = 0
    public var saturation: Float = 0
    public var luminance: Float = 0
    public init(hue: Float = 0, saturation: Float = 0, luminance: Float = 0) {
        self.hue = hue
        self.saturation = saturation
        self.luminance = luminance
    }
    public var isNeutral: Bool { abs(hue) < 0.5 && abs(saturation) < 0.5 && abs(luminance) < 0.5 }
}

/// Selektive Farben: nur der gewählte Farbbereich ändert sich (weiche Übergänge, Grau bleibt grau).
public enum ColorBand: String, Hashable, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case red = "RED", orange = "ORANGE", yellow = "YELLOW", green = "GREEN", aqua = "AQUA", blue = "BLUE",
         purple = "PURPLE", magenta = "MAGENTA"

    public var centerDeg: Float {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .aqua: 180
        case .blue: 225
        case .purple: 270
        case .magenta: 315
        }
    }
}

public struct ColorMix: Hashable, Codable, Sendable {
    public var shifts: [ColorBand: HslShift]
    public init(shifts: [ColorBand: HslShift] = [:]) { self.shifts = shifts }
    public var isNeutral: Bool { shifts.values.allSatisfy(\.isNeutral) }
    public subscript(_ b: ColorBand) -> HslShift { shifts[b] ?? HslShift() }
    public func with(_ b: ColorBand, _ s: HslShift) -> ColorMix {
        var m = shifts
        m[b] = s
        return ColorMix(shifts: m)
    }
}

/// Normierter Punkt (0…1) im Ausgabebild.
public struct NormPoint: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float
    public init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
}

/// Pinselstrich (Ausgabekoordinaten 0…1, Radius relativ zur langen Kante, Härte 0…1).
public struct BrushStroke: Hashable, Codable, Sendable {
    public var points: [NormPoint]
    public var radius: Float
    public var hardness: Float = 0.5
    public var erase = false
    public init(points: [NormPoint], radius: Float, hardness: Float = 0.5, erase: Bool = false) {
        self.points = points
        self.radius = radius
        self.hardness = hardness
        self.erase = erase
    }
}

/// Maske einer lokalen Anpassung. Rein manuell (keine Erkennung).
public enum Mask: Hashable, Codable, Sendable {
    /// Ellipse um `center` mit Halbachsen relativ zur Bildbreite/-höhe, `feather` 0…1 weiche Kante.
    case radial(center: NormPoint, rx: Float, ry: Float, feather: Float, invert: Bool)
    /// Verlauf von `start` (voll) nach `end` (null).
    case linear(start: NormPoint, end: NormPoint)
    case brush(strokes: [BrushStroke])
}

/// Lokale Anpassung: Maske + Regler (nur punktweise Regler wirken lokal).
public struct LocalAdjustment: Hashable, Codable, Sendable {
    public var mask: Mask
    public var adjust: Adjustments
    public init(mask: Mask, adjust: Adjustments = Adjustments()) {
        self.mask = mask
        self.adjust = adjust
    }
}

/// Viereck (normiert): oben links, oben rechts, unten rechts, unten links.
public struct Quad: Hashable, Codable, Sendable {
    public var tl = NormPoint(0, 0)
    public var tr = NormPoint(1, 0)
    public var br = NormPoint(1, 1)
    public var bl = NormPoint(0, 1)

    public init(tl: NormPoint = NormPoint(0, 0), tr: NormPoint = NormPoint(1, 0), br: NormPoint = NormPoint(1, 1),
                bl: NormPoint = NormPoint(0, 1)) {
        self.tl = tl
        self.tr = tr
        self.br = br
        self.bl = bl
    }

    public static let full = Quad()

    public var isIdentity: Bool {
        [tl.x, tl.y, tr.x - 1, tr.y, br.x - 1, br.y - 1, bl.x, bl.y - 1].allSatisfy { abs($0) < NormRect.eps }
    }
    public var corners: [NormPoint] { [tl, tr, br, bl] }

    /// Nach Vierteldrehung des Rahmens im Uhrzeigersinn (Ecken wandern mit).
    public func rotatedClockwise() -> Quad {
        func r(_ p: NormPoint) -> NormPoint { NormPoint(1 - p.y, p.x) }
        return Quad(tl: r(bl), tr: r(tl), br: r(tr), bl: r(br))
    }
    public func flippedH() -> Quad {
        func f(_ p: NormPoint) -> NormPoint { NormPoint(1 - p.x, p.y) }
        return Quad(tl: f(tr), tr: f(tl), br: f(bl), bl: f(br))
    }
    public func flippedV() -> Quad {
        func f(_ p: NormPoint) -> NormPoint { NormPoint(p.x, 1 - p.y) }
        return Quad(tl: f(bl), tr: f(br), br: f(tr), bl: f(tl))
    }
}

/// Rote Augen: Kreis um die Pupille (Ausgabekoordinaten, Radius relativ zur langen Kante). Klassische Farbregel.
public struct RedEyeSpot: Hashable, Codable, Sendable {
    public var center: NormPoint
    public var radius: Float
    public init(center: NormPoint, radius: Float) {
        self.center = center
        self.radius = radius
    }
}

/// Fest eingebaute Filter (reine Farbmatrizen, kein Download).
public enum FilterId: String, Hashable, Codable, Sendable, CaseIterable {
    case none = "NONE", mono = "MONO", monoContrast = "MONO_CONTRAST", warm = "WARM", cool = "COOL", sepia = "SEPIA",
         fade = "FADE", vivid = "VIVID"
}

/// Nicht destruktive Bearbeitung eines Fotos. Wird erst beim Speichern angewendet; Vorschau und Export nutzen dieselbe
/// Beschreibung (gleicher Core-Image-Graph, andere Auflösung).
public struct EditRecipe: Hashable, Codable, Sendable {
    /// Vierteldrehungen im Uhrzeigersinn (0…3).
    public var quarterTurns = 0
    public var flipH = false
    public var flipV = false
    /// Begradigen in Grad (−45…45), Bild wird so vergrößert, dass keine leeren Ecken entstehen.
    public var straighten: Float = 0
    public var crop = NormRect.full
    public var adjust = Adjustments()
    public var filter = FilterId.none
    /// Filterstärke 0…1.
    public var filterIntensity: Float = 1
    /// Zielgröße in Pixeln; `nil` = Größe des Ausschnitts. Nie größer als der Ausschnitt.
    public var resizeWidth: Int?
    public var resizeHeight: Int?
    public var colorMix = ColorMix()
    public var locals: [LocalAdjustment] = []
    /// Markieren: Text, Sticker, Zeichnungen, Formen, Abdeckungen (in dieser Reihenfolge gezeichnet).
    public var layers: [Layer] = []
    public var frame: FrameStyle?
    /// Perspektive im Grundrahmen (nach Drehen/Begradigen); `nil` = keine. Kostenlos wie Zuschneiden.
    public var perspective: Quad?
    /// Rote-Augen-Korrektur (kostenlos).
    public var redEyes: [RedEyeSpot] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case quarterTurns, flipH, flipV, straighten, crop, adjust, filter, filterIntensity, resizeWidth, resizeHeight,
             colorMix, locals, layers, frame, perspective, redEyes
    }

    /// Fehlende Felder (ältere Entwürfe) = Standardwerte.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quarterTurns = try c.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false
        flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false
        straighten = try c.decodeIfPresent(Float.self, forKey: .straighten) ?? 0
        crop = try c.decodeIfPresent(NormRect.self, forKey: .crop) ?? .full
        adjust = try c.decodeIfPresent(Adjustments.self, forKey: .adjust) ?? Adjustments()
        filter = try c.decodeIfPresent(FilterId.self, forKey: .filter) ?? .none
        filterIntensity = try c.decodeIfPresent(Float.self, forKey: .filterIntensity) ?? 1
        resizeWidth = try c.decodeIfPresent(Int.self, forKey: .resizeWidth)
        resizeHeight = try c.decodeIfPresent(Int.self, forKey: .resizeHeight)
        colorMix = try c.decodeIfPresent(ColorMix.self, forKey: .colorMix) ?? ColorMix()
        locals = try c.decodeIfPresent([LocalAdjustment].self, forKey: .locals) ?? []
        layers = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? []
        frame = try c.decodeIfPresent(FrameStyle.self, forKey: .frame)
        perspective = try c.decodeIfPresent(Quad.self, forKey: .perspective)
        redEyes = try c.decodeIfPresent([RedEyeSpot].self, forKey: .redEyes) ?? []
    }

    public var turns: Int { ((quarterTurns % 4) + 4) % 4 }
    public var hasPerspective: Bool { perspective.map { !$0.isIdentity } ?? false }
    public var hasGeometry: Bool {
        turns != 0 || flipH || flipV || abs(straighten) > 0.01 || !crop.isFull || hasPerspective
    }
    public var hasRedEye: Bool { !redEyes.isEmpty }
    /// Ändert Pixelwerte (Tonwerte, Farbe, Filter, Vignette, Körnung, Farbmischer, lokale Anpassungen).
    public var hasColor: Bool {
        !adjust.colorNeutral || (filter != .none && filterIntensity > 0.001) || !colorMix.isNeutral
            || locals.contains { !$0.adjust.pointNeutral }
    }
    /// Schärfen, Klarheit oder Rauschreduzierung (Nachbarpixel nötig).
    public var hasSharpen: Bool { !adjust.detailNeutral }
    public var hasResize: Bool { resizeWidth != nil && resizeHeight != nil }
    public var hasLayers: Bool { !layers.isEmpty }
    public var hasFrame: Bool { frame.map { !$0.isNeutral } ?? false }
    public var isIdentity: Bool {
        !hasGeometry && !hasColor && !hasSharpen && !hasResize && !hasLayers && !hasFrame && !hasRedEye
    }
    public var hasPixelOps: Bool { hasColor || hasRedEye }

    /// Nur Drehen/Spiegeln – bei JPEG/HEIC verlustfrei über die EXIF-Ausrichtung möglich.
    public var isOrientationOnly: Bool {
        (turns != 0 || flipH || flipV) && abs(straighten) <= 0.01 && crop.isFull && !hasPerspective && !hasRedEye
            && !hasColor && !hasSharpen && !hasResize && !hasLayers && !hasFrame
    }

    /// Pro-Werkzeuge (Regler, Filter, Größe, Rahmen) – Zuschneiden/Drehen und Markieren sind kostenlos.
    public var usesProTools: Bool { hasColor || hasSharpen || hasResize || hasFrame }

    public func rotatedClockwise() -> EditRecipe {
        var r = self
        r.quarterTurns = (turns + 1) % 4
        r.crop = crop.rotatedClockwise()
        r.perspective = perspective?.rotatedClockwise()
        r.resizeWidth = nil
        r.resizeHeight = nil
        return r
    }

    /// Nur die Pro-pflichtigen Teile entfernen („Nur Zuschnitt speichern“).
    public func withoutProTools() -> EditRecipe {
        var r = self
        r.adjust = Adjustments()
        r.filter = .none
        r.filterIntensity = 1
        r.colorMix = ColorMix()
        r.locals = []
        r.resizeWidth = nil
        r.resizeHeight = nil
        r.frame = nil
        return r
    }
}

/// Speicherart, die der Nutzer im Speichern-Blatt wählt. Vorauswahl immer `.copy`.
public enum SaveMode: String, Hashable, Codable, Sendable, CaseIterable {
    /// Als Kopie speichern; Original bleibt unverändert.
    case copy = "COPY"
    /// Kopie speichern und Original in „Zuletzt gelöscht“ (Systembestätigung).
    case replace = "REPLACE"
    /// iOS: Original nicht destruktiv bearbeiten (`PHContentEditingOutput`, in der Fotos-App rücksetzbar). E15.
    case editOriginal = "EDIT_ORIGINAL"
}

/// Video-Schnitt in Millisekunden.
public struct TrimRange: Hashable, Codable, Sendable {
    public var startMs: Int64
    public var endMs: Int64
    public init(startMs: Int64, endMs: Int64) {
        self.startMs = startMs
        self.endMs = endMs
    }
    public var durationMs: Int64 { endMs - startMs }
    public static let minMs: Int64 = 1_000

    public static func clamp(start: Int64, end: Int64, totalMs: Int64) -> TrimRange {
        let s = min(max(start, 0), max(0, totalMs - minMs))
        let e = min(max(end, s + minMs), max(s + minMs, totalMs))
        return TrimRange(startMs: s, endMs: min(e, totalMs))
    }
}

/// Eigene Vorlage: nur Einstellungen (Regler, Filter, Farbmischer) – keine Bilder, keine Geometrie. Bleibt lokal.
public struct EditPreset: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var adjust: Adjustments
    public var filter: FilterId
    public var filterIntensity: Float
    public var colorMix: ColorMix

    public init(id: String = UUID().uuidString, name: String, adjust: Adjustments, filter: FilterId = .none,
                filterIntensity: Float = 1, colorMix: ColorMix = ColorMix()) {
        self.id = id
        self.name = String(name.prefix(40))
        self.adjust = adjust
        self.filter = filter
        self.filterIntensity = filterIntensity
        self.colorMix = colorMix
    }

    public static func of(name: String, recipe r: EditRecipe, id: String = UUID().uuidString) -> EditPreset {
        EditPreset(id: id, name: name, adjust: r.adjust, filter: r.filter, filterIntensity: r.filterIntensity,
                   colorMix: r.colorMix)
    }

    /// Übernimmt Farbe/Tonwerte; Zuschnitt, Größe und lokale Masken des Fotos bleiben.
    public func apply(to r: EditRecipe) -> EditRecipe {
        var n = r
        n.adjust = adjust
        n.filter = filter
        n.filterIntensity = filterIntensity
        n.colorMix = colorMix
        return n
    }
}

/// Ausgabeformat je Quelle: Format bleibt (HEIC bleibt HEIC auf iOS), unbekannt → JPEG.
public enum EditFormat: String, Hashable, Codable, Sendable {
    case jpeg, png, heic

    public var utType: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        case .heic: "public.heic"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        }
    }

    public static func forSource(uti: String?) -> EditFormat {
        switch uti?.lowercased() {
        case "public.png": .png
        case "public.heic", "public.heif": .heic
        default: .jpeg
        }
    }

    public static let quality: Double = 0.95
}

/// Art eines von PhotoMaid gespeicherten Ergebnisses.
public enum EditKind: String, Hashable, Codable, Sendable {
    case edit = "EDIT", collage = "COLLAGE", merge = "MERGE", slideshow = "SLIDESHOW", gif = "GIF", frame = "FRAME",
         compress = "COMPRESS", convert = "CONVERT", pdf = "PDF", cutout = "CUTOUT"
}

/// Ein von PhotoMaid gespeichertes Ergebnis (nur lokal, für die Liste „Bearbeitet“).
public struct EditRecord: Hashable, Codable, Sendable, Identifiable {
    public let newId: String
    public let sourceId: String
    public let mode: SaveMode
    public let video: Bool
    public let atMs: Int64
    public let kind: EditKind
    public let count: Int

    public init(newId: String, sourceId: String, mode: SaveMode, video: Bool, atMs: Int64, kind: EditKind = .edit,
                count: Int = 0) {
        self.newId = newId
        self.sourceId = sourceId
        self.mode = mode
        self.video = video
        self.atMs = atMs
        self.kind = kind
        self.count = count
    }

    public var id: String { newId }
}

/// Dateiname der Kopie: „IMG_1234_bearbeitet.jpg“ (Zusatz aus den Texten).
public enum EditNames {
    public static func copyName(original: String?, suffix: String, fileExtension: String) -> String {
        "\(cleanBase(original))_\(suffix).\(fileExtension)"
    }

    public static func sameName(original: String?, fileExtension: String) -> String {
        "\(cleanBase(original)).\(fileExtension)"
    }

    static func cleanBase(_ original: String?) -> String {
        var base = original ?? ""
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
        if base.trimmingCharacters(in: .whitespaces).isEmpty { base = "PhotoMaid" }
        let bad = Set("\\/:*?\"<>|")
        return String(String(base.map { bad.contains($0) ? "_" : $0 }).prefix(80))
    }
}
