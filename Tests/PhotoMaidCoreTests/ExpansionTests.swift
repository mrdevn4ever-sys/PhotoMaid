import Testing
import Foundation
@testable import PhotoMaidCore

/// Port von `Expansion202610Test.kt`: Werbeabstand, Später ohne Termin, Serien, Monate, Reihenfolge, Session-Hilfen.
@Suite struct ExpansionTests {
    let today = LocalDay(year: 2026, month: 10, day: 2)

    @Test func adCardNeedsSixtySecondsGapOnTopOfInterval() {
        var start = FeedAdState()
        start.decisionsTotal = 40
        start.sinceLastAd = 7
        let shown = FeedAdPolicy.onCardShown(start, today: today, nowMs: 1_000_000)
        let afterSeven = (1...7).reduce(shown) { s, _ in FeedAdPolicy.onDecision(s) }
        #expect(!FeedAdPolicy.isDue(afterSeven, today: today, nowMs: 1_030_000), "Takt erreicht, aber erst 30 s vergangen")
        #expect(FeedAdPolicy.isDue(afterSeven, today: today, nowMs: 1_060_000))
        #expect(FeedAdPolicy.isDue(afterSeven, today: today, nowMs: 500_000)) // Uhr zurückgestellt
        #expect(!FeedAdPolicy.isDue(FeedAdPolicy.onDecision(shown), today: today, nowMs: 2_000_000))
        #expect(FeedAdPolicy.isDue(start, today: today, nowMs: 1))
    }

    @Test func bookmarkIsLaterWithoutDateAndNeverReturnsOnItsOwn() async throws {
        let l = try makeLedger()
        let s = ReviewSessionID()
        try await l.decide(photo(1), .later(session: s), session: s)
        try await l.decide(photo(1), .bookmark)
        let r = await l.record(for: photo(1))
        #expect(r.disposition == .later)
        #expect(r.bookmarked)
        #expect(r.dueDay == nil)
        #expect(ReviewQueues.laterStatus(r, today: today) == .bookmarked)
        #expect(ReviewQueues.normalQueue(candidates: [photo(1)], records: [photo(1): r], session: ReviewSessionID(), today: today).isEmpty)
        #expect(ReviewQueues.dueQueue(records: [r], session: ReviewSessionID(), today: LocalDay(year: 2030, month: 1, day: 1)).isEmpty)
        #expect(ReviewQueues.laterGroups(records: [r], today: today).map(\.key) == [.bookmarked])
        try await l.decide(photo(1), .removeDeferral)
        let back = await l.record(for: photo(1))
        #expect(back.disposition == .undecided)
        #expect(!back.bookmarked)
    }

    @Test func scheduleClearsBookmarkAndBookmarkNeedsLater() throws {
        let bookmarked = ItemRecord(item: photo(1), revision: 3, disposition: .later, bookmarked: true)
        let scheduled = try DecisionRules.transition(bookmarked, .schedule(today.adding(days: 3))).get()
        #expect(!scheduled.bookmarked)
        #expect(scheduled.dueDay == today.adding(days: 3))
        guard case .failure(.invalidTransition) = DecisionRules.transition(ItemRecord(item: photo(2)), .bookmark) else {
            Issue.record("Bookmark ohne Später muss abgelehnt werden"); return
        }
    }

    @Test func undoOfLaterWithBookmarkRestoresOpenItem() async throws {
        let l = try makeLedger()
        let s = ReviewSessionID()
        let later = try await l.decide(photo(1), .later(session: s), session: s)
        let laterCmd = await l.events().last!.commandID
        try await l.apply(DecisionCommand(item: photo(1), expectedRevision: later.record.revision, action: .bookmark,
                                          amends: laterCmd))
        try await l.undo()
        let r = await l.record(for: photo(1))
        #expect(r.disposition == .undecided)
        #expect(!r.bookmarked)
    }

    @Test func removedItemThatIsBackCanBeDecidedAgain() async throws {
        let removed = ItemRecord(item: photo(1), revision: 4, disposition: .removed)
        #expect((try? DecisionRules.transition(removed, .keep).get())?.disposition == .kept)
        #expect((try? DecisionRules.transition(removed, .schedule(today)).get()) == nil)
        #expect(ReviewQueues.normalQueue(candidates: [photo(1)], records: [photo(1): removed], session: ReviewSessionID(), today: today) == [photo(1)])
    }

    @Test func seriesNeedSameGroupShortGapsAndThreeMembers() {
        let t0 = Date(timeIntervalSince1970: 1_788_256_800) // 2026-09-01T10:00:00Z
        func m(_ id: String, _ s: Double, _ g: String? = "camera") -> PhotoSeries.Member {
            PhotoSeries.Member(id: id, group: g, takenAt: t0.addingTimeInterval(s))
        }
        let items = [m("a", 0), m("b", 4), m("c", 12), m("d", 19), m("e", 60), m("f", 65),
                     m("g", 0, "Burst-1"), m("h", 1, "Burst-1"), m("i", 2, "burst-1"),
                     PhotoSeries.Member(id: "x", group: "camera", takenAt: nil), PhotoSeries.Member(id: "y", group: nil, takenAt: t0)]
        let g = PhotoSeries.groups(items)
        #expect(Set(g.map { Set($0.map(\.id)) }) == [["a", "b", "c", "d"], ["g", "h", "i"]])
        #expect(PhotoSeries.index(items)["e"] == nil)
        #expect(PhotoSeries.index(items)["c"]?.count == 4)
        #expect(PhotoSeries.groups([m("p", 0), m("q", 11), m("r", 22)]).isEmpty)
    }

