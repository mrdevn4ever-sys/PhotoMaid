import Testing
import Foundation
@testable import PhotoMaidCore

/// Neue Schnellzugriff-Quellen (iOS): Zufällig, An diesem Tag, Lange Videos, Selfies, Porträts, Live Photos, Favoriten.
@Suite struct QuickSourceFilterTests {
    let zurich = TimeZone(identifier: "Europe/Zurich")!

    func q(_ k: QuickSourceKind, _ a: String? = nil) -> QuickAccessItem { QuickAccessItem(kind: k, album: a) }

    func at(_ iso: String) -> Date { TestClock.date(iso, tz: "Europe/Zurich") }

    func ctx(_ now: String = "2026-10-10T12:00", members: Set<String>? = nil, open: Set<String>? = nil,
             seed: UInt64 = 7) -> QuickQueryContext {
        QuickQueryContext(now: at(now), timeZone: zurich, firstWeekday: 2, members: members, open: open, seed: seed)
    }

    func ids(_ l: [QuickMediaFacts]) -> [String] { l.map(\.id) }

    func select(_ k: QuickSourceKind, _ media: [QuickMediaFacts], _ c: QuickQueryContext, album: String? = nil) -> [QuickMediaFacts] {
        QuickSourceFilter.select(q(k, album), in: media, facts: { $0 }, context: c)
    }

    /// 120 Medien, neueste zuerst: Fotos, Screenshots, Videos gemischt.
    var library: [QuickMediaFacts] {
        (0..<120).map { i in
            let kind: MediaKind = i % 3 == 0 ? .video : (i % 3 == 1 ? .photo : .screenshot)
            return QuickMediaFacts(id: "M\(i)", kind: kind, creationDate: at("2026-10-01T10:00").addingTimeInterval(Double(-i) * 3600),
                                   duration: kind == .video ? Double(i) : 0)
        }
    }

    // MARK: Zufällig

    @Test func randomIsSeededAndBounded() {
        let a = select(.random, library, ctx(seed: 42))
        let b = select(.random, library, ctx(seed: 42))
        let c = select(.random, library, ctx(seed: 43))
        #expect(a.count == QuickAccess.randomLimit)
        #expect(ids(a) == ids(b))
        #expect(ids(a) != ids(c))
        #expect(Set(ids(a)).count == a.count)
        // Nicht einfach die neuesten: die Auswahl ist gemischt.
        #expect(ids(a) != ids(Array(library.prefix(QuickAccess.randomLimit))))
    }

    @Test func randomPicksOnlyOpenMediaAndNeverFiles() {
        var media = library
        media.append(QuickMediaFacts(id: "F1", kind: .file, creationDate: nil))
        let open: Set<String> = ["M1", "M2", "M3", "F1"]
        let r = select(.random, media, ctx(open: open))
        #expect(Set(ids(r)) == ["M1", "M2", "M3"])
        let none = select(.random, media, ctx(open: []))
        #expect(none.isEmpty)
        // Ohne Angabe gelten alle als offen.
        let all = select(.random, Array(library.prefix(10)), ctx())
        #expect(Set(ids(all)) == Set(ids(Array(library.prefix(10)))))
    }

    @Test func sampleIsPartialShuffle() {
        let items = Array(0..<1000)
        let s = QuickSourceFilter.sample(items, count: 50, seed: 1)
        #expect(s.count == 50 && Set(s).count == 50)
        #expect(s == QuickSourceFilter.sample(items, count: 50, seed: 1))
        #expect(QuickSourceFilter.sample(items, count: 5000, seed: 1).count == 1000)
        #expect(QuickSourceFilter.sample([Int](), count: 50, seed: 1).isEmpty)
        #expect(QuickSourceFilter.sample(items, count: 0, seed: 1).isEmpty)
    }

