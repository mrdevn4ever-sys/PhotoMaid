import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct PhotoGameRecordsTests {
    private func memory(pairs: Int = 6, finished: Bool = true) throws -> PhotoMemoryGame {
        var game = try #require(PhotoMemoryGame(pairIDs: (0..<pairs).map(String.init), shuffled: false))
        if finished { for card in game.cards { _ = game.reveal(card.id) } }
        return game
    }

    private func snake(eaten: Int) throws -> PhotoSnakeGame {
        typealias Cell = PhotoSnakeGame.Cell
        let cycle = [Cell(0,0), Cell(1,0), Cell(2,0), Cell(3,0), Cell(3,1), Cell(2,1), Cell(1,1), Cell(1,2),
                     Cell(2,2), Cell(3,2), Cell(3,3), Cell(2,3), Cell(1,3), Cell(0,3), Cell(0,2), Cell(0,1)]
        var game = try #require(PhotoSnakeGame(width: 4, height: 4, seed: 47))
        var index = try #require(cycle.firstIndex(of: game.body[0]))
        for _ in 0..<500 where game.score < eaten && game.status == .playing {
            let next = cycle[(index + 1) % cycle.count], head = game.body[0]
            _ = game.turn(next.x > head.x ? .right : next.x < head.x ? .left : next.y > head.y ? .down : .up)
            _ = game.step(); index = (index + 1) % cycle.count
        }
        #expect(game.score == eaten)
        return game
    }

    @Test func snakeKeepsOnlyTheLargestActualFoodCountIncludingUnfinishedRounds() throws {
        var records = PhotoGameRecords()
        let category = PhotoGameRecords.SnakeCategory(mode: .classic, speed: .normal, stepMode: false, width: 4, height: 4)
        #expect(records.recordSnake(try snake(eaten: 0), speed: .normal, stepMode: false) == false)
        #expect(records.recordSnake(try snake(eaten: 3), speed: .normal, stepMode: false) == true)
        #expect(records.recordSnake(try snake(eaten: 2), speed: .normal, stepMode: false) == false)
        #expect(records.recordSnake(try snake(eaten: 3), speed: .normal, stepMode: false) == false)
        #expect(records.snakeBest(for: category) == 3)
    }

    @Test func snakeSeparatesPacesControlsAndBoardSizes() throws {
        var records = PhotoGameRecords()
        let game = try snake(eaten: 2)
        for speed in PhotoSnakeSpeed.allCases { _ = records.recordSnake(game, speed: speed, stepMode: false) }
        _ = records.recordSnake(game, speed: .normal, stepMode: true)
        #expect(records.snake.count == 4)
        #expect(records.snakeBest(for: .init(mode: .relaxed, speed: .normal, stepMode: false, width: 4, height: 4)) == nil)
        #expect(records.snakeBest(for: .init(mode: .classic, speed: .normal, stepMode: false)) == nil)
    }

    @Test func memoryRequiresAWinAndReplacesOnlyWithAFasterWin() throws {
        var records = PhotoGameRecords()
        let game = try memory()
        #expect(records.recordMemory(try memory(finished: false), seconds: 1, usesPhotos: true) == false)
        #expect(records.recordMemory(game, seconds: 32, usesPhotos: true) == true)
        #expect(records.recordMemory(game, seconds: 31.25, usesPhotos: true) == true)
        #expect(records.recordMemory(game, seconds: 35, usesPhotos: true) == false)
        #expect(records.recordMemory(game, seconds: 31.25, usesPhotos: true) == false)
        #expect(records.memoryBest(for: .init(pairs: 6, usesPhotos: true)) == 31.25)
    }

    @Test func memorySeparatesRoundSizesPicturesAndManualMismatchRules() throws {
        var records = PhotoGameRecords()
        for pairs in [2, 6, 12, 18] {
            for photos in [true, false] {
                for manual in [true, false] {
                    _ = records.recordMemory(try memory(pairs: pairs), seconds: Double(pairs), usesPhotos: photos, manualMismatch: manual)
                }
            }
        }
        #expect(records.memory.count == 16)
        #expect(records.memoryBest(for: .init(pairs: 12, usesPhotos: true, manualMismatch: true)) == 12)
    }

    @Test func invalidTimesNeverReplaceARecord() throws {
        var records = PhotoGameRecords()
        let won = try memory()
        _ = records.recordMemory(won, seconds: 10, usesPhotos: true)
        for time in [Double.nan, .infinity, -.infinity, 0, -1] {
            #expect(records.recordMemory(won, seconds: time, usesPhotos: true) == false)
        }
        #expect(records.memoryBest(for: .init(pairs: 6, usesPhotos: true)) == 10)
    }

    @Test func recordsRoundTripWithoutPicturesAndSanitizeDuplicateOrInvalidStoredValues() throws {
        var records = PhotoGameRecords()
        _ = records.recordMemory(try memory(), seconds: 20, usesPhotos: true)
        _ = records.recordSnake(try snake(eaten: 3), speed: .normal, stepMode: false)
        let encoded = try JSONEncoder().encode(records)
        #expect(try JSONDecoder().decode(PhotoGameRecords.self, from: encoded) == records)
        var data = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let stored = try #require((data["memory"] as? [[String: Any]])?.first)
        var invalid = stored; invalid["seconds"] = -1
        var slower = stored; slower["seconds"] = 30
        data["memory"] = [invalid, slower, stored]
        let repaired = try JSONDecoder().decode(PhotoGameRecords.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(repaired.memory.count == 1 && repaired.memory.first?.seconds == 20)
        #expect(try JSONDecoder().decode(PhotoGameRecords.self, from: Data("{}".utf8)) == PhotoGameRecords())
    }

    @Test func clockDoesNotRunUntilStartedAndExcludesLongPauses() {
        var clock = PhotoGameStopwatch()
        #expect(clock.elapsed(at: 100) == 0 && !clock.hasStarted)
        clock.resume(at: 100)
        #expect(clock.elapsed(at: 103.25) == 3.25)
        clock.pause(at: 104)
        #expect(clock.elapsed(at: 10000) == 4 && !clock.isRunning)
        clock.resume(at: 10000); clock.pause(at: 10002)
        #expect(clock.elapsed(at: 20000) == 6)
    }

    @Test func repeatedClockEventsNeverDoubleCountAndResetStartsFresh() {
        var clock = PhotoGameStopwatch()
        clock.resume(at: 10); clock.resume(at: 11); clock.pause(at: 15); clock.pause(at: 20)
        #expect(clock.elapsed(at: 30) == 5)
        clock.reset()
        #expect(!clock.hasStarted && !clock.isRunning && clock.elapsed(at: 300) == 0)
    }

    @Test func invalidClockSamplesNeverCreateNegativeOrNonfiniteTimes() {
        var clock = PhotoGameStopwatch()
        clock.resume(at: .nan)
        #expect(!clock.hasStarted)
        clock.resume(at: 10)
        #expect(clock.elapsed(at: 9) == 0)
        clock.pause(at: .infinity)
        #expect(clock.elapsed(at: 20) == 0 && !clock.isRunning)
    }
}
