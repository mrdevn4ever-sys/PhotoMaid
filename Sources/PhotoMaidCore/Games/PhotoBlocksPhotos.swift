import Foundation

/// Metadata-only sequence, shared with tests. No image data, disk cache, cloud or analysis.
public struct PhotoBlocksPhotos: Equatable, Sendable {
    public enum Source: String, Codable, CaseIterable, Sendable { case random, newest, favorites, selection }
    public private(set) var order: [String]
    public init(ids: [String], shuffle: Bool, seed: UInt64) {
        var seen = Set<String>()
        order = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        if shuffle { var random = PhotoBlocksRandom(state: seed); random.shuffle(&order) }
    }
    /// Traverse every candidate before repeating, in the same reproducible cycle. Empty means neutral fallback.
    public func id(at level: Int) -> String? {
        guard !order.isEmpty else { return nil }
        return order[max(0, level - 1) % order.count]
    }
    public mutating func restrict(to allowed: Set<String>) { order.removeAll { !allowed.contains($0) } }

    /// Fixed normalized photo-space strips; board rows/compaction never participate in this calculation.
    public static func revealedHeight(strips: Int) -> Double { Double(min(10, max(0, strips))) / 10 }

    /// A snapshot is authoritative only for the filter configuration it actually queried.
    public static func scopeReady(loaded: Bool, requestedHidden: Set<String>, appliedHidden: Set<String>,
                                  requestedExcluded: Set<String>, appliedExcluded: Set<String>) -> Bool {
        loaded && requestedHidden == appliedHidden && requestedExcluded == appliedExcluded
    }
}
