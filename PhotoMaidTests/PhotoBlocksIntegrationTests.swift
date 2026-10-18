import PhotoMaidCore
import Testing
import UIKit
@testable import PhotoMaid

/// Apple test-host tests. Syntax-checked on Linux, not represented as executed there.
@MainActor struct PhotoBlocksIntegrationTests {
    private func wait(_ photos: PhotoGamePhotos) async throws {
        for _ in 0..<100 where photos.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!photos.isLoading)
    }

    @Test func windowRetainsOnlyCurrentAndNextAndReusesThePreparedNextPhoto() async throws {
        let photos = PhotoGamePhotos(canUsePhotos: { _ in true })
        photos.updateVisibility(["a", "b", "c", "d"])
        var requests: [String] = []
        let load: @MainActor (String) async -> UIImage? = { id in requests.append(id); return UIImage() }
        photos.prepareOfflineWindow(["a", "b", "c"], load: load)
        try await wait(photos)
        #expect(photos.photoIDs == ["a", "b"] && photos.images.count == 2)
        photos.prepareOfflineWindow(["b", "c"], load: load)
        try await wait(photos)
        #expect(photos.photoIDs == ["b", "c"] && photos.images.count == 2)
        #expect(requests == ["a", "b", "c"] && !photos.allowsCloud)
        photos.clear(); #expect(photos.images.isEmpty && photos.photoIDs.isEmpty)
    }

    @Test func exclusionWhileRequestIsPendingCannotPublishALateThumbnail() async throws {
        var protected = false
        let photos = PhotoGamePhotos(canUsePhotos: { _ in !protected })
        photos.updateVisibility(["a"])
        photos.prepareOfflineWindow(["a"]) { _ in
            // Deliberately ignore cancellation, as a late PhotoKit callback could do.
            try? await Task.sleep(for: .milliseconds(30)); return UIImage()
        }
        await Task.yield()
        protected = true
        photos.restrictOfflineWindow(to: [])
        try await Task.sleep(for: .milliseconds(50))
        #expect(photos.images.isEmpty && photos.photoIDs.isEmpty && !photos.isLoading)
    }

    @Test func limitedScopeMissingImagesAndPermissionRevocationFailClosed() async throws {
        var readable = true
        let photos = PhotoGamePhotos(canUsePhotos: { _ in readable })
        photos.updateVisibility(["permitted", "missing"])
        var requested: [String] = []
        photos.prepareOfflineWindow(["vault", "permitted", "missing"]) { id in
            requested.append(id); return id == "missing" ? nil : UIImage()
        }
        try await wait(photos)
        #expect(requested == ["permitted", "missing"])
        #expect(photos.images.keys.sorted() == ["permitted"])
        readable = false; photos.restrictOfflineWindow(to: [])
        #expect(photos.images.isEmpty && photos.photoIDs.isEmpty)
    }

    @Test func numericalArchivePersistsBesideExistingRecordsAndRestoresPaused() throws {
        let core = try CoreDataStore(inMemory: true)
        let kv = KeyValueStore(core: core)
        let records = PhotoGameRecords()
        try kv.set(StoreKeys.gameRecords, records)
        var game = PhotoBlocksGame(seed: 44); game.start(); game.hardDrop()
        let archive = PhotoBlocksArchive(game: game, best: game.score, discoveredImages: 0, photoSeed: 44, photoSource: .selection)
        try kv.set(StoreKeys.blocksArchive, archive)
        let model = PhotoBlocksModel(archive: kv.get(StoreKeys.blocksArchive)) { try kv.set(StoreKeys.blocksArchive, $0) }
        #expect(model.game.isPaused && model.game.board == game.board && model.best == game.score)
        #expect(kv.get(StoreKeys.gameRecords) == records)
        #expect(model.photos.images.isEmpty && model.currentPhotoID == nil)
        #expect(model.source == .selection)
    }

    @Test func saveFailureKeepsStateAndRetryDoesNotResetBestOrBoard() {
        enum Failure: Error { case unavailable }
        var fail = true, saved: PhotoBlocksArchive?
        let model = PhotoBlocksModel(archive: .init(best: 120)) {
            if fail { throw Failure.unavailable }; saved = $0
        }
        model.checkpoint(); #expect(model.saveFailed)
        let board = model.game.board
        fail = false; model.checkpoint()
        #expect(!model.saveFailed && saved?.best == 120 && saved?.game?.board == board)
        model.invalidatePhotos()
        #expect(model.selection.isEmpty && model.sequence.order.isEmpty && model.photos.images.isEmpty)
    }
}
