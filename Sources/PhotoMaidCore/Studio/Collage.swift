import Foundation

/// Collage-Raster als Baum aus Teilungen. Jede Teilung hat ein Verhältnis (0…1), das der Nutzer über die Trennlinie
/// verschiebt; die Vorlage bleibt dabei sauber (keine Lücken, keine Überlappung).
public indirect enum SplitNode: Hashable, Sendable {
    case leaf(index: Int)
    /// `vertical` = Kinder nebeneinander (senkrechte Trennlinie), sonst übereinander.
    case split(vertical: Bool, ratio: Float, a: SplitNode, b: SplitNode)
}

extension SplitNode: Codable {
    private enum K: String, CodingKey { case type, index, vertical, ratio, a, b }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        if try c.decode(String.self, forKey: .type) == "leaf" {
            self = .leaf(index: try c.decode(Int.self, forKey: .index))
        } else {
            self = .split(vertical: try c.decode(Bool.self, forKey: .vertical), ratio: try c.decode(Float.self, forKey: .ratio),
                          a: try c.decode(SplitNode.self, forKey: .a), b: try c.decode(SplitNode.self, forKey: .b))
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .leaf(let i):
            try c.encode("leaf", forKey: .type); try c.encode(i, forKey: .index)
        case .split(let v, let r, let a, let b):
            try c.encode("split", forKey: .type); try c.encode(v, forKey: .vertical); try c.encode(r, forKey: .ratio)
            try c.encode(a, forKey: .a); try c.encode(b, forKey: .b)
        }
    }
}

/// Eine verschiebbare Trennlinie: Pfad zur Teilung (0 = a, 1 = b), Lage im Einheitsquadrat und Bereich der Teilung.
public struct Divider: Hashable, Sendable {
    public let path: [Int]
    public let vertical: Bool
    public let position: Float
    public let span: NormRect
    public let parent: NormRect
}

public enum CollageLayout {
    public static let minCell: Float = 0.08

    public static func leafCount(_ n: SplitNode) -> Int {
        switch n {
        case .leaf: 1
        case .split(_, _, let a, let b): leafCount(a) + leafCount(b)
        }
    }

    /// Rechtecke je Feld (Index → Rechteck im Einheitsquadrat).
    public static func cells(_ n: SplitNode, _ r: NormRect = .full) -> [Int: NormRect] {
        var out: [Int: NormRect] = [:]
        func walk(_ n: SplitNode, _ r: NormRect) {
            switch n {
            case .leaf(let i): out[i] = r
            case .split(_, _, let a, let b):
                let (ra, rb) = split(n, r)
                walk(a, ra); walk(b, rb)
            }
        }
        walk(n, r)
        return out
    }

    private static func split(_ n: SplitNode, _ r: NormRect) -> (NormRect, NormRect) {
        guard case .split(let vertical, let ratio, _, _) = n else { return (r, r) }
        if vertical {
            let x = r.left + r.width * ratio
            return (NormRect(left: r.left, top: r.top, right: x, bottom: r.bottom),
                    NormRect(left: x, top: r.top, right: r.right, bottom: r.bottom))
        }
        let y = r.top + r.height * ratio
        return (NormRect(left: r.left, top: r.top, right: r.right, bottom: y),
                NormRect(left: r.left, top: y, right: r.right, bottom: r.bottom))
    }

    public static func dividers(_ n: SplitNode, _ r: NormRect = .full, path: [Int] = []) -> [Divider] {
        guard case .split(let vertical, _, let a, let b) = n else { return [] }
        let (ra, rb) = split(n, r)
        let pos = vertical ? ra.right : ra.bottom
        let span = vertical ? NormRect(left: pos, top: r.top, right: pos, bottom: r.bottom)
            : NormRect(left: r.left, top: pos, right: r.right, bottom: pos)
        return [Divider(path: path, vertical: vertical, position: pos, span: span, parent: r)]
            + dividers(a, ra, path: path + [0]) + dividers(b, rb, path: path + [1])
    }

