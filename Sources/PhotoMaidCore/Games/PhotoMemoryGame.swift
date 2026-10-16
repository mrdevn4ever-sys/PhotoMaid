import Foundation

/// A small, interruptible matching game. Pair identifiers are opaque: this type never reads or changes photos.
public struct PhotoMemoryGame: Equatable, Sendable {
    public static let maximumPairs = 18
    public struct Card: Identifiable, Equatable, Sendable {
        public let id: Int
        public let pairID: String
    }

    public enum Turn: Equatable, Sendable { case ignored, revealed, matched, mismatched }

    public let cards: [Card]
    public private(set) var faceUp: [Int] = []
    public private(set) var matchedPairs: Set<String> = []
    public private(set) var moves = 0

    public var pairCount: Int { cards.count / 2 }
    public var isFinished: Bool { matchedPairs.count == pairCount }
    public var hasMismatch: Bool { faceUp.count == 2 }

    /// Up to eighteen different pictures; duplicate selections never create ambiguous four-card pairs.
    public init?(pairIDs: [String], shuffled: Bool = true) {
        var seen = Set<String>()
        let pairs = pairIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard (2...Self.maximumPairs).contains(pairs.count) else { return nil }
        var deck = pairs.flatMap { [$0, $0] }
        if shuffled { deck.shuffle() }
        cards = deck.enumerated().map { Card(id: $0.offset, pairID: $0.element) }
    }

    public func isRevealed(_ card: Card) -> Bool {
        faceUp.contains(card.id) || matchedPairs.contains(card.pairID)
    }

    /// A pending mismatch blocks a third card. Repeated taps and taps on matched cards do not count as moves.
    @discardableResult
    public mutating func reveal(_ id: Int) -> Turn {
        guard !hasMismatch, let card = cards.first(where: { $0.id == id }),
              !isRevealed(card) else { return .ignored }
        faceUp.append(id)
        guard faceUp.count == 2 else { return .revealed }
        moves += 1
        let first = cards.first { $0.id == faceUp[0] }
        if first?.pairID == card.pairID {
            matchedPairs.insert(card.pairID)
            faceUp = []
            return .matched
        }
        return .mismatched
    }

    public mutating func concealMismatch() {
        if hasMismatch { faceUp = [] }
    }
}

/// Photo selection is independent of the game: a source never falls back to the rest of the library.
public enum PhotoMemorySelection {
    public struct Candidate: Sendable {
        public let id: String
        public let isPhoto: Bool
        public let isFavorite: Bool

        public init(id: String, isPhoto: Bool = true, isFavorite: Bool = false) {
            self.id = id; self.isPhoto = isPhoto; self.isFavorite = isFavorite
        }
    }

    public enum Scope: Sendable {
        case library, favorites, collection(Set<String>)
    }

    public static func pool(_ candidates: [Candidate], scope: Scope, excluding: Set<String> = []) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { item in
            guard item.isPhoto, !item.id.isEmpty, !excluding.contains(item.id), seen.insert(item.id).inserted else { return nil }
            switch scope {
            case .library: return item.id
            case .favorites: return item.isFavorite ? item.id : nil
            case .collection(let ids): return ids.contains(item.id) ? item.id : nil
            }
        }
    }

    /// Uniform random candidates, with bounded retries for previews unavailable locally. Never scan an entire
    /// library's images just to start a game; callers stop as soon as enough pictures have loaded.
    public static func sample(_ ids: [String], pairCount: Int, minimumCount: Int = 2) -> [String] {
        guard minimumCount >= 1, minimumCount <= PhotoMemoryGame.maximumPairs,
              (minimumCount...PhotoMemoryGame.maximumPairs).contains(pairCount) else { return [] }
        var seen = Set<String>()
        let unique = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard unique.count >= pairCount else { return [] }
        return Array(unique.shuffled().prefix(pairCount * 3))
    }
}
