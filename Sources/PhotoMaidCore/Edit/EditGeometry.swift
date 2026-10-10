import Foundation

/// Affine 2D-Abbildung (a c tx / b d ty), Spaltenvektoren; entspricht `CGAffineTransform(a:b:c:d:tx:ty:)`.
public struct Affine: Hashable, Sendable {
    public var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    /// Erst `o`, dann `self`.
    public static func * (s: Affine, o: Affine) -> Affine {
        Affine(a: s.a * o.a + s.c * o.b, b: s.b * o.a + s.d * o.b,
               c: s.a * o.c + s.c * o.d, d: s.b * o.c + s.d * o.d,
               tx: s.a * o.tx + s.c * o.ty + s.tx, ty: s.b * o.tx + s.d * o.ty + s.ty)
    }

    public func map(_ x: Double, _ y: Double) -> (Double, Double) { (a * x + c * y + tx, b * x + d * y + ty) }

    public func inverse() -> Affine? {
        let det = a * d - b * c
        guard abs(det) > 1e-12 else { return nil }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return Affine(a: ia, b: ib, c: ic, d: id, tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty))
    }

    public static func translate(_ x: Double, _ y: Double) -> Affine { Affine(tx: x, ty: y) }
    public static func scale(_ sx: Double, _ sy: Double? = nil) -> Affine { Affine(a: sx, d: sy ?? sx) }
    public static func rotate(degrees deg: Double) -> Affine {
        let r = deg * .pi / 180
        return Affine(a: cos(r), b: sin(r), c: -sin(r), d: cos(r))
    }
}

/// Projektive 2D-Abbildung (3 × 3, Zeilen m0 m1 m2 / m3 m4 m5 / m6 m7 m8) für Perspektive.
public struct Homography: Hashable, Sendable {
    public var m: [Double]

    public init(_ m: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]) {
        precondition(m.count == 9)
        self.m = m
    }

    public init(_ a: Affine) { self.init([a.a, a.c, a.tx, a.b, a.d, a.ty, 0, 0, 1]) }

    public var isAffine: Bool { abs(m[6]) < 1e-12 && abs(m[7]) < 1e-12 }

    /// Erst `o`, dann `self`.
    public static func * (s: Homography, o: Homography) -> Homography {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                var sum: Double = 0
                for k in 0..<3 { sum += s.m[i * 3 + k] * o.m[k * 3 + j] }
                r[i * 3 + j] = sum
            }
        }
        return Homography(r)
    }

    public static func * (s: Homography, o: Affine) -> Homography { s * Homography(o) }
    public static func * (s: Affine, o: Homography) -> Homography { Homography(s) * o }

    public func map(_ x: Double, _ y: Double) -> (Double, Double) {
        let w = m[6] * x + m[7] * y + m[8]
        return ((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w)
    }

    public func inverse() -> Homography? {
        let a = m
        let c00 = a[4] * a[8] - a[5] * a[7], c01 = a[5] * a[6] - a[3] * a[8], c02 = a[3] * a[7] - a[4] * a[6]
        let det = a[0] * c00 + a[1] * c01 + a[2] * c02
        guard abs(det) > 1e-15 else { return nil }
        let inv = [c00, a[2] * a[7] - a[1] * a[8], a[1] * a[5] - a[2] * a[4],
                   c01, a[0] * a[8] - a[2] * a[6], a[2] * a[3] - a[0] * a[5],
                   c02, a[1] * a[6] - a[0] * a[7], a[0] * a[4] - a[1] * a[3]]
        return Homography(inv.map { $0 / det })
    }

    /// Abbildung, die die vier Punkte `src` auf `dst` legt (Reihenfolge gleich). `nil` bei entarteten Punkten.
    public static func fromPoints(_ src: [(Double, Double)], _ dst: [(Double, Double)]) -> Homography? {
        precondition(src.count == 4 && dst.count == 4)
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = src[i], (u, v) = dst[i]
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        for col in 0..<8 {
            let piv = (col..<8).max { abs(a[$0][col]) < abs(a[$1][col]) }!
            if abs(a[piv][col]) < 1e-12 { return nil }
            a.swapAt(col, piv)
            for r in 0..<8 where r != col {
                let f = a[r][col] / a[col][col]
                if f != 0 { for k in col...8 { a[r][k] -= f * a[col][k] } }
            }
        }
        return Homography((0..<9).map { $0 == 8 ? 1 : a[$0][8] / a[$0][$0] })
    }
}

