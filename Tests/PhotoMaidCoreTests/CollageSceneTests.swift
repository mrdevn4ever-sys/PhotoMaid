import Testing
import Foundation
@testable import PhotoMaidCore

/// Geometrie der Collage (Vorschau = Export): nie verzerrt, Ränder/Abstände, Frei, Streifen, Ausgabegröße.
@Suite struct CollageSceneTests {
    /// Seitenverhältnis des Ausschnitts (in Bildpixeln) = Seitenverhältnis der Fotofläche (in Ausgabepixeln).
    func undistorted(_ s: CollageScene, _ aspects: [Float], _ p: CollageProject, file: String = #fileID) -> Bool {
        s.placements.allSatisfy { pl in
            let img = CollageGeometry.turnedAspect(aspects[pl.index], quarterTurns: p.items[pl.index].quarterTurns)
            let src = pl.source.width * img / pl.source.height
            let dst = pl.photo.width * s.aspect / pl.photo.height
            return abs(src - dst) / dst < 0.01
        }
    }

    @Test func gridFillAndFitNeverDistort() {
        var p = CollageProject.create(id: "g", ids: ["a", "b", "c", "d"])
        p.items[1].fit = true
        p.items[2].zoom = 2.5; p.items[2].panX = 0.7; p.items[2].panY = -1
        p.items[3].quarterTurns = 1
        let aspects: [Float] = [1.5, 0.75, 4.0 / 3, 0.5]
        for a: Float in [1, 0.8, 9.0 / 16, 16.0 / 9] {
            p.aspect = a
            let s = CollageGeometry.scene(p, imageAspects: aspects)
            #expect(s.placements.count == 4)
            #expect(undistorted(s, aspects, p), "aspect \(a)")
            // Eingepasst: Foto liegt im Feld.
            let fit = s.placements[1]
            #expect(fit.photo.left >= fit.frame.left - 1e-4 && fit.photo.right <= fit.frame.right + 1e-4)
            #expect(fit.photo.top >= fit.frame.top - 1e-4 && fit.photo.bottom <= fit.frame.bottom + 1e-4)
            #expect(fit.source == .full)
            // Ausschnitt bleibt im Foto.
            #expect(s.placements.allSatisfy { $0.source.left >= -1e-4 && $0.source.right <= 1 + 1e-4 })
        }
    }

    @Test func cornersAreClampedToHalfTheCell() {
        var p = CollageProject.create(id: "g", ids: ["a", "b"])
        p.corner = 5
        let s = CollageGeometry.scene(p, imageAspects: [1, 1])
        for pl in s.placements {
            let short = min(pl.frame.width * max(s.aspect, 1), pl.frame.height * max(1 / s.aspect, 1))
            #expect(pl.frameCorner <= short / 2 + 1e-4)
        }
    }

    @Test func freeKeepsPhotoAspectAndPolaroidBorder() {
        var p = CollageProject.create(id: "f", ids: ["a", "b", "c"], kind: .free)
        p.items[0].rotation = 30
        let aspects: [Float] = [1.5, 0.75, 1]
        let s = CollageGeometry.scene(p, imageAspects: aspects)
        #expect(undistorted(s, aspects, p))
        let pl = s.placements[0]
        #expect(pl.polaroid && abs(pl.rotation - 30) < 1e-4)
        #expect(pl.frame.bottom - pl.photo.bottom > pl.photo.top - pl.frame.top)
        // Mitte des Rahmens = Mittelpunkt des Fotos in der Collage.
        #expect(abs((pl.frame.left + pl.frame.right) / 2 - p.items[0].center.x) < 1e-4)
        #expect(abs((pl.frame.top + pl.frame.bottom) / 2 - p.items[0].center.y) < 1e-4)
        p.polaroid = false
        let plain = CollageGeometry.scene(p, imageAspects: aspects).placements[1]
        #expect(plain.frame == plain.photo)
    }

    @Test func hitRespectsRotationAndOrder() {
        var p = CollageProject.create(id: "f", ids: ["a", "b"], kind: .free)
        p.aspect = 1; p.polaroid = false
        p.items[0].center = NormPoint(0.5, 0.5); p.items[0].width = 0.6; p.items[0].rotation = 0
        p.items[1].center = NormPoint(0.5, 0.5); p.items[1].width = 0.2; p.items[1].rotation = 45
        let s = CollageGeometry.scene(p, imageAspects: [1, 1])
        #expect(s.hit(0.5, 0.5) == 1)
        #expect(s.hit(0.25, 0.5) == 0)
        #expect(s.hit(0.95, 0.95) == nil)
        // Gedrehtes Quadrat (45°): Ecke des ungedrehten Rechtecks liegt außerhalb.
        #expect(s.hit(0.595, 0.405) != 1)
        #expect(s.hit(0.5, 0.37) == 1)
    }

