import Foundation

public enum AnalysisKind: String, Codable, Sendable, CaseIterable {
    case blurry, similar, documents, categories
    /// Vorschaugröße je Analyse. Merkmale und Motive rechnet Vision intern ohnehin klein (unter 512 px) – 512 reicht,
    /// liegt bei „iPhone-Speicher optimieren“ viel öfter schon auf dem Gerät und ist dieselbe Anfrage wie bei
    /// „Unscharf“ (so gilt „nur in iCloud“ gleich für alle drei). Nur die Texterkennung braucht mehr.
    public var pixelLimit: Int { self == .documents ? 1600 : 512 }
}

public enum AnalysisItemState: String, Codable, Sendable {
    case pending, waitingForCloud, insufficientQuality, failed, featuresReady, complete
}

public struct AnalysisFingerprint: Codable, Sendable, Equatable {
    public var modified: Date?
    public var width: Int
    public var height: Int
    public init(modified: Date?, width: Int, height: Int) {
        self.modified = modified; self.width = width; self.height = height
    }
}

/// No image bytes or feature archives in the lightweight work queue.
public struct AnalysisItem: Codable, Sendable, Equatable {
    public var id: String
    public var kind: AnalysisKind
    public var fingerprint: AnalysisFingerprint
    public var algorithm: String
    public var captured: Date?
    public var state: AnalysisItemState = .pending
    public var failures: Int = 0
    public var retryAfter: Date?
    public var sharpness: Double?
    public var category: String?
    public var text: String?
    public var sampleWidth = 0
    public var sampleHeight = 0

    public init(id: String, kind: AnalysisKind, fingerprint: AnalysisFingerprint,
                algorithm: String, captured: Date?) {
        self.id = id; self.kind = kind; self.fingerprint = fingerprint
        self.algorithm = algorithm; self.captured = captured
    }

    public func reusable(fingerprint: AnalysisFingerprint, algorithm: String) -> Bool {
        self.fingerprint == fingerprint && self.algorithm == algorithm
    }

    public func canAttempt(now: Date, retryFailures: Bool = false) -> Bool {
        guard state != .complete else { return false }
        if state != .failed { return true }
        return retryFailures || (failures < 3 && (retryAfter.map { $0 <= now } ?? true))
    }

    public mutating func fail(now: Date) {
        state = .failed
        failures = min(failures + 1, 3)
        retryAfter = now.addingTimeInterval([15.0, 60.0, 300.0][max(0, failures - 1)])
    }
}

public struct AnalysisCounts: Sendable, Equatable {
    public var total = 0
    public var complete = 0
    public var cloud = 0
    public var quality = 0
    public var failed = 0
    public var pending: Int { max(0, total - complete - cloud - quality - failed) }
    public var fraction: Double { total > 0 ? Double(complete) / Double(total) : 0 }
    public init() {}
    public mutating func add(_ state: AnalysisItemState, delta: Int = 1) {
        total += delta
        switch state {
        case .complete: complete += delta
        case .waitingForCloud: cloud += delta
        case .insufficientQuality: quality += delta
        case .failed: failed += delta
        default: break
        }
    }
}

/// Callback-to-async bridge. Handles callback-before-request-ID, cancellation-before-registration,
/// duplicate callbacks and late results. Cleanup always runs, including when attached after completion.
public final class AnalysisOneShot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var result: Value?
    private var observer: (@Sendable (Value) -> Void)?
    private var cleanup: [@Sendable () -> Void] = []
    public init() {}
    public var isCompleted: Bool { lock.withLock { completed } }

    public func observe(_ body: @escaping @Sendable (Value) -> Void) {
        let ready: Value? = lock.withLock {
            if completed { return result }
            precondition(observer == nil, "Only one waiter per photo request")
            observer = body
            return nil
        }
        if let ready { body(ready) }
    }

    public func onFinish(_ body: @escaping @Sendable () -> Void) {
        let run = lock.withLock {
            if completed { return true }
            cleanup.append(body); return false
        }
        if run { body() }
    }

    @discardableResult
    public func finish(_ value: Value) -> Bool {
        let callbacks: ((@Sendable (Value) -> Void)?, [@Sendable () -> Void])? = lock.withLock {
            guard !completed else { return nil }
            completed = true; result = value
            let callbacks = (observer, cleanup)
            observer = nil; cleanup = []
            return callbacks
        }
        guard let callbacks else { return false }
        // Never call framework cancellation while holding the latch lock: it can call us back synchronously.
        for release in callbacks.1 { release() }
        callbacks.0?(value)
        return true
    }
}

public struct AnalysisWatchdog: Sendable {
    private var started: TimeInterval
    private var lastProgress: TimeInterval
    private var progress = 0.0
    private let idle: TimeInterval
    private let absolute: TimeInterval
    public init(now: TimeInterval, cloud: Bool) {
        started = now; lastProgress = now
        idle = cloud ? 20 : 3
        absolute = cloud ? 120 : 3
    }
    public mutating func update(_ value: Double, now: TimeInterval) {
        guard value.isFinite, value > progress, value <= 1, now >= lastProgress else { return }
        progress = value; lastProgress = now
    }
    public func expired(now: TimeInterval) -> Bool {
        !now.isFinite || now < started || now - started >= absolute || now - lastProgress >= idle
    }
}

/// Only a spanning forest is persisted: at most n-1 links, not a quadratic list of similar pairs.
public struct AnalysisSimilarityGraph: Sendable {
    private var parents: [String: String] = [:]
    private var sizes: [String: Int] = [:]
    public init() {}
    private mutating func root(_ id: String) -> String {
        guard var parent = parents[id] else { parents[id] = id; sizes[id] = 1; return id }
        var node = id
        while parent != node {
            let next = parents[parent] ?? parent
            parents[node] = next; node = parent; parent = next
        }
        return node
    }
    @discardableResult
    public mutating func join(_ first: String, _ second: String) -> Bool {
        guard first != second else { return false }
        var a = root(first), b = root(second)
        guard a != b else { return false }
        if sizes[a, default: 1] < sizes[b, default: 1] { swap(&a, &b) }
        parents[b] = a; sizes[a, default: 1] += sizes[b, default: 1]
        return true
    }
    public mutating func groups() -> [[String]] {
        var result: [String: [String]] = [:]
        for id in Array(parents.keys) { result[root(id), default: []].append(id) }
        return result.values.filter { $0.count >= 2 }.map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }
}
