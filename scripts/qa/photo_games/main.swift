// Standalone audit of production Core sources. See docs/GAMES_FUNCTION_UI_AUDIT.md.
import Foundation

var state: UInt64 = 90123
@MainActor func random(_ count: Int) -> Int {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return Int((state >> 32) % UInt64(count))
}
var snakeRounds = 0, snakeSteps = 0, memoryDecks = 0, memoryTaps = 0
for (width, height) in [(4,4), (6,6), (12,16), (24,24)] {
    for mode in PhotoSnakeGame.Mode.allCases {
        for seed in 0..<500 {
            var game = PhotoSnakeGame(width: width, height: height, mode: mode, seed: UInt64(seed))!
            snakeRounds += 1
            for _ in 0..<500 {
                if game.status != .playing { break }
                for _ in 0..<random(4) { _ = game.turn(PhotoSnakeGame.Direction.allCases[random(4)]) }
                let oldScore = game.score
                _ = game.step(); snakeSteps += 1
                precondition(game.body.count == 3 + game.score)
                precondition(Set(game.body).count == game.body.count)
                precondition(game.body.allSatisfy { $0.x >= 0 && $0.x < width && $0.y >= 0 && $0.y < height })
                precondition(game.score == oldScore || game.score == oldScore + 1)
                if let food = game.food { precondition(!game.body.contains(food)) }
                if game.status == .won { precondition(game.food == nil && game.body.count == width * height) }
            }
            if game.status != .playing {
                let ended = game
                for direction in PhotoSnakeGame.Direction.allCases { precondition(!game.turn(direction)) }
                precondition(game.step() == .ignored && game == ended)
            }
        }
    }
}
for pairCount in 2...18 {
    for _ in 0..<20 {
        var game = PhotoMemoryGame(pairIDs: (0..<pairCount).map(String.init))!
        memoryDecks += 1
        for _ in 0..<250 {
            let before = game
            let event = game.reveal(random(game.cards.count + 2) - 1)
            memoryTaps += 1
            if event == .ignored { precondition(game == before) }
            precondition(game.faceUp.count <= 2 && Set(game.faceUp).count == game.faceUp.count)
            precondition(game.matchedPairs.count <= pairCount && game.moves >= before.moves)
            if game.hasMismatch && random(3) != 0 { game.concealMismatch() }
        }
        game.concealMismatch()
        if let first = game.faceUp.first {
            let pair = game.cards.first { $0.id == first }!.pairID
            _ = game.reveal(game.cards.first { $0.pairID == pair && $0.id != first }!.id)
        }
        for pair in 0..<pairCount {
            for card in game.cards where card.pairID == String(pair) { _ = game.reveal(card.id) }
        }
        precondition(game.isFinished && game.cards.allSatisfy(game.isRevealed))
    }
}
print("PASS: \(snakeRounds) Snake rounds, \(snakeSteps) steps; \(memoryDecks) Memory decks, \(memoryTaps) random taps, then completed.")
