import Foundation

/// ARGB-Farbe wie Android (`Int`, auch negativ). `argb` liefert die vorzeichenlose Darstellung.
public typealias ARGB = Int64

/// Hilfen für `ARGB` (bewusst keine Erweiterung von `Int64`).
public enum ARGBColor {
    /// (r, g, b, a) in 0…1.
    public static func components(_ c: ARGB) -> (r: Float, g: Float, b: Float, a: Float) {
        let v = UInt32(truncatingIfNeeded: c)
        return (Float((v >> 16) & 0xFF) / 255, Float((v >> 8) & 0xFF) / 255, Float(v & 0xFF) / 255,
                Float((v >> 24) & 0xFF) / 255)
    }

    public static func make(r: Float, g: Float, b: Float, a: Float = 1) -> ARGB {
        func q(_ v: Float) -> UInt32 { UInt32(min(max(v * 255 + 0.5, 0), 255)) }
        let packed: UInt32 = (q(a) << 24) | (q(r) << 16) | (q(g) << 8) | q(b)
        return ARGB(Int32(bitPattern: packed))
    }
}

public enum TextStyle: String, Hashable, Codable, Sendable, CaseIterable {
    case fill = "FILL", outline = "OUTLINE", pill = "PILL", shadow = "SHADOW"
}

public enum TextAlign: String, Hashable, Codable, Sendable, CaseIterable { case start = "START", center = "CENTER", end = "END" }

/// Systemschriften (alle Sprachen inkl. Arabisch/CJK über die Rückfall-Schriften des Systems).
public enum FontId: String, Hashable, Codable, Sendable, CaseIterable {
    case sans = "SANS", sansBold = "SANS_BOLD", black = "BLACK", condensed = "CONDENSED", serif = "SERIF",
         mono = "MONO", handwriting = "HANDWRITING", casual = "CASUAL", smallCaps = "SMALLCAPS"
}

public struct TextLayer: Hashable, Codable, Sendable {
    public var id: String
    public var text: String
    public var center = NormPoint(0.5, 0.5)
    /// Schriftgröße relativ zur kürzeren Bildkante.
    public var size: Float = 0.08
    public var rotation: Float = 0
    public var color: ARGB = 0xFFFF_FFFF
    /// Hintergrund (Pille) bzw. Kontur/Schatten.
    public var accent: ARGB = 0xFF00_0000
    public var style = TextStyle.shadow
    public var align = TextAlign.center
    public var font = FontId.sansBold
    public var opacity: Float = 1

    public init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }
}

public enum StickerKind: String, Hashable, Codable, Sendable, CaseIterable {
    case emoji = "EMOJI", arrow = "ARROW", heart = "HEART", star = "STAR", check = "CHECK", cross = "CROSS",
         bubble = "BUBBLE", circle = "CIRCLE", sparkle = "SPARKLE", date = "DATE"
}

public struct StickerLayer: Hashable, Codable, Sendable {
    public var id: String
    public var kind: StickerKind
    /// Emoji-Zeichen bzw. Text (Datum).
    public var value = ""
    public var center = NormPoint(0.5, 0.5)
    public var size: Float = 0.2
    public var rotation: Float = 0
    public var color: ARGB = 0xFFFF_FFFF
    public var opacity: Float = 1

    public init(id: String = UUID().uuidString, kind: StickerKind, value: String = "") {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

public enum BrushKind: String, Hashable, Codable, Sendable, CaseIterable {
    case pen = "PEN", marker = "MARKER", neon = "NEON", eraser = "ERASER"
}

public struct DrawStroke: Hashable, Codable, Sendable {
    public var points: [NormPoint]
    public var width: Float
    public var color: ARGB
    public var brush = BrushKind.pen
    public init(points: [NormPoint], width: Float, color: ARGB, brush: BrushKind = .pen) {
        self.points = points
        self.width = width
        self.color = color
        self.brush = brush
    }
}

/// Freihand (eine Ebene je Zeichenvorgang; der Radierer wirkt nur auf Zeichnungen derselben Ebene).
public struct DrawLayer: Hashable, Codable, Sendable {
    public var id: String
    public var strokes: [DrawStroke]
    public init(id: String = UUID().uuidString, strokes: [DrawStroke]) {
        self.id = id
        self.strokes = strokes
    }
}

public enum ShapeKind: String, Hashable, Codable, Sendable, CaseIterable {
    case arrow = "ARROW", rect = "RECT", ellipse = "ELLIPSE", line = "LINE"
}

public struct ShapeLayer: Hashable, Codable, Sendable {
    public var id: String
    public var kind: ShapeKind
    public var start: NormPoint
    public var end: NormPoint
    public var color: ARGB = 0xFFFF_3B30
    public var width: Float = 0.012
    public var filled = false
    public var opacity: Float = 1

    public init(id: String = UUID().uuidString, kind: ShapeKind, start: NormPoint, end: NormPoint) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
    }
}

public enum RedactMode: String, Hashable, Codable, Sendable, CaseIterable {
    /// Deckend (empfohlen für Sensibles): Pixel werden vollständig ersetzt.
    case solid = "SOLID"
    case pixelate = "PIXELATE"
    case blur = "BLUR"
}

/// Abdecken: Rechteck oder Pinsel. Wird beim Export **in die Pixel gerechnet** (nie nur überlagert).
public struct RedactLayer: Hashable, Codable, Sendable {
    public var id: String
    public var mode = RedactMode.solid
    public var rect: NormRect?
    public var strokes: [BrushStroke] = []
    public var color: ARGB = 0xFF00_0000
    /// Blockgröße/Unschärfe relativ zur kürzeren Kante (0…1 → 1…6 %).
    public var strength: Float = 0.6