public struct PxSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
    public var longEdge: Int { max(width, height) }
    public var shortEdge: Int { min(width, height) }
    public var pixels: Int64 { Int64(width) * Int64(height) }
}

/// Geometrie eines Rezepts für ein Quellbild der Größe `src` (bereits korrekt ausgerichtet).
/// Koordinaten: Ursprung oben links, y nach unten (wie UIKit). Core Image (y nach oben) rechnet die App um.
public struct EditGeometry: Sendable {
    public let src: PxSize
    public let recipe: EditRecipe

    /// Rahmen nach Vierteldrehung, vor der Perspektive.
    public let baseFrame: PxSize
    /// Vergrößerung beim Begradigen, damit das gedrehte Bild den ganzen Rahmen deckt.
    public let straightenScale: Double
    private let warp: (Homography, PxSize)?
    /// Rahmen, auf den sich der Ausschnitt bezieht (nach Vierteldrehung und Perspektive).
    public let frame: PxSize
    public let cropLeft: Double
    public let cropTop: Double
    public let cropSize: PxSize
    /// Endgültige Ausgabegröße: Zielgröße (nie größer als der Ausschnitt) oder Ausschnitt.
    public let output: PxSize
    /// Quelle → Grundrahmen (Vierteldrehung + Spiegeln + Begradigen um die Mitte).
    public let sourceToBase: Affine
    /// Quelle → Rahmen (inkl. Perspektive).
    public let sourceToFrame: Homography
    /// Quelle → Ausgabe (inkl. Ausschnitt und Skalierung).
    public let sourceToOutput: Homography

    public init(src: PxSize, recipe: EditRecipe) {
        self.src = src
        self.recipe = recipe
        let base = recipe.turns % 2 == 1 ? PxSize(src.height, src.width) : src
        baseFrame = base
        let sScale = Self.coverScale(Double(base.width), Double(base.height), Double(recipe.straighten))
        straightenScale = sScale
        let w = recipe.perspective.flatMap { $0.isIdentity ? nil : PerspectiveMath.warp($0, base: base) }
        warp = w
        let fr = w?.1 ?? base
        frame = fr
        cropLeft = Double(recipe.crop.left) * Double(fr.width)
        cropTop = Double(recipe.crop.top) * Double(fr.height)
        cropSize = PxSize(max(1, Int((Double(recipe.crop.width) * Double(fr.width)).rounded())),
                          max(1, Int((Double(recipe.crop.height) * Double(fr.height)).rounded())))
        output = ResizeRules.clampToSource(recipe.resizeWidth, recipe.resizeHeight, crop: cropSize)

        let sw = Double(src.width), sh = Double(src.height), fw = Double(base.width), fh = Double(base.height)
        let turn = Affine.translate(fw / 2, fh / 2) * Affine.rotate(degrees: 90 * Double(recipe.turns))
            * Affine.translate(-sw / 2, -sh / 2)
        let flip = Affine.translate(fw / 2, fh / 2) * Affine.scale(recipe.flipH ? -1 : 1, recipe.flipV ? -1 : 1)
            * Affine.translate(-fw / 2, -fh / 2)
        let straight = Affine.translate(fw / 2, fh / 2) * Affine.rotate(degrees: Double(recipe.straighten))
            * Affine.scale(sScale) * Affine.translate(-fw / 2, -fh / 2)
        let toBase = straight * flip * turn
        sourceToBase = toBase
        let toFrame = w.map { $0.0 * toBase } ?? Homography(toBase)
        sourceToFrame = toFrame
        sourceToOutput = Affine.scale(Double(output.width) / Double(cropSize.width),
                                      Double(output.height) / Double(cropSize.height))
            * Affine.translate(-cropLeft, -cropTop) * toFrame
    }

