import Observation
import CryptoKit
import Photos
import PhotoMaidCore
import UIKit
import XCTest
@testable import PhotoMaid

@MainActor
final class DuplicateScannerObservationTests: XCTestCase {
    func testConcurrentOriginalReadsCompleteWithoutBlockingTheExecutor() async throws {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw XCTSkip("Requires simulator-provisioned Photos access for \(Bundle.main.bundleIdentifier ?? "unknown host"); ci.yml grants it before unit tests")
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let holders = (0..<8).map { _ in PlaceholderBox() }
        // Only create synthetic simulator media. Never request a Photos deletion.
        try await PHPhotoLibrary.shared().performChanges {
            for holder in holders {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: bytes, options: nil)
                if let id = request.placeholderForCreatedAsset?.localIdentifier { holder.set(id) }
            }
        }
        let ids = holders.compactMap(\.value)
        XCTAssertEqual(ids.count, 8)
        let assets = PhotoLibraryService.phAssetBoxes(ids)
        let media = ids.compactMap { assets[$0].map { PhotoLibraryService.describe($0.value) } }
        XCTAssertEqual(media.count, 8)
        let reader = DuplicatePhotoReader(media: media, includeCloud: false, cloudChanged: { _ in })
        let completed = expectation(description: "Parallel PhotoKit streams must finish and keep the async executor available")
        let work = Task {
            let results = try await withThrowingTaskGroup(of: SizeRecord.self) { group in
                for asset in media {
                    group.addTask { try await reader.prepare(asset, prefetched: assets[asset.id], record: nil) }
                }
                var values: [SizeRecord] = []
                for try await value in group { values.append(value) }
                return values
            }
            completed.fulfill()
            return results
        }
        await fulfillment(of: [completed], timeout: 15)
        work.cancel() // Also stops a failed/hung attempt before leaving the test.
        let results = try await work.value
        XCTAssertEqual(results.count, 8)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        for result in results {
            XCTAssertEqual(result.state, .known)
            XCTAssertEqual(result.bytes, Int64(bytes.count))
            XCTAssertEqual(result.fullHash, digest)
            XCTAssertEqual(result.partialHash, digest)
        }
    }

    func testStartingScanInvalidatesTheObservedRunningState() async throws {
        let app = try AppModel(kv: nil, persistence: InMemoryLedgerPersistence(), qa: true)
        let scanner = DuplicateScanner()
        let changed = expectation(description: "The view observing isRunning must update when a scan starts")
        withObservationTracking {
            XCTAssertFalse(scanner.isRunning)
        } onChange: {
            changed.fulfill()
        }
        scanner.start(app: app)
        XCTAssertTrue(scanner.isRunning)
        await fulfillment(of: [changed], timeout: 1)
        scanner.cancel()
    }
}
