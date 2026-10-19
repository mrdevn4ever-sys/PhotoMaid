import Foundation
import PhotoMaidCore
import Testing
@testable import PhotoMaid

/// All tests use per-test temporary directories and injected paths. Never instantiate the shared vault.
struct VaultConcealmentTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VaultConcealmentTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func boundary(_ root: URL) -> VaultConcealment {
        VaultConcealment(url: root.appendingPathComponent("c.json"), indexURL: root.appendingPathComponent("index.bin"))
    }
    private func assertClosed(_ value: VaultConcealment) {
        #expect(value.isEmpty == false)
        #expect(value.analysisReady == false)
        #expect(value.isConcealed("photo") == true)
        #expect(value.isConcealed(VaultSnapshot.fileConcealmentKey("inode")) == true)
        #expect(value.visible(["photo", "other"]) { $0 }.isEmpty)
        #expect(value.visible(Set(["photo", "other"])).isEmpty)
        let result = value.withAnalysisAccess(["photo"]) { true }
        #expect(result == nil)
    }
    @Test func pristineInstallIsOpen() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let value = boundary(root)
        #expect(value.isEmpty)
        #expect(value.analysisReady)
        #expect(value.visible(["photo"]) { $0 } == ["photo"])
    }
    @Test func missingListWithExistingVaultIsClosed() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("index.bin"))
        let value = boundary(root)
        assertClosed(value)
        #expect(throws: (any Error).self) { try value.conceal(["photo"]) }
        #expect(throws: (any Error).self) { try value.reveal(["photo"]) }
    }
    @Test(arguments: [Data(), Data("{".utf8), Data("{\"version\":99,\"salt\":\"AA==\",\"digests\":[]}".utf8)])
    func invalidListNeverBecomesEmpty(_ data: Data) throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try data.write(to: root.appendingPathComponent("c.json"))
        let value = boundary(root)
        assertClosed(value)
        #expect(throws: (any Error).self) { try value.conceal(["new"]) }
        #expect(try Data(contentsOf: root.appendingPathComponent("c.json")) == data)
    }
    @Test func nonReadableFileTypeIsClosedAndRetryable() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("c.json")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let value = boundary(root)
        assertClosed(value)
        try FileManager.default.removeItem(at: target)
        let repaired = VaultConcealmentSet(salt: Data(repeating: 7, count: 32))
        try JSONEncoder().encode(repaired).write(to: target)
        #expect(value.analysisReady)
        #expect(value.isEmpty)
    }
    @Test func saltedIdentitiesSurviveRelaunchWithoutPlaintextIDs() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let value = boundary(root)
        let fileID = VaultSnapshot.fileConcealmentKey("file-resource")
        try value.conceal(["private-photo-identity", fileID])
        let next = boundary(root)
        #expect(next.isConcealed("private-photo-identity"))
        #expect(next.isConcealed(fileID))
        #expect(next.visible(["private-photo-identity", "public"]) { $0 } == ["public"])
        let data = try Data(contentsOf: root.appendingPathComponent("c.json"))
        #expect(String(decoding: data, as: UTF8.self).contains("private-photo-identity") == false)
    }
    @Test func failedIsolationWritePreventsSnapshotPublication() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let value = VaultConcealment(url: root.appendingPathComponent("c.json"), indexURL: root.appendingPathComponent("index.bin"),
                                    writer: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        var published = 0
        var indexPersisted = false
        #expect(throws: (any Error).self) {
            try VaultTransaction.update(&published, mutate: { $0 = 1 }, persist: { _ in
                try value.conceal(["photo"])
                indexPersisted = true
            })
        }
        #expect(published == 0)
        #expect(indexPersisted == false)
        assertClosed(value)
    }
    @Test func repairRequiresDurableWriteAndPreservesReadableHistoricalHashes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let value = boundary(root)
        try value.conceal(["historical"])
        try value.repair(authenticatedIDs: ["current"])
        let next = boundary(root)
        #expect(next.isConcealed("historical"))
        #expect(next.isConcealed("current"))
        try next.reveal(["current"])
        #expect(next.isConcealed("current") == false)
        #expect(next.isConcealed("historical"))
    }
    @Test func authenticatedRepairRestoresDamagedProjection() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("c.json"))
        let value = boundary(root)
        assertClosed(value)
        try value.repair(authenticatedIDs: ["photo", VaultSnapshot.fileConcealmentKey("inode")])
        #expect(value.analysisReady)
        #expect(value.isConcealed("photo"))
        #expect(value.isConcealed("public") == false)
    }

    @Test func failedRevealKeepsEveryPublicReadClosed() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try boundary(root).conceal(["photo"])
        let failing = VaultConcealment(url: root.appendingPathComponent("c.json"), indexURL: root.appendingPathComponent("index.bin"),
                                      writer: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        #expect(throws: (any Error).self) { try failing.reveal(["photo"]) }
        assertClosed(failing)
        #expect(boundary(root).isConcealed("photo"))
    }

    @Test func failedRepairDoesNotPublishAnEmptyProjection() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("truncated".utf8).write(to: root.appendingPathComponent("c.json"))
        let failing = VaultConcealment(url: root.appendingPathComponent("c.json"), indexURL: root.appendingPathComponent("index.bin"),
                                      writer: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        #expect(throws: (any Error).self) { try failing.repair(authenticatedIDs: ["photo"]) }
        assertClosed(failing)
    }

    @Test(arguments: [0, 1, 2]) func invalidDecodedSetIsClosed(_ variant: Int) throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        var set = VaultConcealmentSet(salt: Data(repeating: 3, count: variant == 0 ? 16 : 32),
                                      digests: variant == 2 ? [String(repeating: "z", count: 64)] : [])
        if variant == 1 { set.version = 99 }
        try JSONEncoder().encode(set).write(to: root.appendingPathComponent("c.json"))
        assertClosed(boundary(root))
    }
}
