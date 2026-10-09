import Testing
import Foundation
@testable import PhotoMaidCore

/// Ports von `OrganizeTest.kt`, `TimelineTest.kt`, `SlideshowTest.kt`, `QuickAccessTest.kt`, `ShareTest.kt`,
/// `CleanupSavingsTest.kt` – plus iOS-eigene Alben-Baum-Tests.
@Suite struct OrganizeTests {
    @Test func rematchPrefersIdThenUniqueFingerprintAndListsTheRest() {
        let a = MediaRef(id: "1", name: "IMG_1.jpg", size: 100, takenMillis: 1000)
        let b = MediaRef(id: "2", name: "IMG_2.jpg", size: 200, takenMillis: 2000)
        let c = MediaRef(id: "3", name: "IMG_3.jpg", size: nil, takenMillis: nil)
        let gone = MediaRef(id: "9", name: "IMG_9.jpg", size: 900, takenMillis: 9000)
        let now = [MediaRef(id: "1", name: "IMG_1.jpg", size: 100, takenMillis: 1000),
                   MediaRef(id: "22", name: "img_2.JPG", size: 200, takenMillis: 2000)]
        let r = Rematch.resolve(stored: [a, b, c, gone], current: now) { $0 }
        #expect(Set(r.found.keys) == ["1", "2"])
        #expect(r.moved == ["2": "22"])
        #expect(r.missing == ["3", "9"])
    }

    @Test func rematchNeverGuessesBetweenTwoCandidates() {
        let r = Rematch.resolve(stored: [MediaRef(id: "old", name: "same.jpg", size: 5, takenMillis: 7)],
                                current: [MediaRef(id: "x", name: "same.jpg", size: 5, takenMillis: 7),
                                          MediaRef(id: "y", name: "same.jpg", size: 5, takenMillis: 7)]) { $0 }
        #expect(r.missing == ["old"])
        let r2 = Rematch.resolve(stored: [MediaRef(id: "o1", name: "same.jpg", size: 5, takenMillis: 7),
                                          MediaRef(id: "o2", name: "same.jpg", size: 5, takenMillis: 7)],
                                 current: [MediaRef(id: "x", name: "same.jpg", size: 5, takenMillis: 7)]) { $0 }
        #expect(r2.missing == ["o1", "o2"])
        let r3 = Rematch.resolve(stored: [MediaRef(id: "x", name: "same.jpg", size: 5, takenMillis: 7),
                                          MediaRef(id: "o", name: "same.jpg", size: 5, takenMillis: 7)],
                                 current: [MediaRef(id: "x", name: "same.jpg", size: 5, takenMillis: 7)]) { $0 }
        #expect(r3.missing == ["o"])
    }

    @Test func tagsAreTrimmedDedupedAccentAndCaseInsensitive() {
        #expect(TagRules.normalize("  #Rechnung ") == "Rechnung")
        #expect(TagRules.normalize("Noch   drucken") == "Noch drucken")
        #expect(TagRules.normalize(" # ") == nil)
        #expect(TagRules.normalize(String(repeating: "x", count: 99))?.count == TagRules.maxLength)
        #expect(TagRules.merge(["Café"], ["cafe", "Ferien", "FERIEN", ""]) == ["Café", "Ferien"])
        #expect(TagRules.remove(["Café", "Ferien"], "CAFE") == ["Ferien"])
        #expect(TagRules.merge([], (1...50).map { "t\($0)" }).count == TagRules.maxPerMedia)
    }

    @Test func tagStateAndCounts() {
        let sel = [["Ferien", "Familie"], ["ferien"], []]
        #expect(TagRules.state("Ferien", tagsOfSelection: sel) == .some)
        #expect(TagRules.state("Ferien", tagsOfSelection: Array(sel.prefix(2))) == .all)
        #expect(TagRules.state("Wohnung", tagsOfSelection: sel) == .none)
        let counts = TagRules.counts(["a": ["Ferien", "Wohnung"], "b": ["ferien"], "c": ["Auto"]])
        #expect(counts.map(\.tag) == ["Ferien", "Auto", "Wohnung"])
        #expect(counts.map(\.count) == [2, 1, 1])
    }

    @Test func notesAndAlbumNames() {
        #expect(NoteRules.normalize("   ") == nil)
        #expect(NoteRules.normalize(String(repeating: "n", count: 800))?.count == NoteRules.maxLength)
        #expect(AlbumRules.normalizeName("  Ferien   2026 ") == "Ferien 2026")
        #expect(AlbumRules.normalizeName(" ") == nil)
        #expect(AlbumRules.uniqueName(existing: ["ferien"], wanted: "Ferien") == "Ferien (2)")
        #expect(AlbumRules.uniqueName(existing: ["Ferien", "Ferien (2)"], wanted: "Ferien") == "Ferien (3)")
        #expect(AlbumRules.uniqueName(existing: ["Ferien"], wanted: "Ferien", ignore: "Ferien") == "Ferien")
    }

