import Observation
import PhotoMaidCore

/// One app-owned record book, persisted atomically through the existing local key/value store.
@MainActor @Observable
final class PhotoGameScores {
    private(set) var records: PhotoGameRecords
    private(set) var saveFailed = false
    @ObservationIgnored private let save: @MainActor (PhotoGameRecords) throws -> Void

    init(records: PhotoGameRecords = .init(), save: @escaping @MainActor (PhotoGameRecords) throws -> Void = { _ in }) {
        self.records = records; self.save = save
    }

    @discardableResult func recordMemory(_ game: PhotoMemoryGame, seconds: Double,
                                        usesPhotos: Bool, manualMismatch: Bool) -> Bool {
        let improved = records.recordMemory(game, seconds: seconds, usesPhotos: usesPhotos, manualMismatch: manualMismatch)
        if improved { retrySave() }
        return improved
    }

    @discardableResult func recordSnake(_ game: PhotoSnakeGame, speed: PhotoSnakeSpeed, stepMode: Bool) -> Bool {
        let improved = records.recordSnake(game, speed: speed, stepMode: stepMode)
        if improved { retrySave() }
        return improved
    }

    func retrySave() {
        do { try save(records); saveFailed = false } catch { saveFailed = true }
    }
}
