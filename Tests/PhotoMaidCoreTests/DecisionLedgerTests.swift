import Testing
import Foundation
@testable import PhotoMaidCore

@Suite("Entscheidungs-Ledger")
struct DecisionLedgerTests {
    @Test("Behalten, Vormerken, Später erzeugen je einen Verlaufseintrag")
    func basicDecisions() async throws {
        let ledger = try makeLedger()
        let s = ReviewSessionID()
        try await ledger.decide(photo(1), .keep, session: s)
        try await ledger.decide(photo(2), .markForCleanup, session: s)
        try await ledger.decide(photo(3), .later(session: s), session: s)
        #expect(await ledger.record(for: photo(1)).disposition == .kept)
        #expect(await ledger.record(for: photo(2)).disposition == .markedForCleanup)
        #expect(await ledger.record(for: photo(3)).disposition == .later)
        #expect(await ledger.events().count == 3)
        #expect(await ledger.basket().map(\.item) == [photo(2)])
    }

    @Test("Erneut dieselbe Entscheidung: keine doppelten Zähler oder Korbeinträge")
    func idempotent() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .markForCleanup)
        let again = try await ledger.decide(photo(1), .markForCleanup)
        guard case .unchanged = again else { Issue.record("expected unchanged"); return }
        #expect(await ledger.events().count == 1)
        #expect(await ledger.basket().count == 1)
        #expect(await ledger.record(for: photo(1)).revision == 1)
    }

    @Test("Wiederholte Command-ID wird nicht doppelt angewendet")
    func duplicateCommand() async throws {
        let ledger = try makeLedger()
        let cmd = DecisionCommand(item: photo(1), expectedRevision: 0, action: .keep)
        try await ledger.apply(cmd)
        let second = try await ledger.apply(cmd)
        guard case .duplicate = second else { Issue.record("expected duplicate"); return }
        #expect(await ledger.events().count == 1)
    }

    @Test("Veraltete Revision wird abgelehnt")
    func staleRevision() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .keep)
        await #expect(throws: DecisionError.staleRevision(expected: 0, actual: 1)) {
            try await ledger.apply(DecisionCommand(item: photo(1), expectedRevision: 0, action: .markForCleanup))
        }
    }

    @Test("Korrektur ersetzt den Stand atomar und ist als Korrektur im Verlauf")
    func correction() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .keep)
        try await ledger.decide(photo(1), .markForCleanup)
        let r = await ledger.record(for: photo(1))
        #expect(r.disposition == .markedForCleanup)
        #expect(r.revision == 2)
        #expect(await ledger.events().map(\.kind) == [.decision, .correction])
    }

    @Test("Undo stellt exakt den vorherigen Zustand wieder her")
    func undoRestores() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .keep)
        try await ledger.decide(photo(1), .markForCleanup)
        let r = try await ledger.undo()
        #expect(r.disposition == .kept)
        #expect(r.revision == 3)
        let r2 = try await ledger.undo()
        #expect(r2.disposition == .undecided)
        await #expect(throws: DecisionError.nothingToUndo) { try await ledger.undo() }
    }

    @Test("Undo überschreibt keine neuere Entscheidung (Bereinigung) und keine laufende Operation")
    func undoConflict() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .markForCleanup)
        let intent = try await ledger.prepareCleanup([photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        await #expect(throws: DecisionError.itemBusy) { try await ledger.undo() }
        #expect(await ledger.record(for: photo(1)).disposition == .markedForCleanup)
        try await ledger.markSubmitted(intent.id)
        try await ledger.reconcile(intent.id, outcome: .succeeded)
        #expect(await ledger.record(for: photo(1)).disposition == .removed)
        await #expect(throws: DecisionError.undoConflict) { try await ledger.undo() }
        #expect(await ledger.record(for: photo(1)).disposition == .removed)
        await #expect(throws: DecisionError.nothingToUndo) { try await ledger.undo() }
    }

    @Test("Undo eines anderen Items nach Korrektur: Reihenfolge bleibt korrekt")
    func undoInterleaved() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .keep)
        try await ledger.decide(photo(2), .markForCleanup)
        try await ledger.decide(photo(1), .markForCleanup)
        #expect(try await ledger.undo().disposition == .kept)             // Item 1
        #expect(try await ledger.undo().item == photo(2))                 // Item 2
        #expect(try await ledger.undo().disposition == .undecided)        // Item 1
        #expect(await ledger.record(for: photo(2)).disposition == .undecided)
    }

    @Test("Terminwahl gehört zur Später-Aktion: Undo nimmt beides zurück")
    func scheduleAmendsLater() async throws {
        let clock = TestClock("2026-06-10T10:00")
        let ledger = try makeLedger(clock: clock)
        let s = ReviewSessionID()
        let later = DecisionCommand(item: photo(1), expectedRevision: 0, action: .later(session: s))
        let r = try await ledger.apply(later, sessionID: s).record
        let day = LaterPreset.sevenDays.dueDay(from: clock.today)
        try await ledger.apply(DecisionCommand(item: photo(1), expectedRevision: r.revision,
                                               action: .schedule(day), amends: later.id))
        #expect(await ledger.record(for: photo(1)).dueDay == LocalDay(year: 2026, month: 6, day: 17))
        let undone = try await ledger.undo()
        #expect(undone.disposition == .undecided)
        #expect(undone.dueDay == nil)
        #expect(await ledger.canUndo() == false)
    }

    @Test("Persistenzfehler: keine stille Erfolgsmeldung, Zustand unverändert")
    func persistenceFailure() async throws {
        let p = InMemoryLedgerPersistence()
        let ledger = try makeLedger(persistence: p)
        p.failNextCommits = 1
        await #expect(throws: DecisionError.self) { try await ledger.decide(photo(1), .keep) }
        #expect(await ledger.record(for: photo(1)).disposition == .undecided)
        #expect(await ledger.events().isEmpty)
        #expect(await ledger.canUndo() == false)
        try await ledger.decide(photo(1), .keep)
        #expect(await ledger.record(for: photo(1)).disposition == .kept)
    }

    @Test("Neustart: Zustand wird vollständig aus der Persistenz geladen")
    func restart() async throws {
        let p = InMemoryLedgerPersistence()
        let ledger = try makeLedger(persistence: p)
        try await ledger.decide(photo(1), .markForCleanup)
        let reloaded = try makeLedger(persistence: p)
        #expect(await reloaded.record(for: photo(1)).disposition == .markedForCleanup)
        #expect(await reloaded.canUndo())
    }

    @Test("Behalten oder Vormerken löst einen aktiven Termin im selben Commit auf")
    func keepResolvesSchedule() async throws {
        let ledger = try makeLedger()
        let s = ReviewSessionID()
        try await ledger.decide(photo(1), .later(session: s))
        try await ledger.decide(photo(1), .schedule(LocalDay(year: 2026, month: 7, day: 1)))
        try await ledger.decide(photo(1), .keep)
        let r = await ledger.record(for: photo(1))
        #expect(r.dueDay == nil && r.disposition == .kept && r.skippedInSession == nil)
    }

    @Test("Zurückstellung entfernen macht Item wieder unentschieden (keine Löschung)")
    func removeDeferral() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .later(session: ReviewSessionID()))
        try await ledger.decide(photo(1), .removeDeferral)
        #expect(await ledger.record(for: photo(1)).disposition == .undecided)
        await #expect(throws: DecisionError.self) { try await ledger.decide(photo(1), .removeDeferral) }
    }

    @Test("Generierte Aktionsfolgen erhalten die Invarianten", arguments: [1, 2, 3, 4, 5] as [UInt64])
    func generatedSequences(seed: UInt64) async throws {
        var rng = SeededRNG(seed)
        let ledger = try makeLedger()
        let items = (0..<6).map(photo)
        let s = ReviewSessionID()
        var lastRevision: [ItemReference: Int] = [:]
        for _ in 0..<300 {
            let item = items.randomElement(using: &rng)!
            let choice = Int.random(in: 0..<7, using: &rng)
            do {
                switch choice {
                case 0: try await ledger.decide(item, .keep, session: s)
                case 1: try await ledger.decide(item, .markForCleanup, session: s)
                case 2: try await ledger.decide(item, .later(session: s), session: s)
                case 3: try await ledger.decide(item, .schedule(LocalDay(year: 2026, month: 7, day: 1)))
                case 4: try await ledger.decide(item, .unmark)
                case 5: try await ledger.decide(item, .removeDeferral)
                default: _ = try await ledger.undo()
                }
            } catch is DecisionError {}
            // Invarianten
            for i in items {
                let r = await ledger.record(for: i)
                #expect(r.revision >= lastRevision[i, default: 0], "Revision darf nie sinken")
                lastRevision[i] = r.revision
                if r.dueDay != nil { #expect(r.disposition == .later, "Termin nur bei Später") }
                #expect(r.disposition != .removed, "Keine Löschung ohne Operation")
            }
            let basket = await ledger.basket()
            #expect(Set(basket.map(\.item)).count == basket.count)
        }
        // Verlauf konsistent: letzte Event-Revision = Record-Revision
        let events = await ledger.events()
        for i in items {
            if let last = events.last(where: { $0.item == i }) {
                #expect(last.revision == (await ledger.record(for: i)).revision)
            }
        }
    }
}

