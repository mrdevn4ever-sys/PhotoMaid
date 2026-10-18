import Testing
@testable import PhotoMaidCore

@Suite struct PhotoSnakeGameTests {
    typealias Cell = PhotoSnakeGame.Cell

    @Test func firstSwipeCanChooseEveryDirectionButCannotTeleportAfterMoving() throws {
        for width in 4...24 {
            for direction in PhotoSnakeGame.Direction.allCases {
                var game = try #require(PhotoSnakeGame(width: width, height: width, seed: 7))
                let faced = game.faceBeforeFirstStep(direction)
                #expect(faced)
                #expect(Set(game.body).count == 3)
                #expect(game.body.allSatisfy { (0..<width).contains($0.x) && (0..<width).contains($0.y) })
                let food = try #require(game.food)
                #expect(!game.body.contains(food))
                _ = game.step()
                let moved = game
                let changed = game.faceBeforeFirstStep(direction.opposite)
                #expect(!changed)
                #expect(game == moved)
            }
        }
    }

    @Test func viewportChoosesUsableGridsForPhoneAndExpandedWindows() {
        let phone = PhotoSnakeViewport(width: 402, height: 874)
        let expanded = PhotoSnakeViewport(width: 744, height: 1133)
        #expect(phone.columns == 8 && phone.rows == 20)
        #expect(expanded.columns == 15 && expanded.rows == 24)
        #expect(PhotoSnakeViewport(width: 1133, height: 744).rows == 15)
        #expect(PhotoSnakeViewport(width: .nan, height: 100).columns == 12)
        #expect(PhotoSnakeViewport(width: 100, height: .infinity).rows == 16)
    }

    @Test func validBoardAndFoodNeverOverlapTheInitialStrip() throws {
        #expect(PhotoSnakeGame(width: 3) == nil)
        #expect(PhotoSnakeGame(height: 25) == nil)
        for seed in 0..<50 {
            let game = try #require(PhotoSnakeGame(seed: UInt64(seed)))
            let food = try #require(game.food)
            #expect(!game.body.contains(food))
            #expect((0..<game.width).contains(food.x) && (0..<game.height).contains(food.y))
            #expect(game.body.count == 3 && game.score == 0)
        }
    }

    @Test func rapidTurnsAreBufferedInOrderAndCannotReverse() throws {
        var game = try #require(PhotoSnakeGame(seed: 1))
        #expect(game.turn(.left) == false)
        #expect(game.turn(.up) == true)
        #expect(game.turn(.down) == false)
        #expect(game.turn(.left) == true)
        #expect(game.turn(.down) == false) // two corners already buffered
        _ = game.step()
        #expect(game.direction == .up)
        _ = game.step()
        #expect(game.direction == .left)
    }

    @Test func classicWallEndsTheRoundButRelaxedModeWraps() throws {
        var classic = try #require(PhotoSnakeGame(width: 6, height: 6, seed: 3))
        var relaxed = try #require(PhotoSnakeGame(width: 6, height: 6, mode: .relaxed, seed: 3))
        for _ in 0..<3 { _ = classic.step(); _ = relaxed.step() }
        #expect(classic.status == .lost)
        #expect(classic.step() == .ignored)
        #expect(relaxed.status == .playing && relaxed.body[0] == Cell(0, 3))
    }

    @Test func collectingGrowsExactlyOnceAndKeepsFoodOffTheBody() throws {
        var game = try #require((0..<1000).compactMap { PhotoSnakeGame(width: 6, height: 6, seed: UInt64($0)) }
            .first { $0.food == Cell(4, 3) })
        #expect(game.step() == .collected)
        #expect(game.score == 1 && game.body.count == 4)
        let food = try #require(game.food)
        #expect(!game.body.contains(food))
    }

    @Test func enteringTheDepartingTailIsLegal() throws {
        var chosen: PhotoSnakeGame?
        for seed in 0..<1000 {
            guard var game = PhotoSnakeGame(width: 6, height: 6, seed: UInt64(seed)), game.food == Cell(4, 3) else { continue }
            _ = game.step()
            guard let food = game.food, ![Cell(4, 2), Cell(3, 2), Cell(3, 3)].contains(food) else { continue }
            chosen = game; break
        }
        var game = try #require(chosen)
        _ = game.turn(.up); _ = game.step()
        _ = game.turn(.left); _ = game.step()
        #expect(game.body.last == Cell(3, 3))
        _ = game.turn(.down)
        #expect(game.step() == .moved)
        #expect(game.status == .playing && Set(game.body).count == game.body.count)
    }

    @Test func collisionWithTheBodyEndsTheRound() throws {
        var game = try #require(PhotoSnakeGame(width: 6, height: 6, seed: 174))
        #expect(game.food == Cell(4, 3))
        #expect(game.step() == .collected)
        #expect(game.food == Cell(4, 2))
        _ = game.turn(.up)
        #expect(game.step() == .collected)
        #expect(game.body.count == 5)
        _ = game.turn(.left); _ = game.step()
        _ = game.turn(.down)
        #expect(game.step() == .lost)
        #expect(game.status == .lost && game.step() == .ignored)
    }

    @Test func aFullBoardWinsWithoutHangingOnFoodPlacement() throws {
        let cycle = [Cell(0,0), Cell(1,0), Cell(2,0), Cell(3,0), Cell(3,1), Cell(2,1), Cell(1,1), Cell(1,2),
                     Cell(2,2), Cell(3,2), Cell(3,3), Cell(2,3), Cell(1,3), Cell(0,3), Cell(0,2), Cell(0,1)]
        var game = try #require(PhotoSnakeGame(width: 4, height: 4, seed: 47))
        var index = try #require(cycle.firstIndex(of: game.body[0]))
        for _ in 0..<500 where game.status == .playing {
            let next = cycle[(index + 1) % cycle.count], head = game.body[0]
            let direction: PhotoSnakeGame.Direction = next.x > head.x ? .right : next.x < head.x ? .left : next.y > head.y ? .down : .up
            _ = game.turn(direction); _ = game.step(); index = (index + 1) % cycle.count
        }
        #expect(game.status == .won && game.food == nil)
        #expect(game.body.count == 16 && game.score == 13)
    }

    @Test func seededRoundIsReproducibleAndOnlyStepsChangeIt() throws {
        let original = try #require(PhotoSnakeGame(seed: 123))
        #expect(PhotoSnakeGame(seed: 123) == original)
        var resumed = original
        #expect(resumed == original)
        _ = resumed.step()
        #expect(resumed != original)
    }
}
