import Foundation

/// Art einer Review-Quelle für Schnellzugriffe. Eine Quelle ist nur eine Abfrage; sie hat KEINEN eigenen
/// Entscheidungszustand. Entscheidungen hängen am Medium (Ledger).
/// Neue Arten nur ANHÄNGEN: gespeichert wird der Rohwert, vorhandene Schnellzugriffe bleiben lesbar.
public enum QuickSourceKind: String, Hashable, Codable, Sendable, CaseIterable {
    case photos, videos, screenshots, latestPhotos, latestVideos, thisWeek
    /// iOS: ein Album der Fotos-App (Android: Ordner).
    case album
    /// Zufällige Auswahl offener Medien, bei jedem Öffnen neu gemischt.
    case random
    /// Aufnahmen vom heutigen Kalendertag aus früheren Jahren.
    case onThisDay
    /// Videos ab `QuickAccess.longVideoSeconds` (Länge aus PhotoKit, keine geschätzte Dateigröße).
    case longVideos
    /// Smart-Album „Selfies“ der Fotos-App (Frontkamera laut PhotoKit, keine Bildanalyse).
    case selfies
    /// Fotos im Porträtmodus (PhotoKit-Untertyp Tiefeneffekt).
    case portraits
    case livePhotos
    /// Favoriten der Fotos-App.
    case favorites

    /// Mitglieder kommen aus einer Sammlung der Fotos-App (Album bzw. Smart-Album) und werden je Abfrage gelesen.
    public var readsCollection: Bool { self == .album || self == .selfies }

    /// Der Feed darf die Reihenfolge wechseln. „Zufällig“ behält die gemischte Reihenfolge.
    public var isOrderable: Bool { self != .random }
}

/// Ein Schnellzugriff. `album` nur bei `.album` (`PHAssetCollection.localIdentifier`, keine Medien-IDs).
public struct QuickAccessItem: Hashable, Codable, Sendable, Identifiable {
    public let kind: QuickSourceKind
    public let album: String?

    public init(kind: QuickSourceKind, album: String? = nil) {
        self.kind = kind
        self.album = album
    }

    public var key: String { album.map { "\(kind.rawValue):\($0)" } ?? kind.rawValue }
    public var id: String { key }
}

public enum QuickAccess {
    /// Bewusst begrenzt: drei Reihen à zwei Kacheln, Heute bleibt ruhig.
    public static let maxItems = 6
    public static let latestPhotosLimit = 50
    public static let latestVideosLimit = 20
    /// „Zufällig“: so viele offene Medien je Öffnen.
    public static let randomLimit = 50
    /// „Lange Videos“: ab dieser Länge in Sekunden.
    public static let longVideoSeconds: Double = 60

    /// Reihenfolge im Katalog „Schnellzugriff hinzufügen“ (Alben folgen darunter).
    public static let catalogue: [QuickSourceKind] = [
        .random, .photos, .videos, .screenshots, .latestPhotos, .latestVideos, .thisWeek,
        .onThisDay, .longVideos, .selfies, .portraits, .livePhotos, .favorites,
    ]

    public static let defaults = [QuickAccessItem(kind: .photos), QuickAccessItem(kind: .videos)]

    public static func canAdd(_ list: [QuickAccessItem], _ item: QuickAccessItem) -> Bool {
        list.count < maxItems && !list.contains { $0.key == item.key }
    }

    public static func add(_ list: [QuickAccessItem], _ item: QuickAccessItem) -> [QuickAccessItem] {
        canAdd(list, item) ? list + [item] : list
    }

    public static func remove(_ list: [QuickAccessItem], _ item: QuickAccessItem) -> [QuickAccessItem] {
        list.filter { $0.key != item.key }
    }

    /// Um eine Position verschieben (−1 = nach vorn, +1 = nach hinten); am Rand ohne Wirkung.
    public static func move(_ list: [QuickAccessItem], _ item: QuickAccessItem, by delta: Int) -> [QuickAccessItem] {
        guard let i = list.firstIndex(where: { $0.key == item.key }), list.indices.contains(i + delta) else { return list }
        var out = list
        let e = out.remove(at: i)
        out.insert(e, at: i + delta)
        return out
    }

    /// Gespeicherten Stand bereinigen (Duplikate, Überlänge, Album ohne Kennung).
    public static func sanitize(_ list: [QuickAccessItem]) -> [QuickAccessItem] {
        var seen = Set<String>()
        return Array(list.filter { $0.kind != .album || !($0.album ?? "").isEmpty }
            .filter { seen.insert($0.key).inserted }
            .prefix(maxItems))
    }

    /// Aktuelle lokale Kalenderwoche [Beginn, Ende) nach Wochenbeginn der Region (Deutsch: Montag).
    public static func thisWeek(now: Date, timeZone: TimeZone, firstWeekday: Int) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = firstWeekday
        let today = LocalDay(now, timeZone: timeZone)
        let weekday = cal.component(.weekday, from: today.startOfDay(in: timeZone))
        let back = (weekday - firstWeekday + 7) % 7
        let start = today.adding(days: -back)
        return (start.startOfDay(in: timeZone), start.adding(days: 7).startOfDay(in: timeZone))
    }
}
