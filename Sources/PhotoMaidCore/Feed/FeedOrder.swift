import Foundation

/// Reihenfolge der offenen Medien im Feed. Ändert nur die Abfolge, nie welche Medien offen sind.
public enum FeedOrder: String, Hashable, Codable, Sendable, CaseIterable {
    case newest, oldest, largest, random
}

public enum FeedOrdering {
    /// Sortiert stabil: bei gleichem Schlüssel entscheidet die ID. Unbekanntes Datum/unbekannte Größe stehen immer am
    /// Ende (unbekannt ≠ 0). `.random` mischt mit festem Startwert je Sitzung, damit „runter“ zuverlässig zurückführt.
    public static func apply<T>(_ items: [T], order: FeedOrder, date: (T) -> Date?, size: (T) -> Int64?,
                                id: (T) -> String, seed: UInt64 = 0) -> [T] {
        switch order {
        case .newest:
            return items.sorted { a, b in
                switch (date(a), date(b)) {
                case let (x?, y?): return x != y ? x > y : id(a) < id(b)
                case (nil, nil): return id(a) < id(b)
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        case .oldest:
            return items.sorted { a, b in
                switch (date(a), date(b)) {
                case let (x?, y?): return x != y ? x < y : id(a) < id(b)
                case (nil, nil): return id(a) < id(b)
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        case .largest:
            return items.sorted { a, b in
                switch (size(a), size(b)) {
                case let (x?, y?): return x != y ? x > y : id(a) < id(b)
                case (nil, nil): return id(a) < id(b)
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        case .random:
            var rng = SeededGenerator(seed: seed)
            return items.sorted { id($0) < id($1) }.shuffled(using: &rng)
        }
    }
}

/// Deterministischer Zufallsgenerator (SplitMix64) – gleiche Reihenfolge für denselben Startwert auf allen Plattformen.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