    @Test func albumAndBasketKeepOrderAndSkipDuplicates() {
        let (list, added) = AlbumRules.add(["a", "b"], ["b", "c", "c", "d"])
        #expect(list == ["a", "b", "c", "d"])
        #expect(added == 2)
        let (basket, n) = BasketRules.add((0..<(BasketRules.max - 1)).map { "x\($0)" }, ["y", "z"])
        #expect(basket.count == BasketRules.max)
        #expect(n == 1)
        #expect(basket.last == "y")
    }
}

@Suite struct LibraryTests {
    let tz = TimeZone(identifier: "Europe/Zurich")!
    struct M { let id: String; let at: Date? }
    var items: [M] {
        let iso = ISO8601DateFormatter()
        return [M(id: "a", at: iso.date(from: "2026-10-01T22:30:00Z")), M(id: "b", at: iso.date(from: "2026-10-01T08:00:00Z")),
                M(id: "c", at: iso.date(from: "2026-09-15T08:00:00Z")), M(id: "d", at: iso.date(from: "2025-12-31T23:30:00Z")),
                M(id: "e", at: nil)]
    }

    @Test func groupsByDayInLocalTimeNewestFirstUnknownLast() {
        let s = Timeline.sections(items, date: { $0.at }, level: .day, timeZone: tz)
        #expect(s.dropLast().map(\.key) == [TimelineKey(year: 2026, month: 10, day: 2), TimelineKey(year: 2026, month: 10, day: 1),
                                            TimelineKey(year: 2026, month: 9, day: 15), TimelineKey(year: 2026, month: 1, day: 1)])
        #expect(s.last?.key.unknown == true)
        #expect(s.last?.items.map(\.id) == ["e"])
    }

    @Test func monthAndYearLevels() {
        let m = Timeline.sections(items, date: { $0.at }, level: .month, timeZone: tz)
        #expect(m.first?.items.map(\.id) == ["a", "b"])
        let y = Timeline.sections(items, date: { $0.at }, level: .year, timeZone: tz)
        #expect(y.first?.key == TimelineKey(year: 2026))
        #expect(y.first?.items.count == 4)
        #expect(TimelineLevel.day.coarser == .month)
        #expect(TimelineLevel.day.finer == .day)
        #expect(TimelineLevel.year.coarser == .year)
    }

    @Test func searchIgnoresAccentsCaseAndSharpS() {
        let fields = [SearchText.normalize("Café Zürich Straße"), SearchText.normalize("Été 2026")]
        #expect(SearchText.matches(SearchText.tokens("cafe"), fields: fields))
        #expect(SearchText.matches(SearchText.tokens("ZURICH strasse"), fields: fields))
        #expect(SearchText.matches(SearchText.tokens("ete"), fields: fields))
        #expect(SearchText.matches(SearchText.tokens("été"), fields: fields))
        #expect(!SearchText.matches(SearchText.tokens("cafe bern"), fields: fields))
        #expect(!SearchText.matches(SearchText.tokens("   "), fields: fields))
        #expect(SearchText.normalize("Øb") == "ob")
    }

    @Test func naturalOrderAndSort() {
        #expect(NaturalOrder.less("IMG_2", "IMG_10"))
        #expect(!NaturalOrder.less("img_10", "IMG_2"))
        #expect(NaturalOrder.compare("Ä1", "a1") == 0)
        struct F { let n: String?; let s: Int64? }
        let list = [F(n: "b10", s: nil), F(n: "b2", s: 5), F(n: nil, s: 9)]
        #expect(MediaSort.name.sort(list, date: { _ in nil }, added: { _ in nil }, name: { $0.n }, size: { $0.s }).map(\.n) == ["b2", "b10", nil])
        #expect(MediaSort.largest.sort(list, date: { _ in nil }, added: { _ in nil }, name: { $0.n }, size: { $0.s }).map(\.s) == [9, 5, nil])
    }

    @Test func albumTreeOrdersRowsSearchesAndCountsDescendants() {
        let d = Date(timeIntervalSince1970: 1_000)
        let tree = [
            AlbumNode(id: "f1", title: "Reisen", isFolder: true, own: 0, latest: nil, children: [
                AlbumNode(id: "a2", title: "Rom 2", isFolder: false, own: 3, latest: d),
                AlbumNode(id: "a10", title: "Rom 10", isFolder: false, own: 5, latest: d.addingTimeInterval(10)),
            ]),
            AlbumNode(id: "a1", title: "Café", isFolder: false, own: 2, latest: d.addingTimeInterval(-10)),
            AlbumNode(id: "empty", title: "Leer", isFolder: true, own: 0, latest: nil),
        ]
        let ordered = AlbumTree.order(tree, sort: .name)
        #expect(ordered.map(\.id) == ["a1", "f1"]) // leerer Ordner entfällt
        #expect(ordered[1].children.map(\.id) == ["a2", "a10"]) // natürliche Reihenfolge
        #expect(ordered[1].total == 8)
        #expect(AlbumTree.order(tree, sort: .recent).first?.id == "f1")
        #expect(AlbumTree.rows(ordered, expanded: []).count == 2)
        #expect(AlbumTree.rows(ordered, expanded: ["f1"]).map(\.depth) == [0, 0, 1, 1])
        #expect(AlbumTree.search(ordered, query: "cafe").map(\.id) == ["a1"])
        #expect(AlbumTree.search(ordered, query: "rom").map(\.id) == ["a2", "a10"])
        #expect(AlbumTree.find(ordered, id: "a10")?.title == "Rom 10")
        #expect(AlbumTree.descendantIDs(ordered[1]) == ["f1", "a2", "a10"])
    }

    @Test func slideshowOrders() {
        struct S: Hashable { let id: Int; let album: String?; let t: Date? }
        let items = (0..<30).map { i in
            S(id: i, album: ["A", "B", "C", nil][i % 4], t: i == 7 ? nil : Date(timeIntervalSince1970: Double(1000 - i)))
        }
        func run(_ s: SlideshowSettings, _ seed: UInt64 = 42) -> [S] {
            Slideshow.order(items, settings: s, seed: seed, album: { $0.album }, date: { $0.t })
        }
        var chrono = SlideshowSettings()
        chrono.order = .chronological
        let c = run(chrono)
        #expect(c.last?.id == 7)
        let dated = c.dropLast().map { $0.t! }
        #expect(dated == dated.sorted())
        var random = SlideshowSettings()
        random.order = .random
        let a = run(random)
        #expect(Set(a) == Set(items) && a.count == items.count)
        #expect(a == run(random))
        #expect(a != run(random, 7))
        for within in [false, true] {
            var s = SlideshowSettings()
            s.order = .albumsRandom
            s.shuffleWithinAlbum = within
            let r = run(s)
            #expect(Set(r) == Set(items))
            var blocks: [String?] = []
            for x in r where blocks.isEmpty || blocks.last! != x.album { blocks.append(x.album) }
            #expect(blocks.count == 4)
        }
    }
}

