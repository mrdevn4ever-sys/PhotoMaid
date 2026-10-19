import Testing
import Foundation
@testable import PhotoMaidCore

/// Ports von `BatchPlanTest.kt`, `WorkflowTest.kt`, `PdfTest.kt` (ohne Android-PDF-Schreiber; iOS nutzt
/// `UIGraphicsPDFRenderer`) plus PDF-Studio-Seitenplan.
@Suite struct BatchTests {
    @Test func needsWorkSkipsPointlessCopies() {
        var r = BatchOptions(tool: .resize); r.longEdge = 2048
        #expect(BatchRules.needsWork(r, width: 4000, height: 3000, uti: "public.jpeg", hasLocation: false))
        #expect(!BatchRules.needsWork(r, width: 2048, height: 1536, uti: "public.jpeg", hasLocation: false))
        var c = BatchOptions(tool: .convert); c.format = .jpeg
        #expect(BatchRules.needsWork(c, width: 10, height: 10, uti: "public.heic", hasLocation: false))
        #expect(!BatchRules.needsWork(c, width: 10, height: 10, uti: "public.jpeg", hasLocation: false))
        #expect(BatchRules.needsWork(c, width: 10, height: 10, uti: "public.png", hasLocation: false))
        let l = BatchOptions(tool: .stripLocation)
        #expect(!BatchRules.needsWork(l, width: 10, height: 10, uti: "public.jpeg", hasLocation: false))
        #expect(BatchRules.needsWork(l, width: 10, height: 10, uti: "public.jpeg", hasLocation: true))
    }

    @Test func summaryIsHonest() {
        let s = BatchSummary().adding(before: 5_000_000, after: 1_000_000).adding(before: nil, after: 800_000)
            .adding(before: 3_000_000, after: 900_000)
        #expect(s.done == 3 && s.unknownSizes == 1)
        #expect(s.beforeBytes == 8_000_000 && s.freedLaterBytes == 0)
        #expect(s.afterBytes == 1_900_000)
        var t = s; t.originalsTrashed = 3
        #expect(t.freedLaterBytes == 0)
        var k = BatchSummary().adding(before: 5_000_000, after: 1_000_000).adding(before: 3_000_000, after: 900_000)
        k.originalsTrashed = 2
        #expect(k.freedLaterBytes == 8_000_000 - 1_900_000)
        k.originalsTrashed = 1
        #expect(k.freedLaterBytes == 0)
        var odd = BatchSummary(); odd.done = 1; odd.beforeBytes = 1; odd.afterBytes = 5; odd.originalsTrashed = 1
        #expect(odd.freedLaterBytes == 0)
    }

    @Test func stitchKeepsAspectAndNeverUpscales() {
        let sizes = [PxSize(1080, 2400), PxSize(1440, 3200), PxSize(720, 1600)]
        let r = StitchPlan.layout(sizes)
        #expect(r.size.width == 720)
        for (p, s) in zip(r.places, sizes) {
            #expect(abs(Double(p.width) / Double(p.height) - Double(s.width) / Double(s.height)) < 0.01)
        }
        #expect(r.places.reduce(0) { $0 + $1.height } == r.size.height)
        #expect(StitchPlan.layout(Array(repeating: PxSize(1080, 2400), count: 20)).size.height <= StitchPlan.maxHeight)
    }

    @Test func gifFramePlacementAndTimes() {
        #expect(GifPlan.frame(firstW: 4000, firstH: 3000, maxEdge: 480) == PxSize(480, 360))
        #expect(GifPlan.frame(firstW: 300, firstH: 200, maxEdge: 720) == PxSize(300, 200))
        let fit = GifPlan.place(srcW: 1000, srcH: 1000, frameW: 480, frameH: 360, fill: false)
        #expect(abs(Double(fit.2 - fit.0) / Double(fit.3 - fit.1) - 1) < 0.01)
        let fill = GifPlan.place(srcW: 1000, srcH: 1000, frameW: 480, frameH: 360, fill: true)
        #expect(fill.2 - fill.0 == 480 && fill.1 < 0)
        let t = GifPlan.videoTimes(startMs: 1000, endMs: 60_000, fps: 10)
        #expect(t.first == 1000 && t.count <= GifPlan.maxFrames && t.last! < 11_000)
    }
}

