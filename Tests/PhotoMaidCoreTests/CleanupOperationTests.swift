import Testing
import Foundation
@testable import PhotoMaidCore

@Suite("Bereinigung, Journal, Free-Limit")
struct CleanupOperationTests {
    func markedLedger(_ n: Int, clock: TestClock = TestClock("2026-06-10T10:00"),
                      persistence: InMemoryLedgerPersistence = InMemoryLedgerPersistence()) async throws -> DecisionLedger {
        let ledger = try makeLedger(clock: clock, persistence: persistence)
        for i in 0..<n { try await ledger.decide(photo(i), .markForCleanup) }
        return ledger
    }

    @Test("PhotoKit-Erfolg: Items entfernt, Limit verbraucht, Verlauf ergänzt")
    func success() async throws {
        let ledger = try await markedLedger(3)
        let intent = try await ledger.prepareCleanup([photo(0), photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        #expect(await ledger.allowance(limit: 15).available == 13) // reserviert
        try await ledger.markSubmitted(intent.id)
        let done = try await ledger.reconcile(intent.id, outcome: .succeeded)
        #expect(done.state == .succeeded)
        #expect(await ledger.allowance(limit: 15).confirmed == 2)
        #expect(await ledger.allowance(limit: 15).available == 13)
        #expect(await ledger.basket().map(\.item) == [photo(2)])
        #expect(await ledger.events().filter { $0.kind == .cleanupConfirmed }.count == 2)
    }

    @Test("Abbruch der System-Bestätigung: kein verbrauchtes Limit, Items bleiben vorgemerkt")
    func cancelled() async throws {
        let ledger = try await markedLedger(2)
        let intent = try await ledger.prepareCleanup([photo(0), photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(intent.id)
        let done = try await ledger.reconcile(intent.id, outcome: .cancelled)
        #expect(done.state == .cancelled)
        #expect(await ledger.allowance(limit: 15).available == 15)
        #expect(await ledger.basket().count == 2)
    }

    @Test("Fehler ohne belegten Teilerfolg wird nicht als Teilerfolg gewertet")
    func failed() async throws {
        let ledger = try await markedLedger(2)
        let intent = try await ledger.prepareCleanup([photo(0), photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(intent.id)
        let done = try await ledger.reconcile(intent.id, outcome: .failed(reason: "x"))
        #expect(done.state == .failed)
        #expect(done.confirmedRemoved.isEmpty)
        #expect(await ledger.allowance(limit: 15).confirmed == 0)
    }

    @Test("Dateien: belegter Teilerfolg zählt nur tatsächlich entfernte Dateien")
    func partial() async throws {
        let ledger = try await markedLedger(3)
        let intent = try await ledger.prepareCleanup([photo(0), photo(1), photo(2)], kind: .fileDeletePermanently, dailyLimit: 15)
        try await ledger.markSubmitted(intent.id)
        let done = try await ledger.reconcile(intent.id, outcome: .partial(removed: [photo(1), photo(99)]))
        #expect(done.state == .partiallySucceeded)
        #expect(done.confirmedRemoved == [photo(1)])
        #expect(await ledger.allowance(limit: 15).confirmed == 1)
    }

    @Test("Wiederholte Callbacks werden genau einmal abgeglichen")
    func repeatedCallbacks() async throws {
        let ledger = try await markedLedger(2)
        let intent = try await ledger.prepareCleanup([photo(0), photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(intent.id)
        try await ledger.reconcile(intent.id, outcome: .succeeded)
        try await ledger.reconcile(intent.id, outcome: .succeeded)
        try await ledger.reconcile(intent.id, outcome: .cancelled)
        #expect(await ledger.allowance(limit: 15).confirmed == 2)
        #expect(await ledger.events().filter { $0.kind == .cleanupConfirmed }.count == 2)
    }

    @Test("Doppeltap: dasselbe Item kann nicht zweimal in eine laufende Operation")
    func doubleTap() async throws {
        let ledger = try await markedLedger(1)
        _ = try await ledger.prepareCleanup([photo(0)], kind: .photoLibraryDelete, dailyLimit: 15)
        await #expect(throws: CleanupError.itemBusy(photo(0))) {
            try await ledger.prepareCleanup([photo(0)], kind: .photoLibraryDelete, dailyLimit: 15)
        }
        await #expect(throws: DecisionError.itemBusy) { try await ledger.decide(photo(0), .keep) }
    }

    @Test("Free-Limit an den Grenzen 0/1/14/15/16", arguments: [0, 1, 14, 15, 16])
    func allowanceBoundaries(requested: Int) async throws {
        let ledger = try await markedLedger(16)
        let items = (0..<requested).map(photo)
        if requested == 0 {
            await #expect(throws: CleanupError.emptySelection) {
                try await ledger.prepareCleanup(items, kind: .photoLibraryDelete, dailyLimit: 15)
            }
        } else if requested <= 15 {
            let intent = try await ledger.prepareCleanup(items, kind: .photoLibraryDelete, dailyLimit: 15)
            try await ledger.markSubmitted(intent.id)
            try await ledger.reconcile(intent.id, outcome: .succeeded)
            #expect(await ledger.allowance(limit: 15).available == 15 - requested)
        } else {
            await #expect(throws: CleanupError.allowanceExceeded(requested: 16, available: 15)) {
                try await ledger.prepareCleanup(items, kind: .photoLibraryDelete, dailyLimit: 15)
            }
        }
    }

    @Test("40 Kandidaten, 7 verfügbar: Nutzer wählt sieben, Rest bleibt vorgemerkt")
    func fortyCandidatesSevenAvailable() async throws {
        let ledger = try await markedLedger(48)
        let first = try await ledger.prepareCleanup((0..<8).map(photo), kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(first.id)
        try await ledger.reconcile(first.id, outcome: .succeeded)
        #expect(await ledger.allowance(limit: 15).available == 7)
        let all = (8..<48).map(photo)
        await #expect(throws: CleanupError.allowanceExceeded(requested: 40, available: 7)) {
            try await ledger.prepareCleanup(all, kind: .photoLibraryDelete, dailyLimit: 15)
        }
        let seven = Array(all.prefix(7))
        let i2 = try await ledger.prepareCleanup(seven, kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(i2.id)
        try await ledger.reconcile(i2.id, outcome: .succeeded)
        #expect(await ledger.basket().count == 33)
        #expect(await ledger.allowance(limit: 15).available == 0)
    }

    @Test("Gleichzeitige Operationen reservieren Kapazität atomar")
    func concurrentReservations() async throws {
        let ledger = try await markedLedger(30)
        let results = await withTaskGroup(of: Bool.self) { group in
            for batch in 0..<6 {
                let items = (batch * 5..<(batch + 1) * 5).map(photo)
                group.addTask {
                    (try? await ledger.prepareCleanup(items, kind: .photoLibraryDelete, dailyLimit: 15)) != nil
                }
            }
            var ok = 0
            for await r in group where r { ok += 1 }
            return ok
        }
        #expect(results == 3)
        #expect(await ledger.allowance(limit: 15).available == 0)
    }

    @Test("Pro: unbegrenzt, keine Reservierung, kein Zählerstand")
    func proUnlimited() async throws {
        let ledger = try await markedLedger(40)
        let intent = try await ledger.prepareCleanup((0..<40).map(photo), kind: .photoLibraryDelete, dailyLimit: nil)
        try await ledger.markSubmitted(intent.id)
        try await ledger.reconcile(intent.id, outcome: .succeeded)
        #expect(await ledger.allowance(limit: 15).confirmed == 0)
    }

    @Test("Verlorener Callback: nach Neustart reconciliationRequired, keine automatische Wiederholung")
    func lostCallback() async throws {
        let p = InMemoryLedgerPersistence()
        let clock = TestClock("2026-06-10T10:00")
        let ledger = try await markedLedger(2, clock: clock, persistence: p)
        let intent = try await ledger.prepareCleanup([photo(0), photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(intent.id)
        // Prozessabbruch.
        let relaunched = try makeLedger(clock: clock, persistence: p)
        let open = try await relaunched.recoverAfterLaunch()
        #expect(open.map(\.state) == [.reconciliationRequired])
        #expect(await relaunched.allowance(limit: 15).available == 13) // weiterhin reserviert
        // Fehlender Zugriff ist kein Löschbeweis.
        let unknown = try await relaunched.resolveReconciliation(intent.id, probes: [photo(0): .unknown, photo(1): .missingWithFullAccess])
        #expect(unknown.state == .reconciliationRequired)
        #expect(await relaunched.record(for: photo(0)).disposition == .markedForCleanup)
        let resolved = try await relaunched.resolveReconciliation(intent.id, probes: [photo(0): .exists, photo(1): .missingWithFullAccess])
        #expect(resolved.state == .partiallySucceeded)
        #expect(await relaunched.record(for: photo(1)).disposition == .removed)
        #expect(await relaunched.record(for: photo(0)).disposition == .markedForCleanup)
        #expect(await relaunched.allowance(limit: 15).confirmed == 1)
        #expect(await relaunched.events().contains { $0.kind == .reconciledMissing && $0.item == photo(1) })
    }

    @Test("Vorbereitet, aber nie gestartet: nach Neustart abgebrochen, Kapazität frei")
    func preparedNeverSubmitted() async throws {
        let p = InMemoryLedgerPersistence()
        let clock = TestClock("2026-06-10T10:00")
        let ledger = try await markedLedger(2, clock: clock, persistence: p)
        _ = try await ledger.prepareCleanup([photo(0)], kind: .photoLibraryDelete, dailyLimit: 15)
        let relaunched = try makeLedger(clock: clock, persistence: p)
        #expect(try await relaunched.recoverAfterLaunch().isEmpty)
        #expect(await relaunched.allowance(limit: 15).available == 15)
        #expect(await relaunched.record(for: photo(0)).disposition == .markedForCleanup)
    }

    @Test("Systemoperation erfolgreich, DB-Save fehlgeschlagen: kein Verlust, erneuter Abgleich möglich")
    func systemSuccessDbFailure() async throws {
        let p = InMemoryLedgerPersistence()
        let clock = TestClock("2026-06-10T10:00")
        let ledger = try await markedLedger(2, clock: clock, persistence: p)
        let intent = try await ledger.prepareCleanup([photo(0), photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(intent.id)
        p.failNextCommits = 1
        await #expect(throws: CleanupError.self) { try await ledger.reconcile(intent.id, outcome: .succeeded) }
        #expect(await ledger.intent(intent.id)?.state == .submitted)
        // Nach Neustart: unklar → Abgleich über Existenzprüfung, keine erneute Löschung.
        let relaunched = try makeLedger(clock: clock, persistence: p)
        _ = try await relaunched.recoverAfterLaunch()
        let resolved = try await relaunched.resolveReconciliation(intent.id, probes: [photo(0): .missingWithFullAccess, photo(1): .missingWithFullAccess])
        #expect(resolved.state == .succeeded)
        #expect(await relaunched.allowance(limit: 15).confirmed == 2)
    }

    @Test("Alias: dieselbe Ressource über zwei Quellen wird nicht doppelt gelöscht/gezählt")
    func alias() async throws {
        let ledger = try await markedLedger(2)
        await #expect(throws: CleanupError.aliasConflict(photo(1))) {
            try await ledger.prepareCleanup([photo(0), photo(1)], kind: .fileDeletePermanently, dailyLimit: 15,
                                            aliasKeys: [photo(0): "inode-7", photo(1): "inode-7"])
        }
    }

    @Test("Zeitzonen-/Uhrwechsel: keine negativen oder doppelten Zähler")
    func clockChanges() async throws {
        let clock = TestClock("2026-06-10T23:50")
        let ledger = try await markedLedger(6, clock: clock)
        let i1 = try await ledger.prepareCleanup([photo(0), photo(1)], kind: .photoLibraryDelete, dailyLimit: 15)
        try await ledger.markSubmitted(i1.id)
        clock.set("2026-06-11T00:10") // Callback nach Mitternacht: gebucht auf Reservierungstag
        try await ledger.reconcile(i1.id, outcome: .succeeded)
        #expect(await ledger.allowance(limit: 15).confirmed == 0)
        clock.set("2026-06-10T23:55") // Uhr zurück
        #expect(await ledger.allowance(limit: 15).confirmed == 2)
        #expect(await ledger.allowance(limit: 15).available == 13)
    }
}
