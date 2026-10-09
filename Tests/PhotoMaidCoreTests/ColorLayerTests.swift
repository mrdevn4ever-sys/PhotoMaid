import Testing
import Foundation
@testable import PhotoMaidCore

/// Ports der punktweisen Teile von `PixelPipelineTest.kt` sowie `LayersTest.kt` und `NoDistortionTest.kt`.
/// Ortsabhängige Stufen (Vignette, Körnung, Masken) rechnet auf iOS Core Image; ihre Karten testet `EditCoreTests`.
@Suite struct ColorPipelineTests {
    func lum(_ c: (Int, Int, Int)) -> Double { 0.2126 * Double(c.0) + 0.7152 * Double(c.1) + 0.0722 * Double(c.2) }
    func ops(_ a: Adjustments = Adjustments(), mix: ColorMix = ColorMix(), filter: FilterId = .none) -> PointOps {
        PointOps(adjust: a, filter: filter, intensity: 1, mix: mix)
    }

    @Test func neutralIsExactIdentity() {
        for i in 0..<64 {
            let c = (i * 3, 255 - i * 2, (i * 37) % 256)
            #expect(ops().applyPoint(r: c.0, g: c.1, b: c.2) == c)
        }
        var r = EditRecipe(); r.filter = .mono; r.filterIntensity = 0
        #expect(PointOps(recipe: r).isNeutral)
    }

    @Test func highlightsOnlyTouchBrightAndShadowsOnlyDark() {
        var hlA = Adjustments(); hlA.highlights = -100
        let hl = ops(hlA)
        #expect(abs(lum(hl.applyPoint(r: 30, g: 30, b: 30)) - 30) <= 1)
        #expect(lum(hl.applyPoint(r: 225, g: 225, b: 225)) < 225 - 15)
        var shA = Adjustments(); shA.shadows = 100
        let sh = ops(shA)
        #expect(abs(lum(sh.applyPoint(r: 225, g: 225, b: 225)) - 225) <= 1)
        #expect(lum(sh.applyPoint(r: 30, g: 30, b: 30)) > 30 + 8)
        #expect(sh.applyPoint(r: 0, g: 0, b: 0).0 == 0) // keine graue Suppe
        var exA = Adjustments(); exA.exposure = 50
        let ex = ops(exA)
        #expect(lum(ex.applyPoint(r: 128, g: 128, b: 128)) > 128 + 20)
        #expect(ex.applyPoint(r: 250, g: 250, b: 250).0 <= 255)
    }

    @Test func toneCurveIsMonotoneForExtremeSettings() {
        var a = Adjustments()
        a.exposure = 100; a.contrast = 100; a.shadows = 100; a.highlights = -100; a.whites = 100; a.blacks = -100; a.brightness = -100
        let lut = ToneCurve.lut(a)
        #expect(zip(lut, lut.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(lut.allSatisfy { (0...1).contains($0) })
    }

    @Test func toneKeepsHueOfSaturatedColour() {
        var a = Adjustments(); a.shadows = 60; a.exposure = 30
        let out = ops(a).applyPoint(r: 200, g: 40, b: 30)
        #expect(out.0 > out.1 && out.0 > out.2)
    }

    @Test func colorMixChangesOnlyItsBand() {
        let p = ops(mix: ColorMix().with(.blue, HslShift(saturation: -100)))
        let ob = p.applyPoint(r: 40, g: 80, b: 220)
        #expect(ob.2 - ob.0 < (220 - 40) / 3)
        #expect(p.applyPoint(r: 220, g: 40, b: 40) == (220, 40, 40))
        #expect(p.applyPoint(r: 120, g: 120, b: 120) == (120, 120, 120))
        let hue = ops(mix: ColorMix().with(.green, HslShift(hue: 100))).applyPoint(r: 40, g: 200, b: 40)
        #expect(hue.2 > 40 || hue.0 > 40)
    }

    @Test func vibranceFavoursMutedColours() {
        var a = Adjustments(); a.vibrance = 100
        let p = ops(a)
        let m = p.applyPoint(r: 140, g: 120, b: 110), v = p.applyPoint(r: 230, g: 30, b: 20)
        let dm = (m.0 - m.2) - (140 - 110), dv = (v.0 - v.2) - (230 - 20)
        #expect(dm > 0 && dm > dv)
    }

    @Test func tintAndWarmthDirections() {
        var t = Adjustments(); t.tint = 100
        let mag = ops(t).applyPoint(r: 128, g: 128, b: 128)
        #expect(mag.1 < mag.0 && mag.1 < mag.2)
        var w = Adjustments(); w.warmth = 100
        let warm = ops(w).applyPoint(r: 128, g: 128, b: 128)
        #expect(warm.0 > warm.2)
    }

    @Test func cubeMatchesPointOpsAndIsIdentityWhenNeutral() {
        let n = 9
        func at(_ cube: [Float], _ r: Int, _ g: Int, _ b: Int) -> (Int, Int, Int) {
            let i = ((b * n + g) * n + r) * 4
            func q(_ v: Float) -> Int { min(max(Int(v * 255 + 0.5), 0), 255) }
            return (q(cube[i]), q(cube[i + 1]), q(cube[i + 2]))
        }
        #expect(at(ops().cube(size: n), 8, 0, 4) == (255, 0, 128))
        var a = Adjustments(); a.contrast = 40; a.warmth = 30
        let p = ops(a, filter: .sepia)
        let cube = p.cube(size: n)
        #expect(at(cube, 8, 0, 0) == p.applyPoint(r: 255, g: 0, b: 0))
        #expect(at(cube, 0, 8, 8) == p.applyPoint(r: 0, g: 255, b: 255))
    }

