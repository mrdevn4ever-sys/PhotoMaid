import Testing
import Foundation
@testable import PhotoMaidCore

@Suite("Später 2.0")
struct LaterTests {
    @Test("Voreinstellungen: Morgen, 7 Tage, 30 Tage (Kalenderarithmetik)")
    func presets() {
        let today = LocalDay(year: 2026, month: 1, day: 31)
        #expect(LaterPreset.tomorrow.dueDay(from: today) == LocalDay(year: 2026, month: 2, day: 1))
        #expect(LaterPreset.sevenDays.dueDay(from: today) == LocalDay(year: 2026, month: 2, day: 7))
        #expect(LaterPreset.thirtyDays.dueDay(from: today) == LocalDay(year: 2026, month: 3, day: 2))
        #expect(LocalDay(year: 2028, month: 2, day: 28).adding(days: 1) == LocalDay(year: 2028, month: 2, day: 29))
    }

    @Test("Drehrad-Intervalle: Tage, Wochen, Monate (Monatsende gekürzt)")
    func intervals() {
        let d = LocalDay(year: 2026, month: 1, day: 31)
        #expect(LaterInterval(value: 2, unit: .days).dueDay(from: d) == LocalDay(year: 2026, month: 2, day: 2))
        #expect(LaterInterval(value: 3, unit: .weeks).dueDay(from: d) == LocalDay(year: 2026, month: 2, day: 21))
        #expect(LaterInterval(value: 1, unit: .months).dueDay(from: d) == LocalDay(year: 2026, month: 2, day: 28))
        #expect(LaterInterval(value: 1, unit: .months).dueDay(from: LocalDay(year: 2028, month: 1, day: 31))
                == LocalDay(year: 2028, month: 2, day: 29))
        #expect(LaterInterval(value: 0, unit: .days).value == 1, "mindestens 1")
        #expect(LaterInterval.defaultQuick == LaterInterval(value: 2, unit: .days))
    }

    @Test("Sommerzeit: kurz vor Mitternacht vor der Umstellung ist 'Morgen' der nächste Kalendertag")
    func daylightSaving() {
        let clock = TestClock("2026-03-28T23:30") // Europe/Zurich, Umstellung am 29.03.
        let today = clock.today
        #expect(LaterPreset.tomorrow.dueDay(from: today) == LocalDay(year: 2026, month: 3, day: 29))
        // Naive 24-h-Arithmetik wäre falsch (landet am 30.03.):
        let naive = LocalDay(clock.now.addingTimeInterval(24 * 3600), timeZone: clock.timeZone)
        #expect(naive == LocalDay(year: 2026, month: 3, day: 30))
        // Herbst-Umstellung
        clock.set("2026-10-24T23:30")
        #expect(LaterPreset.sevenDays.dueDay(from: clock.today) == LocalDay(year: 2026, month: 10, day: 31))
        // Tagesbeginn existiert und ist eindeutig
        let start = LocalDay(year: 2026, month: 3, day: 29).startOfDay(in: clock.timeZone)
        #expect(LocalDay(start, timeZone: clock.timeZone) == LocalDay(year: 2026, month: 3, day: 29))
    }

    @Test("Mitternacht: fällig ab 00:00 des Termintags")
    func midnight() {
        var r = ItemRecord(item: photo(1))
        r.disposition = .later
        r.dueDay = LocalDay(year: 2026, month: 6, day: 11)
        let clock = TestClock("2026-06-10T23:59")
        #expect(ReviewQueues.laterStatus(r, today: clock.today) == .upcoming(r.dueDay!))
        clock.set("2026-06-11T00:00")
        #expect(ReviewQueues.laterStatus(r, today: clock.today) == .due(r.dueDay!))
    }

    @Test("Zeitzonenwechsel: Fälligkeit folgt dem lokalen Kalendertag")
    func timeZoneChange() {
        var r = ItemRecord(item: photo(1))
        r.disposition = .later
        r.dueDay = LocalDay(year: 2026, month: 6, day: 11)
        let clock = TestClock("2026-06-11T02:00") // Zürich: fällig
        #expect(ReviewQueues.laterStatus(r, today: clock.today) == .due(r.dueDay!))
        clock.setTimeZone("America/New_York") // gleicher Instant = 10.06. 20:00 in New York
        #expect(ReviewQueues.laterStatus(r, today: clock.today) == .upcoming(r.dueDay!))
    }

    @Test("Vor Fälligkeit aus normalen Queues ausgeschlossen, ab Fälligkeit nur im Wieder-fällig-Bereich")
    func queues() async throws {
        let clock = TestClock("2026-06-10T10:00")
        let ledger = try makeLedger(clock: clock)
        let s1 = ReviewSessionID()
        try await ledger.decide(photo(1), .later(session: s1), session: s1)
        try await ledger.decide(photo(1), .schedule(LocalDay(year: 2026, month: 6, day: 11)))
        try await ledger.decide(photo(2), .later(session: s1), session: s1) // nur Session
        let candidates = [photo(1), photo(2), photo(3)]
        var recs = await ledger.records(for: candidates)
        #expect(ReviewQueues.normalQueue(candidates: candidates, records: recs, session: s1, today: clock.today) == [photo(3)])
        let s2 = ReviewSessionID()
        #expect(ReviewQueues.normalQueue(candidates: candidates, records: recs, session: s2, today: clock.today) == [photo(2), photo(3)])
        #expect(ReviewQueues.dueQueue(records: Array(recs.values), session: s2, today: clock.today).isEmpty)
        clock.set("2026-06-11T08:00")
        #expect(ReviewQueues.dueQueue(records: Array(recs.values), session: s2, today: clock.today) == [photo(1)])

        // Fälliges Item erneut ohne Datum auf Später: nur Session überspringen, Fälligkeit bleibt.
        try await ledger.decide(photo(1), .later(session: s2), session: s2)
        recs = await ledger.records(for: candidates)
        #expect(recs[photo(1)]!.dueDay == LocalDay(year: 2026, month: 6, day: 11))
        #expect(ReviewQueues.dueQueue(records: Array(recs.values), session: s2, today: clock.today).isEmpty)
        #expect(ReviewQueues.dueQueue(records: Array(recs.values), session: ReviewSessionID(), today: clock.today) == [photo(1)])
    }

    @Test("Neustart: Termin bleibt erhalten, kein Auto-Delete")
    func restartKeepsSchedule() async throws {
        let p = InMemoryLedgerPersistence()
        let clock = TestClock("2026-06-10T10:00")
        let ledger = try makeLedger(clock: clock, persistence: p)
        try await ledger.decide(photo(1), .later(session: ReviewSessionID()))
        try await ledger.decide(photo(1), .schedule(LocalDay(year: 2026, month: 6, day: 17)))
        clock.set("2026-08-01T10:00")
        let reloaded = try makeLedger(clock: clock, persistence: p)
        let r = await reloaded.record(for: photo(1))
        #expect(r.disposition == .later)
        #expect(r.dueDay == LocalDay(year: 2026, month: 6, day: 17))
        #expect(await reloaded.basket().isEmpty)
    }

    @Test("Später-Gruppen nach echten Daten")
    func groups() {
        let today = LocalDay(year: 2026, month: 6, day: 10)
        func rec(_ n: Int, _ d: LocalDay?) -> ItemRecord {
            var r = ItemRecord(item: photo(n)); r.disposition = .later; r.dueDay = d; return r
        }
        let g = ReviewQueues.laterGroups(records: [
            rec(1, LocalDay(year: 2026, month: 6, day: 9)),
            rec(2, LocalDay(year: 2026, month: 6, day: 11)),
            rec(3, LocalDay(year: 2026, month: 6, day: 17)),
            rec(4, LocalDay(year: 2026, month: 7, day: 10)),
            rec(5, nil),
        ], today: today)
        #expect(g.map(\.key) == [.due, .tomorrow, .withinSevenDays, .later(LocalDay(year: 2026, month: 7, day: 10)), .noDate])
    }
}
