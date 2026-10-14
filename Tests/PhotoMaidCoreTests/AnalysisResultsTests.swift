import Foundation
import Testing
@testable import PhotoMaidCore

private final class Gauge: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var peak = 0
    private var levels: [WorkThermalLevel]
    private var waits = 0
    init(levels: [WorkThermalLevel]) { self.levels = levels }
    func enter() { lock.withLock { running += 1; peak = max(peak, running) } }
    func leave() { lock.withLock { running -= 1 } }
    var maxConcurrent: Int { lock.withLock { peak } }
    /// Liefert die nächste Wärmestufe (die letzte bleibt stehen).
    func next() -> WorkThermalLevel { lock.withLock { levels.count > 1 ? levels.removeFirst() : levels[0] } }
    func waited() { lock.withLock { waits += 1 } }
    var waitCount: Int { lock.withLock { waits } }
}

@Suite struct AnalysisResultsTests {
    @Test func pageKeepsOrderAndFiltersDecided() {
        let page = AnalysisResultPage(ordered: ["a", "b", "c", "d", "b"], include: { $0 != "c" }, page: 0, pageSize: 2)
        #expect(page.all == ["a", "b", "d"])
        #expect(page.ids == ["a", "b"])
        #expect(page.total == 3)
        #expect(page.canNext)
    }

    @Test func pageClampsAfterItemsWereDecided() {
        // Seite 2 gibt es nach dem Entscheiden nicht mehr: letzte vorhandene Seite statt leerer Liste.
        let page = AnalysisResultPage(ordered: ["a", "b", "c"], include: { _ in true }, page: 5, pageSize: 2)
        #expect(page.page == 1)
        #expect(page.ids == ["c"])
        #expect(!page.canNext)
        let empty = AnalysisResultPage(ordered: [], include: { _ in true }, page: 3, pageSize: 2)
        #expect(empty.page == 0 && empty.ids.isEmpty && !empty.canNext)
    }

    @Test func feedStartsAtTappedItem() {
        let page = AnalysisResultPage(ordered: ["a", "b", "c", "d"], include: { _ in true }, page: 0, pageSize: 10)
        #expect(page.feedOrder(startingAt: "c") == ["c", "d", "a", "b"])
        #expect(page.feedOrder(startingAt: nil) == ["a", "b", "c", "d"])
        #expect(page.feedOrder(startingAt: "x") == ["a", "b", "c", "d"])
    }

    @Test func groupsDropMembersAndSmallGroups() {
        let page = AnalysisGroupPage(groups: [["a", "b", "c"], ["d", "e"], ["f", "g"]], include: { $0 != "d" && $0 != "a" },
                                     page: 0, pageSize: 10)
        #expect(page.all == [["b", "c"], ["f", "g"]])
        #expect(page.memberCount == 4)
        #expect(!page.canNext)
    }

    @Test func throttleByThermalLevel() {
        #expect(WorkThrottle.decide(.nominal, maxParallel: 3) == .run(parallel: 3, pauseMilliseconds: 0))
        #expect(WorkThrottle.decide(.fair, maxParallel: 3) == .run(parallel: 1, pauseMilliseconds: 150))
        #expect(WorkThrottle.decide(.fair, maxParallel: 4) == .run(parallel: 2, pauseMilliseconds: 150))
        #expect(WorkThrottle.decide(.serious, maxParallel: 3) == .waitForCooling)
        #expect(WorkThrottle.decide(.critical, maxParallel: 3) == .stop)
    }

    @Test func autoResumeRules() {
        #expect(AnalysisAutoResume.shouldResume(after: .background, pendingWork: true, thermal: .fair, cloudReady: false))
        #expect(AnalysisAutoResume.shouldResume(after: .thermal, pendingWork: true, thermal: .nominal, cloudReady: false))
        #expect(!AnalysisAutoResume.shouldResume(after: .thermal, pendingWork: true, thermal: .serious, cloudReady: true))
        #expect(!AnalysisAutoResume.shouldResume(after: .user, pendingWork: true, thermal: .nominal, cloudReady: true))
        #expect(!AnalysisAutoResume.shouldResume(after: .background, pendingWork: false, thermal: .nominal, cloudReady: true))
        #expect(AnalysisAutoResume.shouldResume(after: .network, pendingWork: true, thermal: .nominal, cloudReady: true))
        #expect(!AnalysisAutoResume.shouldResume(after: .network, pendingWork: true, thermal: .nominal, cloudReady: false))
        #expect(!AnalysisAutoResume.shouldResume(after: nil, pendingWork: true, thermal: .nominal, cloudReady: true))
    }

    @Test func throttledWorkRespectsParallelismAndOrder() async throws {
        let gauge = Gauge(levels: [.nominal])
        var seen: [Int] = []
        try await ThrottledWork.run(Array(0..<12), maxParallel: 3, thermal: { gauge.next() }, sleep: { _ in },
                                    work: { (i: Int) -> Int in
                                        gauge.enter(); defer { gauge.leave() }
                                        try await Task.sleep(for: .milliseconds(2))
                                        return i * 10
                                    }, result: { index, value in
                                        #expect(value == index * 10)
                                        seen.append(index)
                                    })
        #expect(seen.sorted() == Array(0..<12))
        #expect(gauge.maxConcurrent <= 3)
    }

    @Test func throttledWorkWaitsWhileWarmThenContinues() async throws {
        // Erst warm (wartet, ohne zu starten), dann kühl: alles wird erledigt.
        let gauge = Gauge(levels: [.serious, .serious, .nominal])
        var count = 0
        try await ThrottledWork.run(Array(0..<4), maxParallel: 2, thermal: { gauge.next() }, sleep: { _ in },
                                    waiting: { gauge.waited() },
                                    work: { (i: Int) in i }, result: { _, _ in count += 1 })
        #expect(count == 4)
        #expect(gauge.waitCount == 2)
    }

    @Test func throttledWorkStopsWhenCritical() async {
        let gauge = Gauge(levels: [.nominal, .critical])
        var count = 0
        await #expect(throws: ThrottledWorkError.critical) {
            try await ThrottledWork.run(Array(0..<5), maxParallel: 1, thermal: { gauge.next() }, sleep: { _ in },
                                        work: { (i: Int) in i }, result: { _, _ in count += 1 })
        }
        #expect(count <= 1)
    }

    @Test func throttledWorkHonoursBeforeStartFailure() async {
        struct Blocked: Error {}
        await #expect(throws: Blocked.self) {
            try await ThrottledWork.run([1, 2], maxParallel: 1, thermal: { .nominal }, sleep: { _ in },
                                        beforeStart: { throw Blocked() },
                                        work: { (i: Int) in i }, result: { _, _ in })
        }
    }
}
