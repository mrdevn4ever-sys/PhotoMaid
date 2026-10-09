import Foundation

// Sicherung der PhotoMaid-Daten: eine kleine JSON-Datei, die der Nutzer selbst irgendwo ablegt (Dateien-App).
// Sie enthält KEINE Fotos – nur Entscheidungen, Schlagwörter, Notizen, Auswahlkorb, Ausgeblendetes und Einstellungen.
// Gleiches Format wie Android (`photomaid-backup` v1): eine Android-Sicherung lässt sich auf dem iPhone lesen
// (Medien werden über Name, Größe und Aufnahmezeit wiedergefunden). Was nicht eindeutig ist, wird gezeigt – nie geraten.
// Wiederherstellen überschreibt nie etwas, das auf diesem Gerät schon entschieden oder eingetragen ist.

/// Beliebiger JSON-Wert (für `extras`, deren Inhalt die App selbst zuordnet).
public enum JSONValue: Hashable, Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Wandelt einen kodierbaren Wert in JSON um (und zurück).
    public static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}

public struct BackupRef: Hashable, Codable, Sendable {
    public let id: String
    public var name: String?
    public var size: Int64?
    public var taken: Int64?

    public init(id: String, name: String? = nil, size: Int64? = nil, taken: Int64? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.taken = taken
    }

    public var mediaRef: MediaRef { MediaRef(id: id, name: name, size: size, takenMillis: taken) }
    public static func of(_ r: MediaRef) -> BackupRef { BackupRef(id: r.id, name: r.name, size: r.size, taken: r.takenMillis) }
}

/// Gesicherter Zustand einer Entscheidung (nur Endzustände, kein Verlauf).
public enum BackupState: String, Hashable, Codable, Sendable { case kept = "KEPT", marked = "MARKED", later = "LATER" }

public struct BackupDecision: Hashable, Codable, Sendable {
    public let ref: Int
    public let state: BackupState
    public var due: LocalDay?
    public var bookmarked = false

    public init(ref: Int, state: BackupState, due: LocalDay? = nil, bookmarked: Bool = false) {
        self.ref = ref
        self.state = state
        self.due = due
        self.bookmarked = bookmarked
    }

    private enum CodingKeys: String, CodingKey { case ref, state, due, bookmarked }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ref = try c.decode(Int.self, forKey: .ref)
        state = try c.decode(BackupState.self, forKey: .state)
        due = try c.decodeIfPresent(LocalDay.self, forKey: .due)
        bookmarked = try c.decodeIfPresent(Bool.self, forKey: .bookmarked) ?? false
    }
}

/// PhotoMaid-eigenes Album aus einer Android-Sicherung (auf iOS als Album der Fotos-App angelegt, E5).
public struct BackupAlbum: Hashable, Codable, Sendable {
    public let name: String
    public let createdAt: Int64
    public let items: [Int]
    public init(name: String, createdAt: Int64, items: [Int]) {
        self.name = name
        self.createdAt = createdAt
        self.items = items
    }
}

public struct PhotoMaidBackup: Hashable, Codable, Sendable {
    public static let format = "photomaid-backup"
    public static let version = 1

    public var format: String = PhotoMaidBackup.format
    public var version: Int = PhotoMaidBackup.version
    public var createdAt: Int64
    public var appVersion: String
    /// Alle bezeichneten Medien; alles andere verweist per Index hierauf.
    public var refs: [BackupRef] = []
    public var decisions: [BackupDecision] = []
    public var albums: [BackupAlbum] = []
    /// Index → Schlagwörter.
    public var tags: [Int: [String]] = [:]
    public var notes: [Int: String] = [:]
    public var basket: [Int] = []
    public var hiddenMedia: [Int] = []
    /// App-Teile ohne Medienbezug (Einstellungen, Abläufe, Vorlagen, Sammlungen, Schnellzugriffe).
    public var extras: [String: JSONValue] = [:]

