import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct PhotoSnakeReadableLayoutTests {
    @Test func phoneFieldUsesTheWindowAndKeepsTheOriginalNormalTempo() {
        for (w, h) in [(320.0, 480.0), (367, 700), (394, 760), (402, 874), (432, 850)] {
            let grid = PhotoSnakeViewport(width: w, height: h)
            let layout = PhotoSnakeLayout(width: w, height: h, columns: grid.columns, rows: grid.rows)
            #expect(Double(grid.columns) * layout.pitch >= w * 0.84)
            #expect(Double(grid.rows) * layout.pitch >= h * 0.89)
            #expect(Double(grid.columns) * layout.pitch + 2 * layout.gutter <= w + 0.00001)
            #expect(Double(grid.rows) * layout.pitch + 2 * layout.gutter <= h + 0.00001)
        }
        #expect(PhotoSnakeSpeed.normal.interval == 0.22)
        #expect(PhotoSnakeSpeed.gentle.interval == 0.32)
        #expect(PhotoSnakeSpeed.fast.interval == 0.14)
    }

    @Test func photosKeepTheirReadableSizeWithThinCircularBordersAndSmallOverlap() {
        for (width, height) in [(320.0, 480.0), (367, 560), (367, 700), (382, 720), (385, 732),
                                (394, 760), (406, 780), (422, 820), (432, 850), (736, 1024), (936, 1240)] {
            let grid = PhotoSnakeViewport(width: width, height: height)
            let layout = PhotoSnakeLayout(width: width, height: height, columns: grid.columns, rows: grid.rows)
            #expect((44...50).contains(layout.photoSide))
            #expect(layout.borderWidth <= 1.14)
            #expect(layout.photoSide - 2 * layout.borderWidth >= 42)
            #expect(abs(layout.cornerRadius - layout.photoSide / 2) < 0.00001)
            #expect((0.10...0.15).contains(1 - layout.pitch / layout.photoSide))
        }
    }

    @Test func circlesFollowTheExistingCornerWithPredictableHeadToTailLayering() {
        let grid = PhotoSnakeViewport(width: 367, height: 700)
        let layout = PhotoSnakeLayout(width: 367, height: 700, columns: grid.columns, rows: grid.rows)
        for i in 0...1000 {
            let p = Double(i) / 1000
            let a = PhotoSnakeMotion.Point(p * layout.pitch, 0)
            let b = PhotoSnakeMotion.Point(0, (1 - p) * layout.pitch)
            let overlap = 1 - hypot(a.x - b.x, a.y - b.y) / layout.photoSide
            // An orthogonal corner temporarily compresses circles more than a straight section.
            // Keep the legal grid path, and make its layering deterministic instead of changing physics.
            #expect(overlap >= 0.12499 && overlap <= 0.382)
            #expect(PhotoSnakeLayout.segmentDepth(index: i + 1) > PhotoSnakeLayout.segmentDepth(index: i + 2))
        }
    }

    @Test func growingTailStaysUnderItsPredecessorWithControlledOverlap() {
        let layout = PhotoSnakeLayout(width: 402, height: 874, columns: 4, rows: 10)
        for i in 0...1000 {
            let p = Double(i) / 1000
            let side = layout.growingSide(progress: p)
            #expect((0...layout.photoSide).contains(side))
            if side > 0 {
                #expect(p * layout.pitch >= 0.875 * (layout.photoSide + side) / 2 - 0.00001)
            }
        }
        #expect(layout.growingSide(progress: 0) == 0)
        #expect(abs(layout.growingSide(progress: 1) - layout.photoSide) < 0.00001)
    }

    @Test func wrapsShowCompletePhotosAndCrossfadeContinuouslyAtEveryEdge() {
        let layout = PhotoSnakeLayout(width: 402, height: 874, columns: 4, rows: 10)
        let c = layout.pitch, w = 4 * c, h = 10 * c, r = layout.photoSide / 2, gutter = layout.gutter
        for axis in 0...1 {
            for i in 0...1000 {
                let value = Double(i) / 1000 * (axis == 0 ? w : h)
                let p = PhotoSnakeMotion.Point(axis == 0 ? value : c / 2, axis == 1 ? value : c / 2)
                let placements = PhotoSnakeLayout.placements(p, width: w, height: h, gutter: gutter, halfExtent: r, wraps: true, pitch: c)
                #expect(abs(placements.map(\.alpha).reduce(0, +) - 1) < 0.00001)
                for item in placements {
                    #expect((0...1).contains(item.alpha))
                    #expect(item.centre.x - r >= -gutter && item.centre.x + r <= w + gutter)
                    #expect(item.centre.y - r >= -gutter && item.centre.y + r <= h + gutter)
                }
            }
        }
        let left = PhotoSnakeLayout.placements(.init(0, c / 2), width: w, height: h, gutter: gutter, halfExtent: r, wraps: true, pitch: c).sorted { $0.centre.x < $1.centre.x }
        let right = PhotoSnakeLayout.placements(.init(w, c / 2), width: w, height: h, gutter: gutter, halfExtent: r, wraps: true, pitch: c).sorted { $0.centre.x < $1.centre.x }
        #expect(left == right)
    }

    @Test func headFitsEvenHalfwayThroughTurnsAndDuringTheEatingPulse() {
        let layout = PhotoSnakeLayout(width: 367, height: 700, columns: 4, rows: 8)
        for i in 0...360 {
            let angle = Double(i) / 180 * .pi
            let extent = layout.headSide * 1.06 / 2 * (abs(cos(angle)) + abs(sin(angle)))
            #expect(extent <= layout.gutter + layout.pitch / 2)
            // The full atlas canvas, not just its opaque pixels, fits in the reserved gutter.
            for p in [PhotoSnakeMotion.Point(0, 0), .init(4 * layout.pitch, 8 * layout.pitch)] {
                let places = PhotoSnakeLayout.placements(p, width: 4 * layout.pitch, height: 8 * layout.pitch,
                    gutter: layout.gutter, halfExtent: extent, wraps: true, pitch: layout.pitch)
                for item in places {
                    #expect(item.centre.x - extent >= -layout.gutter)
                    #expect(item.centre.y - extent >= -layout.gutter)
                    #expect(item.centre.x + extent <= 4 * layout.pitch + layout.gutter)
                    #expect(item.centre.y + extent <= 8 * layout.pitch + layout.gutter)
                }
            }
        }
    }

    @Test func aspectFillKeepsTheRatioAndCropsTheCentre() {
        for (w, h) in [(4000.0, 3000.0), (3000, 4000), (2048, 256), (256, 2048), (256, 256)] {
            let crop = PhotoSnakeLayout.aspectFill(width: w, height: h, side: 256)
            #expect(abs(crop.width / crop.height - w / h) < 0.000001)
            #expect(crop.width >= 256 && crop.height >= 256)
            #expect(abs(crop.x + crop.width / 2 - 128) < 0.000001)
            #expect(abs(crop.y + crop.height / 2 - 128) < 0.000001)
        }
    }

    @Test func everyHeadAnimationMapsToAnAuthoredDirectionalView() {
        for character in PhotoSnakeCharacter.allCases {
            for direction in PhotoSnakeGame.Direction.allCases {
                for pose in PhotoSnakeHeadAnimation.Pose.allCases {
                    let name = PhotoSnakeHeadAnimation.overheadTexture(character: character, pose: pose, direction: direction)
                    #expect(name.hasPrefix("top_\(character.rawValue)_") && name.hasSuffix("_\(direction.rawValue)"))
                }
            }
        }
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 3.05).pose == .blink)
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 4.7).pose == .tongue)
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 0, collision: 0.01).pose == .hurt)
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 0, sleeping: true).pose == .sleep)
    }

    @Test func nearlyFullBoardsAndThreeHundredPhotosKeepAStableOrderAndVisibleCentres() throws {
        typealias Cell = PhotoSnakeGame.Cell
        for (width, height, target) in [(4, 10, 39), (5, 10, 49), (9, 14, 125), (24, 24, 303)] {
            var cycle = (0..<width).map { Cell($0, 0) }
            for y in 1..<height {
                cycle += (y.isMultiple(of: 2) ? Array(1..<width) : Array((1..<width).reversed())).map { Cell($0, y) }
            }
            cycle += (1..<height).reversed().map { Cell(0, $0) }
            var game = try #require(PhotoSnakeGame(width: width, height: height, mode: .relaxed, seed: 47))
            _ = game.faceBeforeFirstStep((height / 2).isMultiple(of: 2) ? .right : .left)
            var motion = PhotoSnakeMotion(game: game)
            var index = try #require(cycle.firstIndex(of: game.body[0]))
            var event = PhotoSnakeGame.Event.ignored
            for _ in 0..<200_000 where game.status == .playing && game.body.count < target {
                let next = cycle[(index + 1) % cycle.count], head = game.body[0]
                _ = game.turn(next.x > head.x ? .right : next.x < head.x ? .left : next.y > head.y ? .down : .up)
                event = game.step(); motion.advance(to: game, event: event)
                index = (index + 1) % cycle.count
            }
            #expect(game.status == .playing && game.body.count >= target)
            // Exercise actual history for several subsequent corners, not just static grid centres.
            for _ in 0..<8 {
                let layout = PhotoSnakeLayout(width: Double(width + 1) * 78, height: Double(height + 1) * 78,
                                              columns: width, rows: height)
                for fraction in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1] {
                    let samples = motion.points(progress: fraction)
                    let photos = samples.enumerated().dropFirst().compactMap { i, sample -> (PhotoSnakeMotion.Point, Double)? in
                        let growing = (event == .collected || event == .won) && i == samples.count - 1
                        let previous = samples[i - 1]
                        let distance = hypot(sample.x - previous.x, sample.y - previous.y) * layout.pitch
                        let side = growing ? layout.growingSide(progress: fraction, separation: distance) : layout.photoSide
                        guard side > 0 else { return nil }
                        let p = motion.wrapped(sample)
                        return (.init(p.x * layout.pitch, p.y * layout.pitch), side)
                    }
                    for a in photos.indices {
                        for b in photos.indices where b > a {
                            let distance = hypot(photos[a].0.x - photos[b].0.x, photos[a].0.y - photos[b].0.y)
                            // Established photos keep their centres visible. A newly appearing tail
                            // starts beneath its predecessor until it is large enough to emerge.
                            if min(photos[a].1, photos[b].1) > layout.photoSide * 0.15 {
                                #expect(distance > max(photos[a].1, photos[b].1) / 2)
                            }
                            #expect(PhotoSnakeLayout.segmentDepth(index: a + 1) > PhotoSnakeLayout.segmentDepth(index: b + 1))
                        }
                    }
                }
                if game.status != .playing { break }
                let next = cycle[(index + 1) % cycle.count], head = game.body[0]
                _ = game.turn(next.x > head.x ? .right : next.x < head.x ? .left : next.y > head.y ? .down : .up)
                event = game.step(); motion.advance(to: game, event: event)
                index = (index + 1) % cycle.count
            }
        }
    }

    @Test func cropFallsBackToTheCentreAndRejectsInvalidFaceBounds() {
        let centred = PhotoSnakeLayout.photoCrop(width: 800, height: 400, side: 256, faces: [])
        #expect(centred == .init(x: 272, y: 72, width: 256, height: 256))
        let invalid = PhotoSnakeLayout.photoCrop(width: 800, height: 400, side: 256,
            faces: [.init(x: .nan, y: 0, width: 1, height: 1), .init(x: -1, y: 0, width: 1, height: 1)])
        #expect(invalid == centred)
        #expect(PhotoSnakeLayout.photoCrop(width: 80, height: 40, side: 256, faces: []).width == 40)
    }

    @Test func offCentreFaceRemainsInsideTheCircularPhoto() {
        let face = PhotoSnakeLayout.Crop(x: 0.1, y: 0.3, width: 0.15, height: 0.3)
        let crop = PhotoSnakeLayout.photoCrop(width: 800, height: 400, side: 256, faces: [face])
        for x in [face.x * 800, (face.x + face.width) * 800] {
            for y in [face.y * 400, (face.y + face.height) * 400] {
                #expect(hypot(x - crop.x - 128, y - crop.y - 128) < 128)
            }
        }
        #expect(crop.x < 100) // A plain centre crop would remove this face entirely.
    }

    @Test func cropKeepsSmallGroupsTogetherAndFavoursTheLargestDistantFace() {
        let a = PhotoSnakeLayout.Crop(x: 0.3, y: 0.4, width: 0.1, height: 0.1)
        let b = PhotoSnakeLayout.Crop(x: 0.45, y: 0.4, width: 0.1, height: 0.1)
        let group = PhotoSnakeLayout.photoCrop(width: 800, height: 400, side: 256, faces: [a, b])
        #expect(abs(group.x + 128 - 340) < 0.0001)
        let large = PhotoSnakeLayout.Crop(x: 0.7, y: 0.3, width: 0.15, height: 0.3)
        let small = PhotoSnakeLayout.Crop(x: 0.1, y: 0.3, width: 0.05, height: 0.1)
        let crop = PhotoSnakeLayout.photoCrop(width: 800, height: 400, side: 256, faces: [small, large])
        #expect(abs(crop.x + 128 - 620) < 0.0001)
        #expect(crop.x >= 0 && crop.x + crop.width <= 800 && crop.y >= 0 && crop.y + crop.height <= 400)
    }
}
