import Foundation

/// „Gespart“ nach dem Leeren – nur aus TATSÄCHLICH entfernten Elementen mit bekannter Größe (keine Kandidatengrößen,
/// unbekannt ≠ 0). `unknownCount > 0` → Anzeige als „mind.“.
public struct CleanupSavings: Hashable, Codable, Sendable {
    public let bytes: Int64
    public let unknownCount: Int
    public let removedCount: Int

    public init(bytes: Int64, unknownCount: Int, removedCount: Int) {
        self.bytes = bytes
        self.unknownCount = unknownCount
        self.removedCount = removedCount
    }

    public var isLowerBound: Bool { unknownCount > 0 }

    public static func of(removed: Set<ItemReference>, sizes: [ItemReference: KnownSize]) -> CleanupSavings {
        var bytes: Int64 = 0
        var unknown = 0
        for r in removed {
            if case .known(let b)? = sizes[r] { bytes += b } else { unknown += 1 }
        }
        return CleanupSavings(bytes: bytes, unknownCount: unknown, removedCount: removed.count)
    }
}

/// Laufende Summe über alle Leerungen (lokal gespeichert, nur Zahlen).
public struct SavingsTotal: Hashable, Codable, Sendable {
    public var bytes: Int64
    public var lowerBound: Bool
    public init(bytes: Int64 = 0, lowerBound: Bool = false) { self.bytes = bytes; self.lowerBound = lowerBound }
    public func adding(_ s: CleanupSavings) -> SavingsTotal {
        SavingsTotal(bytes: bytes + s.bytes, lowerBound: lowerBound || s.isLowerBound)
    }
}
