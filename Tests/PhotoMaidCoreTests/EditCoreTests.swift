import Testing
import Foundation
@testable import PhotoMaidCore

/// Ports von `EditCoreTest.kt` und `PerspectiveTest.kt` (Geometrie, Ausschnitt, Größe, Farbe, Perspektive, Rote Augen).
@Suite struct EditCoreTests {
    let photo = PxSize(4000, 3000)
    func near(_ a: Double, _ b: Double, _ eps: Double = 0.5) -> Bool { abs(a - b) <= eps }

    @Test func identityRecipeKeepsSizeAndPixelsInPlace() {
        let g = EditGeometry(src: photo, recipe: EditRecipe())
        #expect(g.output == photo)
        let (x, y) = g.sourceToOutput.map(123, 456)
        #expect(near(x, 123) && near(y, 456))
        #expect(EditRecipe().isIdentity)
    }

    @Test func quarterTurnSwapsFrameAndMapsCorners() {
        var r = EditRecipe(); r.quarterTurns = 1
        let g = EditGeometry(src: photo, recipe: r)
        #expect(g.output == PxSize(3000, 4000))
        let (x, y) = g.sourceToOutput.map(0, 0)
        #expect(near(x, 3000) && near(y, 0))
        #expect(r.isOrientationOnly)
        #expect(!r.usesProTools)
    }

    @Test func flipMirrorsHorizontally() {
        var r = EditRecipe(); r.flipH = true
        #expect(near(EditGeometry(src: photo, recipe: r).sourceToOutput.map(0, 10).0, 4000))
    }

    @Test func straightenNeverShowsEmptyCorners() {
        for deg: Float in [-45, -12.5, 3, 30, 45] {
            var r = EditRecipe(); r.straighten = deg
            let inv = EditGeometry(src: photo, recipe: r).sourceToOutput.inverse()!
            for (x, y) in [(0.0, 0.0), (4000, 0), (0, 3000), (4000, 3000)] {
                let (sx, sy) = inv.map(x, y)
                #expect(sx >= -0.5 && sx <= 4000.5 && sy >= -0.5 && sy <= 3000.5, "deg=\(deg)")
            }
        }
        #expect(near(EditGeometry.coverScale(4000, 3000, 0), 1, 1e-9))
    }

    @Test func cropAndResizeComposeIntoOutput() {
        var r = EditRecipe()
        r.crop = NormRect(left: 0.25, top: 0.5, right: 0.75, bottom: 1)
        r.resizeWidth = 1000; r.resizeHeight = 750
        let g = EditGeometry(src: photo, recipe: r)
        #expect(g.cropSize == PxSize(2000, 1500))
        #expect(g.output == PxSize(1000, 750))
        let (x, y) = g.sourceToOutput.map(1000, 1500)
        #expect(near(x, 0) && near(y, 0))
        #expect(g.sourceBounds() == (1000, 1500, 3000, 3000))
        #expect(r.usesProTools)
    }

    @Test func resizeNeverUpscales() {
        var r = EditRecipe(); r.resizeWidth = 9000; r.resizeHeight = 9000
        #expect(EditGeometry(src: photo, recipe: r).output == photo)
        #expect(ResizeRules.presets(for: PxSize(3000, 2000)) == [2048, 1080])
        #expect(ResizeRules.forLongEdge(photo, 2048) == PxSize(2048, 1536))
        #expect(ResizeRules.forLongEdge(PxSize(3000, 4000), 2048) == PxSize(1536, 2048))
        #expect(ResizeRules.forWidth(photo, 8000) == PxSize(4000, 3000))
        #expect(ResizeRules.forHeight(photo, 750) == PxSize(1000, 750))
        // Nie verzerren: getrennte Zielwerte werden mit einem gemeinsamen Faktor eingehalten.
        #expect(ResizeRules.clampToSource(1000, 1000, crop: photo) == PxSize(1000, 750))
    }

