import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct PhotoSnakePresentationTests {
    @Test func interpolationFollowsOrthogonalHistoryAndFinishesAtAuthoritativeCells() throws {
        var game = try #require(PhotoSnakeGame(width: 12, height: 16, mode: .relaxed, seed: 123))
        var motion = PhotoSnakeMotion(game: game)
        let directions: [PhotoSnakeGame.Direction] = [.right, .up, .left, .down]
        for direction in directions {
            _ = game.turn(direction)
            let event = game.step(); motion.advance(to: game, event: event)
            for fraction in [0.0, 0.25, 0.5, 0.75, 1] {
                let points = motion.points(progress: fraction)
                #expect(points.count == game.body.count)
                for line in motion.lines(progress: fraction) {
                    #expect(abs(line.a.x - line.b.x) < 0.00001 || abs(line.a.y - line.b.y) < 0.00001)
                }
                if fraction == 1 {
                    for (point, cell) in zip(points, game.body) {
                        #expect(motion.wrapped(point) == .init(Double(cell.x) + 0.5, Double(cell.y) + 0.5))
                    }
                }
            }
        }
    }
    @Test func wrappedEdgesNeverDrawAcrossTheBoard() throws {
        var game = try #require(PhotoSnakeGame(width: 6, height: 6, mode: .relaxed, seed: 3))
        var motion = PhotoSnakeMotion(game: game)
        for _ in 0..<30 {
            let event = game.step(); motion.advance(to: game, event: event)
            for fraction in [0.0, 0.25, 0.5, 0.75, 1] {
                for line in motion.lines(progress: fraction) {
                    #expect(hypot(line.a.x - line.b.x, line.a.y - line.b.y) <= 1.00001)
                }
            }
            #expect(motion.wrapped(try #require(motion.points(progress: 1).first)) == .init(Double(game.body[0].x) + 0.5, Double(game.body[0].y) + 0.5))
        }
    }
    @Test func collisionOnlyTravelsToContactAndCannotChangeTheRules() throws {
        var game = try #require(PhotoSnakeGame(width: 6, height: 6, seed: 3))
        var motion = PhotoSnakeMotion(game: game)
        for _ in 0..<2 { let event = game.step(); motion.advance(to: game, event: event) }
        let before = try #require(motion.points(progress: 1).first)
        let event = game.step(); #expect(event == .lost)
        let ended = game
        motion.advance(to: game, event: event)
        let end = try #require(motion.points(progress: 1).first)
        #expect(abs(end.x - before.x - 0.45) < 0.00001)
        #expect(end.x < Double(game.width))
        #expect(game == ended)
    }
    @Test func growthUnfoldsFromTailWithoutImportingOrTeleportingPhotos() throws {
        var game = try #require(PhotoSnakeGame(width: 6, height: 6, seed: 174))
        var motion = PhotoSnakeMotion(game: game)
        let event = game.step(); #expect(event == .collected)
        motion.advance(to: game, event: event)
        let start = motion.points(progress: 0)
        #expect(start.count == 4 && start[2] == start[3])
        let end = motion.points(progress: 1)
        #expect(end.count == 4 && end[2] != end[3])
        #expect(end.last == .init(1.5, 3.5))
    }
    @Test func historySupportsThreeHundredSegmentsOnTheUnmodifiedGame() throws {
        typealias Cell = PhotoSnakeGame.Cell
        // A Hamiltonian cycle whose even rows travel right, matching the existing starting body.
        var cycle = (0..<24).map { Cell($0, 0) }
        for y in 1..<24 {
            let xs = y.isMultiple(of: 2) ? Array(1..<24) : Array((1..<24).reversed())
            cycle += xs.map { Cell($0, y) }
        }
        cycle += (1..<24).reversed().map { Cell(0, $0) }
        var game = try #require(PhotoSnakeGame(width: 24, height: 24, seed: 47))
        var motion = PhotoSnakeMotion(game: game)
        var index = try #require(cycle.firstIndex(of: game.body[0]))
        for _ in 0..<200_000 where game.status == .playing && game.body.count < 303 {
            let next = cycle[(index + 1) % cycle.count], head = game.body[0]
            let direction: PhotoSnakeGame.Direction = next.x > head.x ? .right : next.x < head.x ? .left : next.y > head.y ? .down : .up
            _ = game.turn(direction)
            let event = game.step(); motion.advance(to: game, event: event)
            index = (index + 1) % cycle.count
        }
        #expect(game.status == .playing && game.body.count >= 303)
        let samples = motion.points(progress: 0.5)
        #expect(samples.count == game.body.count)
        #expect(motion.route(progress: 0.5).count <= game.body.count + 2)
        for line in motion.lines(progress: 0.5) { #expect(line.a.x == line.b.x || line.a.y == line.b.y) }
        // This is CPU/domain validation, not a GPU FPS measurement.
    }
    @Test func animationPriorityTimingAndSkinsUseKitFrames() {
        for character in PhotoSnakeCharacter.allCases {
            #expect(PhotoSnakeHeadAnimation.frame(character: character, time: 0).texture == character.idle)
            #expect(PhotoSnakeHeadAnimation.frame(character: character, time: 3.05).texture == character.blink)
            #expect(PhotoSnakeHeadAnimation.frame(character: character, time: 0, eating: 0.05).texture == character.eat)
            #expect(PhotoSnakeHeadAnimation.frame(character: character, time: 0, collision: 0.3).texture == character.dead)
            #expect(PhotoSnakeHeadAnimation.frame(character: character, time: 0, eating: 0.1, reduceMotion: true).scale == 1)
        }
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 4.7).texture == "head_idle_06")
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 0, danger: true).texture == "head_surprised")
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 0, collision: 0.01, danger: true).texture == "head_hurt")
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 0, collision: 0.5).texture == "head_dead_02")
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 0, sleeping: true).texture == "head_sleep")
        #expect(PhotoSnakeHeadAnimation.frame(character: .snake, time: 0, lookingLeft: false).texture == "head_look_right")
    }
    @Test func rotationTakesTheShortestPathAndPreferencesRoundTrip() throws {
        let angle = PhotoSnakeHeadAnimation.shortestAngle(from: 170 * .pi / 180, to: -170 * .pi / 180, fraction: 0.5)
        #expect(abs(angle - .pi) < 0.00001)
        #expect(PhotoSnakeHeadAnimation.shortestAngle(from: .nan, to: 0, fraction: 1) == 0)
        var preferences = PhotoSnakePreferences()
        preferences.character = .dragon; preferences.night = true; preferences.sound = false
        preferences.food = .pizza; preferences.shufflePhotos = true
        #expect(try JSONDecoder().decode(PhotoSnakePreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
        let defaults = try JSONDecoder().decode(PhotoSnakePreferences.self, from: Data("{\"character\":\"future\"}".utf8))
        #expect(defaults == PhotoSnakePreferences())
        #expect(Set((0..<18).map { PhotoSnakeFood.mixed.texture(score: $0) }).count == 9)
    }
}
