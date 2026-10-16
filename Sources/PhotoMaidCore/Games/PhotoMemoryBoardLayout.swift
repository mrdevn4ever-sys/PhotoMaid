import Foundation

/// Fits the deck to the available viewport without shrinking a card below a 44-point touch target.
public struct PhotoMemoryBoardLayout: Equatable, Sendable {
    public let columns: Int
    public let cardHeight: Double
    public let height: Double
    public let requiresScrolling: Bool

    public init(cards: Int, width: Double, availableHeight: Double, accessibility: Bool = false) {
        let count = max(1, cards), gap = 8.0
        let width = max(44, width), available = max(44, availableHeight)
        let maximum = accessibility ? 2 : min(6, max(1, Int((width + gap) / (44 + gap))))
        var chosen = 1, chosenHeight = 44.0, chosenScore = -Double.infinity
        for cols in 1...maximum {
            let rows = (count + cols - 1) / cols
            let cellWidth = (width - Double(cols - 1) * gap) / Double(cols)
            let preferred = min(accessibility ? 180 : 112, cellWidth * 1.08)
            let cellHeight = max(44, min(preferred, (available - Double(rows - 1) * gap) / Double(rows)))
            let total = Double(rows) * cellHeight + Double(rows - 1) * gap
            let fits = total <= available + 0.5
            let score = min(cellWidth, cellHeight) + (fits ? 10_000 : -total)
            if score > chosenScore { chosen = cols; chosenHeight = cellHeight; chosenScore = score }
        }
        columns = chosen; cardHeight = chosenHeight
        height = Double((count + chosen - 1) / chosen) * chosenHeight + Double((count + chosen - 1) / chosen - 1) * gap
        requiresScrolling = height > available + 0.5
    }
}