    @Test func rotatingKeepsCropOnSameImageArea() {
        var left = EditRecipe(); left.crop = NormRect(left: 0, top: 0, right: 0.5, bottom: 1)
        let turned = left.rotatedClockwise()
        #expect(turned.crop == NormRect(left: 0, top: 0, right: 1, bottom: 0.5))
        #expect(turned.turns == 1)
    }

    @Test func aspectFitAndDragKeepRatio() {
        let sq = CropMath.fitAspect(.full, ratio: 1, frame: photo)
        #expect(near(Double((sq.right - sq.left) * 4000), 3000, 1) && near(Double((sq.bottom - sq.top) * 3000), 3000, 1))
        #expect(CropMath.ratio(.square, frame: photo, landscape: false) == 1)
        #expect(CropMath.ratio(.r4x5, frame: photo, landscape: false) == 0.8)
        #expect(CropMath.ratio(.r4x5, frame: photo, landscape: true) == 1.25)
        #expect(CropMath.ratio(.original, frame: photo, landscape: false) == 4000.0 / 3000.0)
        let dragged = CropMath.drag(sq, handle: .topLeft, dx: 0.1, dy: 0.05, frame: photo, ratio: 1)
        #expect(near(Double((dragged.right - dragged.left) * 4000), Double((dragged.bottom - dragged.top) * 3000), 2))
        #expect(dragged.left >= 0 && dragged.top >= 0 && dragged.right <= 1 && dragged.bottom <= 1)
        let tiny = CropMath.drag(.full, handle: .right, dx: -5, dy: 0, frame: photo, ratio: nil)
        #expect(tiny.width > 0.05)
        let moved = CropMath.drag(NormRect(left: 0.2, top: 0.2, right: 0.6, bottom: 0.6), handle: .move, dx: 0.9, dy: -0.9,
                                  frame: photo, ratio: nil)
        #expect(abs(moved.left - 0.6) < 1e-5 && abs(moved.top) < 1e-5 && abs(moved.right - 1) < 1e-5 && abs(moved.bottom - 0.4) < 1e-5)
    }

    @Test func colorMatricesAreNeutralAtZeroAndMonoIsGray() {
        #expect(zip(ColorMatrices.forRecipe(EditRecipe()), ColorMatrices.identity).allSatisfy { abs($0 - $1) < 1e-5 })
        let gray = ColorMatrices.apply(ColorMatrices.filter(.mono), r: 255, g: 0, b: 0)
        #expect(gray.0 == gray.1 && gray.1 == gray.2 && gray.3 == 255)
        var sepia0 = EditRecipe(); sepia0.filter = .sepia; sepia0.filterIntensity = 0
        #expect(zip(ColorMatrices.forRecipe(sepia0), ColorMatrices.identity).allSatisfy { abs($0 - $1) < 1e-5 })
        #expect(ColorMatrices.apply(ColorMatrices.brightness(50), r: 128, g: 128, b: 128).0 > 128)
        #expect(ColorMatrices.apply(ColorMatrices.brightness(100), r: 255, g: 255, b: 255).0 == 255)
        let w = ColorMatrices.apply(ColorMatrices.warmth(100), r: 128, g: 128, b: 128)
        #expect(w.0 > w.2)
        var c = EditRecipe(); c.adjust.contrast = 20
        #expect(c.hasColor)
    }

    @Test func trimRangeClampsToVideo() {
        #expect(TrimRange.clamp(start: -50, end: 200, totalMs: 10_000) == TrimRange(startMs: 0, endMs: 1_000))
        #expect(TrimRange.clamp(start: 9_800, end: 12_000, totalMs: 10_000) == TrimRange(startMs: 9_000, endMs: 10_000))
        #expect(TrimRange.clamp(start: 2_000, end: 7_000, totalMs: 10_000) == TrimRange(startMs: 2_000, endMs: 7_000))
    }

