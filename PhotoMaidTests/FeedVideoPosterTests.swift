import AVFoundation
import PhotoMaidCore
import Testing
import UIKit
@testable import PhotoMaid

@MainActor struct FeedVideoPosterTests {
    @Test func preparedPosterRemainsReadyDuringPromotionResizeAndPlaybackLoading() async throws {
        let (app, model, items) = try fixture()
        let poster = UIImage()
        model.previewResult(items[0].reference, result: .poster(UIImage()))
        model.previewResult(items[1].reference, result: .poster(poster))
        await decide(.keep, in: model)
        #expect(model.current == items[1].reference && app.player.itemID == nil)
        model.previewLoading(items[1].reference, hasVisibleContent: false)
        model.updateViewport(CGSize(width: 402, height: 580), scale: 3)
        model.refreshWindow()
        #expect(model.previews[items[1].reference] == .ready)
        #expect(model.session.isPreviewReady(items[1].reference))
        #expect(model.posters[items[1].reference] === poster)
        // A failed playback/quality request cannot revoke the actual retained image.
        model.previewResult(items[1].reference, result: .unavailable)
        await decide(.markForCleanup, in: model)
        #expect(model.current == items[2].reference)
        let state = await app.ledger.snapshotState()
        #expect(state.records.count == 2 && state.events.count == 2)
    }

    @Test func consecutiveVideosCanBeKeptTrashedAndDeferredWithoutPreparingAPlayer() async throws {
        let (app, model, items) = try fixture()
        for item in items.prefix(3) { model.previewResult(item.reference, result: .poster(UIImage())) }
        await decide(.keep, in: model)
        await decide(.markForCleanup, in: model)
        await decide(.later, in: model)
        #expect(model.current == items[3].reference && app.player.itemID == nil)
        let state = await app.ledger.snapshotState()
        #expect(state.records.count == 3 && state.events.count == 3)
        // No decision for the unseen fourth card.
        model.perform(.keep)
        #expect(!model.isCommitting && model.current == items[3].reference)
    }

    @Test func aDiscardedVideoFrameDoesNotAuthorizeAnUnseenRevisitedVideo() async throws {
        let (app, model, items) = try fixture()
        let ref = items[0].reference
        model.previewResult(ref, result: .videoFrame)
        #expect(!model.session.isPreviewReady(ref))
        app.player.load(itemID: ref.localIdentifier, item: AVPlayerItem(asset: AVMutableComposition()),
                        autoplay: false, duration: 2)
        model.previewResult(ref, result: .videoFrame)
        #expect(model.session.isPreviewReady(ref) && model.posters[ref] == nil)
        app.player.stop()
        model.refreshWindow()
        model.previewResult(ref, result: .videoFrame) // Late callback from the discarded player.
        model.perform(.keep)
        #expect(model.previews[ref] == .loading && !model.isCommitting && model.current == ref)
        let state = await app.ledger.snapshotState()
        #expect(state.records.isEmpty)
    }

    @Test func posterStorageIsBoundedAndEvictedCallbacksCannotRestoreOldImages() async throws {
        let (_, model, items) = try fixture(count: 7)
        let old = items[0].reference
        for _ in 0..<5 {
            for ref in model.windowItems() { model.previewResult(ref, result: .poster(UIImage())) }
            await decide(.keep, in: model)
            #expect(model.posters.count <= 4)
        }
        model.previewResult(old, result: .poster(UIImage()))
        #expect(model.posters[old] == nil && model.previews[old] == nil)
    }

    private func decide(_ intent: FeedIntent, in model: FeedViewModel) async {
        model.perform(intent)
        for _ in 0..<200 where model.isCommitting { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isCommitting)
    }

    private func fixture(count: Int = 4) throws -> (AppModel, FeedViewModel, [MediaAsset]) {
        let app = try AppModel(kv: nil, persistence: InMemoryLedgerPersistence(), qa: true)
        let items = (0..<count).map { index in
            MediaAsset(id: "QA-POSTER-\(index)", kind: .video, creationDate: nil, modificationDate: nil,
                       duration: 2, pixelWidth: 320, pixelHeight: 400, isLivePhoto: false,
                       isFavorite: false, canDelete: false, canEditProperties: false,
                       latitude: nil, longitude: nil, subtypes: 0, burstIdentifier: nil)
        }
        return (app, FeedViewModel(testAssets: items, app: app), items)
    }
}
