import CryptoKit
import Foundation
import PhotoMaidCore

/// Verbergen-Liste der Tresor-Originale: Medien, die im Tresor liegen, zeigt PhotoMaid nirgends sonst – auch dann
/// nicht, wenn iOS das Löschen in der Fotos-App nicht bestätigt hat oder ein Original aus „Zuletzt gelöscht“
/// zurückkommt. Alle PhotoKit-Zugänge der App (`PhotoLibraryService`, Vorschau, Raster) fragen hier nach.
///
/// Gespeichert werden nur gesalzene SHA-256-Prüfsummen der Kennungen (keine Inhalte, keine Klartext-Kennungen), damit
/// die Liste auch bei gesperrtem Tresor gilt. Threadsicher und ohne Actor, weil PhotoKit-Abfragen abseits des Main
/// Actors laufen.
final class VaultConcealment: @unchecked Sendable {
    static let shared = VaultConcealment()

    private let lock = NSLock()
    private var cached: VaultConcealmentSet?
    private var loaded = false

    static var url: URL { VaultStore.root.appendingPathComponent("c.json") }

    static func digest(_ salt: Data, _ id: String) -> String {
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: Data(id.utf8))
        return Array(hasher.finalize()).hexString
    }

    var isEmpty: Bool { lock.withLock { current()?.isEmpty ?? true } }

    func isConcealed(_ id: String) -> Bool {
        lock.withLock { current()?.contains(id, digest: Self.digest) ?? false }
    }

    /// Entfernt verborgene Einträge; ohne verborgene Medien unverändert (schnell).
    func visible<T>(_ items: [T], id: (T) -> String) -> [T] {
        lock.withLock {
            guard let set = current(), !set.isEmpty else { return items }
            return items.filter { !set.contains(id($0), digest: Self.digest) }
        }
    }

    func visible(_ ids: Set<String>) -> Set<String> {
        lock.withLock {
            guard let set = current(), !set.isEmpty else { return ids }
            return ids.filter { !set.contains($0, digest: Self.digest) }
        }
    }

    /// Verbirgt Originale. Wird erst gespeichert, dann gilt es im Speicher (kein Zustand, der beim Neustart fehlt).
    @discardableResult
    func conceal(_ ids: some Sequence<String>) throws -> Bool {
        try lock.withLock {
            let existing = current()
            // Vorhanden, aber nicht lesbar: nie mit einer neuen, leeren Liste überschreiben.
            guard loaded else { throw CocoaError(.fileReadNoPermission) }
            var set = try existing ?? VaultConcealmentSet(salt: Data(VaultCrypto.randomBytes(32)))
            guard set.insert(ids, digest: Self.digest) else { return false }
            try write(set)
            cached = set
            return true
        }
    }

    /// Zeigt Originale wieder (z. B. nach „Zurück in Fotos“ oder Löschen aus dem Tresor).
    @discardableResult
    func reveal(_ ids: some Sequence<String>) throws -> Bool {
        try lock.withLock {
            guard var set = current(), set.remove(ids, digest: Self.digest) else { return false }
            try write(set)
            cached = set
            return true
        }
    }

    /// Nach dem Löschen des ganzen Tresors: Liste vergessen (die Datei liegt im Tresor-Ordner).
    func forgetAll() {
        lock.withLock {
            try? FileManager.default.removeItem(at: Self.url)
            cached = nil
            loaded = true
        }
    }

    // MARK: Intern (nur unter `lock`)

    /// Liest die Liste einmal. Ist die Datei vorhanden, aber (noch) nicht lesbar – etwa vor der ersten Entsperrung des
    /// iPhones –, wird es beim nächsten Zugriff erneut versucht. Eine beschädigte Datei gilt als leer; beim nächsten
    /// Öffnen des Tresors wird die Liste aus dem verschlüsselten Index neu aufgebaut.
    private func current() -> VaultConcealmentSet? {
        if !loaded {
            if FileManager.default.fileExists(atPath: Self.url.path) {
                if let data = try? Data(contentsOf: Self.url) {
                    cached = try? JSONDecoder().decode(VaultConcealmentSet.self, from: data)
                    loaded = true
                }
            } else {
                loaded = true
            }
        }
        return cached
    }

    private func write(_ set: VaultConcealmentSet) throws {
        try FileManager.default.createDirectory(at: VaultStore.root, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(set).write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
