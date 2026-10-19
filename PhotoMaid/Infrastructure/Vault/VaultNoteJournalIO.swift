import Foundation
import PhotoMaidCore

/// Keystrokes replace only one encrypted note record, not a potentially large media index.
/// Index commits invalidate old journals through a monotonically increasing snapshot sequence.
enum VaultNoteJournalIO {
    private static func directory(_ root: URL) -> URL { root.appendingPathComponent("n", isDirectory: true) }
    static func save(_ journal: VaultNoteJournal, root: URL, lease: VaultSessionLease) throws {
        guard VaultWorkspace.isOpaqueName(journal.note.id) else { throw VaultWorkspaceError.invalidData }
        let bytes = try JSONEncoder().encode(journal)
        let sealed = try VaultCrypto.seal(bytes, key: VaultCrypto.subkey(lease.key, salt: [], info: "pm-vault-note-journal"))
        try lease.withPermit {
            let folder = directory(root)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            try sealed.write(to: folder.appendingPathComponent(journal.note.id), options: [.atomic, .completeFileProtection])
        }
    }
    /// Run before publishing any unlocked content. A corrupt current journal is an error, not permission
    /// to show an older note as if the user's most recent edits had been saved successfully.
    static func replay(into snapshot: inout VaultSnapshot, root: URL, key: VaultKey) throws -> Bool {
        let folder = directory(root)
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var changed = false
        for url in urls where VaultWorkspace.isOpaqueName(url.lastPathComponent) {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size < 8 << 20 else { throw VaultWorkspaceError.invalidData }
            let sealed = try Data(contentsOf: url)
            let plain = try VaultCrypto.open(sealed, key: VaultCrypto.subkey(key, salt: [], info: "pm-vault-note-journal"))
            let journal = try JSONDecoder().decode(VaultNoteJournal.self, from: plain)
            guard journal.note.id == url.lastPathComponent else { throw VaultWorkspaceError.invalidData }
            let current = snapshot.sequence
            changed = try journal.apply(to: &snapshot.workspace, snapshotSequence: current) || changed
        }
        return changed
    }
    /// Called only after all journals were authenticated and any replay was folded into a durable snapshot.
    /// Before unlocked state is published there can be no concurrent note writer.
    static func removeReplayed(root: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory(root), includingPropertiesForKeys: nil) else { return }
        removeAcknowledged(root: root, ids: Set(urls.map(\.lastPathComponent)))
    }
    static func removeAcknowledged(root: URL, ids: Set<String>) {
        for id in ids where VaultWorkspace.isOpaqueName(id) { try? FileManager.default.removeItem(at: directory(root).appendingPathComponent(id)) }
    }
}
