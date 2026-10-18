import Foundation
import Testing
@testable import PhotoMaidCore

struct PhotoBlocksPhotosTests {
    @Test func photoOrderNeverRepeatsUntilExhaustedAndCyclesDeterministically() {
        let photos = PhotoBlocksPhotos(ids: ["a", "b", "c", "a", ""], shuffle: true, seed: 42)
        #expect(photos.order.count == 3)
        #expect(Set((1...3).compactMap { photos.id(at: $0) }).count == 3)
        #expect(photos.id(at: 4) == photos.id(at: 1))
        #expect(photos == PhotoBlocksPhotos(ids: ["a", "b", "c"], shuffle: true, seed: 42))
        #expect(PhotoBlocksPhotos(ids: ["only"], shuffle: true, seed: 42).id(at: 21) == "only")
        #expect(PhotoBlocksPhotos(ids: [], shuffle: true, seed: 42).id(at: 1) == nil)
        let newest = PhotoBlocksPhotos(ids: ["new", "old"], shuffle: false, seed: 100)
        #expect(newest.id(at: 1) == "new" && newest.id(at: 2) == "old")
    }
    @Test func limitedAccessVaultMovesAndRevocationRemoveEveryExcludedIdentifier() {
        var photos = PhotoBlocksPhotos(ids: ["a", "vault", "b", "hidden"], shuffle: false, seed: 1)
        photos.restrict(to: ["a", "b"])
        #expect(photos.order == ["a", "b"])
        for level in 1...100 { #expect(["a", "b"].contains(photos.id(at: level)!)) }
        photos.restrict(to: ["b"])
        #expect(photos.id(at: 20) == "b")
        photos.restrict(to: [])
        #expect(photos.id(at: 1) == nil && photos.order.isEmpty)
    }
    @Test func stripCoordinatesAreFixedClampedAndIndependentOfBoardRows() {
        #expect(PhotoBlocksPhotos.revealedHeight(strips: 1) == 0.1)
        #expect(PhotoBlocksPhotos.revealedHeight(strips: 3) == 0.3)
        #expect(PhotoBlocksPhotos.revealedHeight(strips: 10) == 1)
        #expect(PhotoBlocksPhotos.revealedHeight(strips: 99) == 1)
        #expect(PhotoBlocksPhotos.revealedHeight(strips: -3) == 0)
    }
    @Test func archiveRetainsPhotoScopeAndSeedWithoutPersistingIdentifiers() throws {
        let archive = PhotoBlocksArchive(best: 50, photoSeed: 72, photoSource: .selection)
        let data = try JSONEncoder().encode(archive)
        let restored = try JSONDecoder().decode(PhotoBlocksArchive.self, from: data)
        #expect(restored == archive)
        #expect(restored.photoSource == .selection && restored.photoSeed == 72)
        let old = try JSONDecoder().decode(PhotoBlocksArchive.self, from: Data("{\"best\":50}".utf8))
        #expect(old.best == 50 && old.photoSeed == 1 && old.photoSource == .random)
        let pool = ["a", "b", "c", "d"]
        #expect(PhotoBlocksPhotos(ids: pool, shuffle: true, seed: restored.photoSeed) ==
                PhotoBlocksPhotos(ids: pool, shuffle: true, seed: archive.photoSeed))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("photoID") && !text.contains("thumbnail"))
    }
    @Test func changedAlbumFiltersCannotReuseAnOlderSnapshot() {
        #expect(PhotoBlocksPhotos.scopeReady(loaded: false, requestedHidden: [], appliedHidden: [],
                                            requestedExcluded: [], appliedExcluded: []) == false)
        #expect(PhotoBlocksPhotos.scopeReady(loaded: true, requestedHidden: ["hidden"], appliedHidden: [],
                                            requestedExcluded: [], appliedExcluded: []) == false)
        #expect(PhotoBlocksPhotos.scopeReady(loaded: true, requestedHidden: [], appliedHidden: [],
                                            requestedExcluded: ["private"], appliedExcluded: []) == false)
        #expect(PhotoBlocksPhotos.scopeReady(loaded: true, requestedHidden: ["hidden"], appliedHidden: ["hidden"],
                                            requestedExcluded: ["private"], appliedExcluded: ["private"]) == true)
    }
}
