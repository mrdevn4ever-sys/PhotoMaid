import Foundation

/// 4×5-Farbmatrizen (Zeilen R, G, B, A; Spalten r g b a + Versatz in 0…255) – gleiche Werte wie Android.
/// Auf iOS werden sie als Farbtabelle (`PointOps.cube`) oder `CIColorMatrix` (Versatz / 255) angewendet.
public enum ColorMatrices {
    public static var identity: [Float] { [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0] }
    static let lr: Float = 0.2126, lg: Float = 0.7152, lb: Float = 0.0722

    /// Erst `b`, dann `a` anwenden.
    public static func concat(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: 20)
        for r in 0..<4 {
            for c in 0..<4 {
                out[r * 5 + c] = Float((0..<4).reduce(0.0) { $0 + Double(a[r * 5 + $1] * b[$1 * 5 + c]) })
            }
            out[r * 5 + 4] = Float((0..<4).reduce(0.0) { $0 + Double(a[r * 5 + $1] * b[$1 * 5 + 4]) }) + a[r * 5 + 4]
        }
        return out
    }

    public static func lerp(_ a: [Float], _ b: [Float], _ t: Float) -> [Float] {
        let k = min(max(t, 0), 1)
        return (0..<20).map { a[$0] + (b[$0] - a[$0]) * k }
    }

    public static func brightness(_ v: Float) -> [Float] {
        let o = 255 * 0.25 * (v / 100)
        var m = identity
        m[4] = o; m[9] = o; m[14] = o
        return m
    }

    public static func contrast(_ v: Float) -> [Float] {
        let k = 1 + 0.6 * (v / 100), o = 127.5 * (1 - k)
        return [k, 0, 0, 0, o, 0, k, 0, 0, o, 0, 0, k, 0, o, 0, 0, 0, 1, 0]
    }

    public static func saturation(_ v: Float) -> [Float] { saturationFactor(1 + v / 100) }

    public static func saturationFactor(_ s: Float) -> [Float] {
        let i = 1 - s
        return [lr * i + s, lg * i, lb * i, 0, 0,
                lr * i, lg * i + s, lb * i, 0, 0,
                lr * i, lg * i, lb * i + s, 0, 0,
                0, 0, 0, 1, 0]
    }

    /// Wärmer (positiv) = mehr Rot/weniger Blau, kühler (negativ) umgekehrt.
    public static func warmth(_ v: Float) -> [Float] {
        let t = v / 100
        return [1 + 0.10 * t, 0, 0, 0, 8 * t, 0, 1 + 0.02 * t, 0, 0, 0, 0, 0, 1 - 0.10 * t, 0, -8 * t, 0, 0, 0, 1, 0]
    }

    /// Tönung: positiv = Magenta, negativ = Grün.
    public static func tint(_ v: Float) -> [Float] {
        let t = v / 100
        return [1 + 0.06 * t, 0, 0, 0, 0, 0, 1 - 0.12 * t, 0, 0, 0, 0, 0, 1 + 0.06 * t, 0, 0, 0, 0, 0, 1, 0]
    }

    public static func filter(_ id: FilterId) -> [Float] {
        switch id {
        case .none: identity
        case .mono: saturationFactor(0)
        case .monoContrast: concat(contrast(45), saturationFactor(0))
        case .warm: concat(warmth(55), saturation(10))
        case .cool: concat(warmth(-55), saturation(-5))
        case .sepia: [0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0]
        case .fade: concat(brightness(10), concat(contrast(-30), saturation(-25)))
        case .vivid: concat(contrast(15), saturation(45))
        }
    }

    /// Gesamtmatrix wie Android: erst Filter (mit Stärke), dann Regler (Wärme, Sättigung, Kontrast, Helligkeit).
    public static func forRecipe(_ r: EditRecipe) -> [Float] {
        let f = lerp(identity, filter(r.filter), r.filter == .none ? 0 : r.filterIntensity)
        let adj = concat(brightness(r.adjust.brightness), concat(contrast(r.adjust.contrast),
                         concat(saturation(r.adjust.saturation), warmth(r.adjust.warmth))))
        return concat(adj, f)
    }

    /// Auf einen 8-Bit-Farbwert anwenden (Tests).
    public static func apply(_ m: [Float], r: Int, g: Int, b: Int, a: Int = 255) -> (Int, Int, Int, Int) {
        func ch(_ row: Int) -> Int {
            let v = m[row * 5] * Float(r) + m[row * 5 + 1] * Float(g) + m[row * 5 + 2] * Float(b)
                + m[row * 5 + 3] * Float(a) + m[row * 5 + 4]
            return min(max(Int(v), 0), 255)
        }
        return (ch(0), ch(1), ch(2), ch(3))
    }

    /// Versätze von 0…255 nach 0…1.
    public static func normalized(_ m: [Float]) -> [Float] {
        var o = m
        for r in 0..<4 { o[r * 5 + 4] = m[r * 5 + 4] / 255 }
        return o
    }
}

