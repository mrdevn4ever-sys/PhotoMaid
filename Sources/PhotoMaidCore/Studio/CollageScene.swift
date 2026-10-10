import Foundation

/// Ein Foto auf der Collage-Fläche. Alle Werte normiert auf die Ausgabe (x auf die Breite, y auf die Höhe).
/// Vorschau und Export zeichnen dieselben Zahlen: `source` hat immer das Seitenverhältnis von `photo` (nie verzerrt),
/// gedreht wird um die Mitte von `frame`.
public struct CollagePlacement: Hashable, Sendable {
    /// Index in `CollageProject.items`.
    public let index: Int
    /// Feld (Raster), Sofortbild samt Rand (Frei) bzw. Fotofläche – ungedreht. Dient auch zum Antippen.
    public let frame: NormRect
    /// Fotofläche, ungedreht (beim Einpassen kleiner als das Feld).
    public let photo: NormRect
    /// Sichtbarer Ausschnitt des Fotos nach Vierteldrehung und Spiegeln (0…1).
    public let source: NormRect
    /// Grad im Uhrzeigersinn um die Mitte von `frame` (nur Frei).
    public let rotation: Float
    /// Weißer Sofortbild-Rand mit Schatten (nur Frei).
    public let polaroid: Bool
    /// Eckenradien von `frame` und `photo`, relativ zur kürzeren Ausgabekante.
    public let frameCorner: Float
    public let photoCorner: Float

    public init(index: Int, frame: NormRect, photo: NormRect, source: NormRect, rotation: Float = 0, polaroid: Bool = false,
                frameCorner: Float = 0, photoCorner: Float = 0) {
        self.index = index
        self.frame = frame
        self.photo = photo
        self.source = source
        self.rotation = rotation
        self.polaroid = polaroid
        self.frameCorner = frameCorner
        self.photoCorner = photoCorner
    }
}

/// Fertig berechnete Collage: Seitenverhältnis und Lage jedes Fotos (Zeichenreihenfolge = Reihenfolge der Liste).
public struct CollageScene: Hashable, Sendable {
    /// Breite/Höhe der Ausgabe.
    public let aspect: Float
    public let placements: [CollagePlacement]

    public init(aspect: Float, placements: [CollagePlacement]) {
        self.aspect = aspect
        self.placements = placements
    }

    /// Oberstes Foto unter dem Punkt (normiert auf die Collage), Drehung berücksichtigt.
    public func hit(_ x: Float, _ y: Float) -> Int? {
        let a = max(aspect, 0.0001)
        for p in placements.reversed() {
            let f = p.frame
            let cx = (f.left + f.right) / 2, cy = (f.top + f.bottom) / 2
            // In gleichmäßige Einheiten (Breite) umrechnen, zurückdrehen, wieder normieren.
            let dx = x - cx, dy = (y - cy) / a
            let rad = -p.rotation * .pi / 180
            let rx = dx * cos(rad) - dy * sin(rad), ry = dx * sin(rad) + dy * cos(rad)
            let px = cx + rx, py = cy + ry * a
            if px >= f.left && px <= f.right && py >= f.top && py <= f.bottom { return p.index }
        }
        return nil
    }
}

/// Eine Geometrie für Vorschau und Export (Raster, Frei, Streifen).
public enum CollageGeometry {
    /// Längste Kante eines Streifens in Pixeln (Speicher).
    public static let stripMaxEdge = 16_000
    /// Höchstens so viele Pixel je Collage (≈ 128 MB Bitmap).
    public static let maxPixels: Int64 = 32_000_000
    /// Bezugsgröße für die Streifen-Geometrie (es zählen nur Verhältnisse).
    static let stripUnit = 1_000
    /// Sofortbild-Rand relativ zur Fotobreite: seitlich/oben und unten.
    public static let polaroidSide: Float = 0.05
    public static let polaroidBottom: Float = 0.18

    /// Seitenverhältnis nach Vierteldrehungen.
    public static func turnedAspect(_ aspect: Float, quarterTurns: Int) -> Float {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1
        return ((quarterTurns % 4) + 4) % 4 % 2 == 0 ? a : 1 / a
    }

    /// Umrechnung normierter Breiten/Höhen in Einheiten der kürzeren Kante.
    static func shortUnits(_ aspect: Float) -> (x: Float, y: Float) {
        aspect >= 1 ? (aspect, 1) : (1, 1 / max(aspect, 0.0001))
    }