    @Test func monthProgressCountsRealDecisionsOnly() {
        let tz = TimeZone(identifier: "Europe/Zurich")!
        let iso = ISO8601DateFormatter()
        let sep = iso.date(from: "2026-09-15T10:00:00Z")!, aug = iso.date(from: "2026-08-31T22:30:00Z")!
        let jul = iso.date(from: "2026-07-10T10:00:00Z")!
        let s = ReviewSessionID()
        let recs: [String: ItemRecord] = [
            "k": ItemRecord(item: photo(1), revision: 1, disposition: .kept),
            "t": ItemRecord(item: photo(2), revision: 1, disposition: .markedForCleanup),
            "l": ItemRecord(item: photo(3), revision: 1, disposition: .later, dueDay: today.adding(days: 2)),
            "b": ItemRecord(item: photo(4), revision: 1, disposition: .later, bookmarked: true),
            "s": ItemRecord(item: photo(5), revision: 1, disposition: .later, skippedInSession: s),
            "r": ItemRecord(item: photo(6), revision: 1, disposition: .removed),
        ]
        let items: [(String, Date)] = [("k", sep), ("t", sep), ("l", sep), ("b", aug), ("s", sep), ("r", sep), ("u", sep), ("j", jul)]
        let months = ProgressRules.months(items, date: { $0.1 }, record: { recs[$0.0] }, timeZone: tz)
        #expect(months.map(\.month) == [MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 7)])
        let september = months[0]
        #expect(september.total == 7)
        #expect(september.reviewed == 4)
        #expect(september.later == 2)
        #expect(september.state == .inProgress)
        #expect(months.last?.state == .notStarted)
        #expect(MonthKey.parse("2026-09") == MonthKey(year: 2026, month: 9))
        #expect(MonthKey(year: 2026, month: 9).description == "2026-09")
        #expect(MonthKey.parse("kaputt") == nil)
        #expect(MonthKey.parse("٢٠٢٦-٠٩") == MonthKey(year: 2026, month: 9)) // arabisch-indische Ziffern
    }

    @Test func orderingKeepsUnknownLastAndShuffleIsStable() {
        struct A { let id: String; let d: Date?; let size: Int64? }
        let t = Date(timeIntervalSince1970: 1_788_220_800)
        let list = [A(id: "1", d: t, size: 5), A(id: "2", d: t.addingTimeInterval(10), size: nil),
                    A(id: "3", d: nil, size: 9), A(id: "4", d: t.addingTimeInterval(-10), size: 7)]
        func ids(_ o: FeedOrder, _ seed: UInt64 = 1) -> [String] {
            FeedOrdering.apply(list, order: o, date: { $0.d }, size: { $0.size }, id: { $0.id }, seed: seed).map(\.id)
        }
        #expect(ids(.newest) == ["2", "1", "4", "3"])
        #expect(ids(.oldest) == ["4", "1", "2", "3"])
        #expect(ids(.largest) == ["3", "4", "1", "2"])
        #expect(ids(.random, 42) == ids(.random, 42))
        #expect(Set(ids(.random, 42)) == Set(list.map(\.id)))
    }

    @Test func sessionDropAndReorderOnlyTouchUpcoming() {
        var session = FeedSession(items: (1...6).map(photo))
        session.jump(to: 2)
        session.dropUpcoming([photo(1), photo(3), photo(5)])
        #expect(session.items == [photo(1), photo(2), photo(4), photo(6)])
        #expect(session.current == photo(4))
        session.reorderUpcoming { $0.reversed() }
        #expect(session.items == [photo(1), photo(2), photo(6), photo(4)])
        session.reorderUpcoming { Array($0.dropFirst()) } // unvollständige Liste wird ignoriert
        #expect(session.items.count == 4)
        session.recordDecision(photo(6), intent: .markForCleanup)
        session.recordDecision(photo(4), intent: .previous)
        #expect(session.summary.marked == 1)
        #expect(session.summary.reviewed == 1)
    }

    @Test func photosOlderThanOneYearIsBuiltIn() {
        #expect(SmartCollections.builtIns.contains { $0.source == .photos && $0.filter == .olderThan(days: 365) && $0.builtIn })
    }

    @Test func recordDecodesWithoutBookmarkField() throws {
        let json = #"{"item":{"provider":{"photoLibrary":{}},"localIdentifier":"A"},"revision":2,"disposition":"later"}"#
        let r = try JSONDecoder().decode(ItemRecord.self, from: Data(json.utf8))
        #expect(r.revision == 2 && r.disposition == .later && !r.bookmarked)
    }
}