    /// Benötigter Bereich der Quelle (Pixel, l t r b), gerundet nach außen.
    public func sourceBounds() -> (Int, Int, Int, Int) {
        guard let inv = sourceToOutput.inverse() else { return (0, 0, src.width, src.height) }
        let w = Double(output.width), h = Double(output.height)
        let pts = [(0.0, 0.0), (w, 0), (0, h), (w, h)].map { inv.map($0.0, $0.1) }
        let l = min(max(Int(pts.map(\.0).min()!), 0), src.width - 1)
        let t = min(max(Int(pts.map(\.1).min()!), 0), src.height - 1)
        let r = min(max(Int(pts.map(\.0).max()!.rounded(.up)), l + 1), src.width)
        let b = min(max(Int(pts.map(\.1).max()!.rounded(.up)), t + 1), src.height)
        return (l, t, r, b)
    }

    /// Kleinste Vergrößerung, mit der ein um `deg` gedrehtes W × H-Bild das W × H-Rechteck vollständig deckt.
    public static func coverScale(_ w: Double, _ h: Double, _ deg: Double) -> Double {
        let r = abs(deg) * .pi / 180, c = cos(r), s = sin(r)
        return max((w * c + h * s) / w, (w * s + h * c) / h)
    }
}

/// Perspektive: vier Ecken (normiert im Grundrahmen) werden zum Rechteck. Rein manuell, keine Erkennung.
public enum PerspectiveMath {
    public static let minSide: Float = 0.12

    public static func warp(_ q: Quad, base: PxSize) -> (Homography, PxSize)? {
        let bw = Double(base.width), bh = Double(base.height)
        func px(_ p: NormPoint) -> (Double, Double) { (Double(p.x) * bw, Double(p.y) * bh) }
        let pts = [px(q.tl), px(q.tr), px(q.br), px(q.bl)]
        func len(_ a: (Double, Double), _ b: (Double, Double)) -> Double { hypot(a.0 - b.0, a.1 - b.1) }
        var w = (len(pts[0], pts[1]) + len(pts[3], pts[2])) / 2
        var h = (len(pts[0], pts[3]) + len(pts[1], pts[2])) / 2
        guard w >= 1, h >= 1 else { return nil }
        let cap = (bw * bh) / (w * h)
        if cap < 1 { let k = sqrt(cap); w *= k; h *= k }
        let size = PxSize(max(1, Int(w.rounded())), max(1, Int(h.rounded())))
        let dst = [(0.0, 0.0), (Double(size.width), 0.0), (Double(size.width), Double(size.height)),
                   (0.0, Double(size.height))]
        return Homography.fromPoints(pts, dst).map { ($0, size) }
    }

    /// Ist das Viereck benutzbar (konvex, nicht zu klein)?
    public static func isValid(_ q: Quad) -> Bool {
        let p = [q.tl, q.tr, q.br, q.bl]
        var sign = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            let s = cross > 0 ? 1 : (cross < 0 ? -1 : 0)
            if s == 0 || (sign != 0 && s != sign) { return false }
            sign = s
            if hypot(Double(b.x - a.x), Double(b.y - a.y)) < Double(minSide) { return false }
        }
        return true
    }

    /// Ecke `i` (0 = oben links, im Uhrzeigersinn) verschieben – nur wenn das Viereck gültig bleibt.
    public static func moveCorner(_ q: Quad, _ i: Int, x: Float, y: Float) -> Quad {
        let p = NormPoint(min(max(x, 0), 1), min(max(y, 0), 1))
        var n = q
        switch i {
        case 0: n.tl = p
        case 1: n.tr = p
        case 2: n.br = p
        default: n.bl = p
        }
        return isValid(n) ? n : q
    }

    /// Schnelle Korrektur (Gebäude): `vertical` > 0 zieht die oberen Ecken zusammen, < 0 die unteren;
    /// `horizontal` entsprechend links/rechts. Werte −100…100.
    public static func keystone(vertical: Float, horizontal: Float) -> Quad {
        let v = min(max(vertical / 100, -1), 1) * 0.3, h = min(max(horizontal / 100, -1), 1) * 0.3
        let tIn = max(0, v), bIn = max(0, -v), lIn = max(0, h), rIn = max(0, -h)
        return Quad(tl: NormPoint(tIn, lIn), tr: NormPoint(1 - tIn, rIn), br: NormPoint(1 - bIn, 1 - rIn),
                    bl: NormPoint(bIn, 1 - lIn))
    }
}