    @Test func stripStacksWithoutDistortionAndMargins() {
        var p = CollageProject.create(id: "s", ids: ["a", "b", "c"], kind: .strip)
        p.items[0].trimStart = 0.1
        p.items[2].trimEnd = 0.3
        p.spacing = 0.02; p.margin = 0.03
        let aspects: [Float] = [0.45, 0.45, 0.5]
        let s = CollageGeometry.scene(p, imageAspects: aspects)
        #expect(undistorted(s, aspects, p))
        #expect(s.aspect < 0.3)
        #expect(s.placements[0].photo.left > 0.02 && s.placements[0].photo.top > 0)
        #expect(s.placements[1].photo.top - s.placements[0].photo.bottom > 0)
        p.stripVertical = false
        let h = CollageGeometry.scene(p, imageAspects: aspects)
        #expect(h.aspect > 1)
        #expect(undistorted(h, aspects, p))
    }

    @Test func outputSizeFollowsResolutionAndLimits() {
        let g = CollageProject.create(id: "g", ids: ["a", "b", "c"])
        #expect(CollageGeometry.outputSize(g, aspect: 0.8, resolution: 2048) == PxSize(1638, 2048))
        #expect(CollageGeometry.outputSize(g, aspect: 1, resolution: 1080) == PxSize(1080, 1080))
        var s = CollageProject.create(id: "s", ids: ["a", "b"], kind: .strip)
        #expect(CollageGeometry.outputSize(s, aspect: 0.25, resolution: 1080) == PxSize(1080, 4320))
        let long = CollageGeometry.outputSize(s, aspect: 0.02, resolution: 4096)
        #expect(long.height <= CollageGeometry.stripMaxEdge && long.width < 4096)
        s.stripVertical = false
        #expect(CollageGeometry.outputSize(s, aspect: 4, resolution: 1080) == PxSize(4320, 1080))
        let big = CollageGeometry.outputSize(s, aspect: 3.9, resolution: 4096)
        #expect(big.pixels <= CollageGeometry.maxPixels)
    }

    @Test func dividerHandlesSitOnTheGapAndMove() {
        var p = CollageProject.create(id: "g", ids: ["a", "b"]).withTemplate("c:1,1")
        p.aspect = 1; p.margin = 0.1; p.spacing = 0
        let h = p.dividerHandles()
        #expect(h.count == 1 && h[0].divider.vertical)
        #expect(abs(h[0].point.x - 0.5) < 1e-4 && abs(h[0].point.y - 0.5) < 1e-4)
        let moved = p.movingDivider(h[0].divider, toCanvas: 0.66)
        #expect(abs(moved.cellRects()[0].right - 0.66) < 1e-3)
    }

    @Test func panFollowsTheFingerAndClamps() {
        // Querformat 2:1 im Quadrat: Ausschnitt halb so breit, Spielraum 0,25.
        let r = CellFit.panned(panX: 0, panY: 0, zoom: 1, imgAspect: 2, cellAspect: 1, dx: 0.25, dy: 0.3)
        #expect(abs(r.x + 0.5) < 1e-4)
        #expect(r.y == 0)
        let far = CellFit.panned(panX: 0, panY: 0, zoom: 1, imgAspect: 2, cellAspect: 1, dx: -5, dy: 0)
        #expect(far.x == 1)
        #expect(CellFit.zoomed(4, by: 3) == CellFit.maxZoom)
        #expect(CellFit.zoomed(1.2, by: 0.5) == 1)
    }

    @Test func featuredLayoutsAreValidAndLeadWithBalanced() {
        for n in 1...20 {
            let f = CollageLayout.featured(for: n)
            #expect(!f.isEmpty && f.count <= 24)
            #expect(f.first == "grid")
            #expect(Set(f).count == f.count)
            #expect(Set(f).isSubset(of: Set(CollageLayout.templates(for: n))))
        }
        #expect(CollageLayout.shape("r:1,2") == .rows([1, 2]))
        #expect(CollageLayout.shape("c:3") == .columns([3]))
        #expect(CollageLayout.shape("big:t") == .big(side: "t"))
        #expect(CollageLayout.shape("grid") == .grid)
    }

    @Test func frontReplaceAndKindKeepTheRest() {
        let p = CollageProject.create(id: "f", ids: ["a", "b", "c"], kind: .free)
        #expect(p.bringingToFront(0).items.map(\.mediaId) == ["b", "c", "a"])
        let r = p.replacingItem(1, with: "z")
        #expect(r.items[1].mediaId == "z" && r.items[1].center == p.items[1].center)
        let g = p.withKind(.grid)
        #expect(g.kind == .grid && CollageLayout.leafCount(g.tree) == 3)
        #expect(FreeLayout.normalizedRotation(190) == -170)
        #expect(FreeLayout.moved(NormPoint(0.9, 0.1), dx: 0.5, dy: -0.5) == NormPoint(1, 0))
    }
}
