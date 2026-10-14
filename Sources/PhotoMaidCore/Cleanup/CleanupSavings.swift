import Foundation

/// „Gespart“ nach dem Leeren – nur aus TATSÄCHLICH entfernten Elementen mit bekannter Größe (keine Kandidatengrößen,
/// unbekannt ≠ 0). `unknownCount > 0` → Anzeige als „mind.“.
public struct CleanupSavings: Hashable, Codable, Sendable {
    public let bytes: Int64
    public let unknownCount: Int
    public let removedCount: Int
    /// Schätzung für die Entfernten ohne Messung (z. B. nur in iCloud) – nur für die „ca.“-Anzeige (E17).
    public let estimatedBytes: Int64

    public init(bytes: Int64, unknownCount: Int, removedCount: Int, estimatedBytes: Int64 = 0) {
        self.bytes = bytes
        self.unknownCount = unknownCount
        self.removedCount = removedCount
        self.estimatedBytes = estimatedBytes
    }

    /// Zahl für die Anzeige: gemessen plus geschätzt; „ca.“, sobald ein Teil geschätzt ist.
    public var display: SizeValue {
        unknownCount > 0 && estimatedBytes > 0 ? .approximate(bytes + estimatedBytes) : .exact(bytes)
    }

    public var isLowerBound: Bool { unknownCount > 0 }
    /// True only when at least one removed item's size was actually measured.
    /// All-unknown batches must display "size unknown", never "0 KB saved".
    public var hasKnownSizes: Bool { removedCount > unknownCount }

    /// `estimates`: Schätzung je Eintrag ohne Messung (fehlt sie, bleibt es „unbekannt“ wie bisher).
    public static func of(removed: Set<ItemReference>, sizes: [ItemReference: KnownSize],
                          estimates: [ItemReference: Int64] = [:]) -> CleanupSavings {
        var bytes: Int64 = 0
        var unknown = 0
        var estimated: Int64 = 0
        var allEstimated = true
        for r in removed {
            if case .known(let b)? = sizes[r] {
                bytes += b
            } else {
                unknown += 1
                if let e = estimates[r], e > 0 { estimated += e } else { allEstimated = false }
            }
        }
        return CleanupSavings(bytes: bytes, unknownCount: unknown, removedCount: removed.count,
                              estimatedBytes: allEstimated ? estimated : 0)
    }
}

/// Laufende Summe über alle Leerungen (lokal gespeichert, nur Zahlen).
public struct SavingsTotal: Hashable, Codable, Sendable {
    public var bytes: Int64
    public var lowerBound: Bool
    /// Enthält geschätzte Teile (Anzeige „ca.“).
    public var approximate: Bool
    public init(bytes: Int64 = 0, lowerBound: Bool = false, approximate: Bool = false) {
        self.bytes = bytes
        self.lowerBound = lowerBound
        self.approximate = approximate
    }
    public func adding(_ s: CleanupSavings) -> SavingsTotal {
        let estimated = s.display.isApproximate
        return SavingsTotal(bytes: bytes + s.display.bytes, lowerBound: lowerBound || (s.isLowerBound && !estimated),
                            approximate: approximate || estimated)
    }
}
