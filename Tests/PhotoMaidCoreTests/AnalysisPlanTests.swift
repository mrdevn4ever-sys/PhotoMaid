import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct AnalysisPlanTests {
    @Test func openingAnotherAnalysisQueuesInsteadOfStopping() {
        var plan = AnalysisPlan()
        #expect(plan.request(.blurry, running: false, keepCurrent: false) == .start)
        #expect(plan.request(.similar, running: true, keepCurrent: true) == .queued(position: 1))
        #expect(plan.request(.categories, running: true, keepCurrent: true) == .queued(position: 2))
        // Zweimal tippen reiht nicht doppelt ein.
        #expect(plan.request(.similar, running: true, keepCurrent: true) == .queued(position: 1))
        #expect(plan.current == .blurry && plan.waiting == [.similar, .categories])
        #expect(plan.request(.blurry, running: true, keepCurrent: true) == .alreadyRunning)
    }

    @Test func finishedAnalysisStartsTheNextOne() {
        var plan = AnalysisPlan(current: .blurry, waiting: [.similar, .documents])
        #expect(plan.advance() == .similar)
        #expect(plan.current == .similar && plan.waiting == [.documents])
        #expect(plan.advance() == .documents)
        #expect(plan.advance() == nil)
        #expect(plan.current == nil && plan.waiting.isEmpty)
    }

    @Test func prioritizeKeepsThePreviousNext() {
        var plan = AnalysisPlan(current: .blurry, waiting: [.similar, .categories])
        plan.prioritize(.categories)
        #expect(plan.current == .categories && plan.waiting == [.blurry, .similar])
        plan.prioritize(.categories)
        #expect(plan.waiting == [.blurry, .similar])
    }

    @Test func startingWhileIdleKeepsUnfinishedWorkOnlyIfWanted() {
        var kept = AnalysisPlan(current: .blurry)
        #expect(kept.request(.similar, running: false, keepCurrent: true) == .start)
        #expect(kept.current == .similar && kept.waiting == [.blurry])
        var dropped = AnalysisPlan(current: .blurry)
        #expect(dropped.request(.similar, running: false, keepCurrent: false) == .start)
        #expect(dropped.current == .similar && dropped.waiting.isEmpty)
        // Eine wartende Analyse, die gestartet wird, wartet nicht mehr.
        var waitingOne = AnalysisPlan(current: .blurry, waiting: [.documents])
        _ = waitingOne.request(.documents, running: false, keepCurrent: false)
        #expect(waitingOne.current == .documents && waitingOne.waiting.isEmpty)
    }

    @Test func initRemovesDuplicatesAndCurrent() throws {
        let plan = AnalysisPlan(current: .blurry, waiting: [.blurry, .similar, .similar])
        #expect(plan.waiting == [.similar])
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(AnalysisPlan.self, from: data) == plan)
        var removed = plan
        removed.remove(.similar)
        #expect(removed.waiting.isEmpty && removed.position(of: .similar) == nil)
    }

    @Test func cloudOnlyIsSharedOnlyTowardsEqualOrLargerPreviews() {
        let states: [AnalysisKind: [String: AnalysisItemState]] = [
            .blurry: ["a": .waitingForCloud, "b": .complete, "c": .insufficientQuality],
            .documents: ["d": .waitingForCloud],
        ]
        // Gleich groß (512): von „Unscharf“ übernommen; die 1600er-Texterkennung sagt nichts über 512 aus.
        #expect(AnalysisAvailability.knownCloudOnly(for: .similar, states: states) == ["a"])
        #expect(AnalysisAvailability.knownCloudOnly(for: .categories, states: states) == ["a"])
        // Größer (1600): alles, was schon bei 512 nur in iCloud lag.
        #expect(AnalysisAvailability.knownCloudOnly(for: .documents, states: states) == ["a"])
        // Die eigene Analyse zählt nicht als „andere“.
        #expect(AnalysisAvailability.knownCloudOnly(for: .blurry, states: states).isEmpty)
    }
}

@Suite struct LibraryChangesTests {
    @Test func contentChangesPatchInsteadOfReloading() {
        var s = LibraryChangeSummary()
        s.add(incremental: true, inserted: 0, removed: 0, changed: ["a", "b"])
        s.add(incremental: true, inserted: 0, removed: 0, changed: ["b", "c"])
        #expect(s.reaction(albumsMatter: true) == .patch(["a", "b", "c"]))
    }

    @Test func insertedRemovedOrUnknownReloads() {
        var inserted = LibraryChangeSummary()
        inserted.add(incremental: true, inserted: 1, removed: 0, changed: [])
        #expect(inserted.reaction(albumsMatter: false) == .reload)
        var unknown = LibraryChangeSummary()
        unknown.add(incremental: false, inserted: 0, removed: 0, changed: [])
        #expect(unknown.reaction(albumsMatter: false) == .reload)
    }

    @Test func albumOnlyChangesReloadOnlyWhenAlbumsFilter() {
        var s = LibraryChangeSummary()
        s.add(incremental: nil, inserted: 0, removed: 0, changed: [])
        #expect(!s.isEmpty)
        #expect(s.reaction(albumsMatter: false) == .none)
        #expect(s.reaction(albumsMatter: true) == .reload)
        #expect(LibraryChangeSummary().isEmpty && LibraryChangeSummary().reaction(albumsMatter: true) == .none)
    }

    @Test func coalescerWaitsForQuietButNotForever() {
        var c = ChangeCoalescer(quiet: 0.8, maxDelay: 3)
        #expect(abs(c.register(now: 10) - 0.8) < 1e-9)
        #expect(abs(c.register(now: 10.5) - 0.8) < 1e-9)
        // Dauerfeuer: spätestens 3 s nach der ersten Meldung.
        #expect(abs(c.register(now: 12.5) - 0.5) < 1e-9)
        #expect(c.register(now: 13.5) == 0)
        c.flushed()
        #expect(abs(c.register(now: 20) - 0.8) < 1e-9)
    }
}
