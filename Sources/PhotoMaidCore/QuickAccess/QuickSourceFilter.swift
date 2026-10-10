import Foundation

/// Was eine Schnellzugriff-Abfrage über ein Medium wissen muss: nur Metadaten der Mediathek (PhotoKit), keine
/// Bildanalyse und keine Dateigröße.
public struct QuickMediaFacts: Hashable, Sendable {
    public let id: String
    public let kind: MediaKind
    public let creationDate: Date?
    /// Sekunden (Videos); Fotos 0.
    public let duration: Double
    public let isFavorite: Bool
    public let isLivePhoto: Bool
    /// Porträtmodus (Tiefeneffekt).
    public let isPortrait: Bool

    public init(id: String, kind: MediaKind, creationDate: Date?, duration: Double = 0, isFavorite: Bool = false,
                isLivePhoto: Bool = false, isPortrait: Bool = false) {
        self.id = id
        self.kind = kind
        self.creationDate = creationDate
        self.duration = duration
        self.isFavorite = isFavorite
        self.isLivePhoto = isLivePhoto
        self.isPortrait = isPortrait
    }

    var isReviewable: Bool { kind == .photo || kind == .screenshot || kind == .video }
}

/// Rahmen einer Abfrage. Uhr, Zufall und Sammlungen der Fotos-App kommen von außen – der Kern liest nichts selbst.
public struct QuickQueryContext: Sendable {
    public var now: Date
    public var timeZone: TimeZone
    /// Wochenbeginn der Region (1 = Sonntag, 2 = Montag).
    public var firstWeekday: Int
    /// Mitglieder der Sammlung bei `.album` und `.selfies`; `nil` = nicht lesbar → leer.
    public var members: Set<String>?
    /// Noch offene Medien (dieselbe Regel wie der Feed). Nur „Zufällig“ wählt daraus; `nil` = alle gelten als offen.
    public var open: Set<String>?
    /// Startwert für „Zufällig“ (App: bei jedem Öffnen neu; Tests: fest).
    public var seed: UInt64

    public init(now: Date, timeZone: TimeZone, firstWeekday: Int, members: Set<String>? = nil, open: Set<String>? = nil,
                seed: UInt64 = 0) {
        self.now = now
        self.timeZone = timeZone
        self.firstWeekday = firstWeekday
        self.members = members
        self.open = open
        self.seed = seed
    }
}

/// Zahlen einer Quelle für „Heute“ und den Katalog: Mitglieder und davon offene.
public struct QuickSourceCount: Hashable, Sendable {
    public let members: Int
    public let open: Int

    public init(members: Int, open: Int) {
        self.members = members
        self.open = open
    }
}

/// Reine Abfragen der Schnellzugriffe. `media` kommt neueste zuerst (wie die Mediathek); die Reihenfolge bleibt
/// erhalten – außer bei „Zufällig“. Eine Quelle entscheidet nie etwas, sie liefert nur Kandidaten.
public enum QuickSourceFilter {
    public static func select<T>(_ item: QuickAccessItem, in media: [T], facts: (T) -> QuickMediaFacts,
                                 context: QuickQueryContext) -> [T] {
        switch item.kind {
        case .random:
            let pool = media.filter { m in
                let f = facts(m)
                return f.isReviewable && (context.open?.contains(f.id) ?? true)
            }
            return sample(pool, count: QuickAccess.randomLimit, seed: context.seed)
        case .latestPhotos:
            return first(QuickAccess.latestPhotosLimit, of: media) { facts($0).kind == .photo }
        case .latestVideos:
            return first(QuickAccess.latestVideosLimit, of: media) { facts($0).kind == .video }
        case .thisWeek:
            let w = QuickAccess.thisWeek(now: context.now, timeZone: context.timeZone, firstWeekday: context.firstWeekday)
            return media.filter { m in facts(m).creationDate.map { $0 >= w.start && $0 < w.end } ?? false }
        case .onThisDay:
            let day = CalendarDay(context.now, timeZone: context.timeZone)
            return media.filter { day.isSameDayInEarlierYear(facts($0).creationDate) }
        case .album, .selfies:
            guard let members = context.members, !members.isEmpty else { return [] }
            return media.filter { m in
                let f = facts(m)
                return f.isReviewable && members.contains(f.id)
            }
        case .photos, .videos, .screenshots, .longVideos, .portraits, .livePhotos, .favorites:
            return media.filter { matches(item.kind, facts($0)) }
        }
    }

