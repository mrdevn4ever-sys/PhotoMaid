import PhotoMaidCore
import Testing
import UIKit
@testable import PhotoMaid

/// No real photos, downloads, permissions or changes to the photo library.
@MainActor struct PhotoMemoryModelTests {
    private func settle(_ model: PhotoMemoryModel) async throws {
        for _ in 0..<100 {
            if !model.isLoading { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isLoading, "Preview preparation did not finish")
    }

    @Test func failedSelectionKeepsThePreviousRound() async throws {
        let model = PhotoMemoryModel(canUsePhotos: { _ in true })
        model.startMotifs()
        model.reveal(0)
        let round = model.game
        let token = model.roundID
        model.startPhotos(["a", "b"]) { id in id == "a" ? UIImage() : nil }
        try await settle(model)
        #expect(model.game == round && model.roundID == token)
        #expect(model.photoIDs.isEmpty && model.images.isEmpty)
        #expect(model.error != nil)
    }

    @Test func lateCancelledLoadCannotReplaceANewerRound() async throws {
        let model = PhotoMemoryModel(canUsePhotos: { _ in true })
        var pending: CheckedContinuation<UIImage?, Never>?
        model.startPhotos(["a", "b"]) { _ in
            await withCheckedContinuation { pending = $0 }
        }
        for _ in 0..<100 {
            if pending != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let completion = try #require(pending)
        model.startMotifs()
        let token = model.roundID
        completion.resume(returning: UIImage())
        // Give the cancelled task a chance to receive its result.
        try await Task.sleep(for: .milliseconds(20))
        #expect(!model.isLoading && model.roundID == token)
        #expect(model.photoIDs.isEmpty && model.images.isEmpty)
        #expect(model.game?.pairCount == 6)
    }

    @Test func losingAccessDiscardsBothTheGameAndCachedPhotos() async throws {
        var allowed = true
        let model = PhotoMemoryModel(canUsePhotos: { _ in allowed })
        model.startPhotos(["a", "b"]) { _ in UIImage() }
        try await settle(model)
        #expect(model.photoIDs == ["a", "b"] && model.images.count == 2)
        allowed = false
        model.validatePhotos()
        #expect(model.game == nil && model.images.isEmpty && model.photoIDs.isEmpty)
        #expect(model.error != nil)
    }

    @Test func replayReusesSelectedPreviewsButResetsMoves() async throws {
        let model = PhotoMemoryModel(canUsePhotos: { _ in true })
        model.startPhotos(["a", "b", "a"]) { _ in UIImage() }
        try await settle(model)
        let round = model.roundID
        model.reveal(0)
        model.reveal(1)
        model.replay()
        #expect(model.roundID != round && model.photoIDs == ["a", "b"])
        #expect(model.images.count == 2 && model.game?.moves == 0)
        #expect(model.game?.faceUp.isEmpty == true)
    }

    @Test func randomRoundSkipsUnavailablePreviewsWithinItsSource() async throws {
        let model = PhotoMemoryModel(canUsePhotos: { _ in true })
        let ids = (0..<6).map { "local-\($0)" } + (0..<4).map { "cloud-\($0)" }
        model.startRandom(ids, pairCount: 6) { id in id.hasPrefix("local-") ? UIImage() : nil }
        try await settle(model)
        #expect(model.game?.pairCount == 6 && model.photoIDs.count == 6)
        #expect(model.photoIDs.allSatisfy { $0.hasPrefix("local-") })
        #expect(model.randomSource == .library)
    }

    @Test func insufficientSourceKeepsTheOldRoundWithoutLoadingOutsideIt() async throws {
        let model = PhotoMemoryModel(canUsePhotos: { _ in true })
        model.startMotifs()
        let previous = model.roundID
        var attempts = 0
        model.startRandom(["a", "b", "c"], pairCount: 6) { _ in attempts += 1; return UIImage() }
        try await settle(model)
        #expect(model.roundID == previous && attempts == 0 && model.error != nil)
    }

    @Test func largeRandomRoundKeepsExactlyTheRequestedNumberOfUniquePhotos() async throws {
        let model = PhotoMemoryModel(canUsePhotos: { _ in true })
        let ids = (0..<50).map(String.init)
        model.startRandom(ids, pairCount: 18) { _ in UIImage() }
        try await settle(model)
        #expect(model.game?.cards.count == 36 && model.images.count == 18)
        #expect(Set(model.photoIDs).count == 18 && Set(model.photoIDs).isSubset(of: Set(ids)))
        model.startPhotos(["a", "b"]) { _ in UIImage() }
        try await settle(model)
        #expect(model.randomSource == nil)
    }
}
