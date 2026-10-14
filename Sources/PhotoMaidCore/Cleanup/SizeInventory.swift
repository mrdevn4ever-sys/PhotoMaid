import Foundation

/// Ergebnis einer Größenmessung. Unbekannt ist nie 0 und wird nie geschätzt – aber der Grund wird unterschieden:
/// `notLocal` = Original liegt nur in iCloud (iOS nennt die Größe ohne Download nicht öffentlich),
/// `unreadable` = lokal, aber nicht lesbar.
public enum MeasureState: String, Codable, Sendable {
    case known, notLocal, unreadable
}

/// Gespeicherte Messung je Medium. Gilt nur, solange das Änderungsdatum gleich ist. Optional die Prüfsummen für die
/// Duplikatsuche (erste 64 KB und vollständig) – bleiben nur lokal.
public struct SizeRecord: Codable, Sendable, Equatable {
    public var modified: Date?
    public var state: MeasureState
    public var bytes: Int64?
    public var checkedAt: Date
    public var partialHash: String?
    public var fullHash: String?

    public init(modified: Date?, state: MeasureState, bytes: Int64? = nil, checkedAt: Date,
                partialHash: String? = nil, fullHash: String? = nil) {
        self.modified = modified
        self.state = state
        self.bytes = state == .known ? bytes : nil
        self.checkedAt = checkedAt
        self.partialHash = partialHash
        self.fullHash = fullHash
    }

    public var size: KnownSize {
        if state == .known, let bytes { return .known(bytes) }
        return .unknown
    }

    public func isCurrent(modified: Date?) -> Bool { self.modified == modified }
}

/// Was die Inventur über ein Medium wissen muss (ohne PhotoKit).
public struct InventoryItem: Sendable, Equatable {
    public let id: String
    public let modified: Date?
    public let isVideo: Bool
    public let width: Int
    public let height: Int
    public let duration: TimeInterval

    public init(id: String, modified: Date?, isVideo: Bool, width: Int, height: Int, duration: TimeInterval) {
        self.id = id
        self.modified = modified
        self.isVideo = isVideo
        self.width = width
        self.height = height
        self.duration = duration
    }
}

/// Zählung für die Anzeige: gemessen, noch nicht gemessen, nur in iCloud, nicht lesbar.
public struct SizeCounts: Equatable, Sendable {
    public var known = 0
    public var notMeasured = 0
    public var notLocal = 0
    public var unreadable = 0
    public init() {}
    public var total: Int { known + notMeasured + notLocal + unreadable }
}

public enum SizeInventory {
    /// Nur in iCloud bzw. nicht lesbar wird nach dieser Zeit erneut geprüft (z. B. inzwischen geladen).
    public static let recheckNotLocal: TimeInterval = 12 * 3600
    public static let recheckUnreadable: TimeInterval = 24 * 3600

    /// Muss (erneut) gemessen werden? Fehlt, Medium geändert, oder ein „unbekannt“ ist alt genug für eine neue Prüfung.
    public static func needsMeasure(_ item: InventoryItem, record: SizeRecord?, now: Date) -> Bool {
        guard let record, record.isCurrent(modified: item.modified) else { return true }
        switch record.state {
        case .known: return false
        case .notLocal: return now.timeIntervalSince(record.checkedAt) >= recheckNotLocal || record.checkedAt > now
        case .unreadable: return now.timeIntervalSince(record.checkedAt) >= recheckUnreadable || record.checkedAt > now
        }
    }

    /// Reihenfolge der Messung: Videos zuerst (längste zuerst – meist die größten), danach Fotos nach Pixelzahl.
    /// So erscheinen die großen Treffer früh; gemessen wird trotzdem alles.
    public static func order(_ items: [InventoryItem]) -> [InventoryItem] {
        items.sorted { a, b in
            if a.isVideo != b.isVideo { return a.isVideo }
            if a.isVideo, a.duration != b.duration { return a.duration > b.duration }
            let pa = a.width * a.height, pb = b.width * b.height
            if pa != pb { return pa > pb }
            return a.id < b.id
        }
    }

    public static func counts(_ items: [InventoryItem], records: [String: SizeRecord]) -> SizeCounts {
        var c = SizeCounts()
        for item in items {
            guard let r = records[item.id], r.isCurrent(modified: item.modified) else { c.notMeasured += 1; continue }
            switch r.state {
            case .known: c.known += 1
            case .notLocal: c.notLocal += 1
            case .unreadable: c.unreadable += 1
            }
        }
        return c
    }
}

/// Byte-gleiche Dateien haben zwingend dieselbe Art (Foto/Video), dieselben Pixelmaße und dieselbe Dauer. Nur Medien,
/// die diese Merkmale mit mindestens einem anderen teilen, müssen überhaupt gemessen und verglichen werden.
/// Notwendige Bedingung, keine Ähnlichkeitsaussage: verglichen wird danach immer Byte für Byte (SHA-256).
public enum DuplicatePrefilter {
    public struct Shape: Hashable, Sendable {
        public let isVideo: Bool
        public let width: Int
        public let height: Int
        public let durationMs: Int64
    }

    public static func shape(_ item: InventoryItem) -> Shape {
        Shape(isVideo: item.isVideo, width: item.width, height: item.height,
              durationMs: item.isVideo && item.duration.isFinite ? Int64((item.duration * 1000).rounded()) : 0)
    }

    /// Kennungen aller Medien, deren Merkmale mindestens ein weiteres Medium teilt (Reihenfolge wie die Eingabe).
    public static func candidates(_ items: [InventoryItem]) -> [String] {
        var counts: [Shape: Int] = [:]
        for item in items { counts[shape(item), default: 0] += 1 }
        return items.filter { counts[shape($0), default: 0] >= 2 }.map(\.id)
    }
}
