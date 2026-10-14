import Foundation
import Testing
@testable import PhotoMaidCore

private final class MemoryHashCache: DuplicateHashCache, @unchecked Sendable {
    private let lock = NSLock()
    private var partial: [ItemReference: String] = [:]
    private var full: [ItemReference: String] = [:]
    func partialHash(_ item: ItemReference) -> String? { lock.withLock { partial[item] } }
    func fullHash(_ item: ItemReference) -> String? { lock.withLock { full[item] } }
    func store(_ item: ItemReference, partial p: String?, full f: String?) {
        lock.withLock {
            if let p { partial[item] = p }
            if let f { full[item] = f }
        }
    }
    var fullCount: Int { lock.withLock { full.count } }
}

@Suite struct SizeInventoryTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let modified = Date(timeIntervalSince1970: 500)

    func item(_ id: String, video: Bool = false, w: Int = 4032, h: Int = 3024, duration: TimeInterval = 0,
              modified: Date? = Date(timeIntervalSince1970: 500)) -> InventoryItem {
        InventoryItem(id: id, modified: modified, isVideo: video, width: w, height: h, duration: duration)
    }

    @Test func unknownIsNeverZeroAndOnlyKnownHasBytes() {
        let r = SizeRecord(modified: modified, state: .notLocal, bytes: 99, checkedAt: now)
        #expect(r.bytes == nil)
        #expect(r.size == .unknown)
        #expect(SizeRecord(modified: modified, state: .known, bytes: 42, checkedAt: now).size == .known(42))
    }

    @Test func measureOnlyWhatIsMissingChangedOrDue() {
        let a = item("a")
        #expect(SizeInventory.needsMeasure(a, record: nil, now: now))
        let known = SizeRecord(modified: modified, state: .known, bytes: 1, checkedAt: now)
        #expect(!SizeInventory.needsMeasure(a, record: known, now: now))
        // Medium geändert: neu messen.
        #expect(SizeInventory.needsMeasure(item("a", modified: Date(timeIntervalSince1970: 501)), record: known, now: now))
        // Nur in iCloud: erst nach der Wartezeit erneut prüfen (sonst bei jedem Öffnen 19 000 Anfragen).
        let cloud = SizeRecord(modified: modified, state: .notLocal, checkedAt: now)
        #expect(!SizeInventory.needsMeasure(a, record: cloud, now: now.addingTimeInterval(3600)))
        #expect(SizeInventory.needsMeasure(a, record: cloud, now: now.addingTimeInterval(SizeInventory.recheckNotLocal)))
        let broken = SizeRecord(modified: modified, state: .unreadable, checkedAt: now)
        #expect(!SizeInventory.needsMeasure(a, record: broken, now: now.addingTimeInterval(3600)))
        // Uhr zurückgestellt: lieber neu prüfen als nie wieder.
        #expect(SizeInventory.needsMeasure(a, record: cloud, now: now.addingTimeInterval(-10)))
    }

    @Test func videosFirstLongestFirstThenLargestPhotos() {
        let order = SizeInventory.order([
            item("small", w: 100, h: 100), item("short", video: true, duration: 5), item("big", w: 8000, h: 6000),
            item("long", video: true, duration: 300),
        ]).map(\.id)
        #expect(order == ["long", "short", "big", "small"])
    }

    @Test func countsSeparateNotMeasuredFromUnknown() {
        let items = [item("a"), item("b"), item("c"), item("d"), item("e", modified: Date(timeIntervalSince1970: 9))]
        let records: [String: SizeRecord] = [
            "a": SizeRecord(modified: modified, state: .known, bytes: 5, checkedAt: now),
            "b": SizeRecord(modified: modified, state: .notLocal, checkedAt: now),
            "c": SizeRecord(modified: modified, state: .unreadable, checkedAt: now),
            // veraltet (Medium geändert) zählt als noch nicht gemessen
            "e": SizeRecord(modified: modified, state: .known, bytes: 5, checkedAt: now),
        ]
        let c = SizeInventory.counts(items, records: records)
        #expect(c.known == 1 && c.notLocal == 1 && c.unreadable == 1 && c.notMeasured == 2 && c.total == 5)
    }

    @Test func prefilterKeepsOnlySharedShapes() {
        let ids = DuplicatePrefilter.candidates([
            item("p1"), item("p2"), item("p3", w: 1170, h: 2532),
            item("v1", video: true, w: 1920, h: 1080, duration: 12.0004), item("v2", video: true, w: 1920, h: 1080, duration: 12.0),
            item("v3", video: true, w: 1920, h: 1080, duration: 13),
            // Foto und Video mit gleichen Maßen sind nie byte-gleich
            item("x1", w: 1920, h: 1080),
        ])
        #expect(ids == ["p1", "p2", "v1", "v2"])
    }

    @Test func duplicateScanUsesAndFillsHashCache() throws {
        let src = MemoryByteSource()
        let n = 200 * 1024
        let a = Data((0..<n).map { UInt8($0 % 251) })
        var b = a; b[n - 1] ^= 0xFF
        src.contents[.photo("a")] = a
        src.contents[.photo("a2")] = a
        src.contents[.photo("b")] = b
        let cache = MemoryHashCache()
        let candidates = ["a", "a2", "b"].map { DuplicateCandidate(item: .photo($0), size: .known(Int64(n))) }
        let first = try DuplicateFinder().scan(candidates, source: src, cache: cache)
        #expect(first.groups.map(\.members) == [[.photo("a"), .photo("a2")]])
        #expect(cache.fullCount == 3)
        // Zweiter Durchlauf: nichts muss mehr gelesen werden, gleiches Ergebnis.
        let opened = src.opened
        let second = try DuplicateFinder().scan(candidates, source: src, cache: cache)
        #expect(second.groups == first.groups)
        #expect(src.opened == opened)
    }
}