    @Test func formatsAndNames() {
        #expect(EditFormat.forSource(uti: "public.png") == .png)
        #expect(EditFormat.forSource(uti: "public.heic") == .heic) // iOS: HEIC bleibt HEIC
        #expect(EditFormat.forSource(uti: nil) == .jpeg)
        #expect(EditNames.copyName(original: "IMG_1.HEIC", suffix: "bearbeitet", fileExtension: "jpg") == "IMG_1_bearbeitet.jpg")
        #expect(EditNames.copyName(original: "a/b.png", suffix: "bearbeitet", fileExtension: "png") == "a_b_bearbeitet.png")
        #expect(EditNames.sameName(original: "IMG_1.HEIC", fileExtension: "jpg") == "IMG_1.jpg")
    }

    @Test func feedSessionReplacesEditedItemInPlace() {
        let a = ItemReference.photo("a"), b = ItemReference.photo("b"), n = ItemReference.photo("a2")
        var s = FeedSession(items: [a, b])
        s.markPreviewReady(a)
        s.replaceItem(a, with: n)
        #expect(s.items == [n, b])
        #expect(s.current == n)
        #expect(s.summary.reviewed == 0)
        #expect(!s.isPreviewReady(n))
        s.replaceItem(n, with: b)
        #expect(s.items == [n, b])
    }

    @Test func exifOrientationComposesLikeTheRenderer() {
        typealias M = ExifOrientationMath
        #expect(M.compose(current: 1, turns: 1, flipH: false, flipV: false) == 6)
        #expect(M.compose(current: 6, turns: 1, flipH: false, flipV: false) == 3)
        #expect(M.compose(current: 8, turns: 1, flipH: false, flipV: false) == 1)
        #expect(M.compose(current: 1, turns: 0, flipH: true, flipV: false) == 2)
        #expect(M.compose(current: 1, turns: 0, flipH: false, flipV: true) == 4)
        #expect(M.compose(current: 1, turns: 0, flipH: true, flipV: true) == 3)
        #expect(M.compose(current: 0, turns: 1, flipH: false, flipV: false) == 6)
        #expect(M.compose(current: 1, turns: 1, flipH: true, flipV: false) == 5)
        let exif: [Int: Affine] = [1: Affine(), 2: .scale(-1, 1), 3: .rotate(degrees: 180), 4: .scale(1, -1),
                                   5: Affine(a: 0, b: 1, c: 1, d: 0), 6: .rotate(degrees: 90), 7: Affine(a: 0, b: -1, c: -1, d: 0),
                                   8: .rotate(degrees: 270)]
        func same(_ x: Affine, _ y: Affine) -> Bool { [x.a - y.a, x.b - y.b, x.c - y.c, x.d - y.d].allSatisfy { abs($0) < 1e-9 } }
        for o in 1...8 { for t in 0...3 { for h in [false, true] { for v in [false, true] {
            let recipe = Affine.scale(h ? -1 : 1, v ? -1 : 1) * Affine.rotate(degrees: 90 * Double(t))
            #expect(same(exif[M.compose(current: o, turns: t, flipH: h, flipV: v)]!, recipe * exif[o]!), "o=\(o) t=\(t) h=\(h) v=\(v)")
        } } } }
    }

    // MARK: Perspektive

    @Test func homographyMapsFourPointsExactly() throws {
        let src = [(10.0, 20.0), (300, 5), (320, 260), (0, 240)]
        let dst = [(0.0, 0.0), (100, 0), (100, 80), (0, 80)]
        let h = try #require(Homography.fromPoints(src, dst))
        for i in 0..<4 {
            let (x, y) = h.map(src[i].0, src[i].1)
            #expect(abs(x - dst[i].0) < 1e-6 && abs(y - dst[i].1) < 1e-6)
        }
        let (bx, by) = try #require(h.inverse()).map(100, 80)
        #expect(abs(bx - 320) < 1e-6 && abs(by - 260) < 1e-6)
    }

    @Test func identityQuadChangesNothing() {
        var r = EditRecipe(); r.straighten = 3
        var q = r; q.perspective = .full
        let a = EditGeometry(src: photo, recipe: r), b = EditGeometry(src: photo, recipe: q)
        #expect(a.frame == b.frame)
        let (x1, y1) = a.sourceToOutput.map(123, 456), (x2, y2) = b.sourceToOutput.map(123, 456)
        #expect(abs(x1 - x2) < 1e-6 && abs(y1 - y2) < 1e-6)
    }

