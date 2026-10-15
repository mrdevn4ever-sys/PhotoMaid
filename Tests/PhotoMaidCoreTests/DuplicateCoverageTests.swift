import Foundation
import Testing
@testable import PhotoMaidCore

@Suite("Vollständige Duplikatprüfung")
struct DuplicateCoverageTests {
    private func part(_ role: Int, _ hash: String, bytes: Int64 = 10) -> DuplicateResourceDigest {
        .init(role: role, bytes: bytes, partial: hash, full: hash)
    }

    @Test func resourceOrderAndNamesDoNotMatter() {
        let photo = part(1, "photo"), motion = part(9, "motion")
        #expect(DuplicateResourceSet.hash([photo, motion], partial: false)
                == DuplicateResourceSet.hash([motion, photo], partial: false))
    }
    @Test func differentLiveVideoIsNotAnExactCopy() {
        #expect(DuplicateResourceSet.hash([part(1, "same-photo"), part(9, "video-a")], partial: false)
                != DuplicateResourceSet.hash([part(1, "same-photo"), part(9, "video-b")], partial: false))
    }
    @Test func rawAndEditsMustAlsoMatch() {
        let original = part(1, "original")
        let jpeg = part(1, "jpeg")
        #expect(DuplicateResourceSet.hash([original, jpeg], partial: false)
                != DuplicateResourceSet.hash([original, part(1, "different-jpeg")], partial: false))
        #expect(DuplicateResourceSet.hash([original, part(5, "edit-a")], partial: false)
                != DuplicateResourceSet.hash([original, part(5, "edit-b")], partial: false))
    }
    @Test func resourceRolesAndMultiplicityMatter() {
        let a = part(1, "a"), b = part(9, "b")
        #expect(DuplicateResourceSet.hash([a, b], partial: false) != DuplicateResourceSet.hash([a, b, b], partial: false))
        #expect(DuplicateResourceSet.hash([a, b], partial: false)
                != DuplicateResourceSet.hash([a, part(2, "b")], partial: false))
    }
    @Test func singleResourceStillMatchesAnOrdinaryFile() {
        #expect(DuplicateResourceSet.hash([part(1, "raw-sha256")], partial: false) == "raw-sha256")
        #expect(DuplicateResourceSet.hash([], partial: false) == nil)
    }
    @Test func compoundSignaturesHaveTheirOwnNamespace() throws {
        let hash = try #require(DuplicateResourceSet.hash([part(1, "a"), part(9, "b")], partial: false))
        #expect(hash.hasPrefix("resources-v1:"))
    }
    @Test func truncatedStreamsAreNotDuplicates() throws {
        let source = MemoryByteSource()
        source.contents[file("a")] = Data([1, 2, 3])
        source.contents[file("b")] = Data([1, 2, 3])
        let r = try DuplicateFinder().scan(["a", "b"].map { .init(item: file($0), size: .known(5)) }, source: source)
        #expect(r.groups.isEmpty)
        #expect(r.notChecked.count == 2)
        #expect(!r.isComplete && r.uncheckedCount == 2)
    }
    @Test func oneReadFailureDoesNotAbortTheOtherFiles() throws {
        let source = FailingDuplicateSource()
        let r = try DuplicateFinder().scan(["a", "b", "broken"].map { .init(item: file($0), size: .known(3)) }, source: source)
        #expect(r.groups.count == 1)
        #expect(Set(r.groups[0].members) == [file("a"), file("b")])
        #expect(r.notChecked == [file("broken")])
    }
    @Test func completeAndIncompleteResultsAreDistinct() throws {
        let source = MemoryByteSource()
        source.contents[file("a")] = Data([1])
        let complete = try DuplicateFinder().scan([.init(item: file("a"), size: .known(1))], source: source)
        #expect(complete.isComplete)
        let incomplete = try DuplicateFinder().scan([.init(item: file("cloud"), size: .unknown)], source: source)
        #expect(!incomplete.isComplete)
        var missingFolder = complete
        missingFolder.unavailableSources = 1
        #expect(!missingFolder.isComplete)
    }
    @Test func compoundHashProviderIsUsedInsteadOfAnOriginalOnlyStream() throws {
        let source = CompoundDuplicateSource()
        let r = try DuplicateFinder().scan(["a", "b", "different-motion"].map {
            .init(item: file($0), size: .known(100_000))
        }, source: source)
        #expect(r.groups.count == 1)
        #expect(Set(r.groups[0].members) == [file("a"), file("b")])
    }
    @Test func progressAdvancesWithinALargeBucket() throws {
        let source = MemoryByteSource()
        source.contents[file("a")] = Data(repeating: 7, count: 100_000)
        source.contents[file("b")] = source.contents[file("a")]
        let log = DuplicateProgressLog()
        _ = try DuplicateFinder().scan(["a", "b"].map { .init(item: file($0), size: .known(100_000)) }, source: source) { log.add($0) }
        let values = log.values
        #expect(values.map(\.processed) == values.map(\.processed).sorted())
        #expect(values.contains { $0.processed == 3 })
        #expect(values.last?.processed == values.last?.total)
    }
    @Test func cancellationIsNotConvertedIntoAnUnreadableItem() {
        #expect(throws: CancellationError.self) {
            try DuplicateFinder().scan(["a", "b"].map { .init(item: file($0), size: .known(3)) }, source: CancelledDuplicateSource())
        }
    }
    @Test func filesWithoutMetadataSizeAreMeasuredWithBothHashes() throws {
        let source = MemoryByteSource()
        source.contents[file("unknown-size")] = Data(repeating: 7, count: 100_000)
        let finder = DuplicateFinder()
        let measured = try finder.measure(file("unknown-size"), source: source)
        let value = try #require(measured)
        #expect(value.bytes == 100_000)
        #expect(value.partial == (try finder.hash(file("unknown-size"), source: source, limit: finder.partialHashBytes)))
        #expect(value.full == (try finder.hash(file("unknown-size"), source: source, limit: nil)))
    }
}

private final class DuplicateProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DuplicateScanProgress] = []
    func add(_ value: DuplicateScanProgress) { lock.withLock { stored.append(value) } }
    var values: [DuplicateScanProgress] { lock.withLock { stored } }
}
private struct CancelledDuplicateSource: ByteSourceProvider {
    func openStream(for item: ItemReference) throws -> (any ByteStream)? { throw CancellationError() }
}

private struct FailingDuplicateSource: ByteSourceProvider {
    func openStream(for item: ItemReference) throws -> (any ByteStream)? {
        if item.localIdentifier == "broken" { throw DuplicateReadError.incompleteOrChanged }
        let source = MemoryByteSource()
        source.contents[item] = Data([1, 2, 3])
        return try source.openStream(for: item)
    }
}
private struct CompoundDuplicateSource: DuplicateContentHashSource {
    func openStream(for item: ItemReference) throws -> (any ByteStream)? {
        Issue.record("Compound content must never be reduced to the original image alone")
        return nil
    }
    func contentHash(for item: ItemReference, limit: Int?, expectedSize: Int64?) throws -> String? {
        if limit != nil { return "same-prefix" }
        return item.localIdentifier == "different-motion" ? "resources-v1:different" : "resources-v1:same"
    }
}