    public init(createdAt: Int64, appVersion: String) {
        self.createdAt = createdAt
        self.appVersion = appVersion
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, createdAt, appVersion, refs, decisions, albums, tags, notes, basket, hiddenMedia, extras
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        refs = try c.decodeIfPresent([BackupRef].self, forKey: .refs) ?? []
        decisions = try c.decodeIfPresent([BackupDecision].self, forKey: .decisions) ?? []
        albums = try c.decodeIfPresent([BackupAlbum].self, forKey: .albums) ?? []
        tags = try Self.intKeyed(c, .tags)
        notes = try Self.intKeyed(c, .notes)
        basket = try c.decodeIfPresent([Int].self, forKey: .basket) ?? []
        hiddenMedia = try c.decodeIfPresent([Int].self, forKey: .hiddenMedia) ?? []
        extras = try c.decodeIfPresent([String: JSONValue].self, forKey: .extras) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(version, forKey: .version)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(appVersion, forKey: .appVersion)
        try c.encode(refs, forKey: .refs)
        try c.encode(decisions, forKey: .decisions)
        try c.encode(albums, forKey: .albums)
        // Wie kotlinx: Zahl-Schlüssel als Text („0“), sortiert für eine stabile Datei.
        try c.encode(Dictionary(uniqueKeysWithValues: tags.map { (String($0.key), $0.value) }), forKey: .tags)
        try c.encode(Dictionary(uniqueKeysWithValues: notes.map { (String($0.key), $0.value) }), forKey: .notes)
        try c.encode(basket, forKey: .basket)
        try c.encode(hiddenMedia, forKey: .hiddenMedia)
        try c.encode(extras, forKey: .extras)
    }

    private static func intKeyed<V: Decodable>(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) throws -> [Int: V] {
        guard let raw = try c.decodeIfPresent([String: V].self, forKey: k) else { return [:] }
        var out: [Int: V] = [:]
        for (key, v) in raw { if let i = Int(key) { out[i] = v } }
        return out
    }
}

/// Was sich aus einer Datei lesen lässt.
public enum BackupCheck: Hashable, Sendable {
    case ok(PhotoMaidBackup)
    /// Keine PhotoMaid-Sicherung (anderes Format, beschädigt).
    case notABackup
    /// Aus einer neueren PhotoMaid-Version – lieber nicht halb übernehmen.
    case tooNew(Int)
}

public enum BackupRules {
    /// Höchstens so groß wird eine Sicherungsdatei gelesen (sie enthält keine Medien).
    public static let maxBytes = 32 * 1024 * 1024

    public static func check(_ decoded: PhotoMaidBackup?) -> BackupCheck {
        guard let d = decoded, d.format == PhotoMaidBackup.format else { return .notABackup }
        if d.version > PhotoMaidBackup.version { return .tooNew(d.version) }
        return .ok(d)
    }

    public static func check(data: Data) -> BackupCheck {
        guard data.count <= maxBytes else { return .notABackup }
        return check(try? JSONDecoder().decode(PhotoMaidBackup.self, from: data))
    }

    public static func state(_ d: Disposition) -> BackupState? {
        switch d {
        case .kept: .kept
        case .markedForCleanup: .marked
        case .later: .later
        // Unentschieden muss nicht gesichert werden; Entferntes existiert nicht mehr.
        case .undecided, .removed: nil
        }
    }
}

/// Baut die Bezugsliste (jede ID genau einmal) und liefert Indizes.
public struct BackupRefTable: Sendable {
    private var index: [String: Int] = [:]
    public private(set) var refs: [BackupRef] = []
    public init() {}

    public mutating func add(_ ref: MediaRef) -> Int {
        if let i = index[ref.id] { return i }
        refs.append(.of(ref))
        index[ref.id] = refs.count - 1
        return refs.count - 1
    }
}

/// Wiederherstellen: was übernommen wird – berechnet, bevor irgendetwas geschrieben wird („Das passiert“).
public struct RestorePlan: Hashable, Sendable {
    /// Aktuelle Medien-ID → Zustand (nur für hier noch unentschiedene Medien).
    public let decisions: [String: BackupDecision]
    /// Hier schon entschieden – bleibt, wie es ist.
    public let decisionsKeptLocal: Int
    /// Albumname → aktuelle Medien-IDs (nie leer); vorhandene Alben gleichen Namens werden ergänzt.
    public let albums: [AlbumPlan]
    public let newAlbums: Int
    public let tags: [String: [String]]
    /// Nur Notizen für Medien ohne eigene Notiz.
    public let notes: [String: String]
    public let basket: [String]
    public let hidden: [String]
    /// Nicht (eindeutig) wiedergefundene Medien – werden als Liste gezeigt.
    public let missing: [BackupRef]

