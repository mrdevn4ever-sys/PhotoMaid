import Testing
import Foundation
@testable import PhotoMaidCore

@Suite("Feed-Session")
struct FeedSessionTests {
    func session(_ n: Int) -> FeedSession {
        var s = FeedSession(items: (0..<n).map(photo))
        for i in 0..<n { s.markPreviewReady(photo(i)) }
        return s
    }

    /// Simuliert eine vollständige Geste bis zur Persistenz.
    func perform(_ intent: FeedIntent, _ s: inout FeedSession, _ ledger: DecisionLedger) async throws {
        guard let item = s.current else { return }
        let rev = await ledger.record(for: item).revision
        guard let p = s.requestDecision(intent, currentRevision: rev) else { return }
        do {
            let out = try await ledger.apply(p.command, sessionID: s.id)
            s.commitSucceeded(p.command.id, record: out.record)
        } catch {
            s.commitFailed(p.command.id)
        }
    }

    @Test("Genau ein Behalten pro Wischen nach oben, genau ein Schritt weiter")
    func oneKeepPerSwipe() async throws {
        let ledger = try makeLedger()
        var s = session(5)
        try await perform(.keep, &s, ledger)
        #expect(s.index == 1)
        #expect(await ledger.events().count == 1)
        #expect(s.summary.kept == 1)
    }

    @Test("Runter navigiert zurück, ohne Entscheidung; am Anfang: Anschlag")
    func downNoDecision() async throws {
        let ledger = try makeLedger()
        var s = session(3)
        #expect(s.goBack() == .atStart)
        try await perform(.keep, &s, ledger)
        #expect(s.goBack() == .moved(to: 0))
        #expect(await ledger.events().count == 1)
        #expect(await ledger.record(for: photo(0)).disposition == .kept)
    }

    @Test("Passive Navigation erzeugt kein Behalten")
    func passiveNavigation() async throws {
        let ledger = try makeLedger()
        var s = session(4)
        s.jump(to: 3)
        s.jump(to: 1)
        _ = s.goBack()
        #expect(await ledger.events().isEmpty)
        #expect(s.summary.reviewed == 0)
    }

    @Test("Nicht geladene Vorschau darf nicht entschieden werden")
    func previewRequired() {
        var s = FeedSession(items: [photo(0)])
        #expect(s.requestDecision(.keep, currentRevision: 0) == nil)
        s.markPreviewReady(photo(0))
        #expect(s.requestDecision(.keep, currentRevision: 0) != nil)
    }

    @Test("Callback A verändert niemals B")
    func staleCallback() async throws {
        let ledger = try makeLedger()
        var s = session(3)
        let pA = s.requestDecision(.keep, currentRevision: 0)!
        let outA = try await ledger.apply(pA.command)
        s.commitSucceeded(pA.command.id, record: outA.record)
        // Später eintreffendes Duplikat von A darf B nicht beeinflussen.
        let pB = s.requestDecision(.markForCleanup, currentRevision: 0)!
        #expect(s.commitSucceeded(pA.command.id, record: outA.record) == false)
        #expect(s.index == 1)
        #expect(pB.command.item == photo(1))
    }

    @Test("Schnelle Folge: zweiter Request während offenem Commit wird verworfen")
    func rapidSequence() async throws {
        var s = session(3)
        let p1 = s.requestDecision(.keep, currentRevision: 0)
        let p2 = s.requestDecision(.keep, currentRevision: 0)
        #expect(p1 != nil && p2 == nil)
    }

    @Test("Persistenzfehler setzt die visuelle Aktion zurück")
    func persistenceFailureRollsBack() async throws {
        let p = InMemoryLedgerPersistence()
        let ledger = try makeLedger(persistence: p)
        var s = session(3)
        p.failNextCommits = 1
        try await perform(.markForCleanup, &s, ledger)
        #expect(s.index == 0)
        #expect(s.pending == nil)
        #expect(s.summary.reviewed == 0)
    }

