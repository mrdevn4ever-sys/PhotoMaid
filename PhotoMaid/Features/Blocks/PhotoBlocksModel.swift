import Observation
import Photos
import PhotoMaidCore
import UIKit

/// App-owned simulation, with the same secure photo loader and local store as the other games.
@MainActor @Observable final class PhotoBlocksModel {
    private(set) var game: PhotoBlocksGame
    private(set) var best: Int
    private(set) var newBest = false
    private(set) var discoveredImages: Int
    private(set) var saveFailed = false
    let photos: PhotoGamePhotos
    var source: PhotoBlocksPhotos.Source = .random
    private(set) var selection: [String] = []
    private(set) var sequence = PhotoBlocksPhotos(ids: [], shuffle: false, seed: 1)
    private var seed: UInt64 = 1
    @ObservationIgnored private var roundBest: Int
    @ObservationIgnored private var targetSize = CGSize(width: 640, height: 1200)
    @ObservationIgnored private var attached = false
    @ObservationIgnored private let clock = PhotoBlocksClock()
    @ObservationIgnored private let save: @MainActor (PhotoBlocksArchive) throws -> Void

    init(archive: PhotoBlocksArchive = .init(), photos: PhotoGamePhotos? = nil,
         save: @escaping @MainActor (PhotoBlocksArchive) throws -> Void = { _ in }) {
        game = archive.game?.isValidSnapshot == true ? archive.game! : PhotoBlocksGame()
        best = max(0, archive.best); roundBest = max(0, archive.best)
        discoveredImages = archive.discoveredImages
        self.photos = photos ?? PhotoGamePhotos(); self.save = save
        game.pause() // Restores always require an explicit resume, including celebrations.
    }

    var currentPhotoID: String? { sequence.id(at: game.level) }
    var image: UIImage? { currentPhotoID.flatMap { photos.image(for: $0) } }

    func start(app: AppModel) {
        seed = UInt64.random(in: 1...UInt64.max)
        game = PhotoBlocksGame(seed: seed); game.start()
        roundBest = best; newBest = false
        discoveredImages = 0
        refreshPhotos(app: app); checkpoint()
        syncClock(app: app)
    }
    func pause() { game.pause(); clock.stop(); checkpoint() }
    func resume(app: AppModel) { refreshPhotos(app: app); game.resume(); syncClock(app: app) }
    func attach(app: AppModel) { attached = true; refreshPhotos(app: app); syncClock(app: app) }
    private func syncClock(app: AppModel) {
        if attached && !game.isPaused && game.phase != .ready && game.phase != .gameOver {
            clock.start { [weak self, weak app] delta in
                guard let self, let app else { return }
                self.tick(delta, app: app)
            }
        } else { clock.stop() }
    }
    func apply(_ actions: [PhotoBlocksInput.Action]) {
        var haptic = false
        for action in actions {
            switch action {
            case .left: _ = game.move(-1)
            case .right: _ = game.move(1)
            case .rotate: haptic = game.rotate() || haptic
            case .softDrop(let enabled): game.setSoftDrop(enabled)
            case .hardDrop: haptic = game.hardDrop() || haptic
            }
        }
        if haptic { Haptics.commit() }
        updateBest()
        if actions.contains(.hardDrop) { checkpoint() }
        if game.phase == .gameOver { clock.stop() }
    }
    func tick(_ seconds: Double, app: AppModel) {
        let old = (game.phase, game.level, game.piecesPlaced)
        let hadPhoto = old.0 == .discovered && image != nil
        game.advance(seconds)
        if old.1 != game.level {
            if hadPhoto { discoveredImages += 1 }
            prepareWindow(app: app)
        }
        if old.0 != game.phase || old.2 != game.piecesPlaced {
            updateBest(); checkpoint()
            if game.phase == .clearing || game.phase == .discovered { Haptics.commit() }
        }
        if game.phase == .gameOver { clock.stop() }
    }
    private func updateBest() {
        best = max(best, game.score); newBest = game.score > roundBest
    }
    func checkpoint() {
        do { try save(.init(game: game, best: best, discoveredImages: discoveredImages)); saveFailed = false }
        catch { saveFailed = true }
    }

    func choose(_ ids: [String], app: AppModel) {
        source = .selection
        // Only identifiers from the app's centrally filtered picker; never import unverified image bytes.
        let visible = Set(app.cleanupMedia.filter { !$0.isVideo }.map(\.id))
        selection = photos.permittedIDs(Array(ids.prefix(200))).filter { visible.contains($0) }
        refreshPhotos(app: app)
    }

    func refreshPhotos(app: AppModel) {
        let safe = PhotoGamePhotos.offlineCandidates(app: app)
        let allowed = Set(safe.map(\.id))
        photos.restrictOfflineWindow(to: allowed)
        selection.removeAll { !allowed.contains($0) }
        let candidates: [String]
        switch source {
        case .random: candidates = safe.map(\.id).sorted()
        case .newest:
            candidates = safe.sorted {
                let a = $0.creationDate ?? .distantPast, b = $1.creationDate ?? .distantPast
                return a == b ? $0.id < $1.id : a > b
            }.map(\.id)
        case .favorites: candidates = safe.filter(\.isFavorite).map(\.id).sorted()
        case .selection: candidates = selection
        }
        sequence = PhotoBlocksPhotos(ids: candidates, shuffle: source == .random || source == .favorites, seed: seed)
        prepareWindow(app: app)
    }

    /// Called synchronously on vault changes, before any subsequent paint or late request can publish.
    func invalidatePhotos() {
        photos.clear(); selection = photos.permittedIDs(selection)
        sequence = .init(ids: [], shuffle: false, seed: seed)
    }
    func releaseResources() { pause(); attached = false; photos.clear() }
    func prepareWindow(app: AppModel) {
        guard attached else { return }
        photos.prepareOfflineWindow([sequence.id(at: game.level), sequence.id(at: game.level + 1)].compactMap { $0 },
                                    previews: app.previews, targetSize: targetSize)
    }
    func setDisplaySize(_ size: CGSize, scale: CGFloat, app: AppModel) {
        let factor = min(scale, 1280 / max(1, max(size.width, size.height)))
        let pixels = CGSize(width: max(1, (size.width * factor).rounded()), height: max(1, (size.height * factor).rounded()))
        guard abs(pixels.height - targetSize.height) > 100 || abs(pixels.width - targetSize.width) > 100 else { return }
        targetSize = pixels; photos.clear(); prepareWindow(app: app)
    }
}