    public struct AlbumPlan: Hashable, Sendable {
        public let name: String
        public let items: [String]
    }

    public var extendedAlbums: Int { Set(albums.map { SearchText.normalize($0.name) }).count - newAlbums }

    public var isEmpty: Bool {
        decisions.isEmpty && albums.isEmpty && tags.isEmpty && notes.isEmpty && basket.isEmpty && hidden.isEmpty
    }
}

public enum BackupRestore {
    /// `current`: alle Medien dieses Geräts. `dispositions`: aktueller Zustand je Medien-ID (fehlend = unentschieden).
    /// `albumNames`: vorhandene Alben. `notesPresent`: Medien, die hier schon eine Notiz haben.
    public static func plan<T>(_ b: PhotoMaidBackup, current: [T], ref: (T) -> MediaRef,
                               dispositions: [String: Disposition], albumNames: [String],
                               notesPresent: Set<String>) -> RestorePlan {
        var used = Set<Int>()
        b.decisions.forEach { used.insert($0.ref) }
        b.albums.forEach { used.formUnion($0.items) }
        used.formUnion(b.tags.keys); used.formUnion(b.notes.keys); used.formUnion(b.basket); used.formUnion(b.hiddenMedia)
        let storedIdx = used.filter { b.refs.indices.contains($0) }.sorted()
        let stored = storedIdx.map { b.refs[$0] }
        let r = Rematch.resolve(stored: stored.map(\.mediaRef), current: current, ref: ref)
        func now(_ i: Int) -> String? {
            guard b.refs.indices.contains(i), let c = r.found[b.refs[i].id] else { return nil }
            return ref(c).id
        }
        var decisions: [String: BackupDecision] = [:]
        var keptLocal = 0
        for d in b.decisions {
            guard let id = now(d.ref) else { continue }
            if (dispositions[id] ?? .undecided) != .undecided { keptLocal += 1; continue }
            if decisions[id] == nil { decisions[id] = d }
        }
        let existingKeys = Set(albumNames.map(SearchText.normalize))
        // Ein Album, von dem hier nichts wiederzufinden ist, wird nicht leer angelegt.
        let albums: [RestorePlan.AlbumPlan] = b.albums.compactMap { a in
            guard let name = AlbumRules.normalizeName(a.name) else { return nil }
            var seen = Set<String>()
            let items = a.items.compactMap(now).filter { seen.insert($0).inserted }
            return items.isEmpty ? nil : RestorePlan.AlbumPlan(name: name, items: items)
        }
        let newAlbums = Set(albums.map { SearchText.normalize($0.name) }).filter { !existingKeys.contains($0) }.count
        var tags: [String: [String]] = [:]
        for (i, list) in b.tags.sorted(by: { $0.key < $1.key }) {
            guard let id = now(i) else { continue }
            let clean = list.compactMap(TagRules.normalize)
            if !clean.isEmpty { tags[id] = TagRules.merge(tags[id] ?? [], clean) }
        }
        var notes: [String: String] = [:]
        for (i, text) in b.notes {
            guard let id = now(i), !notesPresent.contains(id), let n = NoteRules.normalize(text) else { continue }
            notes[id] = n
        }
        func distinctIDs(_ list: [Int]) -> [String] {
            var seen = Set<String>()
            return list.compactMap(now).filter { seen.insert($0).inserted }
        }
        let byId = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return RestorePlan(decisions: decisions, decisionsKeptLocal: keptLocal, albums: albums, newAlbums: newAlbums,
                           tags: tags, notes: notes, basket: distinctIDs(b.basket), hidden: distinctIDs(b.hiddenMedia),
                           missing: r.missing.compactMap { byId[$0] })
    }
}
