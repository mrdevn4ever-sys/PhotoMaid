import PhotoMaidCore
import Testing
import UIKit
@testable import PhotoMaid

@MainActor struct PhotoSnakeModelTests {
    @Test func aPreparedRoundStaysStillUntilExplicitResume() throws {
        let model = PhotoSnakeModel()
        model.startMotifs(mode: .relaxed, speed: .gentle, stepMode: false)
        let initial = try #require(model.game)
        model.tick()
        model.steer(.up)
        #expect(!model.running && model.game == initial)
        model.resume(); model.tick(); model.pause()
        let paused = model.game
        model.tick()
        #expect(model.game == paused && model.game != initial)
    }

    @Test func stepModeMovesOncePerValidInputAndNeverReverses() throws {
        let model = PhotoSnakeModel()
        model.startMotifs(mode: .relaxed, speed: .normal, stepMode: true)
        let head = try #require(model.game?.body.first)
        model.resume()
        model.steer(.left)
        #expect(model.game?.body.first == head)
        model.steer(.up)
        #expect(model.game?.body.first == .init(head.x, head.y - 1))
        model.tick()
        #expect(model.game?.body.first == .init(head.x, head.y - 2))
    }

    @Test func realtimeSteeringWaitsForATickAndRestartIsPaused() throws {
        let model = PhotoSnakeModel()
        model.startMotifs(mode: .classic, speed: .normal, stepMode: false)
        let head = try #require(model.game?.body.first), round = model.roundID
        model.resume(); model.steer(.up)
        #expect(model.game?.body.first == head)
        model.tick()
        #expect(model.game?.body.first == .init(head.x, head.y - 1))
        model.restart()
        #expect(!model.running && model.roundID != round && model.game?.score == 0)
        #expect(model.strip.count == 2)
    }

    @Test func voiceOverStepModeAndValidationPreserveSymbolRounds() throws {
        let model = PhotoSnakeModel(canUsePhotos: { _ in false })
        model.startMotifs(mode: .relaxed, speed: .fast, stepMode: false)
        let round = try #require(model.game)
        model.resume(); model.useStepMode(); model.validatePhotos()
        #expect(!model.running && model.stepMode && model.game == round)
    }

    @Test func aSmallFavoriteSourceCanPrepareSnakeWithoutWeakeningMemoryRules() async throws {
        let snakePhotos = PhotoGamePhotos(canUsePhotos: { _ in true })
        let memory = PhotoMemoryModel(canUsePhotos: { _ in true })
        memory.startMotifs()
        let round = memory.game
        var ready = false
        snakePhotos.startRandom(["only"], count: 12, minimumCount: 1, exactCount: false,
                                load: { _ in UIImage() }, ready: { ready = true })
        for _ in 0..<100 {
            if !snakePhotos.isLoading { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(ready && snakePhotos.photoIDs == ["only"])
        #expect(memory.game == round && memory.photoIDs.isEmpty)
        memory.startRandom(["only"], pairCount: 6) { _ in UIImage() }
        for _ in 0..<100 {
            if !memory.isLoading { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(memory.game == round && memory.error != nil)
    }
}