    static func maxCorner(_ r: NormRect, _ aspect: Float) -> Float {
        let u = shortUnits(aspect)
        return max(0, min(r.width * u.x, r.height * u.y) / 2)
    }

    /// `imageAspects[i]` = Breite/Höhe des aufrechten Fotos `i` (vor Vierteldrehung); unbekannt → quadratischer Platzhalter.
    public static func scene(_ p: CollageProject, imageAspects: [Float]) -> CollageScene {
        func turned(_ i: Int) -> Float {
            let raw = i < imageAspects.count ? imageAspects[i] : 1
            return turnedAspect(raw, quarterTurns: p.items[i].quarterTurns)
        }
        switch p.kind {
        case .grid: return grid(p, turned)
        case .free: return free(p, turned)
        case .strip: return strip(p, turned)
        }
    }

    private static func grid(_ p: CollageProject, _ turned: (Int) -> Float) -> CollageScene {
        let a = max(p.aspect, 0.0001)
        let cells = p.cellRects()
        let placements = p.items.indices.map { i -> CollagePlacement in
            let item = p.items[i], cell = cells[i], img = turned(i)
            let cellAspect = cell.width / max(cell.height, 0.0001) * a
            let corner = min(max(p.corner, 0), maxCorner(cell, a))
            if item.fit {
                let f = CellFit.fitRect(imgAspect: img, cellAspect: cellAspect)
                let photo = NormRect(left: cell.left + f.left * cell.width, top: cell.top + f.top * cell.height,
                                     right: cell.left + f.right * cell.width, bottom: cell.top + f.bottom * cell.height)
                let pc = min(corner, maxCorner(photo, a))
                return CollagePlacement(index: i, frame: cell, photo: photo, source: .full, frameCorner: corner, photoCorner: pc)
            }
            let src = CellFit.source(imgAspect: img, cellAspect: cellAspect, zoom: item.zoom, panX: item.panX, panY: item.panY,
                                     fit: false)
            return CollagePlacement(index: i, frame: cell, photo: cell, source: src, frameCorner: corner, photoCorner: corner)
        }
        return CollageScene(aspect: a, placements: placements)
    }

    private static func free(_ p: CollageProject, _ turned: (Int) -> Float) -> CollageScene {
        let a = max(p.aspect, 0.0001)
        let u = shortUnits(a)
        let placements = p.items.indices.map { i -> CollagePlacement in
            let item = p.items[i], img = turned(i)
            let w = FreeLayout.clampWidth(item.width)
            // Höhen zunächst in Einheiten der Collage-Breite, dann auf die Höhe umgerechnet (× Seitenverhältnis).
            let photoH = w / img
            let side = p.polaroid ? w * polaroidSide : 0
            let bottom = p.polaroid ? w * polaroidBottom : 0
            let fw = w + 2 * side, fh = photoH + side + bottom
            let c = item.center
            let frame = NormRect(left: c.x - fw / 2, top: c.y - fh * a / 2, right: c.x + fw / 2, bottom: c.y + fh * a / 2)
            let photo = NormRect(left: frame.left + side, top: frame.top + side * a, right: frame.right - side,
                                 bottom: frame.top + side * a + photoH * a)
            let fc = min(max(p.corner, 0), maxCorner(frame, a))
            let pc = p.polaroid ? min(max(0, fc - side * u.x), maxCorner(photo, a)) : fc
            return CollagePlacement(index: i, frame: frame, photo: photo, source: .full,
                                    rotation: FreeLayout.normalizedRotation(item.rotation), polaroid: p.polaroid,
                                    frameCorner: fc, photoCorner: pc)
        }
        return CollageScene(aspect: a, placements: placements)
    }

