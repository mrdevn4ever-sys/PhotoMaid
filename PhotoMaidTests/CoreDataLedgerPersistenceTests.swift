import XCTest
import PhotoMaidCore
@testable import PhotoMaid

/// Integration: DecisionLedger über den echten Core-Data-Store (In-Memory-SQLite-Beschreibung).
final class CoreDataLedgerPersistenceTests: XCTestCase {
    func testDecisionsSurviveReload() async throws {
        let store = try CoreDataStore(inMemory: true)
        let persistence = CoreDataLedgerPersistence(store: store)
        let ledger = try DecisionLedger(persistence: persistence)
        let item = ItemReference.photo("QA-ALLOWLIST-1")
        try await ledger.apply(DecisionCommand(item: item, expectedRevision: 0, action: .markForCleanup))
        let reloaded = try DecisionLedger(persistence: persistence)
        let record = await reloaded.record(for: item)
        XCTAssertEqual(record.disposition, .markedForCleanup)
        XCTAssertEqual(record.revision, 1)
        let canUndo = await reloaded.canUndo()
        XCTAssertTrue(canUndo)
        let events = await reloaded.events()
        XCTAssertEqual(events.count, 1)
    }

    func testJournalAndAllowancePersist() async throws {
        let store = try CoreDataStore(inMemory: true)
        let persistence = CoreDataLedgerPersistence(store: store)
        let ledger = try DecisionLedger(persistence: persistence)
        let items = (0..<3).map { ItemReference.photo("QA-ALLOWLIST-\($0)") }
        for i in items { try await ledger.apply(DecisionCommand(item: i, expectedRevision: 0, action: .markForCleanup)) }
        let intent = try await ledger.prepareCleanup(items, kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(intent.id)
        // Prozessabbruch simulieren: neuer Ledger auf demselben Store.
        let relaunched = try DecisionLedger(persistence: persistence)
        let open = try await relaunched.recoverAfterLaunch()
        XCTAssertEqual(open.map(\.state), [.reconciliationRequired])
        let allowance = await relaunched.allowance(limit: 15)
        XCTAssertEqual(allowance.available, 12)
    }

    func testKeyValueRoundTrip() throws {
        let store = try CoreDataStore(inMemory: true)
        var settings = AppSettingsData()
        settings.largeFileThresholdMB = 250
        try store.setValue(settings, forKey: "test.settings")
        XCTAssertEqual(store.value(AppSettingsData.self, forKey: "test.settings")?.largeFileThresholdMB, 250)
    }

    func testSafeURLRejectsTraversalAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).txt")
        try Data("y".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.txt"), withDestinationURL: outside)

        XCTAssertNotNil(FileScanner.safeURL(root: root, relativePath: "a.txt"))
        XCTAssertNil(FileScanner.safeURL(root: root, relativePath: "../\(outside.lastPathComponent)"))
        XCTAssertNil(FileScanner.safeURL(root: root, relativePath: "link.txt"))
        XCTAssertNil(FileScanner.safeURL(root: root, relativePath: "/etc/hosts"))
    }

    func testScannerSkipsSymlinksAndReportsUnknownNever() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("empty.bin"))
        try Data(repeating: 1, count: 2048).write(to: root.appendingPathComponent("two.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let entries = try FileScanner.scan(root: root, sourceID: ConnectedSourceID())
        XCTAssertEqual(Set(entries.map(\.name)), ["empty.bin", "two.bin"])
        XCTAssertEqual(entries.first { $0.name == "empty.bin" }?.size, .known(0))
    }
}