/// Seitenverhältnisse beim Zuschneiden.
public enum AspectPreset: String, Hashable, Codable, Sendable, CaseIterable {
    case free, original, square, r4x5, r3x4, r2x3, r9x16, r16x9

    var wh: (Int, Int) {
        switch self {
        case .free, .original: (0, 0)
        case .square: (1, 1)
        case .r4x5: (4, 5)
        case .r3x4: (3, 4)
        case .r2x3: (2, 3)
        case .r9x16: (9, 16)
        case .r16x9: (16, 9)
        }
    }
}

public enum CropMath {
    /// Kleinster Ausschnitt (Anteil der kürzeren Rahmenkante).
    public static let minFraction: Float = 0.08

    /// Seitenverhältnis (Breite/Höhe) eines Presets im Rahmen; `nil` = frei. `landscape` dreht Hoch-/Querformat.
    public static func ratio(_ p: AspectPreset, frame: PxSize, landscape: Bool) -> Double? {
        switch p {
        case .free: return nil
        case .original: return Double(frame.width) / Double(frame.height)
        default:
            let (w, h) = p.wh
            let r = Double(w) / Double(h)
            return landscape == (r >= 1) ? r : 1 / r
        }
    }

    /// Größter Ausschnitt mit Verhältnis `ratio` (Pixel), zentriert in `rect`, vollständig im Rahmen.
    public static func fitAspect(_ rect: NormRect, ratio: Double, frame: PxSize) -> NormRect {
        let rw = Double(rect.width) * Double(frame.width), rh = Double(rect.height) * Double(frame.height)
        let cx = (rect.left + rect.right) / 2, cy = (rect.top + rect.bottom) / 2
        var w = rw, h = rw / ratio
        if h > rh { h = rh; w = rh * ratio }
        let nw = Float(w / Double(frame.width)), nh = Float(h / Double(frame.height))
        let l = min(max(cx - nw / 2, 0), 1 - nw), t = min(max(cy - nh / 2, 0), 1 - nh)
        return NormRect(left: l, top: t, right: l + nw, bottom: t + nh)
    }

    public enum Handle: Hashable, Sendable { case move, left, top, right, bottom, topLeft, topRight, bottomLeft, bottomRight }

    /// Ziehen an einem Griff um (dx, dy) in Rahmenanteilen. Hält Mindestgröße, Rahmengrenzen und – falls gesetzt –
    /// das Seitenverhältnis (Pixel) ein.
    public static func drag(_ rect: NormRect, handle h: Handle, dx: Float, dy: Float, frame: PxSize,
                            ratio: Double?) -> NormRect {
        let short = Float(min(frame.width, frame.height))
        let minW = minFraction * short / Float(frame.width)
        let minH = minFraction * short / Float(frame.height)
        if h == .move {
            let l = min(max(rect.left + dx, 0), 1 - rect.width), t = min(max(rect.top + dy, 0), 1 - rect.height)
            return NormRect(left: l, top: t, right: l + rect.width, bottom: t + rect.height)
        }
        var l = rect.left, t = rect.top, r = rect.right, b = rect.bottom
        switch h {
        case .left, .topLeft, .bottomLeft: l = min(max(l + dx, 0), r - minW)
        case .right, .topRight, .bottomRight: r = min(max(r + dx, l + minW), 1)
        default: break
        }
        switch h {
        case .top, .topLeft, .topRight: t = min(max(t + dy, 0), b - minH)
        case .bottom, .bottomLeft, .bottomRight: b = min(max(b + dy, t + minH), 1)
        default: break
        }
        guard let ratio else { return NormRect(left: l, top: t, right: r, bottom: b) }
        let wPx = Double(r - l) * Double(frame.width), hPx = Double(b - t) * Double(frame.height)
        let horizontalDriven = h == .left || h == .right
            || (h != .top && h != .bottom && abs(dx * Float(frame.width)) >= abs(dy * Float(frame.height)))
        var nw: Double, nh: Double
        if horizontalDriven { nw = wPx; nh = nw / ratio } else { nh = hPx; nw = nh * ratio }
        let fixedRight = h == .left || h == .topLeft || h == .bottomLeft
        let fixedBottom = h == .top || h == .topLeft || h == .topRight
        let maxW = Double(fixedRight ? rect.right : 1 - rect.left) * Double(frame.width)
        let maxH = Double(fixedBottom ? rect.bottom : 1 - rect.top) * Double(frame.height)
        if nw > maxW { nw = maxW; nh = nw / ratio }
        if nh > maxH { nh = maxH; nw = nh * ratio }
        let fw = Float(nw / Double(frame.width)), fh = Float(nh / Double(frame.height))
        let cx = (rect.left + rect.right) / 2, cy = (rect.top + rect.bottom) / 2
        let nl: Float, nr: Float, nt: Float, nb: Float
        if h == .top || h == .bottom {
            nl = min(max(cx - fw / 2, 0), 1 - fw); nr = nl + fw
        } else if fixedRight {
            nr = rect.right; nl = nr - fw
        } else {
            nl = rect.left; nr = nl + fw
        }
        if h == .left || h == .right {
            nt = min(max(cy - fh / 2, 0), 1 - fh); nb = nt + fh
        } else if fixedBottom {
            nb = rect.bottom; nt = nb - fh
        } else {
            nt = rect.top; nb = nt + fh
        }
        return NormRect(left: max(nl, 0), top: max(nt, 0), right: min(nr, 1), bottom: min(nb, 1))
    }
}