    /// Trennlinie `d` auf `position` (Einheitsquadrat) setzen – begrenzt, damit kein Feld zu klein wird.
    public static func moveDivider(_ root: SplitNode, _ d: Divider, to position: Float) -> SplitNode {
        let size = d.vertical ? d.parent.width : d.parent.height
        let start = d.vertical ? d.parent.left : d.parent.top
        let lo = minCell / max(size, 1e-4), hi = 1 - minCell / max(size, 1e-4)
        let ratio = min(max(min(max((position - start) / size, lo), hi), 0.05), 0.95)
        return withRatio(root, d.path[...], ratio)
    }

    private static func withRatio(_ n: SplitNode, _ path: ArraySlice<Int>, _ ratio: Float) -> SplitNode {
        guard case .split(let v, let r, let a, let b) = n else { return n }
        guard let first = path.first else { return .split(vertical: v, ratio: ratio, a: a, b: b) }
        let rest = path.dropFirst()
        return first == 0 ? .split(vertical: v, ratio: r, a: withRatio(a, rest, ratio), b: b)
            : .split(vertical: v, ratio: r, a: a, b: withRatio(b, rest, ratio))
    }

    /// Gleich große Teile entlang einer Achse.
    private static func even(_ ids: [SplitNode], vertical: Bool) -> SplitNode {
        ids.count == 1 ? ids[0]
            : .split(vertical: vertical, ratio: 1 / Float(ids.count), a: ids[0], b: even(Array(ids.dropFirst()), vertical: vertical))
    }

    /// Zeilen mit `counts` Fotos je Zeile (z. B. 1,2 = oben eins, unten zwei); `columns` = als Spalten.
    public static func rows(_ counts: [Int], columns: Bool = false) -> SplitNode {
        var i = 0
        let lines = counts.map { c -> SplitNode in
            let leaves = (0..<c).map { _ -> SplitNode in defer { i += 1 }; return .leaf(index: i) }
            return even(leaves, vertical: !columns)
        }
        return even(lines, vertical: columns)
    }

    /// Ein großes Feld plus Rest in einer Spalte/Zeile (Magazin).
    public static func big(_ n: Int, side: Character) -> SplitNode {
        let rest = (1..<max(1, n)).map { SplitNode.leaf(index: $0) }
        if rest.isEmpty { return .leaf(index: 0) }
        let restRows = rest.count <= 4 ? even(rest, vertical: side == "t" || side == "b")
            : renumber(rows([(rest.count + 1) / 2, rest.count / 2], columns: side == "l" || side == "r"), 1)
        let main = SplitNode.leaf(index: 0)
        switch side {
        case "l": return .split(vertical: true, ratio: 0.62, a: main, b: restRows)
        case "r": return .split(vertical: true, ratio: 0.38, a: restRows, b: main)
        case "t": return .split(vertical: false, ratio: 0.62, a: main, b: restRows)
        default: return .split(vertical: false, ratio: 0.38, a: restRows, b: main)
        }
    }

    private static func renumber(_ n: SplitNode, _ offset: Int) -> SplitNode {
        switch n {
        case .leaf(let i): .leaf(index: i + offset)
        case .split(let v, let r, let a, let b): .split(vertical: v, ratio: r, a: renumber(a, offset), b: renumber(b, offset))
        }
    }

    /// Vorlagen-ID → Baum. „r:1,2“ Zeilen, „c:2,1“ Spalten, „big:l“ Magazin, „grid“ ausgewogen.
    public static func template(_ id: String, _ n: Int) -> SplitNode {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "grid", arg = parts.count > 1 ? parts[1] : ""
        switch kind {
        case "r": return rows(arg.split(separator: ",").compactMap { Int($0) })
        case "c": return rows(arg.split(separator: ",").compactMap { Int($0) }, columns: true)
        case "big": return big(n, side: arg.first ?? "l")
        default: return rows(balanced(n))
        }
    }

    /// Ausgewogene Zeilen (z. B. 7 → 3,2,2; 10 → 4,3,3).
    public static func balanced(_ n: Int) -> [Int] {
        let rowsN = max(1, Int(sqrt(Double(n)).rounded()))
        let base = n / rowsN, extra = n % rowsN
        return (0..<rowsN).map { base + ($0 < extra ? 1 : 0) }.filter { $0 > 0 }
    }