    @Test func randomCountIsStableAndHonest() {
        let open = Set(ids(Array(library.prefix(30))))
        let c = QuickSourceFilter.count(q(.random), in: library, facts: { $0 }, context: ctx(open: open))
        #expect(c == QuickSourceCount(members: QuickAccess.randomLimit, open: 30))
        let done = QuickSourceFilter.count(q(.random), in: library, facts: { $0 }, context: ctx(open: []))
        #expect(done == QuickSourceCount(members: QuickAccess.randomLimit, open: 0))
        let empty = QuickSourceFilter.count(q(.random), in: [QuickMediaFacts](), facts: { $0 }, context: ctx())
        #expect(empty == QuickSourceCount(members: 0, open: 0))
    }

    // MARK: An diesem Tag

    @Test func onThisDayMatchesEarlierYearsInLocalTime() {
        let media = [
            QuickMediaFacts(id: "y2025", kind: .photo, creationDate: at("2025-10-10T09:00")),
            QuickMediaFacts(id: "y2019", kind: .video, creationDate: at("2019-10-10T23:30")),
            QuickMediaFacts(id: "today", kind: .photo, creationDate: at("2026-10-10T08:00")),
            QuickMediaFacts(id: "dayBefore", kind: .photo, creationDate: at("2025-10-09T23:59")),
            QuickMediaFacts(id: "otherMonth", kind: .photo, creationDate: at("2025-09-10T12:00")),
            QuickMediaFacts(id: "noDate", kind: .photo, creationDate: nil),
        ]
        #expect(ids(select(.onThisDay, media, ctx())) == ["y2025", "y2019"])
        // 23:30 in Zürich ist in New York noch derselbe Tag, 00:30 am 11. in Zürich nicht mehr der 10.
        let late = [QuickMediaFacts(id: "z", kind: .photo, creationDate: at("2024-10-11T00:30"))]
        #expect(select(.onThisDay, late, ctx()).isEmpty)
        let ny = QuickQueryContext(now: at("2026-10-10T12:00"), timeZone: TimeZone(identifier: "America/New_York")!,
                                   firstWeekday: 1)
        #expect(ids(QuickSourceFilter.select(q(.onThisDay), in: late, facts: { $0 }, context: ny)) == ["z"])
    }

    @Test func onThisDayLeapDay() {
        let leap = QuickMediaFacts(id: "leap", kind: .photo, creationDate: at("2024-02-29T12:00"))
        let feb28 = QuickMediaFacts(id: "feb28", kind: .photo, creationDate: at("2023-02-28T12:00"))
        // 2027 ist kein Schaltjahr: am 28. Februar erscheint auch der 29. Februar.
        #expect(ids(select(.onThisDay, [leap, feb28], ctx("2027-02-28T10:00"))) == ["leap", "feb28"])
        #expect(select(.onThisDay, [leap], ctx("2027-03-01T10:00")).isEmpty)
        // 2028 ist ein Schaltjahr: der 29. gehört nur zum 29.
        #expect(ids(select(.onThisDay, [leap, feb28], ctx("2028-02-28T10:00"))) == ["feb28"])
        #expect(ids(select(.onThisDay, [leap, feb28], ctx("2028-02-29T10:00"))) == ["leap"])
    }

    // MARK: Merkmale aus PhotoKit

    @Test func longVideosByDurationOnly() {
        let media = [
            QuickMediaFacts(id: "short", kind: .video, creationDate: nil, duration: 59.9),
            QuickMediaFacts(id: "minute", kind: .video, creationDate: nil, duration: 60),
            QuickMediaFacts(id: "long", kind: .video, creationDate: nil, duration: 900),
            QuickMediaFacts(id: "photo", kind: .photo, creationDate: nil, duration: 3600),
        ]
        #expect(ids(select(.longVideos, media, ctx())) == ["minute", "long"])
    }

