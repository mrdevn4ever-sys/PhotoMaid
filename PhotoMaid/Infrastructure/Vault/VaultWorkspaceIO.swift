import CryptoKit
import Foundation
import PhotoMaidCore
import UIKit
import UniformTypeIdentifiers

/// Thread-safe revocation also fences directory creation. A stale worker cannot recreate a session's
/// plaintext directory after lock() has revoked the permit and removed it.
final class VaultSessionLease: @unchecked Sendable {
    let id = UUID()
    let key: VaultKey
    let directory: URL
    private let mutex = NSLock()
    private var valid = true

    init(key: VaultKey, parent: URL) {
        self.key = key
        directory = parent.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func check() throws {
        try mutex.withLock { if !valid { throw CancellationError() } }
        try Task.checkCancellation()
    }

    func withPermit<T>(_ body: () throws -> T) throws -> T {
        try mutex.withLock {
            guard valid else { throw CancellationError() }
            return try body()
        }
    }

    func revoke() { mutex.withLock { valid = false } }

    /// Ohne Abbruchprüfung der laufenden Aufgabe (für Prüfungen außerhalb von Tasks).
    var isValid: Bool { mutex.withLock { valid } }

    func makeDirectory() throws -> URL {
        try withPermit {
            let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var root = directory; try root.setResourceValues(values)
            return folder
        }
    }
}

struct VaultFileImportResult: Sendable {
    var imported: [String] = []
    var failed = 0
    var cancelled = false
}

/// No public Documents directory, no PhotoKit output and no plaintext staging during file import.
enum VaultWorkspaceIO {
    static func importFile(_ source: URL, lease: VaultSessionLease, objects: URL, nowMs: Int64,
                           origin: VaultFileOrigin = .copied) throws -> VaultDocument {
        try lease.check()
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<VaultDocument, any Error> = .failure(VaultCryptoError.io)
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                try lease.check()
                let values = try coordinated.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey,
                                                                      .fileResourceIdentifierKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw VaultWorkspaceError.invalidData }
                let name = try VaultWorkspace.cleanName(coordinated.lastPathComponent)
                let object = UUID().uuidString
                let target = objects.appendingPathComponent(object)
                let writer = try lease.withPermit { try VaultFileWriter(url: target, master: lease.key) }
                do {
                    let input = try FileHandle(forReadingFrom: coordinated)
                    defer { try? input.close() }
                    while let bytes = try input.read(upToCount: 1 << 20), !bytes.isEmpty {
                        try lease.check(); writer.receive(bytes)
                    }
                    try lease.check()
                    let written = try writer.finish()
                    let verified = try VaultFileReader.digest(target, master: lease.key)
                    guard verified.size == written.size, verified.sha256 == written.sha256 else { throw VaultCryptoError.authentication }
                    try lease.check()
                    // iOS bookmarks do not use the macOS-only .withSecurityScope creation option.
                    let bookmark = origin == .copied ? try? source.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) : nil
                    return VaultDocument(name: name, objectName: object,
                        typeIdentifier: values.contentType?.identifier ?? UTType.data.identifier,
                        byteCount: written.size, sha256: written.sha256, nowMs: nowMs, origin: origin, sourceBookmark: bookmark,
                        // Gleiche Darstellung wie `FileScanner` (Bereich „Dateien“), damit das Original dort verborgen wird.
                        sourceKey: values.fileResourceIdentifier.map { String(describing: $0) })
                } catch {
                    writer.abort(); try? FileManager.default.removeItem(at: target); throw error
                }
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func importData(_ bytes: Data, name: String, type: UTType, lease: VaultSessionLease,
                           objects: URL, nowMs: Int64) throws -> VaultDocument {
        try lease.check()
        let clean = try VaultWorkspace.cleanName(name)
        let object = UUID().uuidString
        let target = objects.appendingPathComponent(object)
        let writer = try lease.withPermit { try VaultFileWriter(url: target, master: lease.key) }
        do {
            for offset in stride(from: 0, to: bytes.count, by: 1 << 20) {
                try lease.check(); writer.receive(bytes.subdata(in: offset..<min(bytes.count, offset + (1 << 20))))
            }
            let written = try writer.finish()
            let checked = try VaultFileReader.digest(target, master: lease.key)
            guard checked.size == written.size, checked.sha256 == written.sha256 else { throw VaultCryptoError.authentication }
            try lease.check()
            return VaultDocument(name: clean, objectName: object, typeIdentifier: type.identifier,
                byteCount: written.size, sha256: written.sha256, nowMs: nowMs, origin: .createdInsideVault)
        } catch {
            writer.abort(); try? FileManager.default.removeItem(at: target); throw error
        }
    }