    @Test func redEyeCubeLeavesNonRedUntouched() {
        let n = 5
        let cube = RedEye.cube(size: n)
        let grey = ((2 * n + 2) * n + 2) * 4 // (0,5; 0,5; 0,5)
        #expect(abs(cube[grey] - 0.5) < 1e-6)
        let red = ((0 * n + 0) * n + 4) * 4 // (1, 0, 0)
        #expect(cube[red] < 0.05)
    }
}

@Suite struct LayerTests {
    let layers: [Layer] = [
        .text(TextLayer(id: "t", text: "Hallo")), .sticker(StickerLayer(id: "s", kind: .emoji, value: "🎉")),
        .draw(DrawLayer(id: "d", strokes: [DrawStroke(points: [NormPoint(0.1, 0.1), NormPoint(0.2, 0.3)], width: 0.01, color: -1,
                                                       brush: .marker)])),
        .shape(ShapeLayer(id: "a", kind: .arrow, start: NormPoint(0.1, 0.1), end: NormPoint(0.5, 0.5))),
        .redact(RedactLayer(id: "r", mode: .pixelate, rect: NormRect(left: 0.2, top: 0.2, right: 0.4, bottom: 0.3))),
    ]

    @Test func recipeWithLayersRoundTripsAsJson() throws {
        var r = EditRecipe(); r.layers = layers; r.frame = FrameStyle(width: 0.05)
        #expect(try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(r)) == r)
        // Gleicher Diskriminator wie kotlinx.serialization.
        let json = String(data: try JSONEncoder().encode(layers[0]), encoding: .utf8)!
        #expect(json.contains(#""type":"text""#))
    }

    @Test func markupIsFreeFrameIsPro() {
        var m = EditRecipe(); m.layers = layers
        #expect(!m.usesProTools)
        var f = EditRecipe(); f.frame = FrameStyle()
        #expect(f.usesProTools)
        #expect(!m.isIdentity)
        m.quarterTurns = 1
        #expect(!m.isOrientationOnly)
    }

    @Test func frameLayout() {
        let img = PxSize(1000, 800)
        let inside = FrameMath.layout(image: img, frame: FrameStyle(mode: .inside))
        #expect(inside.size == img && inside.x == 0 && inside.y == 0)
        let out = FrameMath.layout(image: img, frame: FrameStyle(width: 0.05))
        #expect(out.size == PxSize(1080, 880) && out.x == 40 && out.y == 40)
        let pass = FrameMath.layout(image: img, frame: FrameStyle(width: 0, aspect: 0.8))
        #expect(pass.size == PxSize(1000, 1250) && pass.x == 0 && pass.y == 225)
    }

    @Test func layerOrderingAndDuplicate() {
        #expect(LayerOps.toFront(layers, id: "t").last?.id == "t")
        #expect(LayerOps.toBack(layers, id: "r").first?.id == "r")
        let dup = LayerOps.duplicate(layers, id: "t", newID: "t2")
        #expect(dup.count == 6)
        if case .text(let t) = dup.last! { #expect(abs(t.center.x - 0.53) < 1e-5) } else { Issue.record("Text erwartet") }
        #expect(LayerOps.remove(layers, id: "s").count == 4)
    }

    @Test func snappingAndRedactBlocks() {
        #expect(LayerOps.snap(0.51) == (0.5, true))
        #expect(LayerOps.snap(0.53).snapped == false)
        #expect(LayerOps.snapRotation(87) == (90, true))
        #expect(LayerOps.snapRotation(45).snapped == false)
        var weak = RedactLayer(id: "x"); weak.strength = 0
        #expect(weak.blockPx(short: 200) >= 8)
        var strong = RedactLayer(id: "x"); strong.strength = 1
        #expect(strong.blockPx(short: 3000) >= 150)
    }

    @Test func argbHelpersMatchAndroidInts() {
        #expect(ARGBColor.make(r: 1, g: 1, b: 1) == -1) // 0xFFFFFFFF als Android-Int
        let c = ARGBColor.components(ARGB(Int32(bitPattern: 0xFFFF_3B30)))
        #expect(abs(c.r - 1) < 1e-6 && abs(c.g - 59 / 255) < 1e-6 && c.a == 1)
    }
}

@Suite struct NoDistortionTests {
    func sameRatio(_ a: PxSize, _ b: PxSize) -> Bool {
        abs(Double(a.width) / Double(a.height) - Double(b.width) / Double(b.height)) < 2 / Double(min(b.width, b.height))
    }

    @Test func oldRecipeWithIndependentSidesIsNotStretched() {
        let crop = PxSize(4000, 3000)
        #expect(ResizeRules.clampToSource(2000, 2000, crop: crop) == PxSize(2000, 1500))
        #expect(sameRatio(crop, ResizeRules.clampToSource(100, 3000, crop: crop)))
        #expect(ResizeRules.clampToSource(9000, 9000, crop: crop) == crop)
        #expect(ResizeRules.clampToSource(nil, 10, crop: crop) == crop)
    }

    @Test func presetsAndFieldsKeepRatio() {
        let crop = PxSize(3024, 4032)
        for p in ResizeRules.presets(for: crop) { #expect(sameRatio(crop, ResizeRules.forLongEdge(crop, p))) }
        #expect(sameRatio(crop, ResizeRules.forWidth(crop, 1000)))
        #expect(sameRatio(crop, ResizeRules.forHeight(crop, 999)))
    }

    @Test func geometryOutputFollowsCrop() {
        var r = EditRecipe(); r.resizeWidth = 1000; r.resizeHeight = 1000
        #expect(sameRatio(PxSize(4000, 3000), EditGeometry(src: PxSize(4000, 3000), recipe: r).output))
    }
}