@Suite struct WorkflowTests {
    var classifieds: Workflow {
        var w = Workflow(id: "k", name: "Für Kleinanzeigen")
        w.format = .jpeg; w.longEdge = 2000; w.removeLocation = true; w.nameBase = "Kleinanzeige"; w.finish = .share
        return w
    }

    @Test func stepsDescribeOnlyWhatHappensInOrder() {
        #expect(WorkflowRules.steps(classifieds) == [.format, .resize, .quality, .location, .rename, .share])
        var family = Workflow(id: "f", name: "Familie")
        family.longEdge = 2048; family.album = "A/L0/040"; family.photoMaxBytes = 2_000_000; family.videoMaxBytes = 20_000_000
        #expect(WorkflowRules.steps(family) == [.resize, .targetSize, .videoTarget, .album, .save])
        family.finish = .share
        #expect(!WorkflowRules.steps(family).contains(.album))
    }

    @Test func namesAreNumberedAndSafe() {
        #expect(WorkflowRules.fileStem(classifieds, index: 0, total: 12, originalName: "IMG_1.jpg", suffix: "PhotoMaid") == "Kleinanzeige_001")
        #expect(WorkflowRules.fileStem(classifieds, index: 41, total: 1200, originalName: "IMG_1.jpg", suffix: "PhotoMaid") == "Kleinanzeige_0042")
        var plain = classifieds; plain.nameBase = nil
        #expect(WorkflowRules.fileStem(plain, index: 0, total: 1, originalName: "IMG_0042.HEIC", suffix: "bearbeitet") == "IMG_0042_bearbeitet")
        #expect(WorkflowRules.sanitizeBase(" Ferien 2026/ ") == "Ferien_2026")
        #expect(WorkflowRules.sanitizeBase(" /:* ") == nil)
    }

    @Test func formatSizeAndValidity() {
        #expect(WorkflowRules.outputFormat(Workflow(id: "a", name: "a"), uti: "public.png") == .png)
        #expect(WorkflowRules.outputFormat(Workflow(id: "a", name: "a"), uti: "public.heic") == .heic) // iOS: HEIC bleibt
        #expect(WorkflowRules.outputFormat(Workflow(id: "a", name: "a"), uti: "public.jpeg") == .jpeg)
        #expect(WorkflowRules.targetEdge(classifieds, width: 1200, height: 900) == 1200)
        #expect(WorkflowRules.targetEdge(classifieds, width: 4032, height: 3024) == 2000)
        #expect(WorkflowRules.isValid(classifieds))
        var bad = classifieds; bad.name = "  "
        #expect(!WorkflowRules.isValid(bad))
        bad = classifieds; bad.photoMaxBytes = 10_000
        #expect(!WorkflowRules.isValid(bad))
        bad = classifieds; bad.minLongEdge = 3000
        #expect(!WorkflowRules.isValid(bad))
    }

    @Test func budgetIsSharedBySize() {
        #expect(WorkflowRules.budgetShares([1_000_000, 3_000_000], total: 8_000_000) == [2_000_000, 6_000_000])
        #expect(WorkflowRules.budgetShares([nil, 3_000_000], total: 8_000_000) == [4_000_000, 4_000_000])
    }

    func model(_ edge: Int, _ q: Int) -> Int64 { (Int64(edge) * Int64(edge) * 3 / 4) * Int64(q + 10) / 120 }

    @MainActor @Test func targetSizeKeepsEncodingStateOnTheCallingActorAcrossSuspension() async {
        var attempts: [TargetSize.Attempt] = []
        let result = await TargetSize.search(maxBytes: 75, startEdge: 2000, startQuality: 90,
                                           minEdge: 1024, minQuality: 60, lossless: false) { attempt in
            MainActor.preconditionIsolated()
            await Task.yield()
            MainActor.preconditionIsolated()
            attempts.append(attempt)
            return Int64(attempt.quality)
        }
        #expect(attempts.count > 1)
        #expect(result.bytes <= 75)
        #expect(attempts.contains(result.attempt))
    }

    @Test func targetSizeFindsHighestFittingQualityFirst() async {
        let r = await TargetSize.search(maxBytes: 2_000_000, startEdge: 2000, startQuality: 90, minEdge: 1024, minQuality: 60,
                                        lossless: false) { a in model(a.longEdge, a.quality) }
        guard case .met = r else { Issue.record("erreichbar erwartet"); return }
        #expect(r.attempt.longEdge == 2000)
        #expect(r.bytes <= 2_000_000)
        #expect(model(2000, r.attempt.quality + 3) > 2_000_000)
    }

