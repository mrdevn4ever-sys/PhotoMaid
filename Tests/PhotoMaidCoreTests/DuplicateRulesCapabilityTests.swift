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

    /// Masterprompt: 50 000 Metadaten, nur Kandidaten mit gleicher Größe werden gelesen.
    @Test("50 000 Einträge: nur Kandidaten werden gelesen")
    func fiftyThousandEntriesHashOnlyCandidates() throws {
        let src = MemoryByteSource()
        var candidates = (0..<50_000).map { DuplicateCandidate(item: file("m\($0)"), size: .known(1_000 + Int64($0))) }
        candidates += [DuplicateCandidate(item: file("dupA"), size: .known(5)), DuplicateCandidate(item: file("dupB"), size: .known(5))]
        src.contents[file("dupA")] = Data([1, 2, 3, 4, 5])
        src.contents[file("dupB")] = Data([1, 2, 3, 4, 5])
        let r = try DuplicateFinder().scan(candidates, source: src)
        #expect(r.groups.count == 1)
        #expect(src.opened == 2, "kein Full-Hash ohne Kandidatenfilter")
    }
}

@Suite("Sammlungen")
struct CollectionTests {
    let tz = TimeZone(identifier: "Europe/Zurich")!
    var now: Date { TestClock.date("2026-06-10T09:00", tz: "Europe/Zurich") }

    func cand(_ n: Int, _ daysOld: Double?, _ size: KnownSize = .known(1)) -> CollectionCandidate {
        CollectionCandidate(item: photo(n), createdAt: daysOld.map { now.addingTimeInterval(-$0 * 86_400) }, size: size)
    }

    @Test func olderThan() {
        let c = SmartCollection(source: .screenshots, filter: .olderThan(days: 30))
        let r = SmartCollections.evaluate(c, candidates: [cand(1, 45), cand(2, 5), cand(3, nil)], records: [:], now: now, timeZone: tz)
        #expect(r.items == [photo(1)]) // ohne Datum nicht enthalten
    }

    @Test func largerThanExcludesDecidedAndUnknownButReportsUnknown() {
        let c = SmartCollection(source: .videos, filter: .largerThan(bytes: 50_000_000))
        let kept = ItemRecord(item: photo(1), disposition: .kept)
        let r = SmartCollections.evaluate(c, candidates: [
            cand(1, 1, .known(80_000_000)), cand(2, 1, .unknown), cand(3, 1, .known(60_000_000)),
            cand(4, 1, .known(50_000_000)), // genau 50 MB ist nicht „größer als“
        ], records: [photo(1): kept], now: now, timeZone: tz)
        #expect(r.items == [photo(3)])
        #expect(r.knownBytes == 60_000_000)
        #expect(r.unknownSizeCount == 1)
    }

    @Test func alwaysCurrentNoTrigger() {
        let c = SmartCollections.builtIns[0]
        let items = [cand(1, 1, .known(200_000_000))]
        #expect(SmartCollections.evaluate(c, candidates: items, records: [:], now: now, timeZone: tz).items.count == 1)
        #expect(SmartCollections.evaluate(c, candidates: items, records: [:], now: now.addingTimeInterval(60), timeZone: tz).items.count == 1)
        let later = ItemRecord(item: photo(1), disposition: .later, dueDay: LocalDay(now, timeZone: tz).adding(days: 2))
        #expect(SmartCollections.evaluate(c, candidates: items, records: [photo(1): later], now: now, timeZone: tz).items.isEmpty)
    }

    @Test func builtInsAreStableAndSizeChoicesFitMediaType() {
        #expect(SmartCollections.builtIns.allSatisfy { $0.builtIn })
        #expect(Set(SmartCollections.builtIns.map(\.id)).count == SmartCollections.builtIns.count)
        #expect(SmartCollections.sizeChoices(.photos).allSatisfy { $0 <= 20_000_000 })
        #expect(SmartCollections.sizeChoices(.videos)[0] >= 50_000_000)
        // Gleiche feste IDs wie Android (UUID(0x50686f746f4d6169, 1)).
        #expect(SmartCollections.builtIns[0].id.rawValue.uuidString.lowercased() == "50686f74-6f4d-6169-0000-000000000001")
    }

    @Test func codableRoundTrip() throws {
        let c = SmartCollection(source: .photos, filter: .largerThan(bytes: 5_000_000))
        let back = try JSONDecoder().decode(SmartCollection.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }
}

@Suite("Free, Pro-Test, Lifetime Pro")
struct CapabilityTests {
    let tz = TimeZone(identifier: "Europe/Zurich")!
    var now: Date { TestClock.date("2026-06-10T09:00", tz: "Europe/Zurich") }

