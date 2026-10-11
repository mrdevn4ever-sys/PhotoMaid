import CryptoKit
import Foundation
import Photos
import PhotoMaidCore
import Security

extension Notification.Name {
    static let vaultIsolationChanged = Notification.Name("PhotoMaid.vaultIsolationChanged")
}

enum VaultIsolationError: Error { case unavailable, privateMedia, changed, persistence }

/// Public/private reference monitor. This separate, authenticated policy contains
/// identifiers and lineage only, NEVER a vault decryption key or image. It remains
/// usable while the vault is locked. It is not a user-controllable hidden album.
final class VaultIsolation: @unchecked Sendable {
    static let shared = VaultIsolation()

    struct Fingerprint: Codable, Hashable, Sendable {
        let filenames: Set<String>
        let creationMs: Int64?
        let video: Bool
        init(_ item: VaultItem) {
            filenames = Set(item.resources.map { $0.originalFilename.lowercased() }.filter { !$0.isEmpty })
            creationMs = item.creationMs
            video = item.isVideo
        }
        func matches(_ asset: PHAsset, names: Set<String>) -> Bool {
            guard video == (asset.mediaType == .video), !filenames.isDisjoint(with: names) else { return false }
            if let creationMs, let date = asset.creationDate {
                return abs(date.timeIntervalSince1970 * 1000 - Double(creationMs)) < 1000
            }
            // Missing legacy dates are ambiguous. Hide rather than expose.
            return true
        }
    }

    struct Snapshot: Sendable {
        let epoch: UUID
        let ready: Bool
        let denied: Set<String>
        let explicitExports: Set<String>
        let fingerprints: [Fingerprint]
        var hasPrivateMedia: Bool { !denied.isEmpty || !fingerprints.isEmpty }
        func allows(_ id: String) -> Bool {
            VaultVisibilityPolicy.allows(id, ready: ready, denied: denied)
        }
        func allows(_ reference: ItemReference) -> Bool {
            ready && (reference.provider != .photoLibrary || allows(reference.localIdentifier))
        }
    }

    struct Ticket: Sendable {
        let epoch: UUID
        let sourceIDs: [String]
        var isValid: Bool {
            let current = VaultIsolation.shared.snapshot
            return current.ready && current.epoch == epoch && sourceIDs.allSatisfy(current.allows)
        }
        func requireValid() throws {
            guard isValid else { throw VaultIsolationError.changed }
        }
    }

