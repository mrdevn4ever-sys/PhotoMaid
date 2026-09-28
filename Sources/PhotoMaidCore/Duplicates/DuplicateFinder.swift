import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Lesbare Byte-Quelle, die in Blöcken gestreamt wird. Große Dateien werden nie
/// vollständig in den Speicher geladen.
public protocol ByteStream: AnyObject {
    /// Liefert bis zu `maxLength` Bytes; leeres `Data` = Ende.
    func read(maxLength: Int) throws -> Data
    func close()
}

/// Liefert Ströme für vergleichbare Ressourcen. Nur lokal verfügbare Bytes;
/// iCloud-Originale werden **nicht** heimlich heruntergeladen (dann `nil`).
public protocol ByteSourceProvider: Sendable {
    func openStream(for item: ItemReference) throws -> (any ByteStream)?
}

/// Kandidat für die Duplikatprüfung. Nur Kandidaten mit einer definierten,
/// vollständig vergleichbaren Ressourcenmenge dürfen als exakt identisch gelten.
public struct DuplicateCandidate: Hashable, Sendable {
    public let item: ItemReference
    public let size: KnownSize
    /// `false` für Live Photos, RAW+JPEG, bearbeitete Assets u. ä.: werden separat gelistet.
    public let isComparable: Bool
    /// Gleiche physische Ressource über mehrere Quellen (z. B. Datei-Ressourcen-ID).
    public let aliasKey: String?

    public init(item: ItemReference, size: KnownSize, isComparable: Bool = true, aliasKey: String? = nil) {
        self.item = item
        self.size = size
        self.isComparable = isComparable
        self.aliasKey = aliasKey
    }
}

public struct FileFingerprint: Hashable, Codable, Sendable {
    public let item: ItemReference
    public let size: Int64
    /// SHA-256 hex. Bleibt lokal, wird nie an externe Dienste übertragen.
    public let sha256: String
}

/// Hash-bestätigte Gruppe identischer Bytes.
public struct DuplicateGroup: Hashable, Sendable, Identifiable {
    public var id: String { sha256 }
    public let sha256: String
    public let sizeEach: Int64
    public let members: [ItemReference]

    public init(sha256: String, sizeEach: Int64, members: [ItemReference]) {
        self.sha256 = sha256
        self.sizeEach = sizeEach
        self.members = members
    }

    /// Alle identischen Dateien zusammen (z. B. 3 × 14 MB = 42 MB).
    public var totalBytes: Int64 { sizeEach * Int64(members.count) }
    /// Zusätzliche Kopien, wenn genau eine bleibt (z. B. 28 MB). Keine garantierte Ersparnis.
    public var extraCopiesBytes: Int64 { sizeEach * Int64(max(0, members.count - 1)) }

    /// Größe der ausgewählten Kopien. Auswahl aller Mitglieder ist unzulässig.
    public func selectedBytes(_ selection: Set<ItemReference>) -> Int64 {
        sizeEach * Int64(selection.intersection(members).count)
    }

    /// Mindestens eine Kopie bleibt erhalten.
    public func isValidSelection(_ selection: Set<ItemReference>) -> Bool {
        selection.isSubset(of: Set(members)) && selection.intersection(members).count < members.count
    }

    /// Standardauswahl: alle außer der zu behaltenden Kopie.
    public func defaultSelection(keeping keep: ItemReference) -> Set<ItemReference> {
        Set(members.filter { $0 != keep })
    }
}

public struct DuplicateScanResult: Hashable, Sendable {
    public var groups: [DuplicateGroup] = []
    /// Unbekannte Größe oder keine lokal verfügbaren Bytes.
    public var notChecked: [ItemReference] = []
    /// Komplexe Assets ohne definierte vergleichbare Ressourcenmenge.
    public var notComparable: [ItemReference] = []
    /// Nullbyte-Dateien sind trivial gleich und werden nicht als Duplikatgruppe gewertet.
    public var zeroByte: [ItemReference] = []
    public var hashedCount = 0
}

public struct DuplicateScanProgress: Hashable, Sendable {
    public let processed: Int
    public let total: Int
}

/// Deterministische, unterbrechbare Pipeline ohne KI:
/// 1. Inventar, 2. bekannte Größen als Filter, 3. Teilhash nur zum Aussortieren,
/// 4. vollständiges Streaming-SHA-256.
public struct DuplicateFinder: Sendable {
    public var chunkSize = 1 << 20
    public var partialHashBytes = 64 * 1024