    /// Alle angebotenen Vorlagen für `n` Fotos (2…20), sinnvoll sortiert, ohne Doppelte.
    public static func templates(for n: Int) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        add("grid")
        if (2...12).contains(n) {
            add("r:\(n)"); add("c:\(n)")
            for a in 1..<n { let b = n - a; if a <= 5 && b <= 5 { add("r:\(a),\(b)"); add("c:\(a),\(b)") } }
            if n >= 3 { for a in 1...4 { for b in 1...4 { let c = n - a - b; if (1...4).contains(c) { add("r:\(a),\(b),\(c)") } } } }
            add("big:l"); add("big:t"); add("big:r"); add("big:b")
        } else {
            let bal = balanced(n).map(String.init).joined(separator: ",")
            add("r:\(bal)"); add("c:\(bal)"); add("big:l"); add("big:t")
        }
        var seen = Set<String>()
        var res: [String] = []
        for id in out {
            let key = cells(template(id, n)).sorted { $0.key < $1.key }.map { r in
                [r.value.left, r.value.top, r.value.right, r.value.bottom].map { String(Int(($0 * 1000).rounded())) }
                    .joined(separator: ",")
            }.joined(separator: ";")
            if seen.insert(key).inserted { res.append(id) }
        }
        return Array(res.prefix(40))
    }
}

/// Art der Collage.
public enum CollageKind: String, Hashable, Codable, Sendable, CaseIterable { case grid = "GRID", free = "FREE", strip = "STRIP" }

/// Ein Foto der Collage mit eigener Lage im Feld (Zoom ≥ 1 füllt, Verschiebung −1…1) und einfachen Anpassungen.
public struct CollageItem: Hashable, Codable, Sendable {
    public var mediaId: String
    public var zoom: Float = 1
    public var panX: Float = 0
    public var panY: Float = 0
    public var quarterTurns = 0
    public var flipH = false
    /// Ganzes Foto zeigen (mit Hintergrund) statt Feld füllen.
    public var fit = false
    public var filter = FilterId.none
    public var filterIntensity: Float = 1
    public var adjust = Adjustments()
    // Frei
    public var center = NormPoint(0.5, 0.5)
    /// Breite relativ zur Collage-Breite (Frei).
    public var width: Float = 0.45
    public var rotation: Float = 0
    // Streifen: Anfang/Ende abschneiden, Anteil 0…0,45
    public var trimStart: Float = 0
    public var trimEnd: Float = 0

    public init(mediaId: String) { self.mediaId = mediaId }

    func resetPan() -> CollageItem {
        var c = self
        c.zoom = 1; c.panX = 0; c.panY = 0
        return c
    }
}

public enum BackgroundKind: String, Hashable, Codable, Sendable { case color = "COLOR", blur = "BLUR" }

public struct CollageBackground: Hashable, Codable, Sendable {
    public var kind = BackgroundKind.color
    public var color: ARGB = 0xFFFF_FFFF
    public var blurIndex = 0
    public init(kind: BackgroundKind = .color, color: ARGB = 0xFFFF_FFFF, blurIndex: Int = 0) {
        self.kind = kind
        self.color = color
        self.blurIndex = blurIndex
    }
}

