import CryptoKit
import Foundation
import PhotoMaidCore

extension Notification.Name {
    static let analysisVisibilityChanged = Notification.Name("PhotoMaid.analysisVisibilityChanged")
}

/// Public visibility boundary, also used while the vault is locked. Only salted hashes are stored.
/// Unknown, inaccessible, invalid or missing-with-existing-vault state denies EVERY public lookup.
/// No encryption or ciphertext format is changed by this projection.
final class VaultConcealment: @unchecked Sendable {
    static let shared = VaultConcealment()
    static var url: URL { VaultStore.root.appendingPathComponent("c.json") }
    private let lock = NSLock()
    private let storageURL: URL
    private let indexURL: URL
    private let writer: @Sendable (Data, URL) throws -> Void
    private var cached: VaultConcealmentSet?
    private var loaded = false
    private var damaged = false
    private var epoch = UUID()

    /// Changes after a visibility write or a failed write, so stale projections can be discarded.
    var revision: UUID { lock.withLock { _ = current(); return epoch } }

    /// Explicit paths and writer allow isolated disk/error-injection tests, never production data.
    init(url: URL = VaultConcealment.url,
         indexURL: URL = VaultStore.root.appendingPathComponent("index.bin"),
         writer: @escaping @Sendable (Data, URL) throws -> Void = { data, target in
             try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
             try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
         }) {
        storageURL = url
        self.indexURL = indexURL
        self.writer = writer
    }

    static func digest(_ salt: Data, _ id: String) -> String {
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(id.utf8))
        return Array(hasher.finalize()).hexString
    }

    var analysisReady: Bool { lock.withLock { _ = current(); return loaded && !damaged } }
    /// Unknown is deliberately NOT empty: callers must not take an unfiltered fast path.
    var isEmpty: Bool { lock.withLock { let set = current(); return loaded && !damaged && (set?.isEmpty ?? true) } }
    func isConcealed(_ id: String) -> Bool {
        lock.withLock {
            let set = current()
            return !loaded || damaged || (set?.contains(id, digest: Self.digest) ?? false)
        }
    }
    func visible<T>(_ items: [T], id: (T) -> String) -> [T] {
        lock.withLock {
            let set = current()
            guard loaded, !damaged else { return [] }
            guard let set, !set.isEmpty else { return items }
            return items.filter { !set.contains(id($0), digest: Self.digest) }
        }
    }
    func visible(_ ids: Set<String>) -> Set<String> {
        Set(visible(Array(ids)) { $0 })
    }
    /// Body must not re-enter this instance. Visibility and result persistence are serialized.
    func withAnalysisAccess<T>(_ ids: [String], _ body: () throws -> T) rethrows -> T? {
        try lock.withLock {
            let set = current()
            guard loaded, !damaged, !ids.contains(where: { set?.contains($0, digest: Self.digest) ?? false }) else { return nil }
            return try body()
        }
    }

    @discardableResult
    func conceal(_ ids: some Sequence<String>) throws -> Bool {
        var notifyOnExit = true
        defer { if notifyOnExit { notify() } } // Errors also invalidate stale public UI.
        let changed = try lock.withLock {
            let existing = current()
            guard loaded, !damaged else { throw CocoaError(.fileReadCorruptFile) }
            var set = try existing ?? VaultConcealmentSet(salt: Data(VaultCrypto.randomBytes(32)))
            let changed = set.insert(ids, digest: Self.digest)
            // Persist even the initial empty list BEFORE creating an encrypted index.
            if changed || existing == nil { try write(set); cached = set }
            return changed
        }
        notifyOnExit = changed
        return changed
    }

    @discardableResult
    func reveal(_ ids: some Sequence<String>) throws -> Bool {
        var notifyOnExit = true
        defer { if notifyOnExit { notify() } }
        let changed = try lock.withLock {
            let existing = current()
            guard loaded, !damaged else { throw CocoaError(.fileReadCorruptFile) }
            guard var set = existing, set.remove(ids, digest: Self.digest) else { return false }
            try write(set)
            cached = set
            return true
        }
        notifyOnExit = changed
        return changed
    }

    /// Call ONLY after decrypting and validating the authoritative vault snapshot. Preserve all readable
    /// historical hashes. A damaged projection is rebuilt from authenticated original/file identities.
    func repair(authenticatedIDs ids: Set<String>) throws {
        try lock.withLock {
            let previous = current()
            var set = try previous ?? VaultConcealmentSet(salt: Data(VaultCrypto.randomBytes(32)))
            set.insert(ids, digest: Self.digest)
            try write(set)
            cached = set
            loaded = true
            damaged = false
        }
        notify()
    }

    /// Only after explicit, successfully completed whole-vault deletion. Failure never reveals anything.
    func forgetAll() throws {
        try lock.withLock {
            do { try FileManager.default.removeItem(at: storageURL) }
            catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {}
            cached = nil
            loaded = true
            damaged = false
            epoch = UUID()
        }
        notify()
    }

    private func current() -> VaultConcealmentSet? {
        guard !loaded else { return cached }
        do {
            let set = try JSONDecoder().decode(VaultConcealmentSet.self, from: Data(contentsOf: storageURL))
            guard set.version == VaultConcealmentSet.currentVersion, set.salt.count == 32,
                  set.digests.allSatisfy({ $0.count == 64 && $0.allSatisfy { $0.isASCII && $0.isHexDigit } })
            else { throw CocoaError(.fileReadCorruptFile) }
            cached = set
            loaded = true
            damaged = false
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // File existence APIs collapse access errors into false. Only an actual ENOENT on BOTH files
            // proves a pristine install. All other errors remain closed and are retried after unlock.
            do {
                _ = try FileManager.default.attributesOfItem(atPath: indexURL.path)
                damaged = true
            } catch let missing as CocoaError where missing.code == .fileReadNoSuchFile || missing.code == .fileNoSuchFile {
                loaded = true
                damaged = false
            } catch { damaged = true }
        } catch { damaged = true }
        return cached
    }
    private func write(_ set: VaultConcealmentSet) throws {
        do { try writer(JSONEncoder().encode(set), storageURL); epoch = UUID() }
        catch { damaged = true; epoch = UUID(); throw error }
    }
    private func notify() { NotificationCenter.default.post(name: .analysisVisibilityChanged, object: nil) }
}
