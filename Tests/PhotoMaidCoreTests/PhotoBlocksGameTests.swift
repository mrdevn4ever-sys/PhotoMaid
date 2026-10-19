import Foundation
import Testing
@testable import PhotoMaidCore

struct PhotoBlocksGameTests {
    private func blank(_ width: Int = 9, _ height: Int = 17) -> [[PhotoBlocksShape?]] {
        Array(repeating: Array(repeating: nil, count: width), count: height)
    }
    private func clearing(_ count: Int, revealed: Int = 0, level: Int = 1, width: Int = 9, height: Int = 17) -> PhotoBlocksGame {
        var board = blank(width, height)
        // A four-cell tall fern fills one gap per row. Extra cells occupy neighbouring gaps.
        let piece = PhotoBlocksPiece(shape: .fern, origin: .init(0, height - 4))
        for y in (height - count)..<height {
            board[y] = Array(repeating: .arch, count: width)
        }
        for cell in piece.cells { board[cell.y][cell.x] = nil }
        return .init(testBoard: board, active: piece, revealed: revealed, level: level)
    }

    @Test func formsAreDistinctConnectedAndRotateWithoutLosingCells() {
        #expect(PhotoBlocksShape.playableShapes.count == 7)
        #expect(Set(PhotoBlocksShape.playableShapes.map { $0.cells().count }) == [4])
        for shape in PhotoBlocksShape.allCases {
            for rotation in 0..<4 {
                let cells = Set(shape.cells(rotation: rotation))
                #expect(cells.count == shape.cells().count)
                #expect(cells.allSatisfy { $0.x >= 0 && $0.y >= 0 })
                var visited: Set<PhotoBlocksCell> = [cells.first!]
                for _ in cells {
                    for cell in visited {
                        for neighbor in [PhotoBlocksCell(cell.x - 1, cell.y), .init(cell.x + 1, cell.y),
                                         .init(cell.x, cell.y - 1), .init(cell.x, cell.y + 1)] where cells.contains(neighbor) {
                            visited.insert(neighbor)
                        }
                    }
                }
                #expect(visited == cells)
            }
            #expect(shape.cells(rotation: 4) == shape.cells())
        }
    }

    @Test func seededBagsAreFairAndReproducible() {
        var a = PhotoBlocksGame(width: 14, height: 28, seed: 42), b = PhotoBlocksGame(width: 14, height: 28, seed: 42)
        a.start(); b.start()
        #expect(a == b)
        var drawn: [PhotoBlocksShape] = []
        // Independently test the bag generator via a tall, empty board fixture per drop.
        for _ in PhotoBlocksShape.playableShapes { drawn.append(a.active!.shape); a.hardDrop(); b.hardDrop() }
        #expect(a == b)
        #expect(Set(drawn) == Set(PhotoBlocksShape.playableShapes))
    }