@inline(__always) func clamp01(_ v: Float) -> Float { min(max(v, 0), 1) }
@inline(__always) func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}
@inline(__always) func luma(_ r: Float, _ g: Float, _ b: Float) -> Float { 0.2126 * r + 0.7152 * g + 0.0722 * b }

/// Punktweise Stufen eines Reglersatzes (Filter, Tonkurve, Farbmatrix, Dynamik, Farbmischer) – dieselben Formeln wie die
/// Android-Pipeline. Arbeitet auf gamma-kodierten sRGB-Werten 0…1. Ergebnis als 3D-Farbtabelle für `CIColorCube`
/// (Foto und Video, Vorschau und Export → gleiche Farbwirkung).
public struct PointOps: Sendable {
    private let filter: [Float]?
    private let tone: [Float]?
    private let matrix: [Float]?
    private let vibrance: Float
    private let mix: [HslShift]?

    public static let lutSize = 1024

    public init(adjust a: Adjustments, filter filterId: FilterId = .none, intensity: Float = 0, mix: ColorMix = ColorMix()) {
        filter = filterId == .none || intensity <= 0.001 ? nil
            : ColorMatrices.normalized(ColorMatrices.lerp(ColorMatrices.identity, ColorMatrices.filter(filterId), intensity))
        let toneActive = [a.exposure, a.blacks, a.whites, a.shadows, a.highlights, a.contrast, a.brightness]
            .contains { abs($0) >= 0.5 }
        tone = toneActive ? ToneCurve.lut(a) : nil
        let colorActive = [a.warmth, a.tint, a.saturation].contains { abs($0) >= 0.5 }
        matrix = colorActive ? ColorMatrices.normalized(ColorMatrices.concat(ColorMatrices.saturation(a.saturation),
            ColorMatrices.concat(ColorMatrices.tint(a.tint), ColorMatrices.warmth(a.warmth)))) : nil
        vibrance = a.vibrance / 100
        self.mix = mix.isNeutral ? nil : ColorBand.allCases.map { mix[$0] }
    }

    /// Punktweise Stufen des ganzen Rezepts.
    public init(recipe r: EditRecipe) {
        self.init(adjust: r.adjust, filter: r.filter, intensity: r.filterIntensity, mix: r.colorMix)
    }

    public var isNeutral: Bool { filter == nil && tone == nil && matrix == nil && abs(vibrance) < 0.005 && mix == nil }

    public func apply(_ c: inout (Float, Float, Float)) {
        if let f = filter { mul(f, &c) }
        if let t = tone { applyTone(t, &c) }
        if let m = matrix { mul(m, &c) }
        if abs(vibrance) >= 0.005 { applyVibrance(&c) }
        if let m = mix { applyMix(m, &c) }
        c = (clamp01(c.0), clamp01(c.1), clamp01(c.2))
    }