    public init() {}

    public func scan(_ candidates: [DuplicateCandidate], source: any ByteSourceProvider,
                     progress: (@Sendable (DuplicateScanProgress) -> Void)? = nil) throws -> DuplicateScanResult {
        var result = DuplicateScanResult()
        var bySize: [Int64: [DuplicateCandidate]] = [:]
        var aliasSeen = Set<String>()

        for c in candidates {
            guard c.isComparable else { result.notComparable.append(c.item); continue }
            if let key = c.aliasKey {
                // Dieselbe physische Ressource nicht als eigene Kopie zählen.
                guard aliasSeen.insert(key).inserted else { continue }
            }
            switch c.size {
            case .unknown: result.notChecked.append(c.item)
            case .known(0): result.zeroByte.append(c.item)
            case .known(let b): bySize[b, default: []].append(c)
            }
        }

        let sizeBuckets = bySize.filter { $0.value.count > 1 }
        let total = sizeBuckets.values.reduce(0) { $0 + $1.count }
        var processed = 0

        for (size, bucket) in sizeBuckets.sorted(by: { $0.key > $1.key }) {
            try Task.checkCancellation()
            // Teilhash nur zum Aussortieren.
            var byPartial: [String: [DuplicateCandidate]] = [:]
            for c in bucket {
                try Task.checkCancellation()
                if let h = try hash(c.item, source: source, limit: partialHashBytes) {
                    byPartial[h, default: []].append(c)
                } else {
                    result.notChecked.append(c.item)
                }
            }
            for (partial, sub) in byPartial where sub.count > 1 {
                if size <= Int64(partialHashBytes) {
                    // Teilhash deckte die ganze Datei ab: bereits der vollständige SHA-256.
                    result.hashedCount += sub.count
                    result.groups.append(DuplicateGroup(sha256: partial, sizeEach: size,
                                                        members: sub.map(\.item).sorted { $0.description < $1.description }))
                    continue
                }
                var byFull: [String: [ItemReference]] = [:]
                for c in sub {
                    try Task.checkCancellation()
                    if let h = try hash(c.item, source: source, limit: nil) {
                        byFull[h, default: []].append(c.item)
                        result.hashedCount += 1
                    } else {
                        result.notChecked.append(c.item)
                    }
                }
                for (h, members) in byFull where members.count > 1 {
                    result.groups.append(DuplicateGroup(sha256: h, sizeEach: size,
                                                        members: members.sorted { $0.description < $1.description }))
                }
            }
            processed += bucket.count
            progress?(DuplicateScanProgress(processed: processed, total: total))
        }
        result.groups.sort { ($0.extraCopiesBytes, $0.sha256) > ($1.extraCopiesBytes, $1.sha256) }
        return result
    }

    /// SHA-256 der ersten `limit` Bytes (oder aller). `nil`, wenn keine lokalen Bytes verfügbar.
    public func hash(_ item: ItemReference, source: any ByteSourceProvider, limit: Int?) throws -> String? {
        guard let stream = try source.openStream(for: item) else { return nil }
        defer { stream.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            try Task.checkCancellation()
            let chunk = try stream.read(maxLength: min(chunkSize, remaining))
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Vor einer riskanten Aktion: Bytes erneut vollständig vergleichen.
    public func bytesIdentical(_ a: ItemReference, _ b: ItemReference, source: any ByteSourceProvider) throws -> Bool {
        guard let sa = try source.openStream(for: a), let sb = try source.openStream(for: b) else { return false }
        defer { sa.close(); sb.close() }
        while true {
            try Task.checkCancellation()
            let ca = try sa.read(maxLength: chunkSize)
            var cb = Data()
            while cb.count < ca.count {
                let more = try sb.read(maxLength: ca.count - cb.count)
                if more.isEmpty { break }
                cb.append(more)
            }
            if ca != cb { return false }
            if ca.isEmpty { return try sb.read(maxLength: 1).isEmpty }
        }
    }
}

/// Einfache Stream-Implementierung über `FileHandle` (security-scoped Zugriff liegt beim Aufrufer).
public final class FileHandleByteStream: ByteStream {
    private let handle: FileHandle
    public init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
    public func read(maxLength: Int) throws -> Data { try handle.read(upToCount: maxLength) ?? Data() }
    public func close() { try? handle.close() }
}
