import Foundation

/// Was der Mediathek-Filter über ein Medium wissen darf (nur Metadaten der Fotos-App, keine Bildanalyse).
public struct LibraryMediaFacts: Sendable, Equatable {
    public let id: String
    public let kind: MediaKind
    public let isFavorite: Bool
    public let isEdited: Bool
    public let isLivePhoto: Bool
    public let isPortrait: Bool
    public let isPanorama: Bool
    public let isSlowMotion: Bool
    public let isTimelapse: Bool
    public let isCinematic: Bool
    public let isScreenRecording: Bool

    public init(id: String, kind: MediaKind, isFavorite: Bool = false, isEdited: Bool = false, isLivePhoto: Bool = false,
                isPortrait: Bool = false, isPanorama: Bool = false, isSlowMotion: Bool = false, isTimelapse: Bool = false,
                isCinematic: Bool = false, isScreenRecording: Bool = false) {
        self.id = id
        self.kind = kind
        self.isFavorite = isFavorite
        self.isEdited = isEdited
        self.isLivePhoto = isLivePhoto
        self.isPortrait = isPortrait
        self.isPanorama = isPanorama
        self.isSlowMotion = isSlowMotion
        self.isTimelapse = isTimelapse
        self.isCinematic = isCinematic
        self.isScreenRecording = isScreenRecording
    }
}

/// Filter im Tab „Fotos“ wie in der Fotos-App: oben Alle · Favoriten · Bearbeitet · Fotos · Videos · Bildschirmfotos,
/// darunter „Medienarten“. Nur Ansicht: ändert nichts, entscheidet nichts.
public enum LibraryFilter: String, Codable, Sendable, CaseIterable {
    case all, favorites, edited, photos, videos, screenshots
    case selfies, livePhotos, portraits, panoramas, slowMotion, timelapse, cinematic, screenRecordings, raw

    public static let main: [LibraryFilter] = [.all, .favorites, .edited, .photos, .videos, .screenshots]
    public static let mediaTypes: [LibraryFilter] = [.selfies, .livePhotos, .portraits, .panoramas, .slowMotion, .timelapse,
                                                     .cinematic, .screenRecordings, .raw]

    /// Selfies und RAW kennt nur das jeweilige Smart-Album der Fotos-App: dessen Mitglieder werden übergeben.
    public var readsCollection: Bool { self == .selfies || self == .raw }

    /// `members`: Mitglieder des Smart-Albums (nur für `readsCollection`); `nil` = noch nicht geladen → nichts.
    public func accepts(_ f: LibraryMediaFacts, members: Set<String>? = nil) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return f.isFavorite
        case .edited: return f.isEdited
        case .photos: return f.kind == .photo || f.kind == .screenshot
        case .videos: return f.kind == .video
        case .screenshots: return f.kind == .screenshot
        case .livePhotos: return f.isLivePhoto && f.kind != .video
        case .portraits: return f.isPortrait && f.kind != .video
        case .panoramas: return f.isPanorama && f.kind != .video
        case .slowMotion: return f.isSlowMotion && f.kind == .video
        case .timelapse: return f.isTimelapse && f.kind == .video
        case .cinematic: return f.isCinematic && f.kind == .video
        case .screenRecordings: return f.isScreenRecording && f.kind == .video
        case .selfies, .raw: return members?.contains(f.id) ?? false
        }
    }

    /// Gefilterte Liste (Reihenfolge bleibt).
    public static func apply<T>(_ filter: LibraryFilter, to items: [T], facts: (T) -> LibraryMediaFacts,
                                members: Set<String>? = nil) -> [T] {
        filter == .all ? items : items.filter { filter.accepts(facts($0), members: members) }
    }
}

/// Reihenfolge im Tab „Fotos“ wie in der Fotos-App: nach Aufnahmedatum (Zeitachse) oder zuletzt hinzugefügt zuerst.
public enum LibraryOrder: String, Codable, Sendable, CaseIterable {
    case captured, added

    /// Zuletzt hinzugefügt zuerst. `rank`: Position in der Hinzufüge-Reihenfolge der Fotos-App (größer = später
    /// hinzugefügt). Ohne bekannte Position ans Ende, dort in der bisherigen Reihenfolge – nichts wird erfunden.
    public static func addedFirst<T>(_ items: [T], id: (T) -> String, rank: [String: Int]) -> [T] {
        let indexed = items.enumerated().map { (offset: $0.offset, item: $0.element, rank: rank[id($0.element)]) }
        return indexed.sorted { a, b in
            switch (a.rank, b.rank) {
            case let (x?, y?): return x == y ? a.offset < b.offset : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.item)
    }
}