    @Test func keystoneMapsQuadCornersToFrameCornersAndKeepsPixelBudget() {
        let q = PerspectiveMath.keystone(vertical: 60, horizontal: 0)
        var r = EditRecipe(); r.perspective = q
        let g = EditGeometry(src: photo, recipe: r)
        #expect(g.frame.pixels <= photo.pixels)
        let (x, y) = g.sourceToOutput.map(Double(q.tl.x) * 4000, Double(q.tl.y) * 3000)
        #expect(abs(x) < 1e-3 && abs(y) < 1e-3)
        let (x2, y2) = g.sourceToOutput.map(Double(q.br.x) * 4000, Double(q.br.y) * 3000)
        #expect(abs(x2 - Double(g.output.width)) < 1e-3 && abs(y2 - Double(g.output.height)) < 1e-3)
        let sb = g.sourceBounds()
        #expect(sb.0 <= Int(q.bl.x * 4000) && sb.2 >= Int(q.br.x * 4000) - 1)
    }

    @Test func rotatingKeepsPerspectiveOnTheSameImageContent() {
        var r0 = EditRecipe()
        r0.perspective = Quad(tl: NormPoint(0.1, 0.05), tr: NormPoint(0.85, 0.1), br: NormPoint(0.95, 0.9), bl: NormPoint(0.05, 0.95))
        let r1 = r0.rotatedClockwise()
        let g0 = EditGeometry(src: photo, recipe: r0), g1 = EditGeometry(src: photo, recipe: r1)
        let (x0, y0) = g0.sourceToOutput.map(2100, 1300), (x1, y1) = g1.sourceToOutput.map(2100, 1300)
        #expect(abs(Double(g0.output.width) - Double(g1.output.height)) <= 2)
        #expect(abs(Double(g1.output.width) - y0 - x1) <= 3 && abs(x0 - y1) <= 3)
    }

    @Test func invalidCornerMoveIsRejected() {
        #expect(PerspectiveMath.moveCorner(.full, 0, x: 1, y: 1) == .full)
        #expect(!PerspectiveMath.isValid(Quad(tl: NormPoint(0, 0), tr: NormPoint(0.05, 0), br: NormPoint(0.05, 1), bl: NormPoint(0, 1))))
        #expect(PerspectiveMath.moveCorner(.full, 0, x: 0.2, y: 0.1).tl == NormPoint(0.2, 0.1))
    }

    @Test func redEyeRemovesRedInsideOnlyAndSparesSkin() {
        let spots = [RedEyeSpot(center: NormPoint(0.5, 0.5), radius: 0.3)]
        func apply(_ r: Int, _ g: Int, _ b: Int, x: Int, y: Int) -> Int {
            let w = RedEye.spotWeight(x: Float(x) + 0.5, y: Float(y) + 0.5, outW: 100, outH: 100, spots: spots)
            let c = RedEye.corrected(Float(r) / 255, Float(g) / 255, Float(b) / 255, weight: w)
            return Int(c.0 * 255 + 0.5)
        }
        #expect(apply(0xD0, 0x20, 0x20, x: 40, y: 50) < 60)   // Pupille ohne Rot
        #expect(apply(0xE0, 0xA8, 0x8C, x: 60, y: 50) == 0xE0) // Haut im Kreis bleibt
        #expect(apply(0xD0, 0x20, 0x20, x: 5, y: 50) == 0xD0)  // außerhalb des Kreises bleibt alles
    }

    @Test func mixerDesaturationKeepsLuminance() {
        var r = EditRecipe()
        r.colorMix = ColorMix().with(.blue, HslShift(saturation: -100))
        let out = PointOps(recipe: r).applyPoint(r: 0x7F, g: 0xB3, b: 0xF5)
        func luma(_ c: (Int, Int, Int)) -> Double { 0.2126 * Double(c.0) + 0.7152 * Double(c.1) + 0.0722 * Double(c.2) }
        #expect(abs(luma((0x7F, 0xB3, 0xF5)) - luma(out)) <= 4)
        #expect(out.2 - out.0 < (0xF5 - 0x7F) / 2)
    }