    @Test func targetSizeShrinksEdgeOnlyWhenNeededAndReportsUnreachable() async {
        let shrunk = await TargetSize.search(maxBytes: 600_000, startEdge: 2000, startQuality: 90, minEdge: 1024, minQuality: 60,
                                             lossless: false) { a in model(a.longEdge, a.quality) }
        guard case .met = shrunk else { Issue.record("erreichbar erwartet"); return }
        #expect((1024..<2000).contains(shrunk.attempt.longEdge) && shrunk.bytes <= 600_000)
        let impossible = await TargetSize.search(maxBytes: 50_000, startEdge: 2000, startQuality: 90, minEdge: 1024, minQuality: 60,
                                                 lossless: false) { a in model(a.longEdge, a.quality) }
        guard case .unreachable = impossible else { Issue.record("nicht erreichbar erwartet"); return }
        #expect(impossible.attempt == TargetSize.Attempt(longEdge: 1024, quality: 60))
        #expect(impossible.bytes > 50_000)
        let png = await TargetSize.search(maxBytes: 1_000_000, startEdge: 2000, startQuality: 90, minEdge: 640, minQuality: 60,
                                          lossless: true) { a in Int64(a.longEdge) * Int64(a.longEdge) }
        guard case .met = png else { Issue.record("erreichbar erwartet"); return }
        #expect(png.attempt.quality == 100)
    }

    @Test func videoTargetPlansBitrateAndNeverUpscales() throws {
        let p = try #require(VideoTarget.plan(maxBytes: 20_000_000, durationMs: 60_000, hasAudio: true, width: 1920, height: 1080))
        #expect((2_000_000...2_500_000).contains(p.videoBitrate) && p.maxHeight <= 1080)
        #expect(VideoTarget.plan(maxBytes: 20_000_000, durationMs: 60_000, hasAudio: true, width: 640, height: 360)?.maxHeight == 360)
        #expect(VideoTarget.plan(maxBytes: 10_000_000, durationMs: 600_000, hasAudio: true, width: 1920, height: 1080) == nil)
        let tight = try #require(VideoTarget.plan(maxBytes: 10_000_000, durationMs: 120_000, hasAudio: true, width: 3840, height: 2160))
        #expect(tight.maxHeight < 2160)
    }

    @Test func androidWorkflowJsonIsReadable() throws {
        let json = #"{"id":"w1","name":"Verschicken","format":"JPEG","longEdge":2048,"quality":80,"folder":"Pictures/Familie/","finish":"SAVE_AND_SHARE"}"#
        let w = try JSONDecoder().decode(Workflow.self, from: Data(json.utf8))
        #expect(w.format == .jpeg && w.longEdge == 2048 && w.finish == .saveAndShare)
        #expect(w.album == nil) // Android-Ordnerpfad ist kein iOS-Album
        let ios = #"{"id":"w2","name":"x","folder":"8F2A-1/L0/040"}"#
        #expect(try JSONDecoder().decode(Workflow.self, from: Data(ios.utf8)).album == "8F2A-1/L0/040")
    }
}

@Suite struct PdfTests {
    let portrait = SourceSize(width: 3000, height: 4000)
    let wide = SourceSize(width: 4000, height: 2000)

    func inside(_ inner: PtRect, _ outer: PtRect) -> Bool {
        inner.x >= outer.x - 1e-6 && inner.y >= outer.y - 1e-6 && inner.x + inner.w <= outer.x + outer.w + 1e-6
            && inner.y + inner.h <= outer.y + outer.h + 1e-6
    }

    @Test func fitNeverDistortsAndStaysInside() {
        for per in PerPage.allCases {
            for src in [portrait, wide, SourceSize(width: 1000, height: 1000)] {
                var o = PdfOptions(); o.perPage = per; o.fit = .fit; o.caption = .number
                for p in PdfLayout.pages(Array(repeating: src, count: per.count), options: o) {
                    for it in p.items {
                        #expect(abs(it.rect.aspect - src.aspect) < 1e-6)
                        #expect(inside(it.rect, it.cell) && it.crop == .full)
                        #expect(it.rect.y + it.rect.h <= it.caption!.y + 1e-6)
                    }
                }
            }
        }
    }