/// Ganze Collage (Entwurf). Nur lokal; enthält Medien-IDs, nie Bilder.
public struct CollageProject: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public var kind: CollageKind
    public var items: [CollageItem]
    public var template: String
    public var tree: SplitNode
    /// Seitenverhältnis Breite/Höhe (Raster/Frei).
    public var aspect: Float
    /// Abstand zwischen Feldern und Außenrand, relativ zur kürzeren Kante.
    public var spacing: Float
    public var margin: Float
    public var corner: Float = 0
    public var background = CollageBackground()
    /// Frei: weißer Rand + Schatten („Sofortbild“).
    public var polaroid = true
    /// Streifen: untereinander (sonst nebeneinander).
    public var stripVertical = true
    public var layers: [Layer] = []

    public static let max = 20
    public static let freeMax = 4

    public init(id: String, kind: CollageKind, items: [CollageItem], template: String = "grid", tree: SplitNode? = nil,
                aspect: Float = 1, spacing: Float = 0.015, margin: Float = 0.015) {
        self.id = id
        self.kind = kind
        self.items = items
        self.template = template
        self.tree = tree ?? CollageLayout.template(template, items.count)
        self.aspect = aspect
        self.spacing = spacing
        self.margin = margin
    }

    public var count: Int { items.count }

    public func withTemplate(_ t: String) -> CollageProject {
        var p = self
        p.template = t
        p.tree = CollageLayout.template(t, items.count)
        return p
    }

    /// Feldrechtecke (normiert auf die Collage) inklusive Abständen.
    public func cellRects() -> [NormRect] {
        let cells = CollageLayout.cells(tree)
        let ar = aspect
        let sx: Float = ar >= 1 ? 1 / ar : 1, sy: Float = ar >= 1 ? 1 : ar
        let gx = spacing * sx, gy = spacing * sy, mx = margin * sx, my = margin * sy
        return items.indices.map { i in
            let r = cells[i] ?? .full
            func x(_ v: Float) -> Float { mx + v * (1 - 2 * mx) }
            func y(_ v: Float) -> Float { my + v * (1 - 2 * my) }
            return NormRect(left: x(r.left) + (r.left > 0.0001 ? gx / 2 : 0), top: y(r.top) + (r.top > 0.0001 ? gy / 2 : 0),
                            right: x(r.right) - (r.right < 0.9999 ? gx / 2 : 0),
                            bottom: y(r.bottom) - (r.bottom < 0.9999 ? gy / 2 : 0))
        }
    }

    public func swap(_ a: Int, _ b: Int) -> CollageProject {
        guard a != b, items.indices.contains(a), items.indices.contains(b) else { return self }
        var p = self
        let t = items[a]
        p.items[a] = items[b].resetPan()
        p.items[b] = t.resetPan()
        return p
    }

    public func removeItem(_ i: Int) -> CollageProject {
        guard items.count > 1, items.indices.contains(i) else { return self }
        var p = self
        p.items.remove(at: i)
        let t = CollageLayout.templates(for: p.items.count).contains(template) ? template : "grid"
        p.template = t
        p.tree = CollageLayout.template(t, p.items.count)
        return p
    }

    public func addItems(_ ids: [String]) -> CollageProject {
        var p = self
        let old = items.count
        p.items += ids.map { CollageItem(mediaId: $0) }
        let n = p.items.count
        let t = kind == .grid && CollageLayout.templates(for: n).contains(template) ? template : "grid"
        p.template = t
        p.tree = CollageLayout.template(t, n)
        if kind == .free {
            for i in old..<n { p.items[i].center = FreeLayout.spot(i, n); p.items[i].width = FreeLayout.width(n) }
        }
        return p
    }

    public static func create(id: String, ids: [String], kind: CollageKind = .grid) -> CollageProject {
        let n = ids.count
        let items = ids.enumerated().map { i, m -> CollageItem in
            var it = CollageItem(mediaId: m)
            it.center = FreeLayout.spot(i, n); it.width = FreeLayout.width(n); it.rotation = FreeLayout.tilt(i)
            return it
        }
        switch kind {
        case .grid:
            return CollageProject(id: id, kind: kind, items: items, aspect: n == 2 ? 1 : 0.8)
        case .free:
            var p = CollageProject(id: id, kind: kind, items: items, aspect: 0.8)
            p.background = CollageBackground(color: ARGB(Int32(bitPattern: 0xFFF4_EFE6)))
            return p
        case .strip:
            return CollageProject(id: id, kind: kind, items: items, spacing: 0, margin: 0)
        }
    }
}

/// Startpositionen für die freie Collage (lockeres Raster, leicht gedreht).
public enum FreeLayout {
    public static func width(_ n: Int) -> Float {
        if n <= 1 { return 0.62 }
        if n <= 2 { return 0.44 }
        if n <= 4 { return 0.36 }
        return n <= 9 ? 0.27 : 0.2
    }

    public static func spot(_ i: Int, _ n: Int) -> NormPoint {
        let cols = max(1, Int(ceil(sqrt(Double(n))))), rows = max(1, Int(ceil(Double(n) / Double(cols))))
        let c = i % cols, r = i / cols
        return NormPoint((Float(c) + 0.5) / Float(cols), (Float(r) + 0.5) / Float(rows))
    }

    public static func tilt(_ i: Int) -> Float { [-4, 3, -2, 5, -3, 2][i % 6] }
}

