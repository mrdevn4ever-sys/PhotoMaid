import Testing
import Foundation
@testable import PhotoMaidCore

func file(_ name: String) -> ItemReference {
    ItemReference(provider: .connectedSource(ConnectedSourceID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)),
                  localIdentifier: name)
}

@Suite("Exakte Duplikate")
struct DuplicateTests {
    @Test("Gleiche Bytes, anderer Name → eine Gruppe; Mathematik 3 × 14 MB")
    func sameBytesDifferentName() throws {
        let src = MemoryByteSource()
        let payload = Data((0..<(14 * 1024)).map { UInt8($0 % 251) }) // 14 KiB stellvertretend
        src.contents[file("a.jpg")] = payload
        src.contents[file("Kopie von a.JPG")] = payload
        src.contents[file("b.bin")] = payload
        var other = payload; other[100] ^= 0xFF
        src.contents[file("c.jpg")] = other
        let size = KnownSize.known(Int64(payload.count))
        let r = try DuplicateFinder().scan([
            DuplicateCandidate(item: file("a.jpg"), size: size),
            DuplicateCandidate(item: file("Kopie von a.JPG"), size: size),
            DuplicateCandidate(item: file("b.bin"), size: size),
            DuplicateCandidate(item: file("c.jpg"), size: size),
        ], source: src)
        #expect(r.groups.count == 1)
        let g = try #require(r.groups.first)
        #expect(g.members.count == 3)
        #expect(!g.members.contains(file("c.jpg")))

        let mb: Int64 = 14 * 1_000_000
        let big = DuplicateGroup(sha256: "x", sizeEach: mb, members: [file("1"), file("2"), file("3")])
        #expect(big.totalBytes == 42_000_000)
        #expect(big.extraCopiesBytes == 28_000_000)
        let sel = big.defaultSelection(keeping: file("2"))
        #expect(big.isValidSelection(sel))
        #expect(big.selectedBytes(sel) == 28_000_000)
        #expect(!big.isValidSelection(Set(big.members)), "Mindestens eine Kopie bleibt")
    }

    @Test("Große Dateien werden gestreamt; Teilhash sortiert nur aus")
    func largeStreaming() throws {
        let src = MemoryByteSource()
        let n = 3 * 1024 * 1024 + 17
        let a = Data(repeating: 7, count: n)
        var b = a; b[n - 1] = 8 // Unterschied erst am Ende
        src.contents[file("a")] = a
        src.contents[file("a2")] = a
        src.contents[file("b")] = b
        var finder = DuplicateFinder()
        finder.chunkSize = 256 * 1024
        let r = try finder.scan([file("a"), file("a2"), file("b")].map {
            DuplicateCandidate(item: $0, size: .known(Int64(n)))
        }, source: src)
        #expect(r.groups.map(\.members) == [[file("a"), file("a2")]])
        #expect(try finder.bytesIdentical(file("a"), file("a2"), source: src))
        #expect(try !finder.bytesIdentical(file("a"), file("b"), source: src))
    }

    @Test("Nullbyte, unbekannte Größe, nicht vergleichbare Assets und nicht lokale Bytes")
    func specialCases() throws {
        let src = MemoryByteSource()
        src.contents[file("z1")] = Data()
        src.contents[file("z2")] = Data()
        src.contents[file("x")] = Data([1, 2, 3])
        // file("cloud") hat keine lokalen Bytes → nicht geprüft, NICHT herunterladen.
        let r = try DuplicateFinder().scan([
            DuplicateCandidate(item: file("z1"), size: .known(0)),
            DuplicateCandidate(item: file("z2"), size: .known(0)),
            DuplicateCandidate(item: file("u"), size: .unknown),
            DuplicateCandidate(item: .photo("live"), size: .known(3), isComparable: false),
            DuplicateCandidate(item: file("x"), size: .known(3)),
            DuplicateCandidate(item: file("cloud"), size: .known(3)),
        ], source: src)
        #expect(r.groups.isEmpty)
        #expect(r.zeroByte == [file("z1"), file("z2")])
        #expect(r.notChecked.contains(file("u")))
        #expect(r.notChecked.contains(file("cloud")))
        #expect(r.notComparable == [.photo("live")])
    }

    @Test("Aliasquellen zählen nicht als eigene Kopie")
    func aliases() throws {
        let src = MemoryByteSource()
        src.contents[file("a")] = Data([1, 2, 3, 4])
        src.contents[file("alias-a")] = Data([1, 2, 3, 4])
        let r = try DuplicateFinder().scan([
            DuplicateCandidate(item: file("a"), size: .known(4), aliasKey: "res-1"),
            DuplicateCandidate(item: file("alias-a"), size: .known(4), aliasKey: "res-1"),
        ], source: src)
        #expect(r.groups.isEmpty)
    }