@Suite("Ledger: Ergänzungen aus Android")
struct LedgerAndroidPortTests {
    /// Gerätetest K5: aus „Zuletzt gelöscht“ zurückgeholt (gleiche ID) → wieder offen und neu entscheidbar.
    @Test func restoredFromRecentlyDeletedIsPendingAgain() async throws {
        let ledger = try makeLedger()
        try await ledger.decide(photo(1), .markForCleanup)
        let intent = try await ledger.prepareCleanup([photo(1)], kind: .photoLibraryDelete, dailyLimit: 20)
        try await ledger.markSubmitted(intent.id)
        try await ledger.reconcile(intent.id, outcome: .succeeded)
        #expect(await ledger.record(for: photo(1)).disposition == .removed)
        let records = await ledger.records(for: [photo(1), photo(2)])
        #expect(ReviewQueues.normalQueue(candidates: [photo(1), photo(2)], records: records, session: ReviewSessionID(),
                                         today: LocalDay(year: 2026, month: 10, day: 2)) == [photo(1), photo(2)])
        try await ledger.decide(photo(1), .keep)
        #expect(await ledger.record(for: photo(1)).disposition == .kept)
        #expect(await ledger.events().last?.kind == .decision)
        #expect(try await ledger.undo().disposition == .removed)
        let r = await ledger.record(for: photo(1))
        guard case .failure = DecisionRules.transition(r, .unmark), case .failure = DecisionRules.transition(r, .removeDeferral) else {
            Issue.record("Markierungs-/Terminaktionen auf entferntem Item müssen ungültig bleiben"); return
        }
    }

    /// Gleichzeitige Reservierungen sind atomar (Actor): 6 × 5 bei Limit 15 → genau 3 gelingen.
    @Test func concurrentReservationsAreAtomic() async throws {
        let ledger = try makeLedger()
        for i in 0..<30 { try await ledger.decide(photo(i), .markForCleanup) }
        let ok = await withTaskGroup(of: Bool.self) { group -> Int in
            for batch in 0..<6 {
                group.addTask {
                    (try? await ledger.prepareCleanup((batch * 5..<(batch + 1) * 5).map(photo), kind: .photoLibraryDelete,
                                                      dailyLimit: 15)) != nil
                }
            }
            var n = 0
            for await r in group where r { n += 1 }
            return n
        }
        #expect(ok == 3)
        #expect(await ledger.allowance(limit: 15).available == 0)
    }
}
