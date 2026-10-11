import Foundation
import PhotoMaidCore
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

struct AnalysisHitPage: Sendable {
    var ids: [String]
    var total: Int
}

enum AnalysisDatabaseError: Error { case open, statement, read, write, corrupt, privacy }

/// Public, rebuildable analysis only. Full images are never stored here. All calls are serialized;
/// scans and queries run on a utility task, not on MainActor. SQLite commits every completed item.
final class AnalysisDatabase: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let instanceLock = NSLock()
    nonisolated(unsafe) private static var instance: AnalysisDatabase?

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analysis-v2", isDirectory: true)
    }
    static func shared() throws -> AnalysisDatabase {
        try instanceLock.withLock {
            if let instance { return instance }
            let db = try AnalysisDatabase(url: directory.appendingPathComponent("index.sqlite"))
            instance = db
            return db
        }
    }
    /// Called synchronously under the vault visibility lock, before the vault import can report success.
    static func purgeStored(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        let existing = instanceLock.withLock { instance }
        if let existing { try existing.remove(ids); return }
        let url = directory.appendingPathComponent("index.sqlite")
        if FileManager.default.fileExists(atPath: url.path) { try shared().remove(ids) }
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
            throw AnalysisDatabaseError.open
        }
        handle = opened
        do {
            sqlite3_busy_timeout(handle, 1500)
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA wal_autocheckpoint=64;")
            try execute("""
                CREATE TABLE IF NOT EXISTS items (
                  id TEXT NOT NULL, kind TEXT NOT NULL, state TEXT NOT NULL, captured REAL,
                  algorithm TEXT NOT NULL, payload BLOB NOT NULL, recognized TEXT,
                  sharpness REAL, category TEXT, feature BLOB, PRIMARY KEY(id,kind));
                CREATE INDEX IF NOT EXISTS items_state ON items(kind,state);
                CREATE INDEX IF NOT EXISTS items_time ON items(kind,algorithm,captured);
                CREATE TABLE IF NOT EXISTS links (a TEXT NOT NULL,b TEXT NOT NULL,PRIMARY KEY(a,b));
                """)
            #if os(iOS)
            for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: url.path + suffix) {
                try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path + suffix)
            }
            #endif
        } catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { if let handle { sqlite3_close(handle) } }

    func rows(_ kind: AnalysisKind? = nil) throws -> [AnalysisItem] {
        try lock.withLock {
            let sql = "SELECT payload,state FROM items" + (kind == nil ? "" : " WHERE kind=?")
            let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
            if let kind { try bind(kind.rawValue, to: statement, at: 1) }
            var output: [AnalysisItem] = []
            while try step(statement) {
                guard let data = blob(statement, 0), var row = try? JSONDecoder().decode(AnalysisItem.self, from: data),
                      let state = string(statement, 1).flatMap(AnalysisItemState.init(rawValue:)) else { throw AnalysisDatabaseError.corrupt }
                row.state = state; output.append(row)
            }
            return output
        }
    }

    /// Caller must hold its visibility gate while committing. Feature bytes are not copied into queue metadata.
    func save(_ item: AnalysisItem, feature: Data? = nil) throws {
        try lock.withLock {
            var light = item; light.text = nil
            let payload = try JSONEncoder().encode(light)
            let statement = try prepare("""
                INSERT INTO items(id,kind,state,captured,algorithm,payload,recognized,sharpness,category,feature)
                VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id,kind) DO UPDATE SET
                state=excluded.state,captured=excluded.captured,algorithm=excluded.algorithm,payload=excluded.payload,
                recognized=COALESCE(excluded.recognized,items.recognized),sharpness=excluded.sharpness,
                category=excluded.category,feature=COALESCE(excluded.feature,items.feature)
                """)
            defer { sqlite3_finalize(statement) }
            try bind(item.id, to: statement, at: 1); try bind(item.kind.rawValue, to: statement, at: 2)
            try bind(item.state.rawValue, to: statement, at: 3)
            if let date = item.captured { sqlite3_bind_double(statement, 4, date.timeIntervalSince1970) }
            try bind(item.algorithm, to: statement, at: 5); try bind(payload, to: statement, at: 6)
            if let text = item.text { try bind(text, to: statement, at: 7) }
            if let value = item.sharpness { sqlite3_bind_double(statement, 8, value) }
            if let category = item.category { try bind(category, to: statement, at: 9) }
            if let feature { try bind(feature, to: statement, at: 10) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw AnalysisDatabaseError.write }
        }
    }

    func remove(_ ids: Set<String>, kind: AnalysisKind? = nil) throws {
        guard !ids.isEmpty else { return }
        try lock.withLock {
            try transaction {
                let s = try prepare("DELETE FROM items WHERE id=?" + (kind == nil ? "" : " AND kind=?")); defer { sqlite3_finalize(s) }
                for id in ids {
                    sqlite3_reset(s); sqlite3_clear_bindings(s); try bind(id, to: s, at: 1)
                    if let kind { try bind(kind.rawValue, to: s, at: 2) }
                    guard sqlite3_step(s) == SQLITE_DONE else { throw AnalysisDatabaseError.write }
                }
                // Removing a bridge can split a group. Rebuild comparisons from the cached features,
                // not by downloading photographs again; never retain a group containing an excluded item.
                if kind == nil || kind == .similar {
                    try execute("DELETE FROM links; UPDATE items SET state='featuresReady' WHERE kind='similar' AND feature IS NOT NULL;")
                }
            }
            sqlite3_wal_checkpoint_v2(handle, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        }
    }

    func feature(_ id: String) throws -> Data? {
        try lock.withLock {
            let s = try prepare("SELECT feature FROM items WHERE id=? AND kind='similar'"); defer { sqlite3_finalize(s) }
            try bind(id, to: s, at: 1)
            return try step(s) ? blob(s, 0) : nil
        }
    }
    /// Deliberately bounded candidate search for nearby shots, not an exhaustive duplicate detector.
    func neighbors(_ item: AnalysisItem, limit: Int = 64) throws -> [String] {
        guard let date = item.captured else { return [] }
        return try lock.withLock {
            let s = try prepare("""
                SELECT id FROM items WHERE kind='similar' AND feature IS NOT NULL AND algorithm=?
                AND id<>? AND captured BETWEEN ? AND ? ORDER BY ABS(captured-?),id LIMIT ?
                """); defer { sqlite3_finalize(s) }
            try bind(item.algorithm, to: s, at: 1); try bind(item.id, to: s, at: 2)
            let time = date.timeIntervalSince1970
            sqlite3_bind_double(s, 3, time - 600); sqlite3_bind_double(s, 4, time + 600)
            sqlite3_bind_double(s, 5, time); sqlite3_bind_int(s, 6, Int32(max(1, min(64, limit))))
            var ids: [String] = []
            while try step(s) { if let id = string(s, 0) { ids.append(id) } }
            return ids
        }
    }
    func links() throws -> [(String, String)] {
        try lock.withLock {
            let s = try prepare("SELECT a,b FROM links"); defer { sqlite3_finalize(s) }
            var values: [(String, String)] = []
            while try step(s) {
                if let a = string(s, 0), let b = string(s, 1) { values.append((a, b)) }
            }
            return values
        }
    }
    func link(_ a: String, _ b: String) throws {
        try lock.withLock {
            let s = try prepare("INSERT OR IGNORE INTO links(a,b) VALUES (?,?)"); defer { sqlite3_finalize(s) }
            try bind(min(a, b), to: s, at: 1); try bind(max(a, b), to: s, at: 2)
            guard sqlite3_step(s) == SQLITE_DONE else { throw AnalysisDatabaseError.write }
        }
    }

    func hits(kind: AnalysisKind, query: String, category: String?, limit: Int, offset: Int = 0) throws -> AnalysisHitPage {
        try lock.withLock {
            let criterion: String
            switch kind {
            case .blurry: criterion = "sharpness IS NOT NULL AND sharpness<0.0009"
            case .documents: criterion = "recognized IS NOT NULL AND length(recognized)>0"
            case .categories: criterion = "category IS NOT NULL"
            case .similar: return AnalysisHitPage(ids: [], total: 0)
            }
            let search = query.isEmpty ? "" : " AND recognized LIKE ? ESCAPE '\\'"
            let filter = category == nil ? "" : " AND category=?"
            let whereSQL = " WHERE kind=? AND state='complete' AND " + criterion + search + filter
            func bindings(_ s: OpaquePointer?) throws {
                try bind(kind.rawValue, to: s, at: 1)
                var i: Int32 = 2
                if !query.isEmpty {
                    let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
                    try bind("%" + escaped + "%", to: s, at: i); i += 1
                }
                if let category { try bind(category, to: s, at: i) }
            }
            let count = try prepare("SELECT COUNT(*) FROM items" + whereSQL); defer { sqlite3_finalize(count) }
            try bindings(count)
            guard try step(count) else { throw AnalysisDatabaseError.read }
            let total = Int(sqlite3_column_int64(count, 0))
            let order = kind == .blurry ? "sharpness ASC,id" : "captured DESC,id"
            let s = try prepare("SELECT id FROM items" + whereSQL + " ORDER BY " + order
                                + " LIMIT \(max(1, min(10000, limit))) OFFSET \(max(0, offset))")
            defer { sqlite3_finalize(s) }; try bindings(s)
            var ids: [String] = []
            while try step(s) { if let id = string(s, 0) { ids.append(id) } }
            return AnalysisHitPage(ids: ids, total: total)
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw AnalysisDatabaseError.write }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK else { throw AnalysisDatabaseError.statement }
        return s
    }
    private func step(_ s: OpaquePointer?) throws -> Bool {
        let value = sqlite3_step(s)
        if value == SQLITE_DONE { return false }
        guard value == SQLITE_ROW else { throw AnalysisDatabaseError.read }
        return true
    }
    private func bind(_ text: String, to s: OpaquePointer?, at n: Int32) throws {
        guard sqlite3_bind_text(s, n, text, -1, Self.transient) == SQLITE_OK else { throw AnalysisDatabaseError.write }
    }
    private func bind(_ data: Data, to s: OpaquePointer?, at n: Int32) throws {
        guard data.count <= Int(Int32.max) else { throw AnalysisDatabaseError.write }
        let rc = data.withUnsafeBytes { sqlite3_bind_blob(s, n, $0.baseAddress, Int32($0.count), Self.transient) }
        guard rc == SQLITE_OK else { throw AnalysisDatabaseError.write }
    }
    private func string(_ s: OpaquePointer?, _ i: Int32) -> String? {
        sqlite3_column_text(s, i).map { String(cString: $0) }
    }
    private func blob(_ s: OpaquePointer?, _ i: Int32) -> Data? {
        guard let p = sqlite3_column_blob(s, i) else { return nil }
        let n = Int(sqlite3_column_bytes(s, i))
        guard n <= 4 * 1024 * 1024 else { return nil }
        return Data(bytes: p, count: n)
    }
}
