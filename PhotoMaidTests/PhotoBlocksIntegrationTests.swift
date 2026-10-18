import PhotoMaidCore
import Testing
import UIKit
@testable import PhotoMaid

/// Apple test-host tests. Syntax-checked on Linux, not represented as executed there.
@MainActor struct PhotoBlocksIntegrationTests {
    @MainActor private final class Policy {
        var allowed = true
        var shouldFail = true
        var saved: PhotoBlocksArchive?
    }
    private func wait(_ photos: PhotoGamePhotos) async throws {
        for _ in 0..<100 where photos.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!photos.isLoading)
    }

    @Test func windowRetainsOnlyCurrentAndNextAndReusesThePreparedNextPhoto() async throws {
        let photos = PhotoGamePhotos(canUsePhotos: { _ in true })
        photos.updateVisibility(["a", "b", "c", "d"])
        var requests: [String] = []
        let load: @MainActor (String, Bool) async -> UIImage? = { id, _ in requests.append(id); return UIImage() }
        photos.prepareBackgroundWindow(["a", "b", "c"], load: load)
        try await wait(photos)
        #expect(photos.photoIDs == ["a", "b"] && photos.images.count == 2)
        photos.prepareBackgroundWindow(["b", "c"], load: load)
        try await wait(photos)
        #expect(photos.photoIDs == ["b", "c"] && photos.images.count == 2)
        #expect(requests == ["a", "b", "c"] && photos.allowsCloud)
        photos.clear(); #expect(photos.images.isEmpty && photos.photoIDs.isEmpty)
    }

    @Test func exclusionWhileRequestIsPendingCannotPublishALateThumbnail() async throws {
        let policy = Policy()
        let photos = PhotoGamePhotos(canUsePhotos: { _ in policy.allowed })
        photos.updateVisibility(["a"])
        photos.prepareBackgroundWindow(["a"]) { _, _ in
            // Deliberately ignore cancellation, as a late PhotoKit callback could do.
            try? await Task.sleep(for: .milliseconds(30)); return UIImage()
        }
        await Task.yield()
        policy.allowed = false
        photos.restrictBackgroundWindow(to: [])
        try await Task.sleep(for: .milliseconds(50))
        #expect(photos.images.isEmpty && photos.photoIDs.isEmpty && !photos.isLoading)
    }

    @Test func limitedScopeMissingImagesAndPermissionRevocationFailClosed() async throws {
        let policy = Policy()
        let photos = PhotoGamePhotos(canUsePhotos: { _ in policy.allowed })
        photos.updateVisibility(["permitted", "missing"])
        var requested: [String] = []
        photos.prepareBackgroundWindow(["vault", "permitted", "missing"]) { id, _ in
            requested.append(id); return id == "missing" ? nil : UIImage()
        }
        try await wait(photos)
        #expect(requested == ["permitted", "missing"])
        #expect(photos.images.keys.sorted() == ["permitted"])
        policy.allowed = false; photos.restrictBackgroundWindow(to: [])
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
        let policy = Policy()
        let model = PhotoBlocksModel(archive: .init(best: 120)) {
            if policy.shouldFail { throw Failure.unavailable }; policy.saved = $0
        }
        model.checkpoint(); #expect(model.saveFailed)
        let board = model.game.board
        policy.shouldFail = false; model.checkpoint()
        #expect(!model.saveFailed && policy.saved?.best == 120 && policy.saved?.game?.board == board)
        model.invalidatePhotos()
        #expect(model.selection.isEmpty && model.sequence.order.isEmpty && model.photos.images.isEmpty)
    }

    @Test func tallFormCanRotateOnTheFloorUsingThePublicSerializedState() throws {
        let game = PhotoBlocksGame()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as! [String: Any]
        object["active"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            PhotoBlocksPiece(shape: .fern, rotation: 1, origin: .init(4, 15))))
        object["phase"] = "playing"
        var floor = try JSONDecoder().decode(PhotoBlocksGame.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(floor.isValidSnapshot)
        #expect(floor.rotate() == true)
        #expect(floor.active?.origin.y == 13 && floor.isValidSnapshot)
    }

    @Test func changingAlbumExclusionsClosesTheCentralGameSourceUntilTheyAreApplied() async throws {
        let app = try AppModel(kv: nil, persistence: InMemoryLedgerPersistence(), qa: true)
        app.reloadLibraryIfNeeded(force: true)
        for _ in 0..<250 where app.isLoadingLibrary { try await Task.sleep(for: .milliseconds(20)) }
        #expect(app.gamePhotoScopeReady)
        app.updateSettings { $0.excludedAlbums = ["QA-NOT-QUERIED-YET"] }
        // This runs before a queued PhotoKit load can finish, on the same main actor as settings changes.
        #expect(!app.gamePhotoScopeReady)
        #expect(PhotoGamePhotos.gameCandidates(app: app).isEmpty)
        #expect(app.blocks.photos.images.isEmpty && app.blocks.sequence.order.isEmpty)
    }

    @Test func cloudOnlyBackgroundsAndTheNextPhotoLoadByDefaultWithoutRepeatingDownloads() async throws {
        let photos = PhotoGamePhotos(canUsePhotos: { _ in true })
        photos.updateVisibility(["cloud-current", "cloud-next", "vault"])
        var downloads: [String] = []
        let load: @MainActor (String, Bool) async -> UIImage? = { id, network in
            guard network else { return nil } // Represents a photo with no local thumbnail.
            downloads.append(id); return UIImage()
        }
        photos.prepareBackgroundWindow(["cloud-current", "cloud-next"], load: load)
        try await wait(photos)
        #expect(photos.allowsCloud && photos.images.count == 2)
        photos.prepareBackgroundWindow(["cloud-next"], load: load)
        try await wait(photos)
        #expect(downloads == ["cloud-current", "cloud-next"] && photos.images.count == 1)
        photos.restrictBackgroundWindow(to: [])
        #expect(photos.images.isEmpty && photos.photoIDs.isEmpty)
    }

    @Test func unavailableCloudPhotoLeavesFallbackAndCanBeRetriedWithoutResettingTheRound() async throws {
        let photos = PhotoGamePhotos(canUsePhotos: { _ in true })
        photos.updateVisibility(["cloud"])
        photos.prepareBackgroundWindow(["cloud"]) { _, network in
            #expect(network); return nil // Offline / Photos download unavailable.
        }
        try await wait(photos)
        #expect(photos.images.isEmpty && !photos.isLoading)
        photos.prepareBackgroundWindow(["cloud"]) { _, network in network ? UIImage() : nil }
        try await wait(photos)
        #expect(photos.images.count == 1 && photos.allowsCloud)
    }

    @Test func unchangedVisibilityAndRepeatedRefreshDoNotCancelAnInFlightCloudDownload() async throws {
        let photos = PhotoGamePhotos(canUsePhotos: { _ in true })
        photos.restrictBackgroundWindow(to: ["cloud"])
        var requests = 0
        let load: @MainActor (String, Bool) async -> UIImage? = { _, _ in
            requests += 1
            try? await Task.sleep(for: .milliseconds(40))
            return Task.isCancelled ? nil : UIImage()
        }
        photos.prepareBackgroundWindow(["cloud"], load: load)
        await Task.yield()
        for _ in 0..<5 {
            photos.restrictBackgroundWindow(to: ["cloud"])
            photos.prepareBackgroundWindow(["cloud"], load: load)
        }
        try await wait(photos)
        #expect(requests == 1 && photos.images.count == 1)
    }
}