    @Test("Terminleiste gehört zum zurückgestellten Item und wird durch neue Entscheidung geschlossen")
    func receiptBinding() async throws {
        let clock = TestClock("2026-06-10T10:00")
        let ledger = try makeLedger(clock: clock)
        var s = session(3)
        try await perform(.later, &s, ledger)
        let receipt = try #require(s.receipt)
        #expect(receipt.item == photo(0))
        #expect(s.current == photo(1))
        let cmd = try #require(s.scheduleCommand(receiptID: receipt.id, day: LaterPreset.tomorrow.dueDay(from: clock.today)))
        #expect(cmd.item == photo(0))
        #expect(cmd.amends == receipt.laterCommandID)
        try await ledger.apply(cmd)
        #expect(await ledger.record(for: photo(0)).dueDay == LocalDay(year: 2026, month: 6, day: 11))
        // Neue Entscheidung schließt die Leiste; veraltete Leisten-Callbacks werden verworfen.
        try await perform(.keep, &s, ledger)
        #expect(s.receipt == nil)
        #expect(s.scheduleCommand(receiptID: receipt.id, day: LocalDay(year: 2026, month: 7, day: 1)) == nil)
    }

    @Test("Schräg rechts oben: Später mit Wunsch nach eigenem Datum, zählt als Später")
    func laterCustom() async throws {
        let ledger = try makeLedger()
        var s = session(2)
        try await perform(.laterCustom, &s, ledger)
        let r = try #require(s.receipt)
        #expect(r.wantsCustomDate)
        #expect(r.item == photo(0))
        #expect(s.summary.later == 1)
        #expect(await ledger.record(for: photo(0)).disposition == .later)
        try await perform(.later, &s, ledger)
        #expect(s.receipt?.wantsCustomDate == false)
    }

    @Test("Korrektur eines früheren Items: kein Doppelzählen in der Zusammenfassung")
    func correctionSummary() async throws {
        let ledger = try makeLedger()
        var s = session(3)
        try await perform(.keep, &s, ledger)
        _ = s.goBack()
        try await perform(.markForCleanup, &s, ledger)
        #expect(s.summary.kept == 0)
        #expect(s.summary.marked == 1)
        #expect(s.index == 1)
        #expect(await ledger.events().map(\.kind) == [.decision, .correction])
    }

    @Test("Session-Ende: echte Zusammenfassung, keine Endlosschleife")
    func sessionEnd() async throws {
        let ledger = try makeLedger()
        var s = session(2)
        try await perform(.keep, &s, ledger)
        try await perform(.later, &s, ledger)
        #expect(s.isFinished)
        #expect(s.current == nil)
        #expect(s.requestDecision(.keep, currentRevision: 0) == nil)
        #expect(s.summary == SessionSummary(kept: 1, marked: 0, later: 1))
    }

    @Test("Zwei nicht ladbare Medien weiter: keine Entscheidung, kein Sprung durch veraltete Tasten")
    func unavailableItemsCanBePassedWithoutReviewingThem() {
        var s = session(3)
        s.markPreviewUnavailable(photo(0)); s.markPreviewUnavailable(photo(1))
        let blocked = s.requestDecision(.markForCleanup, currentRevision: 0)
        #expect(blocked == nil)
        let first = s.advanceWithoutDecision(from: photo(0))
        #expect(first && s.current == photo(1))
        let stale = s.advanceWithoutDecision(from: photo(0))
        #expect(!stale && s.current == photo(1))
        let second = s.advanceWithoutDecision(from: photo(1))
        #expect(second && s.current == photo(2))
        #expect(s.decisions.isEmpty && s.summary.reviewed == 0 && s.receipt == nil)
        let last = s.advanceWithoutDecision(from: photo(2))
        #expect(last && s.isFinished)
        let ended = s.advanceWithoutDecision(from: photo(2))
        #expect(!ended)
    }

    @Test("Weiter ohne Auswahl kann keinen offenen Commit verlassen")
    func passCannotRaceAnOpenCommit() {
        var s = session(2)
        s.markPreviewReady(photo(0))
        let pending = s.requestDecision(.keep, currentRevision: 0)
        #expect(pending != nil)
        let passed = s.advanceWithoutDecision(from: photo(0))
        #expect(!passed && s.current == photo(0) && s.pending != nil)
    }

    @Test("100 schnelle Entscheidungen: Zählung entspricht dem Ledger")
    func hundredDecisions() async throws {
        let ledger = try makeLedger()
        var s = session(100)
        var rng = SeededRNG(42)
        while !s.isFinished {
            let intent: FeedIntent = [.keep, .markForCleanup, .later].randomElement(using: &rng)!
            try await perform(intent, &s, ledger)
        }
        let records = await ledger.allRecords()
        #expect(records.count == 100)
        #expect(s.summary.reviewed == 100)
        #expect(s.summary.marked == records.filter { $0.disposition == .markedForCleanup }.count)
        #expect(s.summary.kept == records.filter { $0.disposition == .kept }.count)
    }
}
