import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import PhotoMaidCore
import UIKit
import UniformTypeIdentifiers

/// Ein einziger Core-Image-Graph für Vorschau und Export (gleiche Geometrie, gleiche Farbtabellen, gleiche Reihenfolge
/// wie Android: Geometrie → Rote Augen → Punktstufen → Bereiche → Vignette → Körnung → Klarheit/Schärfe → Ebenen → Rahmen).
/// Arbeitsfarbraum: erweitertes sRGB (gamma-kodiert), damit die Formeln aus PhotoMaidCore genau so wirken wie auf Android.
/// Nie verzerrt (Ausschnitt/Skalierung immer proportional), nie hochskaliert (`ResizeRules.clampToSource`).
final class EditRenderer: @unchecked Sendable {
    static let shared = EditRenderer()

    let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .cacheIntermediates: false,
    ])
    private let lock = NSLock()
    private var cubeCache: [Int: Data] = [:]

    // MARK: Quelle

    /// Quellbild aus Originaldaten, richtig ausgerichtet, Ursprung bei (0, 0).
    static func source(_ data: Data) -> CIImage? {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        return normalized(img)
    }

    static func source(_ cg: CGImage) -> CIImage { normalized(CIImage(cgImage: cg)) }

    static func normalized(_ img: CIImage) -> CIImage {
        img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
    }

    /// Verkleinerte Arbeitskopie für die Vorschau (lange Kante ≤ `maxEdge`). Gleicher Graph, nur weniger Pixel.
    static func downscaled(_ img: CIImage, maxEdge: CGFloat) -> CIImage {
        let long = max(img.extent.width, img.extent.height)
        guard long > maxEdge else { return img }
        let s = maxEdge / long
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = img
        f.scale = Float(s)
        f.aspectRatio = 1
        return normalized(f.outputImage ?? img.transformed(by: CGAffineTransform(scaleX: s, y: s)))
    }

    // MARK: Graph

    /// - Parameter forPreview: Zielgröße (Größe ändern) wird in der Vorschau nicht angewendet (gleiches Aussehen,
    ///   weniger Pixel). Ebenen zeichnet derselbe `LayerRenderer` in Vorschau und Export.
    func render(_ src: CIImage, recipe original: EditRecipe, forPreview: Bool = false, includeLayers: Bool = true) -> CIImage {
        var recipe = original
        if forPreview { recipe.resizeWidth = nil; recipe.resizeHeight = nil }
        let W = Int(src.extent.width.rounded()), H = Int(src.extent.height.rounded())
        guard W > 0, H > 0 else { return src }
        let geo = EditGeometry(src: PxSize(W, H), recipe: recipe)
        let outW = geo.output.width, outH = geo.output.height
        let outRect = CGRect(x: 0, y: 0, width: outW, height: outH)

        var img = Self.warp(src.clampedToExtent(), geo: geo, srcH: Double(H)).cropped(to: outRect)
        // Ränder außerhalb des Bildes (Perspektive) bleiben schwarz statt verschmiert.
        img = img.composited(over: CIImage(color: .black).cropped(to: outRect))

        if recipe.hasRedEye {
            let (gw, gh) = MaskGrid.gridSize(outW: outW, outH: outH)
            let mask = Self.maskImage(RedEye.mask(spots: recipe.redEyes, gw: gw, gh: gh), gw: gw, gh: gh, outW: outW, outH: outH)
            let fixed = cube(img, key: -1) { RedEye.cube() }
            img = Self.blend(fixed, over: img, mask: mask)
        }
        let ops = PointOps(recipe: recipe)
        if !ops.isNeutral { img = cube(img, key: Self.key(recipe.adjust, recipe.filter, recipe.filterIntensity, recipe.colorMix)) { ops.cube() } }
        for local in recipe.locals where !local.adjust.pointNeutral {
            let lops = PointOps(adjust: local.adjust)
            let adjusted = cube(img, key: Self.key(local.adjust, .none, 0, ColorMix())) { lops.cube() }
            let grid = MaskGrid.of(local.mask, outW: outW, outH: outH)
            img = Self.blend(adjusted, over: img, mask: Self.maskImage(grid.values, gw: grid.width, gh: grid.height, outW: outW, outH: outH))
        }
        let vignette = recipe.adjust.vignette / 100
        if abs(vignette) >= 0.005 {
            let (gw, gh) = MaskGrid.gridSize(outW: outW, outH: outH)
            let map = Self.maskImage(VignetteMap.factors(strength: vignette, gw: gw, gh: gh), gw: gw, gh: gh, outW: outW, outH: outH)
            let f = CIFilter.multiplyCompositing()
            f.inputImage = map
            f.backgroundImage = img
            img = (f.outputImage ?? img).cropped(to: outRect)
        }
        let grain = min(1, max(0, recipe.adjust.grain / 100))
        if grain >= 0.005 { img = Self.grain(img, amount: grain, outW: outW, outH: outH) }
        img = Self.detail(img, adjust: recipe.adjust, longEdge: max(outW, outH)).cropped(to: outRect)

        // Abdecken wirkt immer in den Pixeln (nie nur überlagert).
        for case .redact(let r) in recipe.layers { img = Self.redact(img, r, outW: outW, outH: outH) }
        if includeLayers { img = LayerRenderer.draw(recipe.layers, over: img, size: geo.output) }
        if let frame = recipe.frame, !frame.isNeutral { img = Self.frame(img, frame, size: geo.output) }
        return img
    }

    /// Ausgabegröße eines Rezepts (für Anzeige „Größe“ und Pro-Prüfungen).
    static func outputSize(src: PxSize, recipe: EditRecipe) -> PxSize {
        let geo = EditGeometry(src: src, recipe: recipe)
        return FrameMath.layout(image: geo.output, frame: recipe.frame).size
    }

    // MARK: Geometrie (oben links → Core Image unten links)

    static func warp(_ src: CIImage, geo: EditGeometry, srcH: Double) -> CIImage {
        let h = geo.sourceToOutput
        let outH = Double(geo.output.height)
        // ci → tl: (x, H - y); tl → out: H; out tl → ci: (x, outH - y)
        func map(_ x: Double, _ yc: Double) -> CGPoint {
            let (ox, oy) = h.map(x, srcH - yc)
            return CGPoint(x: ox, y: outH - oy)
        }
        if h.isAffine {
            let m = h.m
            let tl = CGAffineTransform(a: m[0], b: m[3], c: m[1], d: m[4], tx: m[2], ty: m[5])
            let fs = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: srcH)
            let fo = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: outH)
            return src.transformed(by: fs.concatenating(tl).concatenating(fo), highQualityDownsample: true)
        }
        let w = Double(geo.src.width), sh = srcH
        let f = CIFilter.perspectiveTransform()
        f.inputImage = src.cropped(to: CGRect(x: 0, y: 0, width: w, height: sh))
        f.topLeft = map(0, sh)
        f.topRight = map(w, sh)
        f.bottomLeft = map(0, 0)
        f.bottomRight = map(w, 0)
        return f.outputImage ?? src
    }

    // MARK: Farbe

    private static func key(_ a: Adjustments, _ f: FilterId, _ i: Float, _ m: ColorMix) -> Int {
        var hasher = Hasher()
        hasher.combine(a)
        hasher.combine(f)
        hasher.combine(i)
        hasher.combine(m)
        return hasher.finalize()
    }

    private func cube(_ img: CIImage, key: Int, make: () -> [Float]) -> CIImage {
        let data: Data
        lock.lock()
        if let hit = cubeCache[key] {
            data = hit
            lock.unlock()
        } else {
            lock.unlock()
            let values = make()
            data = values.withUnsafeBufferPointer { Data(buffer: $0) }
            lock.lock()
            if cubeCache.count > 48 { cubeCache.removeAll() }
            cubeCache[key] = data
            lock.unlock()
        }
        let f = CIFilter.colorCubeWithColorSpace()
        f.inputImage = img
        f.cubeDimension = 33
        f.cubeData = data
        f.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        return f.outputImage ?? img
    }

    /// Graustufen-Raster (Zeilen von oben) als Bild in Ausgabegröße.
    static func maskImage(_ values: [Float], gw: Int, gh: Int, outW: Int, outH: Int) -> CIImage {
        var rgba = [Float](repeating: 1, count: gw * gh * 4)
        for i in 0..<(gw * gh) {
            let v = values[i]
            rgba[i * 4] = v; rgba[i * 4 + 1] = v; rgba[i * 4 + 2] = v
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        let img = CIImage(bitmapData: data, bytesPerRow: gw * 16, size: CGSize(width: gw, height: gh), format: .RGBAf,
                          colorSpace: nil)
        return img.samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: CGFloat(outW) / CGFloat(gw), y: CGFloat(outH) / CGFloat(gh)))
            .cropped(to: CGRect(x: 0, y: 0, width: outW, height: outH))
    }

    static func blend(_ top: CIImage, over base: CIImage, mask: CIImage) -> CIImage {
        let f = CIFilter.blendWithMask()
        f.inputImage = top
        f.backgroundImage = base
        f.maskImage = mask
        return f.outputImage ?? base
    }

    // MARK: Struktur

    static func grain(_ img: CIImage, amount: Float, outW: Int, outH: Int) -> CIImage {
        let cell = DetailMath.grainCell(longEdge: max(outW, outH))
        guard let noise = CIFilter.randomGenerator().outputImage else { return img }
        let k = CGFloat(amount * 0.16 * 1.0 * 2)
        // Graues Rauschen um 0 (r = g = b), weich vergrößert wie das Wertrauschen auf Android.
        let m = CIFilter.colorMatrix()
        m.inputImage = noise.samplingLinear().transformed(by: CGAffineTransform(scaleX: CGFloat(cell), y: CGFloat(cell)))
        m.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: k, y: 0, z: 0, w: 0)
        m.bVector = CIVector(x: k, y: 0, z: 0, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        m.biasVector = CIVector(x: -k / 2, y: -k / 2, z: -k / 2, w: 0)
        guard let offset = m.outputImage?.cropped(to: img.extent) else { return img }
        let add = CIFilter.additionCompositing()
        add.inputImage = offset
        add.backgroundImage = img
        return add.outputImage ?? img
    }

    static func detail(_ input: CIImage, adjust a: Adjustments, longEdge: Int) -> CIImage {
        var img = input
        let extent = input.extent
        if a.noiseReduction >= 0.5 {
            let f = CIFilter.noiseReduction()
            f.inputImage = img
            f.noiseLevel = 0.04 * min(1, a.noiseReduction / 100)
            f.sharpness = 0.4
            img = f.outputImage?.cropped(to: extent) ?? img
        }
        if abs(a.clarity) >= 0.5 {
            let r = Float(DetailMath.clarityRadius(longEdge: longEdge))
            if a.clarity > 0 {
                let f = CIFilter.unsharpMask()
                f.inputImage = img.clampedToExtent()
                f.radius = r
                f.intensity = a.clarity / 100 * 0.7
                img = f.outputImage?.cropped(to: extent) ?? img
            } else {
                let blurred = img.clampedToExtent().applyingGaussianBlur(sigma: Double(r)).cropped(to: extent)
                let d = CIFilter.dissolveTransition()
                d.inputImage = img
                d.targetImage = blurred
                d.time = min(1, -a.clarity / 100 * 0.6)
                img = d.outputImage?.cropped(to: extent) ?? img
            }
        }
        if a.sharpness >= 0.5 {
            let f = CIFilter.unsharpMask()
            f.inputImage = img.clampedToExtent()
            f.radius = Float(DetailMath.sharpenRadius(a, longEdge: longEdge))
            f.intensity = DetailMath.sharpenAmount(a.sharpness)
            img = f.outputImage?.cropped(to: extent) ?? img
        }
        return img
    }

    // MARK: Abdecken und Rahmen

    static func redact(_ img: CIImage, _ r: RedactLayer, outW: Int, outH: Int) -> CIImage {
        let extent = img.extent
        let replacement: CIImage
        switch r.mode {
        case .solid:
            let c = ARGBColor.components(r.color)
            replacement = CIImage(color: CIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b))).cropped(to: extent)
        case .pixelate:
            let f = CIFilter.pixellate()
            f.inputImage = img.clampedToExtent()
            f.scale = Float(r.blockPx(short: min(outW, outH)))
            f.center = .zero
            replacement = f.outputImage?.cropped(to: extent) ?? img
        case .blur:
            let sigma = Double(max(4, Float(min(outW, outH)) * 0.02 * max(0.2, r.strength) * 2))
            replacement = img.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        }
        var values: [Float]
        let (gw, gh) = MaskGrid.gridSize(outW: outW, outH: outH)
        if let rect = r.rect {
            values = [Float](repeating: 0, count: gw * gh)
            for y in 0..<gh {
                let v = (Float(y) + 0.5) / Float(gh)
                guard v >= rect.top && v <= rect.bottom else { continue }
                for x in 0..<gw {
                    let u = (Float(x) + 0.5) / Float(gw)
                    if u >= rect.left && u <= rect.right { values[y * gw + x] = 1 }
                }
            }
        } else {
            values = MaskGrid.rasterize(r.strokes, gw: gw, gh: gh)
        }
        // Deckend: harte Kante (kein durchscheinender Rand).
        values = values.map { $0 >= 0.5 ? 1 : 0 }
        return blend(replacement, over: img, mask: maskImage(values, gw: gw, gh: gh, outW: outW, outH: outH).samplingNearest())
    }

    static func frame(_ img: CIImage, _ f: FrameStyle, size: PxSize) -> CIImage {
        let c = ARGBColor.components(f.color)
        let color = CIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b))
        if f.mode == .inside {
            let b = CGFloat(Float(min(size.width, size.height)) * min(max(f.width, 0), 0.25))
            let inner = CGRect(x: b, y: b, width: CGFloat(size.width) - 2 * b, height: CGFloat(size.height) - 2 * b)
            let border = CIImage(color: color).cropped(to: img.extent)
            let mask = CIImage(color: .white).cropped(to: inner).composited(over: CIImage(color: .black).cropped(to: img.extent))
            return blend(img, over: border, mask: mask)
        }
        let layout = FrameMath.layout(image: size, frame: f)
        let canvas = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: layout.size.width, height: layout.size.height))
        // Lage oben links → unten links.
        let y = layout.size.height - layout.y - size.height
        return img.transformed(by: CGAffineTransform(translationX: CGFloat(layout.x), y: CGFloat(y))).composited(over: canvas)
    }

    // MARK: Ausgabe

    func cgImage(_ img: CIImage) -> CGImage? {
        context.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Kodiert das Ergebnis neu. Metadaten des Originals bleiben (Aufnahmedatum, Kamera); Standort nur auf Wunsch.
    /// Ausrichtung ist bereits angewendet (Orientierung = 1).
    func encode(_ img: CIImage, format: EditFormat, metadata: [String: Any]?, removeLocation: Bool,
                quality: Double = EditFormat.quality) -> Data? {
        guard let cg = cgImage(img) else { return nil }
        let out = NSMutableData()
        let type = (UTType(format.utType) ?? .jpeg).identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, type, 1, nil) else { return nil }
        var props = metadata ?? [:]
        props[kCGImagePropertyOrientation as String] = 1
        props[kCGImagePropertyPixelWidth as String] = cg.width
        props[kCGImagePropertyPixelHeight as String] = cg.height
        if removeLocation { props[kCGImagePropertyGPSDictionary as String] = nil }
        if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            tiff[kCGImagePropertyTIFFSoftware as String] = AppConfig.brandName
            props[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if format != .png { props[kCGImageDestinationLossyCompressionQuality as String] = min(max(quality, 0.3), 1) }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Metadaten des Originals (EXIF/TIFF/GPS) lesen.
    static func metadata(_ data: Data) -> (props: [String: Any], uti: String?)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
        return (props, CGImageSourceGetType(src) as String?)
    }
}
