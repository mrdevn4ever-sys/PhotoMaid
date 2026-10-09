import Foundation

/// Reihenfolge der Diashow (nur Ansehen, nie eine Entscheidung).
public enum SlideshowOrder: String, Hashable, Codable, Sendable, CaseIterable {
    case chronological, random, albumsRandom
}

/// Übergang zwischen zwei Bildern.
public enum SlideshowTransition: String, Hashable, Codable, Sendable, CaseIterable { case fade, none }

/// Einstellungen der Diashow (gespeichert, keine Medien-IDs).
public struct SlideshowSettings: Hashable, Codable, Sendable {
    public var order: SlideshowOrder = .chronological
    /// Bei „Album für Album“: innerhalb eines Albums zufällig (sonst chronologisch).
    public var shuffleWithinAlbum = false
    public var seconds = 5
    public var transition: SlideshowTransition = .fade
    /// Videos ganz abspielen (stumm) statt überspringen.
    public var playVideos = true
    public var loop = false

    public static let secondsChoices = [3, 5, 8, 12]
    public init() {}
}

/// Reihenfolge einer Diashow. Fester Zufalls-Startwert je Start (wiederholbar, testbar).
/// - Chronologisch: älteste zuerst; Medien ohne Datum am Ende (keine erfundenen Daten).
/// - Zufällig: alle gemischt.
/// - Album für Album zufällig: Alben in zufälliger Reihenfolge, jedes zusammenhängend; innen chronologisch oder gemischt.
public enum Slideshow {
    public static func order<T>(_ items: [T], settings: SlideshowSettings, seed: UInt64, album: (T) -> String?,
                                date: (T) -> Date?) -> [T] {
        var rng = SeededGenerator(seed: seed)
        func chrono(_ list: [T]) -> [T] {
            list.sorted { a, b in
                switch (date(a), date(b)) {
                case let (x?, y?): return x < y
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
        switch settings.order {
        case .chronological:
            return chrono(items)
        case .random:
            return items.shuffled(using: &rng)
        case .albumsRandom:
            var groups: [String: [T]] = [:]
            for it in items { groups[album(it)?.lowercased() ?? "", default: []].append(it) }
            let keys = groups.keys.sorted().shuffled(using: &rng)
            return keys.flatMap { k -> [T] in
                let v = groups[k]!
                return settings.shuffleWithinAlbum ? v.shuffled(using: &rng) : chrono(v)
            }
        }
    }
}
