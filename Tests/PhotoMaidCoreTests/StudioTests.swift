import Testing
import Foundation
@testable import PhotoMaidCore

/// Ports von `CollageTest.kt`, `VideoPlanTest.kt`, `MoviePlanTest.kt`.
@Suite struct CollageTests {
    func area(_ r: NormRect) -> Float { r.width * r.height }

    @Test func everyTemplateTilesTheSquareWithoutGaps() {
        for n in 2...20 {
            let ts = CollageLayout.templates(for: n)
            #expect(!ts.isEmpty, "n=\(n)")
            for t in ts {
                let cells = CollageLayout.cells(CollageLayout.template(t, n))
                #expect(cells.count == n, "\(t) n=\(n)")
                #expect(Set(cells.keys) == Set(0..<n), "\(t) n=\(n)")
                #expect(abs(cells.values.reduce(0) { $0 + area($1) } - 1) < 1e-3, "\(t) n=\(n)")
            }
        }
        #expect(CollageLayout.templates(for: 3).count >= 6)
    }

    @Test func movingADividerResizesNeighboursAndClamps() {
        let tree = CollageLayout.template("c:1,1", 2)
        let d = CollageLayout.dividers(tree)
        #expect(d.count == 1 && d[0].vertical && abs(d[0].position - 0.5) < 1e-5)
        let cells = CollageLayout.cells(CollageLayout.moveDivider(tree, d[0], to: 0.7))
        #expect(abs(cells[0]!.width - 0.7) < 1e-4 && abs(cells[1]!.width - 0.3) < 1e-4)
        let edge = CollageLayout.cells(CollageLayout.moveDivider(tree, d[0], to: 0.99))
        #expect(edge[1]!.width >= 0.05 - 1e-4)
        let t3 = CollageLayout.template("r:1,2", 3)
        let inner = CollageLayout.dividers(t3).first { !$0.path.isEmpty }!
        let c3 = CollageLayout.cells(CollageLayout.moveDivider(t3, inner, to: inner.parent.left + inner.parent.width * 0.25))
        #expect(abs(c3[1]!.width - 0.25) < 1e-3)
    }

    @Test func spacingKeepsCellsInsideAndApart() {
        var p = CollageProject.create(id: "x", ids: ["a", "b", "c", "d"])
        p.spacing = 0.04; p.margin = 0.05; p.aspect = 1
        let rects = p.cellRects()
        #expect(rects.allSatisfy { $0.left >= 0.05 - 1e-4 && $0.right <= 0.95 + 1e-4 })
        let a = rects[0], b = rects[1]
        #expect(b.left - a.right >= 0.04 - 1e-3 || b.top - a.bottom >= 0.04 - 1e-3)
    }

    @Test func swapRemoveAddAndJson() throws {
        let p = CollageProject.create(id: "x", ids: ["a", "b", "c"])
        #expect(p.swap(0, 1).items.map(\.mediaId) == ["b", "a", "c"])
        let r = p.removeItem(1)
        #expect(r.count == 2 && CollageLayout.leafCount(r.tree) == 2)
        let add = p.addItems(["d", "e"])
        #expect(CollageLayout.leafCount(add.tree) == 5)
        #expect(try JSONDecoder().decode(CollageProject.self, from: JSONEncoder().encode(add)) == add)
        #expect(p.removeItem(0).removeItem(0).count == 1)
        #expect(p.removeItem(0).removeItem(0).removeItem(0).count == 1)
    }

    @Test func cellFitCoversAndPans() {
        let s = CellFit.source(imgAspect: 2, cellAspect: 1, zoom: 1, panX: 0, panY: 0, fit: false)
        #expect(abs(s.width - 0.5) < 1e-4 && abs(s.left - 0.25) < 1e-4)
        #expect(abs(CellFit.source(imgAspect: 2, cellAspect: 1, zoom: 1, panX: 1, panY: 0, fit: false).right - 1) < 1e-4)
        #expect(abs(CellFit.source(imgAspect: 1, cellAspect: 1, zoom: 2, panX: 0, panY: 0, fit: false).width - 0.5) < 1e-4)
        #expect(CellFit.source(imgAspect: 2, cellAspect: 1, zoom: 3, panX: 1, panY: 1, fit: true) == .full)
        #expect(abs(CellFit.fitRect(imgAspect: 2, cellAspect: 1).height - 0.5) < 1e-4)
    }

