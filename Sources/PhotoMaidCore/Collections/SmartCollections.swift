import Foundation

/// Woraus eine Sammlung schöpft (Mediathek; für Dateien in Ordnern gibt es „Große Dateien“).
public enum CollectionSource: String, Hashable, Codable, Sendable, CaseIterable {
    case photos, videos, screenshots
}

/// Eine einzige, verständliche Bedingung. Keine Skripte, keine automatische Aktion.
public enum CollectionFilter: Hashable, Codable, Sendable {
    /// „größer als …“ – nur Elemente mit bekannter Größe; unbekannt zählt nie als groß (und nie als 0).
    case largerThan(bytes: Int64)
    /// „älter als …“ – nach Aufnahmedatum; ohne Datum nicht enthalten.
    case olderThan(days: Int)
}

public struct SmartCollectionID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Dauerhafte Sammlung: immer aktuell, jederzeit antippbar. Kein Auslöser, keine Aufgaben, keine Hintergrundarbeit,
/// niemals Löschung – sie öffnet nur den Feed mit den passenden, noch offenen Medien.
public struct SmartCollection: Hashable, Codable, Sendable, Identifiable {
    public let id: SmartCollectionID
    public var source: CollectionSource
    public var filter: CollectionFilter
    /// Fertige Sammlungen (für alle); eigene Sammlungen sind Pro.
    public let builtIn: Bool

    public init(id: SmartCollectionID = SmartCollectionID(), source: CollectionSource, filter: CollectionFilter,
                builtIn: Bool = false) {
        self.id = id
        self.source = source
        self.filter = filter
        self.builtIn = builtIn
    }
}

/// Ein tatsächlich gelesenes Element.
public struct CollectionCandidate: Hashable, Sendable {
    public let item: ItemReference
    public let createdAt: Date?
    public let size: KnownSize
    public init(item: ItemReference, createdAt: Date?, size: KnownSize) {
        self.item = item
        self.createdAt = createdAt
        self.size = size
    }
}

/// Aktueller Stand einer Sammlung.
public struct CollectionResult: Hashable, Sendable {
    /// Noch offene passende Elemente in Feed-Reihenfolge.
    public let items: [ItemReference]
    /// Summe der bekannten Größen dieser Elemente.
    public let knownBytes: Int64
    /// Elemente der Quelle mit unbekannter Größe (bei „größer als“ nicht enthalten – nur als Hinweis).
    public let unknownSizeCount: Int
}

public enum SmartCollections {
    public static let mb: Int64 = 1_000_000

    /// Fertige Sammlungen. Feste IDs, damit Zustand/Tests stabil bleiben.
    public static let builtIns: [SmartCollection] = [
        SmartCollection(id: fixed(1), source: .videos, filter: .largerThan(bytes: 100 * mb), builtIn: true),
        SmartCollection(id: fixed(2), source: .screenshots, filter: .olderThan(days: 30), builtIn: true),
        SmartCollection(id: fixed(3), source: .photos, filter: .largerThan(bytes: 10 * mb), builtIn: true),
        SmartCollection(id: fixed(4), source: .videos, filter: .olderThan(days: 365), builtIn: true),
        SmartCollection(id: fixed(5), source: .photos, filter: .olderThan(days: 365), builtIn: true),
    ]

    /// Schnellwahl je Quelle – passend zur Medienart statt eines +/−-Zählers.
    public static func sizeChoices(_ source: CollectionSource) -> [Int64] {
        switch source {
        case .videos: [50 * mb, 100 * mb, 500 * mb, 1_000 * mb]
        case .photos, .screenshots: [2 * mb, 5 * mb, 10 * mb, 20 * mb]
        }
    }

    public static let ageChoices = [30, 182, 365, 730]

    public static func evaluate(_ collection: SmartCollection, candidates: [CollectionCandidate],
                                records: [ItemReference: ItemRecord], now: Date, timeZone: TimeZone) -> CollectionResult {
        let today = LocalDay(now, timeZone: timeZone)
        let matching = candidates.filter { c in
            switch collection.filter {
            case .largerThan(let bytes): return (c.size.bytes ?? 0) > bytes && c.size.bytes != nil
            case .olderThan(let days):
                guard let d = c.createdAt else { return false }
                return LocalDay(d, timeZone: timeZone).adding(days: days) <= today
            }
        }
        // Gleiche Offen-Logik wie die normale Prüfung (entschiedene Elemente tauchen nicht wieder auf).
        let open = ReviewQueues.normalQueue(candidates: matching.map(\.item), records: records,
                                            session: ReviewSessionID(), today: today)
        let openSet = Set(open)
        let known = matching.filter { openSet.contains($0.item) }.reduce(Int64(0)) { $0 + ($1.size.bytes ?? 0) }
        var unknown = 0
        if case .largerThan = collection.filter {
            unknown = ReviewQueues.normalQueue(candidates: candidates.filter { $0.size.bytes == nil }.map(\.item),
                                               records: records, session: ReviewSessionID(), today: today).count
        }
        return CollectionResult(items: open, knownBytes: known, unknownSizeCount: unknown)
    }

    static func fixed(_ n: Int) -> SmartCollectionID {
        // Gleiches Bitmuster wie Android (UUID(0x50686f746f4d6169, n)).
        let hi: [UInt8] = [0x50, 0x68, 0x6f, 0x74, 0x6f, 0x4d, 0x61, 0x69]
        var lo = [UInt8](repeating: 0, count: 8)
        var v = UInt64(n)
        for i in (0..<8).reversed() { lo[i] = UInt8(v & 0xff); v >>= 8 }
        let b = hi + lo
        return SmartCollectionID(UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                             b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])))
    }
}