    @Test("SHA-256 entspricht Testvektor")
    func sha256Vector() throws {
        let src = MemoryByteSource()
        src.contents[file("abc")] = Data("abc".utf8)
        let h = try DuplicateFinder().hash(file("abc"), source: src, limit: nil)
        #expect(h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Scan ist abbrechbar")
    func cancellation() async throws {
        let src = MemoryByteSource()
        for i in 0..<50 { src.contents[file("f\(i)")] = Data(repeating: 1, count: 200_000) }
        let candidates = (0..<50).map { DuplicateCandidate(item: file("f\($0)"), size: .known(200_000)) }
        let task = Task { () throws -> DuplicateScanResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try DuplicateFinder().scan(candidates, source: src)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@Suite("Regeln und Routinen")
struct RuleTests {
    let tz = TimeZone(identifier: "Europe/Zurich")!

    func inv(_ n: Int, daysOld: Int, size: KnownSize = .known(1), now: Date, firstSeen: Date? = nil) -> InventoryItem {
        InventoryItem(item: photo(n), source: .screenshots, createdAt: now.addingTimeInterval(Double(-daysOld) * 86_400),
                      size: size, firstSeenAt: firstSeen ?? now)
    }

    @Test("Screenshots älter als 30 Tage → Review-Aufgabe, idempotent pro Tag, keine Löschung")
    func olderThan() {
        let now = TestClock.date("2026-06-10T09:00", tz: tz.identifier)
        let rule = ReviewRule(source: .screenshots, filter: .olderThan(days: 30), trigger: .daily)
        let items = [inv(1, daysOld: 45, now: now), inv(2, daysOld: 5, now: now)]
        let task = RuleEvaluator.evaluate(rule, inventory: items, records: [:], existingTaskIDs: [],
                                          lastEvaluatedAt: nil, now: now, timeZone: tz)
        #expect(task?.items == [photo(1)])
        let again = RuleEvaluator.evaluate(rule, inventory: items, records: [:], existingTaskIDs: [task!.id],
                                           lastEvaluatedAt: now, now: now.addingTimeInterval(3600), timeZone: tz)
        #expect(again == nil, "Keine doppelte Aufgabe am selben Tag")
    }

    @Test("Bereits entschiedene Items und unbekannte Größen werden nicht erfasst")
    func filters() {
        let now = TestClock.date("2026-06-10T09:00", tz: tz.identifier)
        let rule = ReviewRule(source: .screenshots, filter: .knownSizeAtLeast(bytes: 1_000_000_000), trigger: .daily)
        var kept = ItemRecord(item: photo(1)); kept.disposition = .kept
        let task = RuleEvaluator.evaluate(rule, inventory: [
            inv(1, daysOld: 1, size: .known(2_000_000_000), now: now),
            inv(2, daysOld: 1, size: .unknown, now: now),
            inv(3, daysOld: 1, size: .known(1_500_000_000), now: now),
        ], records: [photo(1): kept], existingTaskIDs: [], lastEvaluatedAt: nil, now: now, timeZone: tz)
        #expect(task?.items == [photo(3)])
    }

    @Test("Wöchentlich nur am Wochentag; deaktiviert: nichts")
    func weekly() {
        let sunday = TestClock.date("2026-06-14T09:00", tz: tz.identifier)
        let monday = TestClock.date("2026-06-15T09:00", tz: tz.identifier)
        var rule = ReviewRule(source: .screenshots, filter: .all, trigger: .weekly(weekday: 1))
        let items = [inv(1, daysOld: 1, now: sunday)]
        #expect(RuleEvaluator.evaluate(rule, inventory: items, records: [:], existingTaskIDs: [], lastEvaluatedAt: nil, now: sunday, timeZone: tz) != nil)
        #expect(RuleEvaluator.evaluate(rule, inventory: items, records: [:], existingTaskIDs: [], lastEvaluatedAt: nil, now: monday, timeZone: tz) == nil)
        rule.isEnabled = false
        #expect(RuleEvaluator.evaluate(rule, inventory: items, records: [:], existingTaskIDs: [], lastEvaluatedAt: nil, now: sunday, timeZone: tz) == nil)
    }

    @Test("Nach zehn neu entdeckten Items eine Aufgabe")
    func newlyDiscovered() {
        let last = TestClock.date("2026-06-09T09:00", tz: tz.identifier)
        let now = TestClock.date("2026-06-10T09:00", tz: tz.identifier)
        let rule = ReviewRule(source: .screenshots, filter: .all, trigger: .newlyDiscovered(count: 10))
        let nine = (0..<9).map { inv($0, daysOld: 0, now: now) }
        let old = (100..<120).map { inv($0, daysOld: 3, now: now, firstSeen: last.addingTimeInterval(-60)) }
        #expect(RuleEvaluator.evaluate(rule, inventory: nine + old, records: [:], existingTaskIDs: [], lastEvaluatedAt: last, now: now, timeZone: tz) == nil)
        let ten = (0..<10).map { inv($0, daysOld: 0, now: now) }
        #expect(RuleEvaluator.evaluate(rule, inventory: ten + old, records: [:], existingTaskIDs: [], lastEvaluatedAt: last, now: now, timeZone: tz)?.items.count == 10)
    }
}

@Suite("Free, Pro, Rewarded")
struct CapabilityTests {
    let tz = TimeZone(identifier: "Europe/Zurich")!

    @Test("Kaufzustände", arguments: [PurchaseState.unknown, .notPurchased, .pending, .purchased, .revoked])
    func purchaseStates(_ state: PurchaseState) {
        let caps = Capabilities.resolve(purchase: state, rewards: RewardLedger(), now: Date())
        if state == .purchased {
            #expect(caps.tier == .pro && caps.dailyCleanupLimit == nil && !caps.adsAllowed && caps.exactDuplicates)
        } else {
            #expect(caps.tier == .free && caps.dailyCleanupLimit == 15 && !caps.exactDuplicates)
            #expect(caps.adsAllowed == (state != .unknown))
        }
    }

    @Test("Reward: 30 reale Minuten, idempotent, einmal pro Tag, Limit bleibt 15")
    func reward() throws {
        let now = TestClock.date("2026-06-10T09:00", tz: tz.identifier)
        var ledger = RewardLedger()
        let w = try ledger.grant(rewardID: "r1", now: now, timeZone: tz, purchase: .notPurchased)
        #expect(try ledger.grant(rewardID: "r1", now: now.addingTimeInterval(5), timeZone: tz, purchase: .notPurchased) == w)
        #expect(throws: RewardError.dailyUnlockUsed) {
            try ledger.grant(rewardID: "r2", now: now.addingTimeInterval(3600), timeZone: tz, purchase: .notPurchased)
        }
        let during = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(10 * 60))
        #expect(during.tier == .rewardedPreview && during.exactDuplicates && during.dailyCleanupLimit == 15)
        #expect(!during.persistentRoutines && during.oneTimeRuleTestScan)
        #expect(abs((during.rewardRemaining ?? 0) - 20 * 60) < 0.001)
        let after = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(30 * 60 + 1))
        #expect(after.tier == .free)
        // Nächster Tag: erneut möglich.
        #expect(ledger.canOfferReward(now: now.addingTimeInterval(86_400), timeZone: tz, purchase: .notPurchased))
    }

    @Test("Uhr zurückgestellt: Vorschau konservativ abgelaufen")
    func clockBack() throws {
        let now = TestClock.date("2026-06-10T09:00", tz: tz.identifier)
        var ledger = RewardLedger()
        _ = try ledger.grant(rewardID: "r1", now: now, timeZone: tz, purchase: .notPurchased)
        #expect(ledger.active(at: now.addingTimeInterval(-60)) == nil)
    }

    @Test("Pro: kein Reward, keine Ads")
    func proNoAds() {
        var ledger = RewardLedger()
        #expect(throws: RewardError.alreadyPurchased) {
            try ledger.grant(rewardID: "r", now: Date(), timeZone: tz, purchase: .purchased)
        }
        #expect(!ledger.canOfferReward(now: Date(), timeZone: tz, purchase: .purchased))
    }