    private static func strip(_ p: CollageProject, _ turned: (Int) -> Float) -> CollageScene {
        guard !p.items.isEmpty else { return CollageScene(aspect: 1, placements: []) }
        let unit = stripUnit * 10
        let sizes = p.items.indices.map { i in PxSize(max(1, Int((Float(unit) * turned(i)).rounded())), unit) }
        let spacingPx = Int((max(p.spacing, 0) * Float(stripUnit)).rounded())
        let marginPx = Int((max(p.margin, 0) * Float(stripUnit)).rounded())
        let r = StripLayout.layout(sizes: sizes, items: p.items, vertical: p.stripVertical, spacingPx: spacingPx,
                                   targetCross: stripUnit, maxEdge: Int.max / 4)
        let sw = Float(r.size.width), sh = Float(r.size.height), m = Float(marginPx)
        let w = sw + 2 * m, h = sh + 2 * m
        let a = w / max(h, 1)
        let placements = r.placements.enumerated().map { i, pl -> CollagePlacement in
            let d = pl.dst
            let photo = NormRect(left: (m + d.left * sw) / w, top: (m + d.top * sh) / h,
                                 right: (m + d.right * sw) / w, bottom: (m + d.bottom * sh) / h)
            let corner = min(max(p.corner, 0), maxCorner(photo, a))
            return CollagePlacement(index: i, frame: photo, photo: photo, source: pl.src, frameCorner: corner, photoCorner: corner)
        }
        return CollageScene(aspect: a, placements: placements)
    }

    /// Ausgabegröße in Pixeln. Raster/Frei: `resolution` = längere Kante. Streifen: `resolution` = Breite (untereinander)
    /// bzw. Höhe (nebeneinander), begrenzt durch `stripMaxEdge`. Immer höchstens `maxPixels`, nie verzerrt.
    public static func outputSize(_ p: CollageProject, aspect: Float, resolution: Int) -> PxSize {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1
        var w: Float, h: Float
        if p.kind == .strip {
            let cross = Float(max(16, resolution))
            if p.stripVertical { w = cross; h = cross / a } else { h = cross; w = cross * a }
            let longest = max(w, h)
            if longest > Float(stripMaxEdge) {
                let s = Float(stripMaxEdge) / longest
                w *= s; h *= s
            }
        } else {
            let s = CollageExport.size(aspect: a, longEdge: CollageExport.clampLong(resolution))
            w = Float(s.width); h = Float(s.height)
        }
        if Double(w) * Double(h) > Double(maxPixels) {
            let s = Float((Double(maxPixels) / (Double(w) * Double(h))).squareRoot())
            w *= s; h *= s
        }
        return PxSize(max(1, Int(w.rounded(.down))), max(1, Int(h.rounded(.down))))
    }

    /// Nötige längere Kante des Quellfotos in Pixeln, damit es in der Ausgabe nicht hochgerechnet werden muss –
    /// begrenzt auf `cap`. So werden nie mehr Pixel geladen als gebraucht (gilt für gedrehte wie ungedrehte Fotos).
    public static func neededSourceEdge(_ pl: CollagePlacement, output: PxSize, cap: Int) -> Int {
        let pw = pl.photo.width * Float(output.width), ph = pl.photo.height * Float(output.height)
        let fullW = pw / max(pl.source.width, 0.0001), fullH = ph / max(pl.source.height, 0.0001)
        let need = Int(max(fullW, fullH).rounded(.up))
        return min(max(need, 64), max(64, cap))
    }
}

/// Lesbare Form einer Vorlagen-ID (für Vorschaubilder und VoiceOver).
public enum CollageTemplateShape: Hashable, Sendable {
    case grid
    case rows([Int])
    case columns([Int])
    /// Seite des großen Fotos: "l", "r", "t", "b".
    case big(side: String)
}

extension CollageLayout {
    public static func shape(_ id: String) -> CollageTemplateShape {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "grid", arg = parts.count > 1 ? parts[1] : ""
        let counts = arg.split(separator: ",").compactMap { Int($0) }
        switch kind {
        case "r" where !counts.isEmpty: return .rows(counts)
        case "c" where !counts.isEmpty: return .columns(counts)
        case "big": return .big(side: ["l", "r", "t", "b"].contains(arg) ? arg : "l")
        default: return .grid
        }
    }

    /// Angebotene Vorlagen in sinnvoller Reihenfolge: ausgewogen, Magazin, zwei Reihen, drei Reihen, eine Reihe
    /// (nur bei wenigen Fotos weit vorn). Ohne Doppelte, höchstens `limit`.
    public static func featured(for n: Int, limit: Int = 24) -> [String] {
        func rank(_ id: String) -> Int {
            switch shape(id) {
            case .grid: return 0
            case .big: return 1
            case .rows(let c), .columns(let c):
                switch c.count {
                case 1: return n <= 3 ? 1 : 4
                case 2: return 2
                default: return 3
                }
            }
        }
        let all = templates(for: n)
        let sorted = all.enumerated().sorted { lhs, rhs in
            let a = rank(lhs.element), b = rank(rhs.element)
            return a != b ? a < b : lhs.offset < rhs.offset
        }
        return Array(sorted.map(\.element).prefix(max(1, limit)))
    }
}