/// Streifen: Gesamtgröße und Lage je Bild (lange Screenshots untereinander).
public enum StripLayout {
    /// `sizes` = Pixelgrößen der Fotos. Alle auf die gemeinsame Breite (bzw. Höhe); `maxEdge` begrenzt die lange Kante.
    public static func layout(sizes: [PxSize], items: [CollageItem], vertical: Bool, spacingPx: Int, targetCross: Int,
                              maxEdge: Int = 16_000) -> (size: PxSize, placements: [(dst: NormRect, src: NormRect)]) {
        var cross = targetCross
        func lengths(_ cr: Int) -> [Float] {
            sizes.enumerated().map { i, s in
                let it = items[i]
                let keep = min(max(1 - it.trimStart - it.trimEnd, 0.1), 1)
                return vertical ? Float(s.height) * Float(cr) / Float(s.width) * keep
                    : Float(s.width) * Float(cr) / Float(s.height) * keep
            }
        }
        let gaps = Float(spacingPx * max(0, sizes.count - 1))
        var total = lengths(cross).reduce(0, +) + gaps
        if total > Float(maxEdge) {
            cross = max(16, Int(Float(cross) * Float(maxEdge) / total))
            total = lengths(cross).reduce(0, +) + gaps
        }
        let lens = lengths(cross)
        var out: [(NormRect, NormRect)] = []
        var pos: Float = 0
        for i in sizes.indices {
            let it = items[i], l = lens[i]
            let dst = vertical ? NormRect(left: 0, top: pos / total, right: 1, bottom: (pos + l) / total)
                : NormRect(left: pos / total, top: 0, right: (pos + l) / total, bottom: 1)
            let src = vertical ? NormRect(left: 0, top: it.trimStart, right: 1, bottom: 1 - it.trimEnd)
                : NormRect(left: it.trimStart, top: 0, right: 1 - it.trimEnd, bottom: 1)
            out.append((dst, src))
            pos += l + Float(spacingPx)
        }
        let w = vertical ? cross : Int(total.rounded()), h = vertical ? Int(total.rounded()) : cross
        return (PxSize(w, h), out.map { (dst: $0.0, src: $0.1) })
    }
}

/// Wie ein Foto in ein Feld kommt (füllen mit Zoom/Verschiebung oder ganz zeigen). Ergebnis: Quellausschnitt (0…1).
public enum CellFit {
    public static func source(imgAspect: Float, cellAspect: Float, zoom: Float, panX: Float, panY: Float,
                              fit: Bool) -> NormRect {
        if fit { return .full }
        let z = max(1, zoom)
        var w: Float = 1, h: Float = 1
        if imgAspect > cellAspect { w = cellAspect / imgAspect } else { h = imgAspect / cellAspect }
        w /= z; h /= z
        let cx = 0.5 + min(max(panX, -1), 1) * (1 - w) / 2, cy = 0.5 + min(max(panY, -1), 1) * (1 - h) / 2
        return NormRect(left: cx - w / 2, top: cy - h / 2, right: cx + w / 2, bottom: cy + h / 2)
    }

    /// Ganzes Foto einpassen: Zielrechteck im Feld (normiert aufs Feld).
    public static func fitRect(imgAspect: Float, cellAspect: Float) -> NormRect {
        if imgAspect > cellAspect {
            let h = cellAspect / imgAspect
            return NormRect(left: 0, top: (1 - h) / 2, right: 1, bottom: (1 + h) / 2)
        }
        let w = imgAspect / cellAspect
        return NormRect(left: (1 - w) / 2, top: 0, right: (1 + w) / 2, bottom: 1)
    }
}

/// Exportgrößen.
public enum CollageExport {
    /// A4 bei 300 dpi (hoch).
    public static let a4Short = 2480
    public static let a4Long = 3508

    public static func size(aspect: Float, longEdge: Int) -> PxSize {
        aspect >= 1 ? PxSize(longEdge, max(1, Int((Float(longEdge) / aspect).rounded())))
            : PxSize(max(1, Int((Float(longEdge) * aspect).rounded())), longEdge)
    }

    public static func clampLong(_ v: Int) -> Int { min(8192, max(512, v)) }
}