    @Test(arguments: PhotoBlocksShape.playableShapes)
    func fourSquarePiecesRotateAtBothWallsAndTheFloorAndLockFourCells(_ shape: PhotoBlocksShape) {
        let cells = shape.cells()
        let width = cells.map(\.x).max()! + 1, height = cells.map(\.y).max()! + 1
        for x in [0, 9 - width] {
            var game = PhotoBlocksGame(testBoard: blank(), active: .init(shape: shape, origin: .init(x, 17 - height)))
            for _ in 0..<4 { #expect(game.rotate()); #expect(game.fits(game.active!)) }
            game.hardDrop()
            #expect(game.piecesPlaced == 1)
            #expect(game.board.flatMap { $0 }.compactMap { $0 }.count == 4)
            #expect(game.isValidSnapshot)
        }
    }

    @Test func fourSquareLineClearsFourRowsAndRevealsFortyPercent() {
        var board = blank()
        for y in 13..<17 { board[y] = Array(repeating: .square, count: 9); board[y][4] = nil }
        var game = PhotoBlocksGame(testBoard: board, active: .init(shape: .line, origin: .init(4, 13)))
        game.hardDrop()
        #expect(game.clearedRows == [13, 14, 15, 16])
        game.advance(0.18)
        #expect(game.totalRows == 4 && game.progress == 0.4)
        #expect(game.score == 405)
        #expect(game.board.allSatisfy { $0.allSatisfy { $0 == nil } })
    }

    @Test func oldSavedPiecesAndRecordsSurviveWhileFutureDrawsUseFourSquares() throws {
        let oldGame = PhotoBlocksGame(testBoard: blank(), active: .init(shape: .pebble, origin: .init(2, 16)))
        var stored = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(oldGame)) as? [String: Any])
        stored["bag"] = [0, 1, 2, 3, 4, 5]
        stored["next"] = PhotoBlocksShape.fern.rawValue
        let bytes = try JSONSerialization.data(withJSONObject: stored)
        var restored = try JSONDecoder().decode(PhotoBlocksGame.self, from: bytes)
        #expect(restored.isValidSnapshot && restored.active?.shape == .pebble)
        var archive = PhotoBlocksArchive(game: restored, best: 1_234)
        restored.hardDrop()
        #expect(restored.active?.shape == .fern) // Already promised next piece remains intact.
        restored.hardDrop()
        #expect(restored.active?.shape.isLegacy == false)
        #expect(restored.next.isLegacy == false)
        #expect(restored.board[16][2] == .pebble && restored.board[16][3] == .pebble)
        #expect(restored.isValidSnapshot)
        archive.game = restored
        let roundTrip = try JSONDecoder().decode(PhotoBlocksArchive.self, from: JSONEncoder().encode(archive))
        #expect(roundTrip.best == 1_234 && roundTrip.game == restored)
    }

    @Test func gravityFallsAndFloorLocksExactlyOnce() {
        var game = PhotoBlocksGame(); game.start()
        let before = game.active!.origin.y
        for _ in 0..<4 { game.advance(0.22) }
        #expect(game.active!.origin.y == before + 1)
        var floor = PhotoBlocksGame(testBoard: blank(), active: .init(shape: .pebble, origin: .init(2, 16)))
        floor.advance(0.20); #expect(floor.piecesPlaced == 0)
        floor.advance(0.20); #expect(floor.piecesPlaced == 1)
        #expect(floor.board[16][2] == .pebble && floor.board[16][3] == .pebble)
        #expect(floor.score == 5)
    }

    @Test func collisionAndBoundariesNeverAllowAnIllegalMove() {
        var board = blank(); board[15][3] = .arch
        var game = PhotoBlocksGame(testBoard: board, active: .init(shape: .pebble, origin: .init(1, 15)))
        #expect(game.move(1) == false)
        #expect(game.move(-1) == true); #expect(game.move(-1) == false)
        #expect(game.move(2) == false); #expect(game.move(0) == false)
        #expect(!game.fits(.init(shape: .pebble, origin: .init(8, 10))))
        #expect(!game.fits(.init(shape: .shoot, origin: .init(0, -1))))
        #expect(!game.fits(.init(shape: .shoot, origin: .init(0, 16))))
    }

    @Test func rotationAtWallAndFloorKicksOnlyToLegalPositions() {
        for x in [0, 7] {
            var game = PhotoBlocksGame(testBoard: blank(), active: .init(shape: .fern, origin: .init(x, 13)))
            #expect(game.rotate() == true); #expect(game.fits(game.active!))
            for _ in 0..<20 { _ = game.rotate(); #expect(game.fits(game.active!)) }
        }
        var enclosed = blank()
        for y in 14..<17 { enclosed[y] = Array(repeating: .shoot, count: 9) }
        enclosed[16][0] = nil; enclosed[16][1] = nil
        var game = PhotoBlocksGame(testBoard: enclosed, active: .init(shape: .pebble, origin: .init(0, 16)))
        #expect(game.rotate() == false)
    }

    @Test func rowsClearTogetherAndRemainingCellsCompactCorrectly() {
        for count in 1...4 {
            var game = clearing(count)
            game.hardDrop(); #expect(game.phase == .clearing)
            #expect(game.clearedRows.count == count)
            game.advance(0.18)
            #expect(game.totalRows == count)
            #expect(game.revealedStrips == count)
            #expect(game.progress == Double(count) / 10)
            #expect(game.board.count == 17)
            #expect(game.board.prefix(count).allSatisfy { $0.allSatisfy { $0 == nil } })
            #expect(game.score == 5 + 20 * count * (count + 1))
        }
        var board = blank()
        board[10][7] = .petal; board[16] = Array(repeating: .shoot, count: 9)
        board[16][0] = nil; board[16][1] = nil
        var game = PhotoBlocksGame(testBoard: board, active: .init(shape: .pebble, origin: .init(0, 16)))
        game.hardDrop(); game.advance(0.18)
        #expect(game.board[11][7] == .petal && game.board[10][7] == nil)
    }

    @Test func discoveryPausesForTwoSecondsCarriesRowsAndKeepsTheBoard() {
        var game = clearing(3, revealed: 8)
        game.hardDrop(); game.advance(0.18)
        #expect(game.phase == .discovered && game.revealedStrips == 10)
        #expect(game.discoveredPhotos == 1 && game.totalRows == 11)
        #expect(game.isValidSnapshot)
        let board = game.board, score = game.score
        #expect(game.move(1) == false); #expect(game.rotate() == false); #expect(game.hardDrop() == false)
        game.advance(1); #expect(game.phase == .discovered)
        game.pause(); game.advance(10); #expect(game.phase == .discovered)
        game.resume(); game.advance(1)
        #expect(game.level == 2 && game.revealedStrips == 1 && game.progress == 0.1)
        #expect(game.board == board && game.score == score && game.phase == .playing)
        #expect(game.isValidSnapshot)
    }

    @Test func exactTenRowsAndGameOverAreDetected() {
        var game = clearing(2, revealed: 8)
        game.hardDrop(); game.advance(0.18); game.advance(2)
        #expect(game.level == 2 && game.revealedStrips == 0)
        var blocked = blank()
        blocked[0] = Array(repeating: .shoot, count: 9)
        blocked[0][0] = nil // Block spawn without creating a full row that would legitimately clear.
        var over = PhotoBlocksGame(testBoard: blocked, active: .init(shape: .pebble, origin: .init(0, 16)))
        over.hardDrop()
        #expect(over.phase == .gameOver && over.active == nil)
        let snapshot = over; over.advance(10); over.rotate(); over.hardDrop()
        #expect(over == snapshot)
    }

    @Test func pausesStopGravityDropInputAndCelebrationsWithoutCatchUp() {
        var game = PhotoBlocksGame(); game.start(); game.setSoftDrop(true); game.pause()
        let frozen = game
        game.advance(200); game.move(1); game.rotate(); game.hardDrop()
        #expect(game == frozen)
        game.resume(); let y = game.active!.origin.y
        game.advance(0.05); #expect(game.active!.origin.y == y)
        game.setSoftDrop(true); game.advance(0.05); #expect(game.active!.origin.y > y)
        game.advance(.nan); game.advance(.infinity); game.advance(-1)
        #expect(game.isValidSnapshot)
    }

    @Test func persistenceRoundTripContinuesDeterministicallyAndContainsNoPhotos() throws {
        var game = clearing(3, revealed: 8); game.hardDrop(); game.advance(0.18); game.pause()
        let archive = PhotoBlocksArchive(game: game, best: 450)
        let data = try JSONEncoder().encode(archive)
        let restored = try JSONDecoder().decode(PhotoBlocksArchive.self, from: data)
        #expect(restored == archive && restored.game!.isValidSnapshot)
        var a = restored.game!, b = game
        a.resume(); b.resume(); a.advance(2); b.advance(2)
        for _ in 0..<20 { a.rotate(); b.rotate(); a.advance(0.05); b.advance(0.05) }
        #expect(a == b)
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["assetID", "image", "photoID", "thumbnail", "selection", "path"] { #expect(!text.contains(forbidden)) }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as! [String: Any]
        object["board"] = [[1]]
        let invalid = try JSONDecoder().decode(PhotoBlocksGame.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!invalid.isValidSnapshot && PhotoBlocksArchive(game: invalid).game == nil)
    }

    @Test func twentyContinuousLevelTransitionsPausesAndDifferentBoards() throws {
        for (width, height) in [(6, 12), (9, 17), (14, 28)] {
            var game = PhotoBlocksGame(width: width, height: height, seed: 99); game.start()
            var transitions = 0
            while game.level <= 20 {
                // Feed legal row-completion fixtures into ONE continuing serialized simulation.
                // Counters, score, pending bag, PRNG, carry and level remain the actual prior state.
                let fixture = clearing(4, width: width, height: height)
                var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as! [String: Any]
                let replacement = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as! [String: Any]
                data["board"] = replacement["board"]; data["active"] = replacement["active"]
                game = try JSONDecoder().decode(PhotoBlocksGame.self, from: JSONSerialization.data(withJSONObject: data))
                let oldLevel = game.level, interval = game.fallInterval
                game.hardDrop(); game.pause(); let frozen = game
                game.advance(200); #expect(game == frozen)
                game.resume(); game.advance(0.18)
                let board = game.board
                if game.phase == .discovered {
                    game.advance(2); transitions += 1
                    #expect(game.level == oldLevel + 1)
                    #expect(game.board == board && game.fallInterval < interval)
                }
                #expect(game.isValidSnapshot)
                #expect(game.fallInterval > 0.16)
            }
            #expect(transitions == 20 && game.totalRows == 200 && game.discoveredPhotos == 20)
            #expect(PhotoBlocksGame(width: width, height: height).score == 0)
        }
        let end = clearing(2, revealed: 8, level: 1_000_000)
        #expect(end.fallInterval >= 0.16 && end.fallInterval < 0.161)
    }

    @Test func tenThousandRealInputsAndRestartsKeepAllBoardInvariants() {
        var random = PhotoBlocksRandom(state: 77)
        var game = PhotoBlocksGame(seed: 123); game.start()
        for index in 0..<10_000 {
            if game.phase == .gameOver { game = PhotoBlocksGame(seed: UInt64(index)); game.start() }
            switch random.next() % 5 {
            case 0: _ = game.move(-1)
            case 1: _ = game.move(1)
            case 2: _ = game.rotate()
            case 3: _ = game.hardDrop()
            default: game.advance(0.20)
            }
            if index.isMultiple(of: 11) { game.pause(); let frozen = game; game.advance(10); #expect(game == frozen); game.resume() }
            if game.phase == .clearing { game.advance(0.18) }
            if game.phase == .discovered { game.advance(2) }
            #expect(game.isValidSnapshot)
        }
    }

    @Test func restingPieceCannotAvoidLockForeverByShufflingAndGhostStopsOnAnObstacle() {
        var game = PhotoBlocksGame(testBoard: blank(), active: .init(shape: .pebble, origin: .init(2, 16)))
        for index in 0..<20 where game.piecesPlaced == 0 {
            _ = game.move(index.isMultiple(of: 2) ? 1 : -1)
            game.advance(0.10)
        }
        #expect(game.piecesPlaced == 1)
        var board = blank(); board[12][3] = .arch
        let above = PhotoBlocksGame(testBoard: board, active: .init(shape: .pebble, origin: .init(3, 0)))
        #expect(above.ghost?.origin.y == 11)
        #expect(above.active?.origin.y == 0)
    }
    @Test func fourCellTallFormCanRotateAtTheFloorWithoutCrossingAnyBoundary() {
        var game = PhotoBlocksGame(testBoard: blank(), active: .init(shape: .fern, rotation: 1, origin: .init(4, 15)))
        #expect(game.rotate() == true)
        #expect(game.active?.origin.y == 13 && game.active?.rotation == 2)
        #expect(game.fits(game.active!))
        #expect(game.active!.cells.allSatisfy { (0..<17).contains($0.y) && (0..<9).contains($0.x) })
    }
    @Test func softDropDoesNotConvertOldGravityTimeIntoAnInstantMultiRowFall() {
        var game = PhotoBlocksGame(); game.start()
        for _ in 0..<3 { game.advance(0.22) }
        let y = game.active!.origin.y
        game.setSoftDrop(true); game.advance(0.01)
        #expect(game.active!.origin.y == y)
        game.advance(0.01); #expect(game.active!.origin.y == y + 1)
        game.setSoftDrop(false); game.advance(0.01)
        #expect(game.active!.origin.y == y + 1)
    }
}