    /// Mitglieder und offene. „Zufällig“ zählt ohne zu mischen: höchstens `randomLimit` je Öffnen.
    public static func count<T>(_ item: QuickAccessItem, in media: [T], facts: (T) -> QuickMediaFacts,
                                context: QuickQueryContext) -> QuickSourceCount {
        if item.kind == .random {
            var all = 0
            var open = 0
            for m in media {
                let f = facts(m)
                guard f.isReviewable else { continue }
                all += 1
                if context.open?.contains(f.id) ?? true { open += 1 }
            }
            return QuickSourceCount(members: min(all, QuickAccess.randomLimit), open: min(open, QuickAccess.randomLimit))
        }
        var ctx = context
        ctx.open = nil
        let list = select(item, in: media, facts: facts, context: ctx)
        guard let openIDs = context.open else { return QuickSourceCount(members: list.count, open: list.count) }
        return QuickSourceCount(members: list.count, open: list.reduce(0) { $0 + (openIDs.contains(facts($1).id) ? 1 : 0) })
    }

    /// Einfache Merkmalsfilter (ohne Sammlung, Datum oder Zufall).
    static func matches(_ kind: QuickSourceKind, _ f: QuickMediaFacts) -> Bool {
        switch kind {
        case .photos: f.kind == .photo || f.kind == .screenshot
        case .videos: f.kind == .video
        case .screenshots: f.kind == .screenshot
        case .longVideos: f.kind == .video && f.duration >= QuickAccess.longVideoSeconds
        case .portraits: f.kind == .photo && f.isPortrait
        case .livePhotos: f.kind == .photo && f.isLivePhoto
        case .favorites: f.isReviewable && f.isFavorite
        case .random, .latestPhotos, .latestVideos, .thisWeek, .onThisDay, .album, .selfies: f.isReviewable
        }
    }

    /// Gleicher Kalendertag (Monat und Tag, lokale Zeitzone) in einem früheren Jahr. Am 28. Februar eines
    /// Nicht-Schaltjahrs zählt auch der 29. Februar. Ohne Aufnahmedatum: nie.
    public static func isOnThisDay(_ date: Date?, now: Date, timeZone: TimeZone) -> Bool {
        CalendarDay(now, timeZone: timeZone).isSameDayInEarlierYear(date)
    }

    static func first<T>(_ n: Int, of media: [T], where include: (T) -> Bool) -> [T] {
        var out: [T] = []
        guard n > 0 else { return out }
        for m in media where include(m) {
            out.append(m)
            if out.count == n { break }
        }
        return out
    }

    /// Höchstens `count` Elemente in zufälliger Reihenfolge (teilweises Fisher-Yates, reproduzierbar je Startwert).
    public static func sample<T>(_ items: [T], count: Int, seed: UInt64) -> [T] {
        var pool = items
        var rng = SeededGenerator(seed: seed)
        let k = max(0, min(count, pool.count))
        for i in 0..<k {
            let j = Int.random(in: i..<pool.count, using: &rng)
            if i != j { pool.swapAt(i, j) }
        }
        return Array(pool.prefix(k))
    }
}

/// Heutiger Kalendertag einmal zerlegt (nicht je Medium neu).
struct CalendarDay {
    private let calendar: Calendar
    private let year: Int
    private let month: Int
    private let day: Int
    private let februaryHas29: Bool

    init(_ now: Date, timeZone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: now)
        calendar = cal
        year = c.year ?? 0
        month = c.month ?? 0
        day = c.day ?? 0
        februaryHas29 = cal.date(from: DateComponents(year: year, month: 2, day: 1))
            .flatMap { cal.range(of: .day, in: .month, for: $0)?.count } == 29
    }

    func isSameDayInEarlierYear(_ date: Date?) -> Bool {
        guard let date else { return false }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day, y < year, m == month else { return false }
        if d == day { return true }
        return month == 2 && day == 28 && d == 29 && !februaryHas29
    }
}
