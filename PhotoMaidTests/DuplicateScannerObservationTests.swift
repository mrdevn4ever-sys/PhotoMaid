import Observation
import PhotoMaidCore
import XCTest
@testable import PhotoMaid

@MainActor
final class DuplicateScannerObservationTests: XCTestCase {
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