    static func preview(_ document: VaultDocument, lease: VaultSessionLease, objects: URL) throws -> URL {
        try lease.check()
        guard VaultWorkspace.isOpaqueName(document.objectName) else { throw VaultWorkspaceError.invalidData }
        let folder = try lease.makeDirectory()
        // The user-visible name is used only after validation and only inside this private session folder.
        let target = folder.appendingPathComponent(try VaultWorkspace.cleanName(document.name))
        do {
            let result = try VaultFileReader.decrypt(objects.appendingPathComponent(document.objectName), to: target, master: lease.key)
            guard result.size == document.byteCount, result.sha256 == document.sha256 else { throw VaultCryptoError.authentication }
            try lease.check()
            return target
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    static func removeOriginal(_ document: VaultDocument, lease: VaultSessionLease) throws {
        try lease.check()
        guard document.origin == .copied, let bookmark = document.sourceBookmark else { throw VaultWorkspaceError.missingItem }
        var stale = false
        let source = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw VaultWorkspaceError.missingItem }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, any Error> = .failure(VaultCryptoError.io)
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forDeleting, error: &coordinationError) { coordinated in
            result = Result {
                try lease.check()
                let values = try coordinated.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw VaultWorkspaceError.invalidData }
                let input = try FileHandle(forReadingFrom: coordinated)
                defer { try? input.close() }
                var hash = SHA256(); var count: Int64 = 0
                while let bytes = try input.read(upToCount: 1 << 20), !bytes.isEmpty {
                    try lease.check(); hash.update(data: bytes); count += Int64(bytes.count)
                }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                guard count == document.byteCount, digest == document.sha256 else { throw VaultWorkspaceError.conflict }
                try input.close()
                // Revocation and destructive action cannot race each other.
                try lease.withPermit { try FileManager.default.removeItem(at: coordinated) }
            }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}

/// Consent is presented on the actual topmost controller, including a full-screen vault viewer.
/// Locking the vault dismisses the prompt and resumes the awaiting operation with false.
@MainActor
enum VaultDisclosure {
    private static var continuation: CheckedContinuation<Bool, Never>?
    private static weak var alert: UIAlertController?

    static func confirm(messageKey: String = "vault2_export_warning") async -> Bool {
        guard continuation == nil, VaultStore.shared.phase == .unlocked else { return false }
        guard var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return false }
        while let next = presenter.presentedViewController { presenter = next }
        if presenter.isBeingDismissed { return false }
        return await withCheckedContinuation { pending in
            continuation = pending
            let dialog = UIAlertController(title: L("vault_title"), message: L(messageKey), preferredStyle: .alert)
            dialog.addAction(UIAlertAction(title: L("cancel"), style: .cancel) { _ in Task { @MainActor in finish(false) } })
            dialog.addAction(UIAlertAction(title: L("vault2_continue"), style: .default) { _ in Task { @MainActor in finish(true) } })
            alert = dialog
            presenter.present(dialog, animated: true)
        }
    }

    static func cancel() {
        alert?.dismiss(animated: false)
        finish(false)
    }

    private static func finish(_ approved: Bool) {
        let pending = continuation
        continuation = nil; alert = nil
        pending?.resume(returning: approved)
    }
}
