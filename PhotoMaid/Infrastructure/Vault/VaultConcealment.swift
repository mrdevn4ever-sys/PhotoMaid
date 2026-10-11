import CryptoKit
import Foundation
import PhotoMaidCore

extension Notification.Name {
    static let analysisVisibilityChanged = Notification.Name("PhotoMaid.analysisVisibilityChanged")
}

/// The coverage marker describes a validated snapshot, not an authentication credential.
/// A new/replaced snapshot invalidates it until the unlocked vault has been checked again.
private struct AnalysisVaultCoverage: Codable, Equatable {
    let modified: Date
    let bytes: Int64
    let complete: Bool
    static func stamp(complete: Bool) throws -> AnalysisVaultCoverage {
        let url = VaultStore.root.appendingPathComponent("index.bin")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attributes[.modificationDate] as? Date, let size = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return AnalysisVaultCoverage(modified: date, bytes: size.int64Value, complete: complete)
    }
}
private struct AnalysisConcealmentMetadata: Codable { var analysisCoverage: AnalysisVaultCoverage? }

/// Persistent salted exclusion identifiers. Unknown/unreadable state is never treated as public.
/// The same lock serializes admitting analysis results and purging them during a vault import.
final class VaultConcealment: @unchecked Sendable {
    static let shared = VaultConcealment()
    private let lock = NSLock()
    private var cached: VaultConcealmentSet?
    private var coverage: AnalysisVaultCoverage?
    private var loaded = false
    static var url: URL { VaultStore.root.appendingPathComponent("c.json") }

    static func digest(_ salt: Data, _ id: String) -> String {
        var hasher = SHA256(); hasher.update(data: salt); hasher.update(data: Data(id.utf8))
        return Array(hasher.finalize()).hexString
    }
    private var hasVault: Bool {
        FileManager.default.fileExists(atPath: VaultStore.root.appendingPathComponent("index.bin").path)
    }
    private func known(_ set: VaultConcealmentSet?) -> Bool { loaded && (set != nil || !hasVault) }
    private func analysisKnown(_ set: VaultConcealmentSet?) -> Bool {
        guard known(set) else { return false }
        guard hasVault else { return true }
        guard let coverage, coverage.complete, let current = try? AnalysisVaultCoverage.stamp(complete: true) else { return false }
        return current == coverage
    }
    var analysisReady: Bool { lock.withLock { analysisKnown(current()) } }
    var isEmpty: Bool { lock.withLock { let s = current(); return known(s) && (s?.isEmpty ?? true) } }
    func isConcealed(_ id: String) -> Bool {
        lock.withLock { let s = current(); return !known(s) || (s?.contains(id, digest: Self.digest) ?? false) }
    }
    func visible<T>(_ items: [T], id: (T) -> String) -> [T] {
        lock.withLock {
            let s = current(); guard known(s) else { return [] }
            guard let s, !s.isEmpty else { return items }
            return items.filter { !s.contains(id($0), digest: Self.digest) }
        }
    }
    func visible(_ ids: Set<String>) -> Set<String> {
        lock.withLock {
            let s = current(); guard known(s) else { return [] }
            guard let s, !s.isEmpty else { return ids }
            return ids.filter { !s.contains($0, digest: Self.digest) }
        }
    }
    /// The body must not reenter this object. nil is a privacy veto, never a negative analysis result.
    func withAnalysisAccess<T>(_ ids: [String], _ body: () throws -> T) rethrows -> T? {
        try lock.withLock {
            let s = current()
            guard analysisKnown(s), ids.allSatisfy({ !(s?.contains($0, digest: Self.digest) ?? false) }) else { return nil }
            return try body()
        }
    }
    /// Invoked only with the currently unlocked, validated snapshot on MainActor. Legacy items whose
    /// original identifier was lost keep analysis blocked; no guessed rematching or photo deletion.
    @MainActor
    func confirmAnalysisCoverage(_ snapshot: VaultSnapshot, provenanceComplete: Bool) throws {
        try snapshot.validate()
        let all = snapshot.allMedia
        let complete = provenanceComplete && all.count == snapshot.mediaSlotsUsed && all.allSatisfy {
            !($0.originalID ?? $0.sourceID ?? "").isEmpty
        }
        let stamp = try AnalysisVaultCoverage.stamp(complete: complete)
        try lock.withLock {
            let existing = current()
            guard loaded else { throw CocoaError(.fileReadNoPermission) }
            var set = try existing ?? VaultConcealmentSet(salt: Data(VaultCrypto.randomBytes(32)))
            let ids = snapshot.originalIDs.union(snapshot.fileConcealmentKeys)
            let changed = set.insert(ids, digest: Self.digest)
            try AnalysisDatabase.purgeStored(ids)
            if changed || coverage != stamp || existing == nil { try write(set, coverage: stamp) }
            cached = set; coverage = stamp
        }
        NotificationCenter.default.post(name: .analysisVisibilityChanged, object: nil)
    }
    @discardableResult
    func conceal(_ ids: some Sequence<String>) throws -> Bool {
        defer { NotificationCenter.default.post(name: .analysisVisibilityChanged, object: nil) }
        let ids = Array(ids)
        return try lock.withLock {
            let existing = current()
            guard loaded else { throw CocoaError(.fileReadNoPermission) }
            var set = try existing ?? VaultConcealmentSet(salt: Data(VaultCrypto.randomBytes(32)))
            let changed = set.insert(ids, digest: Self.digest)
            if changed { try write(set, coverage: coverage); cached = set }
            // Repeated imports also purge old OCR/features. Failure must be returned to the vault caller.
            try AnalysisDatabase.purgeStored(Set(ids))
            return changed
        }
    }
    @discardableResult
    func reveal(_ ids: some Sequence<String>) throws -> Bool {
        let changed = try lock.withLock {
            guard var set = current(), set.remove(ids, digest: Self.digest) else { return false }
            try write(set, coverage: coverage); cached = set; return true
        }
        if changed { NotificationCenter.default.post(name: .analysisVisibilityChanged, object: nil) }
        return changed
    }
    func forgetAll() {
        lock.withLock {
            try? FileManager.default.removeItem(at: Self.url)
            cached = nil; coverage = nil
            loaded = !FileManager.default.fileExists(atPath: Self.url.path)
        }
        NotificationCenter.default.post(name: .analysisVisibilityChanged, object: nil)
    }
    private func current() -> VaultConcealmentSet? {
        if !loaded {
            if FileManager.default.fileExists(atPath: Self.url.path) {
                guard let data = try? Data(contentsOf: Self.url),
                      let value = try? JSONDecoder().decode(VaultConcealmentSet.self, from: data),
                      value.version == VaultConcealmentSet.currentVersion, value.salt.count >= 16,
                      value.digests.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
                cached = value
                coverage = (try? JSONDecoder().decode(AnalysisConcealmentMetadata.self, from: data))?.analysisCoverage
                loaded = true
            } else { loaded = true }
        }
        return cached
    }
    private func write(_ set: VaultConcealmentSet, coverage: AnalysisVaultCoverage?) throws {
        try FileManager.default.createDirectory(at: VaultStore.root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        // Preserve the existing flat c.json schema; older decoders ignore this optional metadata field.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(set)) as? [String: Any] ?? [:]
        if let coverage {
            object["analysisCoverage"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(coverage))
        }
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: Self.url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