public enum ResizeRules {
    public static let presetLongEdges = [4096, 2048, 1080]
    public static let minEdge = 16

    /// Vorgaben, die wirklich verkleinern.
    public static func presets(for size: PxSize) -> [Int] { presetLongEdges.filter { $0 < size.longEdge } }

    public static func forLongEdge(_ size: PxSize, _ longEdge: Int) -> PxSize {
        let l = min(max(longEdge, minEdge), size.longEdge)
        if size.width >= size.height {
            return PxSize(l, max(1, Int((Double(l) * Double(size.height) / Double(size.width)).rounded())))
        }
        return PxSize(max(1, Int((Double(l) * Double(size.width) / Double(size.height)).rounded())), l)
    }

    /// Breite eingegeben, Verhältnis gesperrt.
    public static func forWidth(_ size: PxSize, _ width: Int) -> PxSize {
        let w = min(max(width, minEdge), size.width)
        return PxSize(w, max(1, Int((Double(w) * Double(size.height) / Double(size.width)).rounded())))
    }

    public static func forHeight(_ size: PxSize, _ height: Int) -> PxSize {
        let h = min(max(height, minEdge), size.height)
        return PxSize(max(1, Int((Double(h) * Double(size.width) / Double(size.height)).rounded())), h)
    }

    /// Nie hochskalieren und NIE verzerren: ein gemeinsamer Faktor für beide Kanten (die engere Kante gilt).
    public static func clampToSource(_ w: Int?, _ h: Int?, crop: PxSize) -> PxSize {
        guard let w, let h else { return crop }
        let s = max(min(1, Double(w) / Double(crop.width), Double(h) / Double(crop.height)),
                    1 / Double(max(crop.width, crop.height)))
        return PxSize(max(1, Int((Double(crop.width) * s).rounded())), max(1, Int((Double(crop.height) * s).rounded())))
    }
}

/// Verlustfreies Drehen/Spiegeln: neue EXIF-Ausrichtung (1…8) aus der bisherigen und dem Rezept
/// (erst Vierteldrehung im Uhrzeigersinn, dann Spiegeln). Unbekannt/0 gilt als 1.
public enum ExifOrientationMath {
    private static let toRF: [Int: (Int, Bool)] = [1: (0, false), 2: (0, true), 3: (2, false), 4: (2, true),
                                                   5: (3, true), 6: (1, false), 7: (1, true), 8: (3, false)]

    public static func compose(current: Int, turns: Int, flipH: Bool, flipV: Bool) -> Int {
        let (r0, f0) = toRF[current] ?? (0, false)
        var r = r0 + turns, f = f0
        if flipH && flipV { r += 2 } else if flipH { r = -r; f.toggle() } else if flipV { r = 2 - r; f.toggle() }
        let key = (((r % 4) + 4) % 4, f)
        return toRF.first { $0.value == key }!.key
    }
}