    @Test func stripStacksScreenshotsWithTrims() {
        var a = CollageItem(mediaId: "a"); a.trimStart = 0.1
        var b = CollageItem(mediaId: "b"); b.trimEnd = 0.2
        let r = StripLayout.layout(sizes: [PxSize(1080, 2400), PxSize(1080, 2400)], items: [a, b], vertical: true, spacingPx: 0,
                                   targetCross: 1080)
        #expect(r.size.width == 1080)
        #expect(abs(r.size.height - Int(2400 * 0.9 + 2400 * 0.8)) <= 1)
        #expect(abs(r.placements[0].src.top - 0.1) < 1e-4)
        #expect(abs(r.placements[1].dst.bottom - 1) < 1e-3)
        let many = (1...20).map { CollageItem(mediaId: "\($0)") }
        let r2 = StripLayout.layout(sizes: many.map { _ in PxSize(1080, 2400) }, items: many, vertical: true, spacingPx: 0,
                                    targetCross: 1080, maxEdge: 16_000)
        #expect(r2.size.height <= 16_000 && r2.size.width < 1080)
        #expect(abs(r2.size.height - 16_000) < 200)
    }

    @Test func freeCollageStartsSpreadOut() {
        let p = CollageProject.create(id: "f", ids: ["a", "b", "c", "d"], kind: .free)
        #expect(Set(p.items.map(\.center)).count == 4)
    }
}

@Suite struct VideoPlanTests {
    let clip = VideoClip(id: "c", mediaId: "m", sourceDurationMs: 10_000)

    @Test func cutRemovesTheMiddleAndTimesMapBothWays() {
        let c = VideoRules.addCut(clip, TimeRange(startMs: 3_000, endMs: 5_000))
        #expect(VideoPlan.segments(c).count == 2)
        #expect(c.outputDurationMs == 8_000)
        #expect(VideoPlan.toOutputMs(c, sourceMs: 4_000) == nil)
        #expect(VideoPlan.toOutputMs(c, sourceMs: 5_500) == 3_500)
        #expect(VideoPlan.toSourceMs(c, outMs: 3_500) == 5_500)
        #expect(VideoPlan.toSourceMs(c, outMs: 1_000) == 1_000)
    }

    @Test func speedShortensOutputAndScalesMapping() {
        var c = clip; c.speed = 2; c.trimStartMs = 2_000
        #expect(c.outputDurationMs == 4_000)
        #expect(VideoPlan.toOutputMs(c, sourceMs: 4_000) == 1_000)
        #expect(VideoPlan.toSourceMs(c, outMs: 1_000) == 4_000)
    }

    @Test func overlappingCutsMergeAndNeverRemoveEverything() {
        var c = VideoRules.addCut(clip, TimeRange(startMs: 1_000, endMs: 4_000))
        c = VideoRules.addCut(c, TimeRange(startMs: 3_000, endMs: 6_000))
        #expect(c.cuts == [TimeRange(startMs: 1_000, endMs: 6_000)])
        #expect(VideoRules.addCut(c, TimeRange(startMs: 0, endMs: 10_000)) == c)
    }

    @Test func gainFadesInAndOutAndMuteIsSilent() {
        var c = clip; c.volume = 0.5; c.fadeInMs = 1_000; c.fadeOutMs = 2_000
        #expect(abs(VideoPlan.gain(c, outMs: 0)) < 1e-4)
        #expect(abs(VideoPlan.gain(c, outMs: 500) - 0.25) < 1e-4)
        #expect(abs(VideoPlan.gain(c, outMs: 5_000) - 0.5) < 1e-4)
        #expect(abs(VideoPlan.gain(c, outMs: 9_000) - 0.25) < 1e-4)
        c.muted = true
        #expect(VideoPlan.gain(c, outMs: 5_000) == 0)
    }

    @Test func layoutRotatesCropsAndNeverUpscales() {
        var rc = clip; rc.quarterTurns = 1; rc.crop = NormRect(left: 0, top: 0, right: 1, bottom: 0.5)
        let p = VideoProject(id: "p", clips: [rc])
        let l = VideoPlan.layout(display: VSize(1920, 1080), clip: rc, project: p)
        #expect(l.rotated == VSize(1080, 1920) && l.cropped == VSize(1080, 960) && l.output == VSize(1080, 960))
        var small = p.withClips([clip]); small.profile = .small
        #expect(VideoPlan.layout(display: VSize(1920, 1080), clip: clip, project: small).output == VSize(1280, 720))
        var fill = p.withClips([clip]); fill.aspect = 9.0 / 16.0; fill.fill = true
        let f = VideoPlan.layout(display: VSize(1920, 1080), clip: clip, project: fill)
        #expect(f.output.height == 1080 && f.output.width == 608)
        var fit = p.withClips([clip]); fit.aspect = 1; fit.fill = false
        #expect(VideoPlan.layout(display: VSize(1920, 1080), clip: clip, project: fit).output == VSize(1920, 1920))
    }

    @Test func estimateIsMonotoneInProfileAndAudio() {
        let p = VideoProject(id: "p", clips: [clip])
        let l = VideoPlan.layout(display: VSize(1920, 1080), clip: clip, project: p)
        let high = VideoPlan.estimateBytes(p, layout: l, fps: 30)
        var ps = p; ps.profile = .small
        let small = VideoPlan.estimateBytes(ps, layout: VideoPlan.layout(display: VSize(1920, 1080), clip: clip, project: ps), fps: 30)
        #expect(small < high)
        var silent = p; silent.removeAudio = true
        #expect(VideoPlan.estimateBytes(silent, layout: l, fps: 30) < high)
    }