extension CollageProject {
    /// Griffpunkte der Trennlinien (normiert auf die Collage, Ränder eingerechnet, mittig auf der Linie).
    public func dividerHandles() -> [(divider: Divider, point: NormPoint)] {
        guard kind == .grid else { return [] }
        let m = marginUnits()
        return CollageLayout.dividers(tree).map { d in
            let midX = (d.span.left + d.span.right) / 2, midY = (d.span.top + d.span.bottom) / 2
            return (d, NormPoint(m.x + midX * (1 - 2 * m.x), m.y + midY * (1 - 2 * m.y)))
        }
    }

    /// Trennlinie auf eine Position der Collage setzen (normiert, Ränder herausgerechnet).
    public func movingDivider(_ d: Divider, toCanvas value: Float) -> CollageProject {
        let m = marginUnits()
        let mm = d.vertical ? m.x : m.y
        let unit = (value - mm) / Swift.max(1 - 2 * mm, 0.0001)
        var p = self
        p.tree = CollageLayout.moveDivider(tree, d, to: unit)
        return p
    }

    private func marginUnits() -> (x: Float, y: Float) {
        let ar = aspect
        let sx: Float = ar >= 1 ? 1 / ar : 1, sy: Float = ar >= 1 ? 1 : ar
        return (margin * sx, margin * sy)
    }

    /// Foto nach oben legen (Frei: Zeichenreihenfolge).
    public func bringingToFront(_ i: Int) -> CollageProject {
        guard items.indices.contains(i), i != items.count - 1 else { return self }
        var p = self
        let item = p.items.remove(at: i)
        p.items.append(item)
        return p
    }

    /// Foto `i` durch ein anderes ersetzen (Lage bleibt, Ausschnitt startet neu).
    public func replacingItem(_ i: Int, with mediaId: String) -> CollageProject {
        guard items.indices.contains(i) else { return self }
        var p = self
        var item = p.items[i].resetPan()
        item.mediaId = mediaId
        item.quarterTurns = 0
        item.flipH = false
        item.trimStart = 0
        item.trimEnd = 0
        p.items[i] = item
        return p
    }

    /// Art wechseln: Raster bekommt seine Vorlage zurück; nichts anderes geht verloren.
    public func withKind(_ k: CollageKind) -> CollageProject {
        var p = self
        p.kind = k
        p.tree = CollageLayout.template(template, items.count)
        return p
    }
}

extension CellFit {
    /// Neue Verschiebung nach Ziehen um `dx`/`dy` (Anteil der Feldbreite/-höhe): das Foto folgt dem Finger.
    public static func panned(panX: Float, panY: Float, zoom: Float, imgAspect: Float, cellAspect: Float, dx: Float,
                              dy: Float) -> (x: Float, y: Float) {
        let s = source(imgAspect: imgAspect, cellAspect: cellAspect, zoom: zoom, panX: 0, panY: 0, fit: false)
        func move(_ pan: Float, _ d: Float, _ w: Float) -> Float {
            let slack = (1 - w) / 2
            guard slack > 0.0001 else { return min(max(pan, -1), 1) }
            return min(max(pan - d * w / slack, -1), 1)
        }
        return (move(panX, dx, s.width), move(panY, dy, s.height))
    }

    public static let maxZoom: Float = 5

    public static func zoomed(_ zoom: Float, by factor: Float) -> Float { min(max(zoom * factor, 1), maxZoom) }
}

extension FreeLayout {
    public static func clampWidth(_ w: Float) -> Float { min(max(w, 0.08), 1.2) }

    public static func moved(_ c: NormPoint, dx: Float, dy: Float) -> NormPoint {
        NormPoint(min(max(c.x + dx, 0), 1), min(max(c.y + dy, 0), 1))
    }

    /// Grad auf −180…180.
    public static func normalizedRotation(_ deg: Float) -> Float {
        guard deg.isFinite else { return 0 }
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        return d
    }
}
