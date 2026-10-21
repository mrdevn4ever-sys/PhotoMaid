import Observation
import PhotoMaidCore
import UIKit

@MainActor @Observable
final class PhotoSnakeModel {
    typealias Speed = PhotoSnakeSpeed
    let photos: PhotoGamePhotos
    let gallery: SnakePhotoLibrary
    let audio = SnakeAudio()
    var preferences: PhotoSnakePreferences {
        didSet {
            do { try savePreferences(preferences); preferencesError = nil }
            catch { preferencesError = L("game_records_save_failed") }
            if !preferences.sound { audio.stop() }
        }
    }
    private(set) var preferencesError: String?
    @ObservationIgnored private let savePreferences: @MainActor (PhotoSnakePreferences) throws -> Void
    private(set) var usesSavedPhotos = false
    private var savedOrder: [String] = []
    private(set) var stepSerial = 0
    private(set) var facingRevision = 0
    private(set) var lastEvent = PhotoSnakeGame.Event.ignored
    private(set) var stepOrigin: PhotoSnakeGame?
    private(set) var presentationPending = false
    private(set) var presentedScore = 0
    let scores: PhotoGameScores
    private(set) var game: PhotoSnakeGame?
    private(set) var roundID = UUID()
    private(set) var running = false
    private(set) var started = false
    private(set) var speed = Speed.normal
    private(set) var stepMode = false
    private(set) var tooWarm = false
    private(set) var memorySuspended = false
    private(set) var strip: [String] = []
    private(set) var nextPhoto = 0
    private(set) var newBest = false
    private var viewport = PhotoSnakeViewport(width: 432, height: 576)

    init(scores: PhotoGameScores? = nil, canUsePhotos: (@MainActor ([String]) -> Bool)? = nil,
         gallery: SnakePhotoLibrary? = nil, preferences: PhotoSnakePreferences = .init(),
         savePreferences: @escaping @MainActor (PhotoSnakePreferences) throws -> Void = { _ in }) {
        self.gallery = gallery ?? SnakePhotoLibrary()
        self.preferences = preferences; self.savePreferences = savePreferences
        self.scores = scores ?? PhotoGameScores(); photos = PhotoGamePhotos(canUsePhotos: canUsePhotos)
    }

    /// Ein Rekord je Spiel (Nutzerentscheidung 21.10.2026): Modus, Tempo, Steuerung und Feldgröße zählen nicht getrennt.
    func menuBest(mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) -> Int? { scores.records.snakeOverallBest }

    var bestEaten: Int? { scores.records.snakeOverallBest }

    var pictureIDs: [String] {
        if usesSavedPhotos {
            let permitted = Set(gallery.ids)
            let order = savedOrder.filter { permitted.contains($0) }
            return order.isEmpty ? ["placeholder"] : order
        }
        return photos.photoIDs.isEmpty ? PhotoMemoryModel.motifs : photos.photoIDs
    }
    var visibleImages: [String: UIImage] {
        if usesSavedPhotos { return gallery.images }
        return photos.images.filter { photos.image(for: $0.key) != nil }
    }
    var displayedStatus: PhotoSnakeGame.Status { presentationPending ? .playing : (game?.status ?? .playing) }
    func finishPresentation() { presentationPending = false; presentedScore = game?.score ?? 0 }

    func startSaved(mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        pause(); photos.clear(); usesSavedPhotos = true
        savedOrder = gallery.selection.order(shuffled: preferences.shufflePhotos, seed: UInt64.random(in: 1...UInt64.max)).map(\.uuidString)
        makeRound(mode: mode, speed: speed, stepMode: stepMode)
    }
    func applyGalleryChanges() {
        guard usesSavedPhotos, let game else { return }
        let ids = Set(gallery.ids)
        savedOrder.removeAll { !ids.contains($0) }
        savedOrder += gallery.ids.filter { !savedOrder.contains($0) }
        if !preferences.shufflePhotos { savedOrder = gallery.ids }
        strip = (0..<max(0, game.body.count - 1)).map { pictureIDs[$0 % pictureIDs.count] }
        nextPhoto = strip.count % pictureIDs.count
    }
    var foodPicture: String { pictureIDs[nextPhoto % pictureIDs.count] }

    func startMotifs(mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        pause(); usesSavedPhotos = false; photos.clear(); makeRound(mode: mode, speed: speed, stepMode: stepMode)
    }