    @Test func layerAlphaFadesAtEdges() {
        let l = TimedLayer(layer: .text(TextLayer(id: "t", text: "Hallo")), startMs: 1_000, endMs: 3_000)
        #expect(VideoPlan.layerAlpha(l, outMs: 500) == 0)
        #expect(abs(VideoPlan.layerAlpha(l, outMs: 1_100) - 0.5) < 1e-4)
        #expect(VideoPlan.layerAlpha(l, outMs: 2_000) == 1)
        #expect(VideoPlan.layerAlpha(l, outMs: 3_100) == 0)
    }
}

@Suite struct MoviePlanTests {
    func project() -> VideoProject {
        VideoProject(id: "p", clips: [MoviePlan.photoClip(id: "a", mediaId: "1", durationMs: 3000),
                                      MoviePlan.videoClip(id: "b", mediaId: "2", durationMs: 4000),
                                      MoviePlan.photoClip(id: "c", mediaId: "3", durationMs: 2000)],
                     transitions: [.fadeBlack, .none], transitionMs: 600)
    }

    @Test func startsAndTotal() {
        #expect(MoviePlan.starts(project()) == [0, 3000, 7000])
        #expect(MoviePlan.totalMs(project()) == 9000)
        #expect(MoviePlan.blackSeams(project()) == [3000])
    }

    @Test func blackAlphaPeaksOnSeamOnly() {
        let p = project()
        #expect(abs(MoviePlan.blackAlpha(p, outMs: 3000) - 1) < 0.001)
        #expect(abs(MoviePlan.blackAlpha(p, outMs: 2850) - 0.5) < 0.01)
        #expect(MoviePlan.blackAlpha(p, outMs: 2600) < 0.001)
        #expect(MoviePlan.blackAlpha(p, outMs: 7000) < 0.001)
        let short = VideoProject(id: "s", clips: [MoviePlan.photoClip(id: "a", mediaId: "1", durationMs: 600),
                                                  MoviePlan.photoClip(id: "b", mediaId: "2", durationMs: 600)],
                                 transitions: [.fadeBlack], transitionMs: 1500)
        #expect(MoviePlan.blackAlpha(short, outMs: 300) < 0.001)
    }

    @Test func musicFadesAtBothEnds() {
        var p = project(); p.music = MusicTrack(uri: "u", name: "n", volume: 0.5, fadeMs: 1000)
        #expect(MoviePlan.musicGain(p, outMs: 0) < 0.001)
        #expect(abs(MoviePlan.musicGain(p, outMs: 500) - 0.25) < 0.001)
        #expect(abs(MoviePlan.musicGain(p, outMs: 4000) - 0.5) < 0.001)
        #expect(MoviePlan.musicGain(p, outMs: 9000) < 0.001)
        #expect(MoviePlan.musicGain(project(), outMs: 4000) == 0)
    }

    @Test func frameKeepsAspectAndEvenSizes() {
        var p = project()
        #expect(MoviePlan.frame(p, first: VSize(4000, 2250)) == VSize(1920, 1080))
        p.aspect = 9.0 / 16.0
        #expect(MoviePlan.frame(p, first: VSize(4000, 3000)) == VSize(1080, 1920))
        p.aspect = 1
        #expect(MoviePlan.frame(p, first: VSize(4000, 3000)) == VSize(1080, 1080))
        var s = project(); s.profile = .small
        let small = MoviePlan.frame(s, first: VSize(4000, 3000))
        #expect(small.height == 720 && small.width % 2 == 0)
    }

    @Test func limitsAndSlideshow() {
        #expect(MoviePlan.problem(project()) == nil)
        #expect(MoviePlan.problem(project().withClips(Array(project().clips.prefix(1)))) == .tooFew)
        let s = MoviePlan.slideshow(id: "s", photoIDs: ["1", "2", "3"], seconds: 4)
        #expect(MoviePlan.totalMs(s) == 12_000)
        #expect(s.transitions == [.fadeBlack, .fadeBlack])
        #expect(s.clips.allSatisfy { $0.isPhoto && $0.kenBurns })
        #expect(MoviePlan.withPhotoDuration(s.clips[0], ms: 10).outputDurationMs == VideoRules.minClipMs)
        #expect(MoviePlan.kenBurnsScale(-1) == 1 && abs(MoviePlan.kenBurnsScale(2) - 1.08) < 0.0001)
    }

    @Test func projectCodableRoundTrip() throws {
        var p = project()
        p.layers = [TimedLayer(layer: .sticker(StickerLayer(id: "s", kind: .heart)), startMs: 100, endMs: 900)]
        p.music = MusicTrack(uri: "bookmark", name: "Lied")
        #expect(try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(p)) == p)
    }
}
