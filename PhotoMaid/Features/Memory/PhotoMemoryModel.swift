import Observation
import PhotoMaidCore
import UIKit

/// App-owned round; the photo loader is shared with Snake, with a separate preview store for each game.
@MainActor @Observable
final class PhotoMemoryModel {
    static let motifs = ["sun.max.fill", "leaf.fill", "mountain.2.fill", "camera.fill", "heart.fill", "moon.stars.fill"]
    let photos: PhotoGamePhotos
    let scores: PhotoGameScores
    private(set) var game: PhotoMemoryGame?
    private(set) var roundID = UUID()
    private(set) var newBest = false
    private(set) var manualMismatch = false
    private var stopwatch = PhotoGameStopwatch()
    @ObservationIgnored private var timingActive = false
    @ObservationIgnored private let now: @MainActor () -> Double
    var photoIDs: [String] { photos.photoIDs }
    var images: [String: UIImage] { photos.images }
    var isLoading: Bool { photos.isLoading }
    var randomSource: PhotoGameSource? { photos.randomSource }
    var allowsCloud: Bool { photos.allowsCloud }
    var error: String? { photos.error }
    var elapsedSeconds: Double { stopwatch.elapsed(at: now()) }
    var timerRunning: Bool { stopwatch.isRunning }
    var recordCategory: PhotoGameRecords.MemoryCategory? {
        game.map { .init(pairs: $0.pairCount, usesPhotos: !photoIDs.isEmpty, manualMismatch: manualMismatch) }
    }
    var bestSeconds: Double? { recordCategory.flatMap { scores.records.memoryBest(for: $0) } }

    init(scores: PhotoGameScores? = nil, canUsePhotos: (@MainActor ([String]) -> Bool)? = nil,
         now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.scores = scores ?? PhotoGameScores(); self.now = now
        photos = PhotoGamePhotos(canUsePhotos: canUsePhotos)
    }

    func startMotifs(manualMismatch: Bool = false) {
        photos.clear()
        game = PhotoMemoryGame(pairIDs: Self.motifs); roundID = UUID()
        resetTime(manualMismatch: manualMismatch)
    }

    func startPhotos(_ selection: [String], previews: PreviewPipeline, allowNetwork: Bool, manualMismatch: Bool = false) {
        stopwatch.pause(at: now())
        photos.startPhotos(selection, previews: previews, allowNetwork: allowNetwork) { [weak self] in self?.prepared(manualMismatch: manualMismatch) }
        if !isLoading { setTimingActive(timingActive) }
    }

    func startPhotos(_ selection: [String], allowNetwork: Bool = false,
                     load: @escaping @MainActor (String) async -> UIImage?) {
        stopwatch.pause(at: now())
        photos.startPhotos(selection, allowNetwork: allowNetwork, load: load) { [weak self] in self?.prepared(manualMismatch: false) }
        if !isLoading { setTimingActive(timingActive) }
    }

    func startRandom(source: PhotoGameSource, pairCount: Int, app: AppModel, allowNetwork: Bool, manualMismatch: Bool = false) {
        stopwatch.pause(at: now())
        photos.startRandom(source: source, count: pairCount, app: app, allowNetwork: allowNetwork) { [weak self] in self?.prepared(manualMismatch: manualMismatch) }
        if !isLoading { setTimingActive(timingActive) }
    }

    func startRandom(_ candidates: [String], pairCount: Int, load: @escaping @MainActor (String) async -> UIImage?) {
        stopwatch.pause(at: now())
        photos.startRandom(candidates, count: pairCount, load: load) { [weak self] in self?.prepared(manualMismatch: false) }
        if !isLoading { setTimingActive(timingActive) }
    }

    private func prepared(manualMismatch: Bool) {
        game = PhotoMemoryGame(pairIDs: photos.photoIDs); roundID = UUID()
        resetTime(manualMismatch: manualMismatch)
    }

    func replay(manualMismatch: Bool? = nil) {
        validatePhotos()
        guard game != nil else { return }
        game = PhotoMemoryGame(pairIDs: photoIDs.isEmpty ? Self.motifs : photoIDs); roundID = UUID()
        resetTime(manualMismatch: manualMismatch ?? self.manualMismatch)
        photos.error = nil
    }

    func reveal(_ id: Int) {
        validatePhotos()
        guard !isLoading else { return }
        let instant = now()
        let advancedMismatch = game?.hasMismatch == true
        guard let turn = game?.select(id), turn != .ignored else { return }
        if advancedMismatch { manualMismatch = true }
        if !stopwatch.hasStarted {
            stopwatch.resume(at: instant)
            if !timingActive { stopwatch.pause(at: instant) }
        }
        if turn == .matched { Haptics.commit() }
        if let game, game.isFinished {
            stopwatch.pause(at: instant)
            newBest = scores.recordMemory(game, seconds: elapsedSeconds, usesPhotos: !photoIDs.isEmpty, manualMismatch: manualMismatch)
        }
    }

    func setTimingActive(_ active: Bool) {
        timingActive = active
        if active, stopwatch.hasStarted, game?.isFinished == false, !isLoading { stopwatch.resume(at: now()) }
        else { stopwatch.pause(at: now()) }
    }

    func noteManualMismatch() { if game?.isFinished == false { manualMismatch = true } }

    private func resetTime(manualMismatch: Bool) {
        stopwatch.reset(); newBest = false; self.manualMismatch = manualMismatch
    }

    func concealMismatch() { game?.concealMismatch() }
    func concealMismatch(round: UUID, faceUp: [Int]) {
        guard roundID == round, game?.faceUp == faceUp else { return }
        concealMismatch()
    }
    func cancelLoading() { photos.cancelLoading() }
    func validatePhotos() { if photos.validatePhotos() { game = nil; roundID = UUID(); resetTime(manualMismatch: false) } }
    func image(for id: String) -> UIImage? { photos.image(for: id) }
}