    func startPhotos(_ ids: [String], app: AppModel, allowNetwork: Bool,
                     mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        pause()
        photos.startPhotos(ids, previews: app.previews, allowNetwork: allowNetwork, minimumCount: 1) { [weak self] in
            self?.usesSavedPhotos = false
            self?.makeRound(mode: mode, speed: speed, stepMode: stepMode)
        }
    }

    func startRandom(source: PhotoGameSource, app: AppModel, allowNetwork: Bool,
                     mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        pause()
        photos.startRandom(source: source, count: 12, app: app, allowNetwork: allowNetwork,
                           minimumCount: 1, exactCount: false) { [weak self] in
            self?.usesSavedPhotos = false
            self?.makeRound(mode: mode, speed: speed, stepMode: stepMode)
        }
    }

    private func makeRound(mode: PhotoSnakeGame.Mode, speed: Speed, stepMode: Bool) {
        preferences.mode = mode; preferences.speed = speed
        game = PhotoSnakeGame(width: viewport.columns, height: viewport.rows, mode: mode)
        self.speed = speed; self.stepMode = stepMode
        stepSerial = 0; facingRevision = 0; lastEvent = .ignored; stepOrigin = nil
        presentationPending = false; presentedScore = 0
        roundID = UUID(); running = false; started = false; newBest = false; nextPhoto = 2 % pictureIDs.count
        strip = [pictureIDs[0], pictureIDs[1 % pictureIDs.count]]
    }

    func restart() {
        validatePhotos()
        guard let game else { return }
        if usesSavedPhotos {
            savedOrder = gallery.selection.order(shuffled: preferences.shufflePhotos, seed: UInt64.random(in: 1...UInt64.max)).map(\.uuidString)
        }
        makeRound(mode: game.mode, speed: speed, stepMode: stepMode)
    }

    func resume() {
        validatePhotos(); updateTemperature()
        guard game?.status == .playing, !photos.isLoading, !tooWarm else { return }
        memorySuspended = false; started = true; running = true
    }

    func pause() { running = false }
    func memoryWarning() { pause(); audio.stop(); memorySuspended = true }

    func updateViewport(width: Double, height: Double) {
        let next = PhotoSnakeViewport(width: width, height: height)
        guard next != viewport else { return }
        viewport = next
        // Folding/resizing never changes an active round, its food, score or rules.
        if let game, !started { makeRound(mode: game.mode, speed: speed, stepMode: stepMode) }
    }

    func swipe(_ direction: PhotoSnakeGame.Direction) {
        if game?.status != .playing { restart() }
        if !started { _ = game?.faceBeforeFirstStep(direction); facingRevision += 1 }
        if !running { resume() }
        steer(direction)
    }
    func useStepMode() {
        pause()
        guard !stepMode else { return }
        stepMode = true; newBest = false
        if let game { newBest = scores.recordSnakeOverall(game, speed: speed, stepMode: true) }
    }

    func steer(_ direction: PhotoSnakeGame.Direction) {
        guard running, game?.status == .playing else { return }
        let forward = game?.nextDirection == direction
        let accepted = game?.turn(direction) == true
        if accepted { audio.play(.turn, enabled: preferences.sound) }
        if stepMode && (forward || accepted) { tick() }
    }

    func tick() {
        guard running else { return }
        updateTemperature()
        guard !tooWarm else { return }
        let before = game?.score
        stepOrigin = game
        lastEvent = game?.step() ?? .ignored
        guard lastEvent != .ignored else { return }
        stepSerial += 1; presentationPending = true
        if game?.score != before {
            strip.append(foodPicture); nextPhoto = (nextPhoto + 1) % pictureIDs.count
            if let game, scores.recordSnakeOverall(game, speed: speed, stepMode: stepMode) { newBest = true }
        }
        if game?.status != .playing { pause() }
    }

    func updateTemperature() {
        let state = ProcessInfo.processInfo.thermalState
        tooWarm = state == .serious || state == .critical
        if tooWarm { pause() }
    }

    func validatePhotos() {
        gallery.visibilityChanged()
        if usesSavedPhotos, gallery.ids.count != gallery.selection.photos.count { pause() }
        if !usesSavedPhotos && photos.validatePhotos() { pause(); game = nil; strip = []; nextPhoto = 0; newBest = false; roundID = UUID() }
    }
}