    @Test func fillCropsInsteadOfStretching() throws {
        var o = PdfOptions(); o.perPage = .four; o.fit = .fill
        let pages = PdfLayout.pages([wide], options: o)
        let it = try #require(pages.first?.items.first)
        #expect(it.cell == it.rect)
        let cw = (it.crop.right - it.crop.left) * Double(wide.width), ch = (it.crop.bottom - it.crop.top) * Double(wide.height)
        #expect(abs(it.rect.aspect - cw / ch) < 1e-6)
        #expect(it.crop.top == 0 && it.crop.bottom == 1)
    }

    @Test func pagingOrientationAndMargins() {
        let src = [wide, portrait, wide, portrait, portrait]
        let one = PdfLayout.pages(src, options: PdfOptions())
        #expect(one.count == 5 && one[0].widthPt > one[0].heightPt && one[1].heightPt > one[1].widthPt)
        var four = PdfOptions(); four.perPage = .four
        let sheet = PdfLayout.pages(src, options: four)
        #expect(sheet.map(\.items.count) == [4, 1])
        #expect(sheet.allSatisfy { $0.heightPt > $0.widthPt })
        var land = PdfOptions(); land.orientation = .landscape; land.perPage = .six; land.margin = .none
        let l = PdfLayout.pages(src, options: land)
        #expect(l.allSatisfy { $0.widthPt > $0.heightPt } && abs(l[0].items[0].cell.x) < 1e-9)
        #expect(sheet.flatMap { $0.items.map(\.index) } == [0, 1, 2, 3, 4])
        var letter = PdfOptions(); letter.paper = .letter
        let lp = PdfLayout.pages([portrait], options: letter)[0]
        #expect(lp.widthPt == 612 && lp.heightPt == 792)
    }

    @Test func pixelsNeverExceedSource() {
        let small = SourceSize(width: 400, height: 300)
        let (rect, crop) = PdfLayout.place(small, area: PtRect(x: 0, y: 0, w: 500, h: 700), fit: .fit)
        #expect(PdfLayout.pixels(for: rect, src: small, crop: crop, dpi: 300) == PxSize(400, 300))
        #expect(PdfLayout.pixels(for: PtRect(x: 0, y: 0, w: 72, h: 54), src: portrait, crop: .full, dpi: 200) == PxSize(200, 267))
    }

    @Test func rulesAndNames() {
        var four = PdfOptions(); four.perPage = .four
        #expect(PdfRules.needsPro(four, count: 2))
        #expect(PdfRules.needsPro(PdfOptions(), count: PdfRules.freeMax + 1))
        var two = PdfOptions(); two.perPage = .two
        #expect(!PdfRules.needsPro(two, count: PdfRules.freeMax))
        #expect(PdfRules.fileName(" Rechnung/ 2026 ", fallback: "PhotoMaid") == "Rechnung 2026.pdf")
        #expect(PdfRules.fileName("..", fallback: "PhotoMaid") == "PhotoMaid.pdf")
        #expect(PdfRules.fileName("a.pdf", fallback: "x") == "a.pdf")
    }

    @Test func pdfStudioPagePlan() {
        let pages = PdfEdit.merged(pageCounts: [2, 3])
        #expect(pages.map(\.id) == ["0:0", "0:1", "1:0", "1:1", "1:2"])
        let moved = PdfEdit.move(pages, from: 4, to: 0)
        #expect(moved.first?.id == "1:2")
        let rotated = PdfEdit.rotate(pages, at: 1)
        #expect(rotated[1].quarterTurns == 1 && rotated[1].rotationDegrees(base: 270) == 0)
        #expect(PdfEdit.rotate(rotated, at: 1, clockwise: false)[1].quarterTurns == 0)
        #expect(PdfEdit.remove(pages, at: [0, 2]).map(\.id) == ["0:1", "1:1", "1:2"])
        #expect(PdfEdit.remove(Array(pages.prefix(1)), at: [0]).count == 1) // nie leer
        #expect(PdfEdit.parseRanges("1-3, 5, 8-", count: 9) == [0, 1, 2, 4, 7, 8])
        #expect(PdfEdit.parseRanges("2,2,1", count: 3) == [1, 0])
        #expect(PdfEdit.parseRanges("0", count: 3) == nil)
        #expect(PdfEdit.parseRanges("4", count: 3) == nil)
        #expect(PdfEdit.parseRanges("3-1", count: 3) == nil)
        #expect(PdfEdit.parseRanges("abc", count: 3) == nil)
        #expect(PdfEdit.split(count: 7, pagesPerPart: 3) == [0..<3, 3..<6, 6..<7])
    }
}
