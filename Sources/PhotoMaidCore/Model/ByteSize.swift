import Foundation

/// Eine Größenangabe, die unbekannt sein darf. Unbekannt ist niemals null.
public enum KnownSize: Hashable, Codable, Sendable {
    case known(Int64)
    case unknown

    public var bytes: Int64? {
        if case .known(let b) = self { return b }
        return nil
    }
}

/// Summe über mehrere Größen: bekannte Bytes und Anzahl unbekannter Einträge getrennt.
public struct SizeTally: Hashable, Codable, Sendable {
    public private(set) var knownBytes: Int64 = 0
    public private(set) var knownCount: Int = 0
    public private(set) var unknownCount: Int = 0

    public init() {}

    public init<S: Sequence>(_ sizes: S) where S.Element == KnownSize {
        for s in sizes { add(s) }
    }

    public mutating func add(_ size: KnownSize) {
        switch size {
        case .known(let b): knownBytes += b; knownCount += 1
        case .unknown: unknownCount += 1
        }
    }

    public mutating func merge(_ other: SizeTally) {
        knownBytes += other.knownBytes
        knownCount += other.knownCount
        unknownCount += other.unknownCount
    }

    public var totalCount: Int { knownCount + unknownCount }
    /// `true`, wenn die Bytezahl nur eine Untergrenze ist.
    public var isLowerBound: Bool { unknownCount > 0 }
}