    @Test func pointOpsNeutralAndCubeShape() {
        #expect(PointOps(recipe: EditRecipe()).isNeutral)
        let cube = PointOps(recipe: EditRecipe()).cube(size: 9)
        #expect(cube.count == 9 * 9 * 9 * 4)
        // Neutral: Tabelle = Eingang (r schnellste Achse).
        #expect(abs(cube[4] - 0.125) < 1e-6 && cube[5] == 0 && cube[6] == 0) // Index (r=1,g=0,b=0)
        var bright = EditRecipe(); bright.adjust.exposure = 50
        let c = PointOps(recipe: bright).applyPoint(r: 100, g: 100, b: 100)
        #expect(c.0 > 100 && c.0 == c.1 && c.1 == c.2)
    }

    @Test func toneCurveIsMonotonicAndBounded() {
        var a = Adjustments()
        a.highlights = -80; a.shadows = 70; a.contrast = 40; a.exposure = -30; a.whites = 50; a.blacks = -50
        let lut = ToneCurve.lut(a)
        #expect(zip(lut, lut.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(lut.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func masksAndVignette() {
        let radial = MaskGrid.of(.radial(center: NormPoint(0.5, 0.5), rx: 0.25, ry: 0.25, feather: 0, invert: false), outW: 1000, outH: 1000)
        #expect(radial.sample(0.5, 0.5) == 1 && radial.sample(0.05, 0.05) == 0)
        let linear = MaskGrid.of(.linear(start: NormPoint(0.5, 0), end: NormPoint(0.5, 1)), outW: 800, outH: 600)
        #expect(linear.sample(0.5, 0.02) > 0.95 && linear.sample(0.5, 0.98) < 0.05)
        let brush = MaskGrid.of(.brush(strokes: [BrushStroke(points: [NormPoint(0.2, 0.5), NormPoint(0.8, 0.5)], radius: 0.05)]), outW: 1000, outH: 500)
        #expect(brush.sample(0.5, 0.5) > 0.9 && brush.sample(0.5, 0.05) == 0)
        let v = VignetteMap.factors(strength: -1, gw: 64, gh: 64)
        #expect(v[32 * 64 + 32] > 0.99 && v[0] < 0.5)
        #expect(VignetteMap.factors(strength: 0, gw: 4, gh: 4).allSatisfy { $0 == 1 })
    }

    @Test func histogramCountsAndClipping() {
        let px: [UInt8] = [255, 255, 255, 255, 0, 0, 0, 255, 128, 128, 128, 255]
        let h = Histogram.of(rgba: px)
        #expect(h.total == 3 && h.clippedHigh == 1 && h.clippedLow == 1 && h.luma[128] == 1)
    }

    @Test func recipeCodableRoundTripIncludingLayers() throws {
        var r = EditRecipe()
        r.quarterTurns = 1
        r.adjust.highlights = -20
        r.colorMix = ColorMix().with(.red, HslShift(hue: 10))
        r.locals = [LocalAdjustment(mask: .radial(center: NormPoint(0.3, 0.3), rx: 0.2, ry: 0.1, feather: 0.5, invert: true))]
        r.layers = [.text(TextLayer(id: "t", text: "Hallo")), .redact(RedactLayer(id: "r", rect: .full))]
        r.frame = FrameStyle(width: 0.05)
        let back = try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(r))
        #expect(back == r)
        // Ältere Entwürfe ohne neue Felder lassen sich lesen.
        let old = try JSONDecoder().decode(EditRecipe.self, from: Data(#"{"quarterTurns":2}"#.utf8))
        #expect(old.turns == 2 && old.layers.isEmpty)
        // ColorMix wie kotlinx: Farbbänder als Objekt-Schlüssel.
        let mixJSON = String(data: try JSONEncoder().encode(ColorMix().with(.blue, HslShift())), encoding: .utf8)!
        #expect(mixJSON.contains("\"BLUE\""))
    }
}
