import Foundation
import Testing
@testable import PhotoMaidCore

private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func add(_ value: Int) { lock.withLock { values.append(value) } }
    var result: [Int] { lock.withLock { values } }
}

@Suite struct AnalysisWorkTests {
    func item() -> AnalysisItem {
        AnalysisItem(id: "asset", kind: .documents,
            fingerprint: .init(modified: Date(timeIntervalSince1970: 12), width: 1200, height: 800),
            algorithm: "ocr-v2", captured: nil)
    }
    @Test func completionBeforeObserver() {
        let gate = AnalysisOneShot<Int>(), probe = Probe()
        #expect(gate.finish(4)); gate.observe { probe.add($0) }
        #expect(probe.result == [4])
    }
    @Test func observerBeforeCompletion() {
        let gate = AnalysisOneShot<Int>(), probe = Probe()
        gate.observe { probe.add($0) }; gate.finish(8); gate.finish(9)
        #expect(probe.result == [8])
    }
    @Test func cleanupBeforeAndAfterCompletion() {
        let gate = AnalysisOneShot<Int>(), probe = Probe()
        gate.onFinish { probe.add(1) }; gate.finish(3); gate.onFinish { probe.add(2) }
        #expect(probe.result == [1, 2])
    }
    @Test func lateRequestIDIsCancelled() {
        let gate = AnalysisOneShot<Int>(), probe = Probe()
        gate.finish(-1)
        gate.onFinish { probe.add(444) }
        #expect(probe.result == [444])
    }
    @Test func reentrantCancellationDoesNotDeadlock() {
        let gate = AnalysisOneShot<Int>(), probe = Probe()
        gate.onFinish { _ = gate.finish(100); probe.add(1) }
        #expect(gate.finish(1)); #expect(probe.result == [1])
    }
    @Test func concurrentCallbacksResumeExactlyOnce() {
        let gate = AnalysisOneShot<Int>(), probe = Probe()
        gate.observe { probe.add($0) }
        DispatchQueue.concurrentPerform(iterations: 1000) { gate.finish($0) }
        #expect(probe.result.count == 1)
    }
    @Test func cancelledContinuationTerminates() async {
        let gate = AnalysisOneShot<Int>()
        let value: Int = await withCheckedContinuation { c in
            gate.observe { c.resume(returning: $0) }; gate.finish(-1)
        }
        #expect(value == -1)
    }
    @Test func localWatchdogTerminatesWithoutCallback() {
        let watchdog = AnalysisWatchdog(now: 10, cloud: false)
        #expect(!watchdog.expired(now: 12.9)); #expect(watchdog.expired(now: 13))
    }
    @Test func cloudProgressExtendsIdleButNotAbsoluteDeadline() {
        var watchdog = AnalysisWatchdog(now: 0, cloud: true)
        for step in 1...11 { watchdog.update(Double(step) / 12, now: Double(step * 10)) }
        #expect(!watchdog.expired(now: 119)); #expect(watchdog.expired(now: 120))
    }
    @Test func unchangedOrInvalidProgressCannotKeepARequestAlive() {
        var watchdog = AnalysisWatchdog(now: 0, cloud: true)
        watchdog.update(0.2, now: 10); watchdog.update(0.2, now: 25)
        watchdog.update(.nan, now: 28); watchdog.update(1.2, now: 29)
        #expect(watchdog.expired(now: 30))
    }
    @Test func backwardClockExpires() {
        let watchdog = AnalysisWatchdog(now: 10, cloud: true)
        #expect(watchdog.expired(now: 9)); #expect(watchdog.expired(now: .infinity))
    }
    @Test func cachedSuccessIsNotScheduledAgain() {
        var value = item(); value.state = .complete
        #expect(!value.canAttempt(now: Date(), retryFailures: true))
    }
    @Test func versionAndEditsInvalidateCache() {
        let value = item()
        #expect(value.reusable(fingerprint: value.fingerprint, algorithm: "ocr-v2"))
        #expect(!value.reusable(fingerprint: value.fingerprint, algorithm: "ocr-v3"))
        var fingerprint = value.fingerprint; fingerprint.width += 1
        #expect(!value.reusable(fingerprint: fingerprint, algorithm: "ocr-v2"))
        fingerprint = value.fingerprint; fingerprint.modified = nil
        #expect(!value.reusable(fingerprint: fingerprint, algorithm: "ocr-v2"))
    }
    @Test func retryBackoffAndThreeAttemptLimit() {
        var value = item(); let now = Date(timeIntervalSince1970: 100)
        value.fail(now: now); #expect(!value.canAttempt(now: now.addingTimeInterval(14)))
        #expect(value.canAttempt(now: now.addingTimeInterval(15)))
        value.fail(now: now); value.fail(now: now)
        #expect(!value.canAttempt(now: now.addingTimeInterval(1000)))
        #expect(value.canAttempt(now: now, retryFailures: true))
    }
    @Test func emptyProgressIsNotNanOrComplete() {
        let counts = AnalysisCounts(); #expect(counts.fraction == 0); #expect(counts.pending == 0)
    }
    @Test func cloudAndErrorsAreNotAnalysed() {
        var counts = AnalysisCounts()
        for state: AnalysisItemState in [.complete, .waitingForCloud, .failed, .insufficientQuality, .featuresReady] { counts.add(state) }
        #expect(counts.total == 5); #expect(counts.complete == 1)
        #expect(counts.pending == 1); #expect(counts.fraction == 0.2)
        counts.add(.waitingForCloud, delta: -1); counts.add(.complete)
        #expect(counts.total == 5); #expect(counts.cloud == 0); #expect(counts.complete == 2)
    }
    @Test func failedAndUnknownRoundTrip() throws {
        var value = item(); value.fail(now: Date(timeIntervalSince1970: 100))
        #expect(try JSONDecoder().decode(AnalysisItem.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func graphUnionsAreStableAndDoNotStoreCycles() {
        var graph = AnalysisSimilarityGraph()
        let ab = graph.join("a", "b"), bc = graph.join("b", "c")
        #expect(ab); #expect(bc)
        let ac = graph.join("a", "c"), xx = graph.join("x", "x")
        #expect(!ac); #expect(!xx)
        #expect(graph.groups() == [["a", "b", "c"]])
    }
    @Test func graphHandles37177AssetsWithLinearNumberOfLinks() {
        var graph = AnalysisSimilarityGraph(); var accepted = 0
        for n in 1..<37177 { if graph.join(String(n - 1), String(n)) { accepted += 1 } }
        for n in 2..<37177 { let joined = graph.join("0", String(n)); #expect(!joined) }
        #expect(accepted == 37176); #expect(graph.groups().first?.count == 37177)
    }
    @Test func resolutionDependsOnlyOnSelectedTask() {
        #expect(AnalysisKind.blurry.pixelLimit == 512)
        #expect(AnalysisKind.documents.pixelLimit == 1600)
        #expect(AnalysisKind.similar.pixelLimit == 512)
        #expect(AnalysisKind.categories.pixelLimit == 512)
    }
}
