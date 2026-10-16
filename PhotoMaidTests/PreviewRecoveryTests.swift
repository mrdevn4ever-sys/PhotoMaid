import AVFoundation
import Foundation
import Photos
import Testing
import UIKit
@testable import PhotoMaid

@MainActor struct PreviewRecoveryTests {
    @Test func missingCloudFlagStillTriesNetworkAndRecovers() async {
        let full = UIImage()
        let fixture = ImageCallbacks([[.init(nil, nil)], [.init(full, nil)]])
        let updates = await collect(fixture)
        #expect(fixture.networks == [false, true])
        #expect(updates.contains { if case .image(let image, true) = $0 { image === full } else { false } })
        #expect(!updates.contains { if case .failed = $0 { true } else { false } })
    }

    @Test func degradedPosterSurvivesUntilNetworkQualityArrives() async {
        let small = UIImage(), full = UIImage()
        let fixture = ImageCallbacks([[.init(small, [PHImageResultIsDegradedKey: true]), .init(nil, nil)], [.init(full, nil)]])
        let updates = await collect(fixture)
        let images: [(UIImage, Bool)] = updates.compactMap {
            if case .image(let image, let final) = $0 { (image, final) } else { nil }
        }
        #expect(images.count == 2)
        #expect(images.first?.0 === small && images.first?.1 == false)
        #expect(images.last?.0 === full && images.last?.1 == true)
    }

    @Test func prefetchDoesNotDownloadButPromotionCanRecover() async {
        let local = ImageCallbacks([[.init(nil, [PHImageResultIsInCloudKey: true])]])
        let before = await collect(local, network: false)
        #expect(local.networks == [false])
        #expect(before.contains { if case .failed(inCloud: true) = $0 { true } else { false } })
        let visible = ImageCallbacks([[.init(nil, nil)], [.init(UIImage(), nil)]])
        let after = await collect(visible)
        #expect(visible.networks == [false, true])
        #expect(after.contains { if case .image(_, true) = $0 { true } else { false } })
    }

    @Test func localFinalImageDoesNotStartUnnecessaryDownload() async {
        let fixture = ImageCallbacks([[.init(UIImage(), nil)]])
        _ = await collect(fixture)
        #expect(fixture.networks == [false])
    }

    @Test func networkErrorWithoutCloudFlagIsReportedAsCloudFailure() async {
        let fixture = ImageCallbacks([[.init(nil, nil)], [.init(nil, [PHImageErrorKey: NSError(domain: NSURLErrorDomain,
                                                                                         code: NSURLErrorNotConnectedToInternet)])]])
        let updates = await collect(fixture)
        #expect(updates.contains { if case .failed(inCloud: true) = $0 { true } else { false } })
    }

    @Test func cancellationBeforeRegistrationCancelsTheLateIDAndIgnoresResults() async {
        let fixture = PendingResult()
        let request = PhotoRequest<Int>(cancelledValue: -1, cancel: { fixture.cancel($0) })
        request.cancel()
        let result = await withCheckedContinuation { continuation in
            #expect(!request.install(continuation))
        }
        request.register(19)
        request.finish(8)
        #expect(result == -1 && fixture.cancelled == [19])
    }

    @Test func cancellingAnUnresponsivePhotoKitRequestDoesNotWaitForItsCallback() async {
        let fixture = PendingResult()
        let task = Task {
            await PhotoRequest<Int>.perform(cancelledValue: -1, cancel: { fixture.cancel($0) }) { result in
                fixture.install(result)
                return 21
            }
        }
        for _ in 0..<100 where !fixture.started { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(fixture.started)
        task.cancel()
        #expect(await task.value == -1)
        fixture.complete(7); fixture.complete(9)
        #expect(fixture.cancelled == [21])
    }

    @Test func oldVideoRequestCannotReplaceNextVideoOrRevisitedAsset() {
        let player = FeedPlayer()
        let old = player.beginLoading()
        player.stop()
        let current = player.beginLoading()
        let item = AVPlayerItem(asset: AVMutableComposition())
        #expect(!player.load(itemID: "old", item: item, autoplay: false, duration: 2, requestID: old))
        #expect(player.load(itemID: "current", item: item, autoplay: false, duration: 2, requestID: current))
        #expect(!player.load(itemID: "old", item: item, autoplay: false, duration: 2, requestID: old))
        #expect(player.itemID == "current")
        player.stop()
        #expect(!player.load(itemID: "current", item: item, autoplay: false, duration: 2, requestID: current))
    }

    private func collect(_ fixture: ImageCallbacks, network: Bool = true) async -> [PreviewUpdate] {
        var updates: [PreviewUpdate] = []
        for await update in PreviewPipeline.requestProgressiveImage(allowNetwork: network,
            request: { fixture.request($0, result: $1) }, cancel: { fixture.cancel($0) }) { updates.append(update) }
        return updates
    }
}

private final class ImageCallbacks: @unchecked Sendable {
    struct Response {
        let image: UIImage?
        let info: [AnyHashable: Any]?
        init(_ image: UIImage?, _ info: [AnyHashable: Any]?) { self.image = image; self.info = info }
    }
    private let lock = NSLock()
    private let responses: [[Response]]
    private var requested: [Bool] = []
    private var cancelled: [PHImageRequestID] = []
    init(_ responses: [[Response]]) { self.responses = responses }
    var networks: [Bool] { lock.withLock { requested } }
    func request(_ options: PHImageRequestOptions,
                 result: @escaping @Sendable (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        let (id, values) = lock.withLock {
            let index = requested.count
            requested.append(options.isNetworkAccessAllowed)
            return (PHImageRequestID(index + 1), index < responses.count ? responses[index] : [])
        }
        for value in values { result(value.image, value.info) }
        return id
    }
    func cancel(_ id: PHImageRequestID) { lock.withLock { cancelled.append(id) } }
}

private final class PendingResult: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (Int) -> Void)?
    private var ids: [PHImageRequestID] = []
    var cancelled: [PHImageRequestID] { lock.withLock { ids } }
    var started: Bool { lock.withLock { callback != nil } }
    func install(_ callback: @escaping @Sendable (Int) -> Void) { lock.withLock { self.callback = callback } }
    func cancel(_ id: PHImageRequestID) { lock.withLock { ids.append(id) } }
    func complete(_ value: Int) { lock.withLock { callback }?(value) }
}