    /// 3D-Farbtabelle (RGBA Float32, Index r schnellste Achse, wie `CIColorCube` erwartet), Werte gamma-kodiert sRGB.
    public func cube(size n: Int = 33) -> [Float] {
        var out = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        let d = Float(n - 1)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    var c = (Float(r) / d, Float(g) / d, Float(b) / d)
                    apply(&c)
                    out[i] = c.0; out[i + 1] = c.1; out[i + 2] = c.2; out[i + 3] = 1
                    i += 4
                }
            }
        }
        return out
    }

    private func mul(_ m: [Float], _ c: inout (Float, Float, Float)) {
        let (r, g, b) = c
        c = (m[0] * r + m[1] * g + m[2] * b + m[4], m[5] * r + m[6] * g + m[7] * b + m[9],
             m[10] * r + m[11] * g + m[12] * b + m[14])
    }

    private func applyTone(_ lut: [Float], _ c: inout (Float, Float, Float)) {
        let r = clamp01(c.0), g = clamp01(c.1), b = clamp01(c.2)
        let y = luma(r, g, b)
        let n = lut.count
        let fi = y * Float(n - 1)
        let i = min(max(Int(fi), 0), n - 2)
        let t = fi - Float(i)
        let y2 = lut[i] + (lut[i + 1] - lut[i]) * t
        if y < 1e-4 { c = (y2, y2, y2); return }
        let s = y2 / y
        var nr = r * s, ng = g * s, nb = b * s
        let m = max(nr, max(ng, nb))
        if m > 1 && m > y2 {
            // Weich in den Farbumfang zurück: Helligkeit bleibt, Sättigung gibt nach.
            let k = (1 - y2) / (m - y2)
            nr = y2 + (nr - y2) * k; ng = y2 + (ng - y2) * k; nb = y2 + (nb - y2) * k
        }
        c = (nr, ng, nb)
    }

    private func applyVibrance(_ c: inout (Float, Float, Float)) {
        let mx = max(c.0, max(c.1, c.2)), mn = min(c.0, min(c.1, c.2))
        let sat: Float = mx <= 1e-4 ? 0 : (mx - mn) / mx
        // Wenig gesättigte Farben stärker, kräftige kaum – anders als die Sättigung.
        let f = 1 + vibrance * pow(1 - sat, 1.5) * 0.9
        let y = luma(c.0, c.1, c.2)
        c = (y + (c.0 - y) * f, y + (c.1 - y) * f, y + (c.2 - y) * f)
    }

    private func applyMix(_ m: [HslShift], _ c: inout (Float, Float, Float)) {
        let r = clamp01(c.0), g = clamp01(c.1), b = clamp01(c.2)
        let mx = max(r, max(g, b)), mn = min(r, min(g, b)), ch = mx - mn
        guard ch >= 1e-3, mx > 0 else { return }
        var hue: Float
        if mx == r { hue = 60 * ((g - b) / ch).truncatingRemainder(dividingBy: 6) }
        else if mx == g { hue = 60 * ((b - r) / ch + 2) }
        else { hue = 60 * ((r - g) / ch + 4) }
        if hue < 0 { hue += 360 }
        let sat = ch / mx
        let greyGuard = smoothstep(0.03, 0.22, sat)
        var dh: Float = 0, ds: Float = 0, dl: Float = 0
        let bands = ColorBand.allCases
        for k in bands.indices {
            let s = m[k]
            if s.isNeutral { continue }
            let wgt = Self.bandWeight(bands, k, hue) * greyGuard
            if wgt <= 0 { continue }
            dh += wgt * s.hue * 0.3; ds += wgt * s.saturation / 100; dl += wgt * s.luminance / 100
        }
        if dh == 0 && ds == 0 && dl == 0 { return }
        var h2 = (hue + dh).truncatingRemainder(dividingBy: 360)
        if h2 < 0 { h2 += 360 }
        let s2 = clamp01(sat * (1 + ds))
        // Farbton/Sättigung behalten die Helligkeit (Luma); nur der Helligkeits-Regler hellt auf bzw. dunkelt ab.
        let l0 = luma(r, g, b)
        var out = Self.hsvToRgb(h2, s2, mx)
        let target = clamp01(l0 * (1 + dl * 0.6 * sat))
        let shift = target - luma(out.0, out.1, out.2)
        out = (clamp01(out.0 + shift), clamp01(out.1 + shift), clamp01(out.2 + shift))
        c = out
    }

    static func angDist(_ a: Float, _ b: Float) -> Float {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// Dreiecksgewicht zwischen den Nachbar-Mitten (weich), Summe der Bänder ≈ 1.
    static func bandWeight(_ bands: [ColorBand], _ k: Int, _ hue: Float) -> Float {
        let c = bands[k].centerDeg
        let prev = bands[(k - 1 + bands.count) % bands.count].centerDeg
        let next = bands[(k + 1) % bands.count].centerDeg
        let d = angDist(hue, c)
        let toward = ((hue - c + 360).truncatingRemainder(dividingBy: 360)) < 180 ? angDist(next, c) : angDist(prev, c)
        if d >= toward { return 0 }
        let t = 1 - d / toward
        return t * t * (3 - 2 * t)
    }

    static func hsvToRgb(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
        let cc = v * s
        let x = cc * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - cc
        let rgb: (Float, Float, Float)
        switch min(max(Int(h / 60), 0), 5) {
        case 0: rgb = (cc, x, 0)
        case 1: rgb = (x, cc, 0)
        case 2: rgb = (0, cc, x)
        case 3: rgb = (0, x, cc)
        case 4: rgb = (x, 0, cc)
        default: rgb = (cc, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }

    /// Ein einzelner 8-Bit-Farbwert (Tests).
    public func applyPoint(r: Int, g: Int, b: Int) -> (Int, Int, Int) {
        var c = (Float(r) / 255, Float(g) / 255, Float(b) / 255)
        apply(&c)
        func q(_ v: Float) -> Int { min(max(Int(v * 255 + 0.5), 0), 255) }
        return (q(c.0), q(c.1), q(c.2))
    }
}

/// Tonwertkurve auf der (Gamma-)Helligkeit. Jede Stufe wirkt in ihrem Bereich; Ergebnis monoton und in 0…1.
public enum ToneCurve {
    static func toLin(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func toGamma(_ v: Float) -> Float { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
    /// Weiche Schulter statt hartem Abschneiden bei hoher Belichtung.
    static func shoulder(_ x: Float) -> Float { x <= 0.85 ? x : 0.85 + 0.15 * (1 - exp(-(x - 0.85) / 0.15)) }

    public static func map(_ a: Adjustments, _ y0: Float) -> Float {
        var y = y0
        if abs(a.exposure) >= 0.5 { y = toGamma(clamp01(shoulder(toLin(y) * pow(2, a.exposure / 100 * 2)))) }
        if abs(a.blacks) >= 0.5 { y += 0.16 * (a.blacks / 100) * pow(1 - y, 4) }
        if abs(a.whites) >= 0.5 { y += 0.16 * (a.whites / 100) * pow(y, 4) }
        if abs(a.shadows) >= 0.5 {
            y += 0.28 * (a.shadows / 100) * (1 - smoothstep(0, 0.6, y)) * smoothstep(0, 0.06, y) * (1 - y)
        }
        if abs(a.highlights) >= 0.5 {
            y += 0.28 * (a.highlights / 100) * smoothstep(0.45, 1, y) * min(y, 1) * (1 - 0.5 * smoothstep(0.95, 1, y))
        }
        if abs(a.contrast) >= 0.5 {
            let c = a.contrast / 100, yc = clamp01(y)
            y = c > 0 ? yc + (yc * yc * (3 - 2 * yc) - yc) * c * 0.9 : yc + (0.5 + (yc - 0.5) * 0.45 - yc) * (-c) * 0.8
        }
        if abs(a.brightness) >= 0.5 { y = pow(clamp01(y), pow(2, -a.brightness / 100 * 0.85)) }
        return clamp01(y)
    }

    public static func lut(_ a: Adjustments, size n: Int = PointOps.lutSize) -> [Float] {
        var out = (0..<n).map { map(a, Float($0) / Float(n - 1)) }
        for i in 1..<n where out[i] < out[i - 1] { out[i] = out[i - 1] } // monoton
        return out
    }
}

/// Rote Augen: im Kreis wird nur deutliches Rot (Rot klar über Grün und Blau) durch das Mittel aus Grün und Blau
/// ersetzt – Haut bleibt unberührt, weiche Kante am Rand. Klassische Farbregel, keine Erkennung.
/// iOS: Farbregel als Farbtabelle (`cube`), Kreise als Maske (`spotWeight`) → `CIBlendWithMask`.
public enum RedEye {
    /// Farbanteil der Regel (ohne Kante): 0 bei Haut/Grau, 1 bei typischem Blitz-Rot.
    public static func redness(_ r: Float, _ g: Float, _ b: Float) -> Float {
        let other = max(g, b)
        return smoothstep(0.06, 0.22, r - other) * smoothstep(1.55, 2.2, r / max(0.02, other))
    }

    public static func corrected(_ r: Float, _ g: Float, _ b: Float, weight: Float = 1) -> (Float, Float, Float) {
        let k = weight * redness(r, g, b)
        guard k > 0 else { return (r, g, b) }
        let target = (g + b) / 2
        return (r + (target - r) * k, g, b)
    }

    /// Farbtabelle der vollen Korrektur (Kante kommt über die Maske).
    public static func cube(size n: Int = 33) -> [Float] {
        var out = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        let d = Float(n - 1)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let c = corrected(Float(r) / d, Float(g) / d, Float(b) / d)
                    out[i] = c.0; out[i + 1] = c.1; out[i + 2] = c.2; out[i + 3] = 1
                    i += 4
                }
            }
        }
        return out
    }

    /// Kantengewicht an Pixel (x, y) in einem Ausgabebild outW × outH (1 innen, weich zum Rand).
    public static func spotWeight(x: Float, y: Float, outW: Int, outH: Int, spots: [RedEyeSpot]) -> Float {
        let long = Float(max(outW, outH))
        var w: Float = 0
        for s in spots {
            let rad = s.radius * long
            if rad < 0.5 { continue }
            let dx = x - s.center.x * Float(outW), dy = y - s.center.y * Float(outH)
            let d = sqrt(dx * dx + dy * dy) / rad
            if d >= 1 { continue }
            w = max(w, 1 - smoothstep(0.75, 1, d))
        }
        return w
    }

    /// Maske (Graustufen 0…1, Zeilen von oben) in Rastergröße gw × gh.
    public static func mask(spots: [RedEyeSpot], gw: Int, gh: Int) -> [Float] {
        var a = [Float](repeating: 0, count: gw * gh)
        for y in 0..<gh {
            for x in 0..<gw {
                a[y * gw + x] = spotWeight(x: Float(x) + 0.5, y: Float(y) + 0.5, outW: gw, outH: gh, spots: spots)
            }
        }
        return a
    }
}

/// Maske als Raster (lange Kante ≤ 512, Zeilen von oben), bilinear gelesen. Unabhängig von der Exportgröße.
public struct MaskGrid: Sendable {
    public let width: Int
    public let height: Int
    public let values: [Float]

    public static let longEdge = 512

    /// Rastergröße für ein Ausgabebild mit Seitenverhältnis outW/outH.
    public static func gridSize(outW: Int, outH: Int) -> (Int, Int) {
        let aspect = Float(outW) / Float(outH)
        if aspect >= 1 { return (longEdge, max(2, Int(Float(longEdge) / aspect))) }
        return (max(2, Int(Float(longEdge) * aspect)), longEdge)
    }

    public static func of(_ m: Mask, outW: Int, outH: Int) -> MaskGrid {
        let (gw, gh) = gridSize(outW: outW, outH: outH)
        let aspect = Float(outW) / Float(outH)
        switch m {
        case .radial(let center, let rx, let ry, let feather, let invert):
            var a = [Float](repeating: 0, count: gw * gh)
            let f = clamp01(feather)
            for y in 0..<gh {
                let v = (Float(y) + 0.5) / Float(gh)
                for x in 0..<gw {
                    let u = (Float(x) + 0.5) / Float(gw)
                    let dx = (u - center.x) / max(1e-4, rx), dy = (v - center.y) / max(1e-4, ry)
                    let d = sqrt(dx * dx + dy * dy)
                    let w: Float = f <= 0.001 ? (d <= 1 ? 1 : 0) : 1 - smoothstep(1 - f, 1, d)
                    a[y * gw + x] = invert ? 1 - w : w
                }
            }
            return MaskGrid(width: gw, height: gh, values: a)
        case .linear(let start, let end):
            var a = [Float](repeating: 0, count: gw * gh)
            let sx = start.x * aspect, ex = end.x * aspect
            let dx = ex - sx, dy = end.y - start.y
            let len2 = dx * dx + dy * dy
            for y in 0..<gh {
                let v = (Float(y) + 0.5) / Float(gh)
                for x in 0..<gw {
                    let px = (Float(x) + 0.5) / Float(gw) * aspect
                    if len2 < 1e-8 { continue }
                    let t = ((px - sx) * dx + (v - start.y) * dy) / len2
                    a[y * gw + x] = 1 - smoothstep(0, 1, t)
                }
            }
            return MaskGrid(width: gw, height: gh, values: a)
        case .brush(let strokes):
            return MaskGrid(width: gw, height: gh, values: rasterize(strokes, gw: gw, gh: gh))
        }
    }

    public func sample(_ u: Float, _ v: Float) -> Float {
        let w = width, h = height
        if w < 2 || h < 2 { return values.first ?? 0 }
        let fx = min(max(u * Float(w) - 0.5, 0), Float(w - 1)), fy = min(max(v * Float(h) - 0.5, 0), Float(h - 1))
        let x = max(0, min(Int(fx), w - 2)), y = max(0, min(Int(fy), h - 2))
        let tx = fx - Float(x), ty = fy - Float(y)
        let p = values[y * w + x], q = values[y * w + x + 1], r = values[(y + 1) * w + x], s = values[(y + 1) * w + x + 1]
        let top = p + (q - p) * tx, bottom = r + (s - r) * tx
        return top + (bottom - top) * ty
    }

    /// Striche nacheinander (Radierer zieht ab). Radius relativ zur langen Kante.
    public static func rasterize(_ strokes: [BrushStroke], gw: Int, gh: Int) -> [Float] {
        var a = [Float](repeating: 0, count: gw * gh)
        let long = Float(max(gw, gh))
        for s in strokes {
            let rad = max(0.5, s.radius * long)
            let hard = min(max(s.hardness, 0), 0.98)
            let pts = s.points.map { (Float($0.x) * Float(gw), Float($0.y) * Float(gh)) }
            guard !pts.isEmpty else { continue }
            let minX = max(0, Int(pts.map(\.0).min()! - rad)), maxX = min(gw - 1, Int(pts.map(\.0).max()! + rad) + 1)
            let minY = max(0, Int(pts.map(\.1).min()! - rad)), maxY = min(gh - 1, Int(pts.map(\.1).max()! + rad) + 1)
            if minX > maxX || minY > maxY { continue }
            for y in minY...maxY {
                for x in minX...maxX {
                    let px = Float(x) + 0.5, py = Float(y) + 0.5
                    var best = Float.greatestFiniteMagnitude
                    if pts.count == 1 { best = hypotf(px - pts[0].0, py - pts[0].1) } else {
                        for k in 0..<(pts.count - 1) { best = min(best, segDist(px, py, pts[k], pts[k + 1])) }
                    }
                    let t = best / rad
                    if t >= 1 { continue }
                    let wgt: Float = t <= hard ? 1 : 1 - smoothstep(hard, 1, t)
                    let i = y * gw + x
                    a[i] = s.erase ? a[i] * (1 - wgt) : max(a[i], wgt)
                }
            }
        }
        return a
    }

    static func segDist(_ x: Float, _ y: Float, _ a: (Float, Float), _ b: (Float, Float)) -> Float {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let l2 = dx * dx + dy * dy
        let t = l2 < 1e-6 ? 0 : min(max(((x - a.0) * dx + (y - a.1) * dy) / l2, 0), 1)
        return hypotf(x - (a.0 + t * dx), y - (a.1 + t * dy))
    }
}

/// Vignette als Faktorkarte (Zeilen von oben): Faktor 1 + v·0,65·smooth(0,3; 1,05; d), d = Abstand zur Mitte.
public enum VignetteMap {
    public static func factors(strength v: Float, gw: Int, gh: Int) -> [Float] {
        var a = [Float](repeating: 1, count: gw * gh)
        guard abs(v) >= 0.005 else { return a }
        for y in 0..<gh {
            let vv = (Float(y) + 0.5) / Float(gh)
            for x in 0..<gw {
                let u = (Float(x) + 0.5) / Float(gw)
                let dx = (u - 0.5) * 2, dy = (vv - 0.5) * 2
                let d = sqrt(dx * dx + dy * dy) / 1.41421356
                a[y * gw + x] = 1 + v * 0.65 * smoothstep(0.3, 1.05, d)
            }
        }
        return a
    }
}

/// Histogramm (Helligkeit + R/G/B, je 256 Klassen) und Anteil abgeschnittener Lichter/Tiefen. Nur Anzeige.
public struct Histogram: Hashable, Sendable {
    public let luma: [Int]
    public let red: [Int]
    public let green: [Int]
    public let blue: [Int]
    public let total: Int
    public let clippedHigh: Int
    public let clippedLow: Int

    /// Aus RGBA8-Daten (4 Bytes je Pixel), jedes `step`-te Pixel.
    public static func of(rgba: [UInt8], step: Int = 1) -> Histogram {
        var l = [Int](repeating: 0, count: 256), r = l, g = l, b = l
        var n = 0, hi = 0, lo = 0
        var i = 0
        let stride = 4 * max(1, step)
        while i + 2 < rgba.count {
            let rr = Int(rgba[i]), gg = Int(rgba[i + 1]), bb = Int(rgba[i + 2])
            r[rr] += 1; g[gg] += 1; b[bb] += 1
            let y: Float = 0.2126 * Float(rr) + 0.7152 * Float(gg) + 0.0722 * Float(bb) + 0.5
            l[min(max(Int(y), 0), 255)] += 1
            if rr >= 254 || gg >= 254 || bb >= 254 { hi += 1 }
            if rr <= 1 && gg <= 1 && bb <= 1 { lo += 1 }
            n += 1
            i += stride
        }
        return Histogram(luma: l, red: r, green: g, blue: b, total: n, clippedHigh: hi, clippedLow: lo)
    }
}

/// Detail-Stufen: Radien wachsen mit der Ausgabegröße → gleicher Eindruck in Vorschau und Export.
public enum DetailMath {
    public static func clarityRadius(longEdge: Int) -> Int { min(max(longEdge / 140, 2), 48) }
    public static func sharpenBaseRadius(longEdge: Int) -> Int { min(max(longEdge / 1600, 1), 4) }
    public static func sharpenRadius(_ a: Adjustments, longEdge: Int) -> Int {
        let base = sharpenBaseRadius(longEdge: longEdge)
        return a.sharpenRadius < 0.5 ? base : max(1, Int(Float(base) * (0.5 + a.sharpenRadius / 100 * 2.5)))
    }
    public static func sharpenAmount(_ sharpness: Float) -> Float { 1.4 * clamp01(sharpness / 100) }
    /// Körnung: Zellgröße in Pixeln (lange Kante / 1100) und Stärke.
    public static func grainCell(longEdge: Int) -> Float { max(1, Float(longEdge) / 1100) }
}