    public init(id: String = UUID().uuidString, mode: RedactMode = .solid, rect: NormRect? = nil,
                strokes: [BrushStroke] = []) {
        self.id = id
        self.mode = mode
        self.rect = rect
        self.strokes = strokes
    }

    /// Blockgröße in Pixeln für ein Ausgabebild mit kürzerer Kante `short`: mindestens 8 px, nie fein.
    public func blockPx(short: Int) -> Int {
        max(8, Int((Float(short) * (0.01 + 0.05 * clamp01(strength))).rounded()))
    }
}

/// Ebenen über dem Bild (Markieren). Koordinaten normiert auf das Ausgabebild (nach Zuschnitt), Größen relativ zur
/// kürzeren Kante → gleiche Wirkung in Vorschau, 100-%-Ansicht und Export. Alles setzt der Nutzer selbst.
public enum Layer: Hashable, Sendable, Identifiable {
    case text(TextLayer)
    case sticker(StickerLayer)
    case draw(DrawLayer)
    case shape(ShapeLayer)
    case redact(RedactLayer)

    public var id: String {
        switch self {
        case .text(let l): l.id
        case .sticker(let l): l.id
        case .draw(let l): l.id
        case .shape(let l): l.id
        case .redact(let l): l.id
        }
    }

    public func moved(dx: Float, dy: Float) -> Layer {
        func mv(_ p: NormPoint) -> NormPoint { NormPoint(p.x + dx, p.y + dy) }
        switch self {
        case .text(var l): l.center = mv(l.center); return .text(l)
        case .sticker(var l): l.center = mv(l.center); return .sticker(l)
        case .draw(var l):
            l.strokes = l.strokes.map { var s = $0; s.points = s.points.map(mv); return s }
            return .draw(l)
        case .shape(var l): l.start = mv(l.start); l.end = mv(l.end); return .shape(l)
        case .redact(var l):
            l.rect = l.rect.map { NormRect(left: $0.left + dx, top: $0.top + dy, right: $0.right + dx, bottom: $0.bottom + dy) }
            l.strokes = l.strokes.map { var s = $0; s.points = s.points.map(mv); return s }
            return .redact(l)
        }
    }

    public func transformed(scale: Float, rotationDeg: Float) -> Layer {
        switch self {
        case .text(var l):
            l.size = min(max(l.size * scale, 0.01), 0.6); l.rotation = rotationDeg
            return .text(l)
        case .sticker(var l):
            l.size = min(max(l.size * scale, 0.03), 1.2); l.rotation = rotationDeg
            return .sticker(l)
        default: return self
        }
    }

