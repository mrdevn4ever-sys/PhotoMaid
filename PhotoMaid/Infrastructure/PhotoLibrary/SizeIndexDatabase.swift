import Foundation
import PhotoMaidCore
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

enum SizeIndexError: Error { case open, statement, write, read }

/// Gemessene Größen (und Prüfsummen für Duplikate) je Medium in SQLite. Ersetzt den früheren JSON-Block im
/// Schlüssel-Wert-Speicher, der bei jeder Messung komplett neu geschrieben wurde. Einträge werden einzeln ergänzt.
/// Nur lokal, nicht im Backup, jederzeit neu aufbaubar. Medien im Tresor werden entfernt (`purge`).
final class SizeIndexDatabase: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let instanceLock = NSLock()
    nonisolated(unsafe) private static var instance: SizeIndexDatabase?

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("size-index-v1", isDirectory: true).appendingPathComponent("index.sqlite")
    }

    static func shared() -> SizeIndexDatabase? {
        instanceLock.withLock {
            if let instance { return instance }
            guard let db = try? SizeIndexDatabase(url: url) else { return nil }
            instance = db
            return db
        }
    }

    /// Unter der Tresor-Sperre: Größen und Prüfsummen abgelegter Medien nicht außerhalb des Tresors behalten.
    static func purge(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let existing = instanceLock.withLock { instance }
        if let existing { try? existing.remove(ids); return }
        if FileManager.default.fileExists(atPath: url.path) { try? shared()?.remove(ids) }
    }

    init(url: URL) throws {
        let fm = FileManager.default
        var parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: parent.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try parent.setResourceValues(values)
        #endif
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let opened { sqlite3_close(opened) }
            throw SizeIndexError.open
        }
        handle = opened
        do {
            sqlite3_busy_timeout(handle, 1500)
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA secure_delete=ON;")
            try execute("CREATE TABLE IF NOT EXISTS sizes (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);")
        } catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { if let handle { sqlite3_close(handle) } }

    func all() throws -> [String: SizeRecord] {
        try lock.withLock {
            let s = try prepare("SELECT id,payload FROM sizes"); defer { sqlite3_finalize(s) }
            let decoder = JSONDecoder()
            var out: [String: SizeRecord] = [:]
            while true {
                let rc = sqlite3_step(s)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw SizeIndexError.read }
                guard let idText = sqlite3_column_text(s, 0), let bytes = sqlite3_column_blob(s, 1) else { continue }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 1)))
                // Unlesbarer Eintrag: wie nie gemessen (wird neu gemessen), nie als 0 übernommen.
                if let record = try? decoder.decode(SizeRecord.self, from: data) { out[String(cString: idText)] = record }
            }
            return out
        }
    }

    func upsert(_ records: [String: SizeRecord]) throws {
        guard !records.isEmpty else { return }
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                let s = try prepare("INSERT INTO sizes(id,payload) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload")
                defer { sqlite3_finalize(s) }
                let encoder = JSONEncoder()
                for (id, record) in records {
                    sqlite3_reset(s); sqlite3_clear_bindings(s)
                    let data = try encoder.encode(record)
                    guard sqlite3_bind_text(s, 1, id, -1, Self.transient) == SQLITE_OK else { throw SizeIndexError.write }
                    let rc = data.withUnsafeBytes { sqlite3_bind_blob(s, 2, $0.baseAddress, Int32($0.count), Self.transient) }
                    guard rc == SQLITE_OK, sqlite3_step(s) == SQLITE_DONE else { throw SizeIndexError.write }
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    func remove(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                let s = try prepare("DELETE FROM sizes WHERE id=?"); defer { sqlite3_finalize(s) }
                for id in ids {
                    sqlite3_reset(s); sqlite3_clear_bindings(s)
                    guard sqlite3_bind_text(s, 1, id, -1, Self.transient) == SQLITE_OK,
                          sqlite3_step(s) == SQLITE_DONE else { throw SizeIndexError.write }
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw SizeIndexError.write }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK else { throw SizeIndexError.statement }
        return s
    }
}