    @Test func purchaseStates() {
        for state in [PurchaseState.unknown, .notPurchased, .pending, .purchased, .revoked] {
            let caps = Capabilities.resolve(purchase: state, rewards: RewardLedger(), now: now, timeZone: tz)
            if state == .purchased {
                #expect(caps.tier == .lifetimePro && caps.dailyCleanupLimit == nil && !caps.adsAllowed && caps.exactDuplicates)
                #expect(caps.batchLimit == nil)
            } else {
                #expect(caps.tier == .free && caps.dailyCleanupLimit == 20 && !caps.exactDuplicates)
                #expect(caps.adsAllowed == (state != .unknown))
                #expect(caps.batchLimit == 10)
            }
        }
    }

    @Test func reward() throws {
        var ledger = RewardLedger()
        let w = try ledger.grant(rewardID: "r1", now: now, timeZone: tz, purchase: .notPurchased)
        #expect(try ledger.grant(rewardID: "r1", now: now.addingTimeInterval(5), timeZone: tz, purchase: .notPurchased) == w)
        #expect(throws: RewardError.dailyUnlockUsed) {
            try ledger.grant(rewardID: "r2", now: now.addingTimeInterval(3600), timeZone: tz, purchase: .notPurchased)
        }
        let during = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(600), timeZone: tz)
        #expect(during.tier == .temporaryPro && during.exactDuplicates && during.dailyCleanupLimit == 20)
        #expect(during.hasProToolsAccess && !during.hasUnlimitedTrashAccess)
        #expect(during.customCollections)
        #expect(abs((during.rewardRemaining ?? 0) - 20 * 60) < 1)
        #expect(Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(30 * 60 + 1), timeZone: tz).tier == .free)
        #expect(ledger.canOfferReward(now: now.addingTimeInterval(86_400), timeZone: tz, purchase: .notPurchased))
    }

    @Test func limitBonusOnlyToday() throws {
        var ledger = RewardLedger()
        try ledger.grantBonus(rewardID: "b1", now: now, timeZone: tz, purchase: .notPurchased)
        #expect(throws: RewardError.dailyBonusUsed) {
            try ledger.grantBonus(rewardID: "b2", now: now.addingTimeInterval(60), timeZone: tz, purchase: .notPurchased)
        }
        #expect(Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now, timeZone: tz).dailyCleanupLimit == 40)
        #expect(Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(86_400), timeZone: tz).dailyCleanupLimit == 20)
        // Pro-Test und Bonus sind getrennt; der Test hebt das Limit nie auf.
        try ledger.grant(rewardID: "t1", now: now, timeZone: tz, purchase: .notPurchased)
        let both = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(60), timeZone: tz)
        #expect(both.tier == .temporaryPro && both.dailyCleanupLimit == 40)
    }

    @Test func clockBackExpiresConservatively() throws {
        var ledger = RewardLedger()
        try ledger.grant(rewardID: "r1", now: now, timeZone: tz, purchase: .notPurchased)
        #expect(ledger.active(at: now.addingTimeInterval(-60)) == nil)
        #expect(ledger.usedToday(now: now.addingTimeInterval(-86_400 * 2), timeZone: tz))
    }

    @Test func proNoRewardNoAds() {
        var ledger = RewardLedger()
        #expect(throws: RewardError.alreadyPurchased) {
            try ledger.grant(rewardID: "r", now: now, timeZone: tz, purchase: .purchased)
        }
        #expect(!RewardLedger().canOfferReward(now: now, timeZone: tz, purchase: .purchased))
    }

    @Test func workUnit() throws {
        var ledger = RewardLedger()
        try ledger.grant(rewardID: "r1", now: now, timeZone: tz, purchase: .notPurchased)
        let caps = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(29 * 60), timeZone: tz)
        #expect(WorkUnitGrant.begin(requires: \.exactDuplicates, in: caps, now: now) != nil)
        let expired = Capabilities.resolve(purchase: .notPurchased, rewards: ledger, now: now.addingTimeInterval(31 * 60), timeZone: tz)
        #expect(WorkUnitGrant.begin(requires: \.exactDuplicates, in: expired, now: now) == nil)
    }

    @Test func storageDoesNotAddOverlappingCategories() {
        let o = StorageOverview(device: DeviceCapacity(totalBytes: 128, availableForImportantUsageBytes: 64), categories: [
            .photos: SizeTally([.known(10), .unknown]),
            .videos: SizeTally([.known(20)]),
            .screenshots: SizeTally([.known(5)]),
            .duplicates: SizeTally([.known(10)]),
        ], scannedAt: nil)
        #expect(o.scannedTotal.knownBytes == 30)
        #expect(o.scannedTotal.isLowerBound)
        #expect(StorageCategory.screenshots.isOverlappingView)
    }

    @Test func rewardLedgerDecodesOlderFormat() throws {
        let old = #"{"windows":[]}"#
        let l = try JSONDecoder().decode(RewardLedger.self, from: Data(old.utf8))
        #expect(l.bonuses.isEmpty)
    }
}