    public func withID(_ newID: String) -> Layer {
        switch self {
        case .text(var l): l.id = newID; return .text(l)
        case .sticker(var l): l.id = newID; return .sticker(l)
        case .draw(var l): l.id = newID; return .draw(l)
        case .shape(var l): l.id = newID; return .shape(l)
        case .redact(var l): l.id = newID; return .redact(l)
        }
    }
}

// Gleiche Form wie kotlinx.serialization (Diskriminator „type“: text, sticker, draw, shape, redact).
extension Layer: Codable {
    private enum Kind: String, Codable { case text, sticker, draw, shape, redact }
    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let kind = try decoder.container(keyedBy: TypeKey.self).decode(Kind.self, forKey: .type)
        switch kind {
        case .text: self = .text(try TextLayer(from: decoder))
        case .sticker: self = .sticker(try StickerLayer(from: decoder))
        case .draw: self = .draw(try DrawLayer(from: decoder))
        case .shape: self = .shape(try ShapeLayer(from: decoder))
        case .redact: self = .redact(try RedactLayer(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .text(let l): try c.encode(Kind.text, forKey: .type); try l.encode(to: encoder)
        case .sticker(let l): try c.encode(Kind.sticker, forKey: .type); try l.encode(to: encoder)
        case .draw(let l): try c.encode(Kind.draw, forKey: .type); try l.encode(to: encoder)
        case .shape(let l): try c.encode(Kind.shape, forKey: .type); try l.encode(to: encoder)
        case .redact(let l): try c.encode(Kind.redact, forKey: .type); try l.encode(to: encoder)
        }
    }
}

/// Rahmen: innen über dem Bildrand oder außen (Bild wird größer), optional auf ein Seitenverhältnis (Passepartout).
public enum FrameMode: String, Hashable, Codable, Sendable { case inside = "INSIDE", outside = "OUTSIDE" }

public struct FrameStyle: Hashable, Codable, Sendable {
    public var mode = FrameMode.outside
    /// Breite relativ zur kürzeren Kante (0…0,25).
    public var width: Float = 0.04
    public var color: ARGB = 0xFFFF_FFFF
    /// Außen: Ziel-Seitenverhältnis Breite/Höhe (z. B. 0,8 für 4:5), `nil` = gleichmäßiger Rand.
    public var aspect: Float?
    /// Ecken des Bildes abrunden (relativ zur kürzeren Kante).
    public var corner: Float = 0

    public init(mode: FrameMode = .outside, width: Float = 0.04, color: ARGB = 0xFFFF_FFFF, aspect: Float? = nil,
                corner: Float = 0) {
        self.mode = mode
        self.width = width
        self.color = color
        self.aspect = aspect
        self.corner = corner
    }

    public var isNeutral: Bool { width < 0.001 && aspect == nil && corner < 0.001 }
}

public enum FrameMath {
    /// Größe nach dem Rahmen und Lage des Bildes darin (links, oben).
    public static func layout(image: PxSize, frame f: FrameStyle?) -> (size: PxSize, x: Int, y: Int) {
        guard let f, !f.isNeutral, f.mode == .outside else { return (image, 0, 0) }
        let b = Int((Float(min(image.width, image.height)) * min(max(f.width, 0), 0.25)).rounded())
        var w = image.width + 2 * b, h = image.height + 2 * b
        if let a = f.aspect {
            if Float(w) / Float(h) > a { h = Int((Float(w) / a).rounded()) } else { w = Int((Float(h) * a).rounded()) }
        }
        return (PxSize(w, h), (w - image.width) / 2, (h - image.height) / 2)
    }
}

/// Kleine Hilfen fürs Bearbeiten der Ebenenliste (Reihenfolge = Zeichenreihenfolge).
public enum LayerOps {
    public static func replace(_ list: [Layer], _ l: Layer) -> [Layer] { list.map { $0.id == l.id ? l : $0 } }
    public static func remove(_ list: [Layer], id: String) -> [Layer] { list.filter { $0.id != id } }
    public static func toFront(_ list: [Layer], id: String) -> [Layer] {
        guard let l = list.first(where: { $0.id == id }) else { return list }
        return list.filter { $0.id != id } + [l]
    }
    public static func toBack(_ list: [Layer], id: String) -> [Layer] {
        guard let l = list.first(where: { $0.id == id }) else { return list }
        return [l] + list.filter { $0.id != id }
    }
    public static func duplicate(_ list: [Layer], id: String, newID: String) -> [Layer] {
        guard let l = list.first(where: { $0.id == id }) else { return list }
        return list + [l.withID(newID).moved(dx: 0.03, dy: 0.03)]
    }

    /// Einrasten an Mitte (Hilfslinie) innerhalb `tol`.
    public static func snap(_ v: Float, target: Float = 0.5, tol: Float = 0.015) -> (value: Float, snapped: Bool) {
        abs(v - target) <= tol ? (target, true) : (v, false)
    }

    /// Drehung an 0/90/180/270° einrasten (±4°).
    public static func snapRotation(_ deg: Float, tol: Float = 4) -> (value: Float, snapped: Bool) {
        let n = (deg / 90).rounded() * 90
        return abs(deg - n) <= tol ? (n, true) : (deg, false)
    }
}
