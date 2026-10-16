import Observation
import PhotoMaidCore
import UIKit

@MainActor @Observable
final class PhotoSnakeModel {
    typealias Speed = PhotoSnakeSpeed
    let photos: PhotoGamePhotos
    let scores: PhotoGameScores
    private(set) var game: PhotoSnakeGame?
    private(set) var roundID = UUID()
    private(set) var running = false
    private(set) var started = false
    private(set) var speed = Speed.normal
    private(set) var stepMode = false
    private(set) var tooWarm = false
    private(set) var strip: [String] = []
    private(set) var nextPhoto = 0
    private(set) var newBest = false

    init(scores: PhotoGameScores? = nil, canUsePhotos: (@MainActor ([String]) -> Bool)? = nil) {
        self.scores = scores ?? PhotoGameScores(); photos = PhotoGamePhotos(canUsePhotos: canUsePhotos)
    }

    var bestEaten: Int? {
        guard let game else { return nil }
        return scores.records.snakeBest(for: .init(mode: game.mode, speed: speed, stepMode: stepMode,
                                                    width: game.width, height: game.height))
    }

    var pictureIDs: [String] { photos.photoIDs.isEmpty ? PhotoMemoryModel.motifs : photos.photoIDs }
    var foodPicture: String { pictureIDs[nextPhoto % pictureIDs.count] }

    func startMotifs(mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        pause(); photos.clear(); makeRound(mode: mode, speed: speed, stepMode: stepMode)
    }

    func startPhotos(_ ids: [String], app: AppModel, allowNetwork: Bool,
                     mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        pause()
        photos.startPhotos(ids, previews: app.previews, allowNetwork: allowNetwork, minimumCount: 1) { [weak self] in
            self?.makeRound(mode: mode, speed: speed, stepMode: stepMode)
        }
    }

    func startRandom(source: PhotoGameSource, app: AppModel, allowNetwork: Bool,
                     mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        pause()
        photos.startRandom(source: source, count: 12, app: app, allowNetwork: allowNetwork,
                           minimumCount: 1, exactCount: false) { [weak self] in
            self?.makeRound(mode: mode, speed: speed, stepMode: stepMode)
        }
    }

    private func makeRound(mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        game = PhotoSnakeGame(mode: mode); self.speed = speed; self.stepMode = stepMode
        roundID = UUID(); running = false; started = false; newBest = false; nextPhoto = 2 % pictureIDs.count
        strip = [pictureIDs[0], pictureIDs[1 % pictureIDs.count]]
    }

    func restart() {
        validatePhotos()
        guard let game else { return }
        makeRound(mode: game.mode, speed: speed, stepMode: stepMode)
    }

    func resume() {
        validatePhotos(); updateTemperature()
        guard game?.status == .playing, !photos.isLoading, !tooWarm else { return }
        started = true; running = true
    }

    func pause() { running = false }
    func useStepMode() {
        pause()
        guard !stepMode else { return }
        stepMode = true; newBest = false
        if let game { newBest = scores.recordSnake(game, speed: speed, stepMode: true) }
    }

    func steer(_ direction: PhotoSnakeGame.Direction) {
        guard running, game?.status == .playing else { return }
        let forward = game?.nextDirection == direction
        let accepted = game?.turn(direction) == true
        if stepMode && (forward || accepted) { tick() }
    }

    func tick() {
        guard running else { return }
        updateTemperature()
        guard !tooWarm else { return }
        let before = game?.score
        _ = game?.step()
        if game?.score != before {
            strip.append(foodPicture); nextPhoto = (nextPhoto + 1) % pictureIDs.count
            if let game, scores.recordSnake(game, speed: speed, stepMode: stepMode) { newBest = true }
            Haptics.commit()
        }
        if game?.status != .playing { pause() }
    }

    func updateTemperature() {
        let state = ProcessInfo.processInfo.thermalState
        tooWarm = state == .serious || state == .critical
        if tooWarm { pause() }
    }

    func validatePhotos() {
        if photos.validatePhotos() { pause(); game = nil; strip = []; nextPhoto = 0; newBest = false; roundID = UUID() }
    }
}