    @Test func portraitsLiveFavoritesAndSelfies() {
        let media = [
            QuickMediaFacts(id: "p", kind: .photo, creationDate: nil, isPortrait: true),
            QuickMediaFacts(id: "l", kind: .photo, creationDate: nil, isLivePhoto: true),
            QuickMediaFacts(id: "fv", kind: .video, creationDate: nil, isFavorite: true),
            QuickMediaFacts(id: "fp", kind: .photo, creationDate: nil, isFavorite: true, isPortrait: true),
            QuickMediaFacts(id: "s", kind: .screenshot, creationDate: nil, isPortrait: true),
            QuickMediaFacts(id: "file", kind: .file, creationDate: nil, isFavorite: true),
        ]
        #expect(ids(select(.portraits, media, ctx())) == ["p", "fp"])
        #expect(ids(select(.livePhotos, media, ctx())) == ["l"])
        #expect(ids(select(.favorites, media, ctx())) == ["fv", "fp"])
        #expect(ids(select(.selfies, media, ctx(members: ["l", "fv", "gone", "file"]))) == ["l", "fv"])
        // Smart-Album nicht lesbar → leer, nie „alles“.
        #expect(select(.selfies, media, ctx(members: nil)).isEmpty)
        #expect(select(.album, media, ctx(members: []), album: "A").isEmpty)
    }

    @Test func existingSourcesKeepTheirMeaning() {
        let lib = library
        #expect(select(.photos, lib, ctx()).count == 80)
        #expect(select(.videos, lib, ctx()).count == 40)
        #expect(select(.screenshots, lib, ctx()).count == 40)
        let latest = select(.latestPhotos, lib, ctx())
        #expect(latest.count == 40 && latest.allSatisfy { $0.kind == .photo })
        #expect(ids(select(.latestVideos, lib, ctx())) == ids(Array(lib.filter { $0.kind == .video }.prefix(20))))
        // Woche 5.–11. Oktober 2026 (Montag): Mediathek beginnt am 1. Oktober → nichts.
        #expect(select(.thisWeek, lib, ctx()).isEmpty)
        #expect(ids(select(.thisWeek, lib, ctx("2026-10-01T18:00"))) == ids(lib.filter { $0.creationDate! >= at("2026-09-28T00:00") }))
    }

    @Test func countUsesOpenSetForOrdinarySources() {
        let open: Set<String> = ["M0", "M3", "M1"]
        let c = QuickSourceFilter.count(q(.videos), in: library, facts: { $0 }, context: ctx(open: open))
        #expect(c == QuickSourceCount(members: 40, open: 2))
        let noOpenInfo = QuickSourceFilter.count(q(.videos), in: library, facts: { $0 }, context: ctx())
        #expect(noOpenInfo == QuickSourceCount(members: 40, open: 40))
    }

    // MARK: Modell und Speicherung

    @Test func newKindsPersistAndOldDataStillDecodes() throws {
        let old = #"[{"kind":"photos"},{"kind":"thisWeek"},{"kind":"album","album":"X/L0/040"}]"#
        let decoded = try JSONDecoder().decode([QuickAccessItem].self, from: Data(old.utf8))
        #expect(decoded == [q(.photos), q(.thisWeek), q(.album, "X/L0/040")])
        for k in QuickAccess.catalogue {
            let data = try JSONEncoder().encode(q(k))
            #expect(try JSONDecoder().decode(QuickAccessItem.self, from: data) == q(k))
        }
        #expect(String(data: try JSONEncoder().encode(q(.random)), encoding: .utf8) == #"{"kind":"random"}"#)
    }

    @Test func catalogueAndFlags() {
        #expect(Set(QuickAccess.catalogue) == Set(QuickSourceKind.allCases).subtracting([.album]))
        #expect(QuickAccess.catalogue.count == Set(QuickAccess.catalogue).count)
        #expect(QuickSourceKind.selfies.readsCollection && QuickSourceKind.album.readsCollection)
        #expect(!QuickSourceKind.random.readsCollection)
        #expect(!QuickSourceKind.random.isOrderable && QuickSourceKind.onThisDay.isOrderable)
        // Selfies ohne Album-Kennung bleiben beim Bereinigen erhalten (nur `.album` braucht eine Kennung).
        #expect(QuickAccess.sanitize([q(.selfies), q(.random)]) == [q(.selfies), q(.random)])
    }
}
