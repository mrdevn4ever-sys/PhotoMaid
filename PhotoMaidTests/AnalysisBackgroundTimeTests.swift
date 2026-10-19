import UIKit
import XCTest
@testable import PhotoMaid

@MainActor final class AnalysisBackgroundTimeTests: XCTestCase {
    func testRepeatedRequestsOwnOnlyOneBalancedLease() {
        var begins = 0
        var ended: [UIBackgroundTaskIdentifier] = []
        let lease = AnalysisBackgroundTime(begin: { _ in begins += 1; return .init(rawValue: 7) }, end: { ended.append($0) })
        XCTAssertTrue(lease.begin {})
        XCTAssertTrue(lease.begin {})
        XCTAssertEqual(begins, 1)
        lease.end(); lease.end()
        XCTAssertEqual(ended, [.init(rawValue: 7)])
        XCTAssertFalse(lease.isActive)
    }

    func testExpirationEndsTimeAndRequestsCheckpointOnce() async throws {
        var expire: (@Sendable () -> Void)?
        var ended = 0, checkpoints = 0
        let lease = AnalysisBackgroundTime(begin: { expire = $0; return .init(rawValue: 8) }, end: { _ in ended += 1 })
        lease.begin { checkpoints += 1 }
        expire?(); expire?()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(checkpoints, 1)
        XCTAssertFalse(lease.isActive)
    }

    func testStaleExpirationCannotStopANewerBackgroundSession() async throws {
        var callbacks: [@Sendable () -> Void] = []
        var ended = 0, checkpoints = 0
        let lease = AnalysisBackgroundTime(begin: { callback in
            callbacks.append(callback); return .init(rawValue: 9)
        }, end: { _ in ended += 1 })
        lease.begin { checkpoints += 1 }
        lease.end() // App returned to the foreground.
        lease.begin { checkpoints += 1 }
        callbacks[0]()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(lease.isActive)
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(checkpoints, 0)
        callbacks[1]()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(ended, 2)
        XCTAssertEqual(checkpoints, 1)
    }

    func testRefusedBackgroundTimeDoesNotPretendToBeRunning() {
        var ended = 0
        let lease = AnalysisBackgroundTime(begin: { _ in .invalid }, end: { _ in ended += 1 })
        XCTAssertFalse(lease.begin { XCTFail("No expiration without a granted lease") })
        lease.end()
        XCTAssertFalse(lease.isActive)
        XCTAssertEqual(ended, 0)
    }

    func testMigrationOnlyCancelsOwnOldAnalysisRequests() {
        let id = UUID().uuidString
        XCTAssertTrue(AnalysisBackgroundTime.isLegacyAnalysisRequest("com.example.app.analysis." + id, bundleID: "com.example.app"))
        for other in ["com.example.app.export." + id, "com.other.app.analysis." + id,
                      "com.example.app.analysis2." + id, "com.example.app.analysis.scheduled", "analysis." + id] {
            XCTAssertFalse(AnalysisBackgroundTime.isLegacyAnalysisRequest(other, bundleID: "com.example.app"))
        }
    }
}
