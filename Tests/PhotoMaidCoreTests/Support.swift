import Foundation
@testable import PhotoMaidCore

final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    private var _tz: TimeZone

    init(_ iso: String, tz: String = "Europe/Zurich") {
        _tz = TimeZone(identifier: tz)!
        _now = TestClock.date(iso, tz: tz)
    }

    var now: Date { lock.withLock { _now } }
    var timeZone: TimeZone { lock.withLock { _tz } }

    func set(_ iso: String) { let tz = timeZone.identifier; lock.withLock { _now = TestClock.date(iso, tz: tz) } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
    func setTimeZone(_ id: String) { lock.withLock { _tz = TimeZone(identifier: id)! } }

    /// "2026-03-28T23:30" in der angegebenen Zeitzone.
    static func date(_ iso: String, tz: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz)!
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: iso)!
    }
}

func photo(_ n: Int) -> ItemReference { .photo("QA-\(n)") }

func makeLedger(clock: TestClock = TestClock("2026-06-10T10:00"),
                persistence: InMemoryLedgerPersistence = InMemoryLedgerPersistence()) throws -> DecisionLedger {
    try DecisionLedger(persistence: persistence, clock: clock)
}

extension DecisionLedger {
    @discardableResult
    func decide(_ item: ItemReference, _ action: DecisionAction, session: ReviewSessionID? = nil) throws -> CommitOutcome {
        let r = record(for: item)
        return try apply(DecisionCommand(item: item, expectedRevision: r.revision, action: action), sessionID: session)
    }
}

final class MemoryByteSource: ByteSourceProvider, @unchecked Sendable {
    var contents: [ItemReference: Data] = [:]
    var opened = 0
    func openStream(for item: ItemReference) throws -> (any ByteStream)? {
        guard let d = contents[item] else { return nil }
        opened += 1
        return MemoryStream(d)
    }
}

final class MemoryStream: ByteStream {
    private let data: Data
    private var offset = 0
    init(_ data: Data) { self.data = data }
    func read(maxLength: Int) throws -> Data {
        let end = min(data.count, offset + maxLength)
        defer { offset = end }
        return data.subdata(in: offset..<end)
    }
    func close() {}
}

/// Deterministischer Zufallsgenerator für generierte Aktionsfolgen.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