@Suite struct QuickAccessShareTests {
    func q(_ k: QuickSourceKind, _ a: String? = nil) -> QuickAccessItem { QuickAccessItem(kind: k, album: a) }

    @Test func defaultsArePhotosAndVideos() { #expect(QuickAccess.defaults == [q(.photos), q(.videos)]) }

    @Test func addRemoveMoveAndLimit() {
        var l = QuickAccess.defaults
        l = QuickAccess.add(l, q(.photos))
        #expect(l.count == 2)
        for k in [QuickSourceKind.screenshots, .latestPhotos, .latestVideos, .thisWeek] { l = QuickAccess.add(l, q(k)) }
        #expect(l.count == QuickAccess.maxItems)
        #expect(!QuickAccess.canAdd(l, q(.album, "X/L0/040")))
        l = QuickAccess.move(l, q(.thisWeek), by: -1)
        #expect(l[4].kind == .thisWeek)
        #expect(QuickAccess.move(l, q(.photos), by: -1) == l)
        l = QuickAccess.remove(l, q(.videos))
        #expect(l.count == 5)
        #expect(QuickAccess.add([q(.album, "A")], q(.album, "B")).count == 2)
    }

    @Test func sanitizeAndPersistence() throws {
        let raw = [q(.photos), q(.photos), q(.album, nil)] + (0..<8).map { q(.album, "A\($0)") }
        let s = QuickAccess.sanitize(raw)
        #expect(s.count == 6 && s[0].kind == .photos)
        // Gespeichert wird nur Art (+ Album-Kennung), keine Medien-IDs.
        let json = String(data: try JSONEncoder().encode(q(.latestPhotos)), encoding: .utf8)
        #expect(json == #"{"kind":"latestPhotos"}"#)
    }

    @Test func thisWeekIsLocalCalendarWeek() {
        let zurich = TimeZone(identifier: "Europe/Zurich")!
        let iso = ISO8601DateFormatter()
        let w = QuickAccess.thisWeek(now: iso.date(from: "2026-09-30T08:00:00Z")!, timeZone: zurich, firstWeekday: 2)
        #expect(w.start == iso.date(from: "2026-09-27T22:00:00Z"))
        #expect(w.end == iso.date(from: "2026-10-04T22:00:00Z"))
        let w2 = QuickAccess.thisWeek(now: iso.date(from: "2026-10-04T21:30:00Z")!, timeZone: zurich, firstWeekday: 2)
        #expect(w2.start == w.start)
        let us = QuickAccess.thisWeek(now: iso.date(from: "2026-09-30T08:00:00Z")!, timeZone: TimeZone(identifier: "America/New_York")!,
                                      firstWeekday: 1)
        #expect(us.start == iso.date(from: "2026-09-27T04:00:00Z"))
    }

    @Test func acceptsOnlyPhotosAndVideos() {
        #expect(ShareRules.accepts("image/jpeg") && ShareRules.accepts("VIDEO/mp4") && ShareRules.accepts("public.heic"))
        #expect(!ShareRules.accepts("application/pdf") && !ShareRules.accepts(nil) && !ShareRules.accepts("text/plain"))
    }

    @Test func matchNeedsNameAndSizeAndNeverGuesses() {
        let lib = [LibraryFingerprint(id: "a", name: "IMG_1.jpg", size: 100), LibraryFingerprint(id: "b", name: "img_2.jpg", size: 200),
                   LibraryFingerprint(id: "c", name: "img_2.jpg", size: 200)]
        #expect(ShareMatch.unique(name: "img_1.JPG", size: 100, candidates: lib) == "a")
        #expect(ShareMatch.unique(name: "img_2.jpg", size: 200, candidates: lib) == nil)
        #expect(ShareMatch.unique(name: "IMG_1.jpg", size: nil, candidates: lib) == nil)
        #expect(ShareMatch.unique(name: "IMG_1.jpg", size: 0, candidates: lib) == nil)
        #expect(ShareMatch.unique(name: nil, size: 100, candidates: lib) == nil)
        #expect(ShareMatch.unique(name: "IMG_1.jpg", size: 101, candidates: lib) == nil)
    }

    @Test func intakeCountsRejectedUnmatchedAndDeduplicates() {
        let items = [SharedItem(url: "u1", type: "image/jpeg"), SharedItem(url: "u2", type: "application/pdf"),
                     SharedItem(url: "u3", type: "video/mp4"), SharedItem(url: "u1b", type: "image/jpeg"),
                     SharedItem(url: "u4", type: "image/png")]
        let ids = ["u1": "m1", "u1b": "m1", "u3": "m3"]
        let r = ShareIntake.of(items) { ids[$0.url] }
        #expect(r.matched == ["m1", "m3"])
        #expect(r.unmatched == 1 && r.rejected == 1 && r.overflow == 0)
        let many = (0..<(ShareRules.maxItems + 3)).map { SharedItem(url: "u\($0)", type: "image/jpeg") }
        let r2 = ShareIntake.of(many) { $0.url }
        #expect(r2.matched.count == ShareRules.maxItems && r2.overflow == 3)
    }

    @Test func actionsNeverIncludeADecision() {
        #expect(ShareActions.available(matched: 0).isEmpty)
        #expect(ShareActions.available(matched: 1).contains(.edit))
        #expect(!ShareActions.available(matched: 2).contains(.edit))
        #expect(Set(ShareAction.allCases.map(\.rawValue)) == ["workflow", "edit", "pdf", "album", "basket"])
    }

    @Test func shortcutIdsRoundTripAndPlan() {
        for t in ShortcutTarget.fixed + [.workflow("abc")] { #expect(ShortcutTarget.parse(t.id) == t) }
        #expect(ShortcutTarget.parse("delete") == nil && ShortcutTarget.parse("wf:") == nil && ShortcutTarget.parse(nil) == nil)
        let p = ShortcutTarget.plan(workflowIDs: ["1", "2", "3", "4", "5", "1"], max: 15)
        #expect(p.count == 8)
        #expect(Array(p.prefix(4)) == ShortcutTarget.fixed)
        #expect(ShortcutTarget.plan(workflowIDs: ["1", "2"], max: 5).count == 5)
        #expect(ShortcutTarget.plan(workflowIDs: ["1"], max: 3).count == 3)
    }

    @Test func onlyRemovedItemsWithKnownSizeCount() {
        let sizes: [ItemReference: KnownSize] = [photo(1): .known(3_000_000), photo(2): .unknown, photo(3): .known(9_999_999)]
        let s = CleanupSavings.of(removed: [photo(1), photo(2)], sizes: sizes)
        #expect(s.bytes == 3_000_000 && s.unknownCount == 1 && s.removedCount == 2 && s.isLowerBound)
        let all = CleanupSavings.of(removed: [photo(1)], sizes: sizes)
        #expect(!all.isLowerBound)
        let total = SavingsTotal().adding(all).adding(s)
        #expect(total.bytes == 6_000_000 && total.lowerBound)
        #expect(CleanupSavings.of(removed: [photo(4)], sizes: sizes).unknownCount == 1)
    }
}
