import Foundation
import Testing
@testable import PhotoMaidCore

/// Isolated policy/helper tests only. They are not integration tests of the
/// actual vault, PhotoKit, Keychain, CryptoKit, UI or iOS file protection.
@Suite("Vault security primitives; not app integration")
struct VaultSecurityTests {
    @Test func visibilityIsFailClosedUntilReady() {
        for token in ["private", "ordinary", "new"] {
            #expect(!VaultVisibilityPolicy.allows(token, ready: false, denied: []))
        }
        #expect(!VaultVisibilityPolicy.allows("private", ready: true, denied: ["private"]))
        #expect(VaultVisibilityPolicy.allows("ordinary", ready: true, denied: ["private"]))
    }
    @Test func mixedCompositesAndDescendantsArePrivate() {
        let parents: [String: Set<String>] = [
            "edit": ["original"], "collage": ["edit", "ordinary"],
            "movie": ["collage"], "unrelated": ["ordinary"]
        ]
        #expect(VaultVisibilityPolicy.closure(roots: ["original"], parentsByOutput: parents)
                == ["original", "edit", "collage", "movie"])
    }
    @Test func cyclesTerminateWithoutTaintingUnrelatedNodes() {
        let graph: [String: Set<String>] = ["b": ["a"], "c": ["b"], "a": ["c"], "z": ["z"]]
        #expect(VaultVisibilityPolicy.closure(roots: ["a"], parentsByOutput: graph) == ["a", "b", "c"])
    }
    @Test func policyHasNoHiddenPreviousRootState() {
        let graph: [String: Set<String>] = ["a-edit": ["a"], "b-edit": ["b"]]
        #expect(VaultVisibilityPolicy.closure(roots: ["a"], parentsByOutput: graph) == ["a", "a-edit"])
        #expect(VaultVisibilityPolicy.closure(roots: ["b"], parentsByOutput: graph) == ["b", "b-edit"])
        #expect(VaultVisibilityPolicy.closure(roots: [], parentsByOutput: graph).isEmpty)
    }
    @Test func leaseCannotBeIssuedBeforeActivation() {
        let fence = VaultSessionFence()
        #expect(throws: VaultSessionError.expired) { try fence.lease() }
    }
    @Test func lockAndNewSessionDoNotReviveOldLease() throws {
        let fence = VaultSessionFence()
        let original = fence.activate()
        #expect(original.isValid)
        #expect(try fence.lease().isValid)
        fence.revoke()
        #expect(!original.isValid)
        #expect(throws: VaultSessionError.expired) { try original.requireValid() }
        let replacement = fence.activate()
        #expect(replacement.isValid)
        #expect(!original.isValid)
    }
    @Test func revokedLeaseDoesNotExecuteSink() {
        let fence = VaultSessionFence()
        let lease = fence.activate()
        fence.revoke()
        var wrote = false
        #expect(throws: VaultSessionError.expired) { try lease.withValidity { wrote = true } }
        #expect(!wrote)
    }
    @Test func activeLeaseExecutesSink() throws {
        let lease = VaultSessionFence().activate()
        #expect(try lease.withValidity { 42 } == 42)
    }
    @Test func failedPersistencePreservesValueSnapshot() {
        enum DiskError: Error { case full }
        var index = ["first", "second"]
        #expect(throws: DiskError.self) {
            try VaultTransaction.update(&index, mutate: { $0.removeAll() }, persist: { _ in throw DiskError.full })
        }
        #expect(index == ["first", "second"])
    }
    @Test func failedMutationDoesNotReachPersistence() {
        enum MutationError: Error { case invalid }
        var index = ["first"]
        var persisted = false
        #expect(throws: MutationError.self) {
            try VaultTransaction.update(&index, mutate: { $0.append("second"); throw MutationError.invalid },
                                        persist: { _ in persisted = true })
        }
        #expect(index == ["first"])
        #expect(!persisted)
    }
    @Test func successfulValueMutationPublishesSavedValue() throws {
        var memory = ["a"]
        var disk: [String] = []
        try VaultTransaction.update(&memory, mutate: { $0.append("b") }, persist: { disk = $0 })
        #expect(memory == ["a", "b"])
        #expect(memory == disk)
    }
    @Test(arguments: ["", ".", "..", "../IMG.jpg", "/tmp/foo", "a/b", "a\\b", "x\0y", String(repeating: "a", count: 256)])
    func rejectsUnsafePathComponents(_ name: String) { #expect(!VaultPathRules.isComponent(name)) }
    @Test func safeOpaqueNamesAndSanitizedExtensions() {
        let id = UUID()
        #expect(VaultPathRules.isComponent(id.uuidString))
        #expect(VaultPathRules.temporaryName(id: id, fileExtension: "../MOV") == id.uuidString + ".mov")
        #expect(VaultPathRules.temporaryName(id: id, fileExtension: nil) == id.uuidString)
        #expect(VaultPathRules.temporaryName(id: id, fileExtension: String(repeating: "x", count: 13)) == id.uuidString)
    }
}