    private struct Manifest: Codable {
        var version = 1
        var roots: Set<String> = []
        var parentsByOutput: [String: Set<String>] = [:]
        var fingerprints: [Fingerprint] = []
        var explicitExports: Set<String> = []
        var needsReconciliation = false
    }
    private struct Anchor: Codable {
        var key: Data
        var digest: Data
    }
    private let lock = NSRecursiveLock()
    private var manifest = Manifest()
    private var anchor: Anchor?
    private var valid = false
    private var epoch = UUID()
    private var denied: Set<String> = []
    private static let account = "vault.isolation.anchor.v1"
    private static let service = (Bundle.main.bundleIdentifier ?? "photomaid") + ".vault"
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".pmv-isolation.bin")
    }
    private static var vaultExists: Bool { FileManager.default.fileExists(atPath: VaultStore.root.path) }

    private init() { reload() }

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(epoch: epoch, ready: valid && !manifest.needsReconciliation, denied: denied,
                        explicitExports: manifest.explicitExports, fingerprints: manifest.fingerprints)
    }

    /// No app screen may bypass this for cached data. PhotoKit-backed readers
    /// additionally use publicAsset(), which recognizes legacy/restored identities.
    func allows(_ id: String) -> Bool { snapshot.allows(id) }
    func allows(_ reference: ItemReference) -> Bool { snapshot.allows(reference) }

    func publicAsset(_ id: String) -> PHAsset? {
        let state = snapshot
        guard state.allows(id), let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              isPublic(asset, in: state), snapshot.epoch == state.epoch else { return nil }
        return asset
    }

    func isPublic(_ asset: PHAsset, in state: Snapshot? = nil) -> Bool {
        let state = state ?? snapshot
        guard state.allows(asset.localIdentifier) else { return false }
        if state.explicitExports.contains(asset.localIdentifier) { return true }
        let possible = state.fingerprints.filter { fingerprint in
            guard fingerprint.video == (asset.mediaType == .video) else { return false }
            guard let ms = fingerprint.creationMs, let date = asset.creationDate else { return true }
            return abs(date.timeIntervalSince1970 * 1000 - Double(ms)) < 1000
        }
        guard !possible.isEmpty else { return true }
        let names = Set(PHAssetResource.assetResources(for: asset).map { $0.originalFilename.lowercased() })
        return !possible.contains { $0.matches(asset, names: names) }
    }

    func ticket(for ids: [String]) throws -> Ticket {
        let state = snapshot
        guard state.ready else { throw VaultIsolationError.unavailable }
        guard ids.allSatisfy(state.allows) else { throw VaultIsolationError.privateMedia }
        return Ticket(epoch: state.epoch, sourceIDs: ids)
    }

    /// No automatic recovery from a missing/tampered policy. An existing vault
    /// without this policy is a legacy migration, not an empty public library.
    func reload() {
        lock.lock(); defer { lock.unlock() }
        do {
            if let data = try Self.readAnchor() {
                let read = try JSONDecoder().decode(Anchor.self, from: data)
                let encrypted = try Data(contentsOf: Self.url)
                guard read.key.count == 32, Data(SHA256.hash(data: encrypted)) == read.digest else {
                    throw VaultIsolationError.unavailable
                }
                let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: SymmetricKey(data: read.key))
                let decoded = try JSONDecoder().decode(Manifest.self, from: plain)
                guard decoded.version == 1 else { throw VaultIsolationError.unavailable }
                anchor = read; manifest = decoded; valid = true
                denied = VaultVisibilityPolicy.closure(roots: decoded.roots, parentsByOutput: decoded.parentsByOutput)
            } else {
                valid = !Self.vaultExists && !FileManager.default.fileExists(atPath: Self.url.path)
                manifest.needsReconciliation = !valid
            }
        } catch { valid = false; manifest.needsReconciliation = true }
        epoch = UUID()
    }

    /// Before a vault import, persist a fail-closed marker. A killed process
    /// cannot reopen public views before the encrypted index is reconciled.
    func beginPrivateMutation() throws {
        lock.lock(); defer { lock.unlock() }
        guard valid else { throw VaultIsolationError.unavailable }
        var next = manifest
        next.needsReconciliation = true
        try persist(next)
    }

    /// Called only with an authenticated, decrypted vault index. Roots are
    /// tombstones: deleting a vault entry never silently republishes its original.
    /// Legacy composites without recorded source IDs are conservatively hidden.
    func reconcile(items: [VaultItem], retainedSourceIDs: Set<String>, edits: [EditRecord],
                   additionalPrivateIDs: Set<String> = []) throws {
        lock.lock(); defer { lock.unlock() }
        var next = manifest
        next.roots.formUnion(retainedSourceIDs)
        next.roots.formUnion(items.compactMap(\.sourceID))
        next.roots.formUnion(additionalPrivateIDs)
        next.fingerprints = Array(Set(next.fingerprints).union(items.map(Fingerprint.init)))
        for record in edits {
            if !record.sourceId.isEmpty {
                next.parentsByOutput[record.newId, default: []].insert(record.sourceId)
            } else if !items.isEmpty && (record.count > 1 || record.kind == .collage || record.kind == .merge || record.kind == .slideshow) {
                // Old builds did not retain all inputs. Do not guess an output safe.
                next.roots.insert(record.newId)
            }
        }
        next.needsReconciliation = false
        try persist(next)
    }

    /// Register complete lineage for new generated media before public UI reloads.
    /// A result finishing after a privacy boundary changed remains private.
    func registerOutput(_ id: String, sources: Set<String>, originatingEpoch: UUID? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        var next = manifest
        next.parentsByOutput[id, default: []].formUnion(sources)
        if let originatingEpoch, originatingEpoch != epoch { next.roots.insert(id) }
        try persist(next, notify: false)
    }

    /// Only an explicit restore/share operation inside an authenticated vault may
    /// release a newly created PhotoKit identity. Existing originals stay denied.
    func allowExplicitExport(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var next = manifest
        next.explicitExports.insert(id)
        next.roots.remove(id)
        next.parentsByOutput[id] = nil
        try persist(next)
    }

    func protect(_ ids: Set<String>) throws {
        lock.lock(); defer { lock.unlock() }
        var next = manifest
        next.roots.formUnion(ids)
        next.explicitExports.subtract(ids)
        try persist(next)
    }

    private func persist(_ next: Manifest, notify: Bool = true) throws {
        do {
            let keyData: Data
            if let anchor { keyData = anchor.key } else {
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                    throw VaultIsolationError.persistence
                }
                keyData = Data(bytes)
            }
            let plain = try JSONEncoder().encode(next)
            guard let encrypted = try AES.GCM.seal(plain, using: SymmetricKey(data: keyData)).combined else {
                throw VaultIsolationError.persistence
            }
            try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encrypted.write(to: Self.url, options: [.atomic, .completeFileProtection])
            let nextAnchor = Anchor(key: keyData, digest: Data(SHA256.hash(data: encrypted)))
            try Self.writeAnchor(JSONEncoder().encode(nextAnchor))
            anchor = nextAnchor; manifest = next; valid = true
            denied = VaultVisibilityPolicy.closure(roots: next.roots, parentsByOutput: next.parentsByOutput)
            if notify { epoch = UUID(); signal() }
        } catch {
            valid = false; epoch = UUID(); signal()
            throw error
        }
    }

    private func signal() {
        Task { @MainActor in NotificationCenter.default.post(name: .vaultIsolationChanged, object: nil) }
    }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    private static func readAnchor() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultIsolationError.unavailable }
        return data
    }
    private static func writeAnchor(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw VaultIsolationError.persistence }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw VaultIsolationError.persistence }
    }
}