    @Test("Arbeitseinheit startet nur mit Fähigkeit und läuft nach Ablauf zu Ende")
    func workUnit() throws {
        let now = TestClock.date("2026-06-10T09:00", tz: tz.identifier)
        var ledger = RewardLedger()
        _ = try ledger.grant(rewardID: "r1", now: now, timeZone: tz, purchase: .notPurchased)
        let caps = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(29 * 60))
        #expect(WorkUnitGrant.begin(requires: \.exactDuplicates, in: caps, now: now) != nil)
        let expired = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(31 * 60))
        #expect(WorkUnitGrant.begin(requires: \.exactDuplicates, in: expired, now: now) == nil)
    }

    @Test("Speicherübersicht addiert keine überlappenden Kategorien")
    func storage() {
        let o = StorageOverview(device: DeviceCapacity(totalBytes: 128, availableForImportantUsageBytes: 64),
                                categories: [.photos: SizeTally([.known(10), .unknown]), .videos: SizeTally([.known(20)]),
                                             .screenshots: SizeTally([.known(5)]), .duplicates: SizeTally([.known(10)])],
                                scannedAt: nil)
        #expect(o.scannedTotal.knownBytes == 30)
        #expect(o.scannedTotal.isLowerBound)
        #expect(StorageCategory.screenshots.isOverlappingView)
    }
}
