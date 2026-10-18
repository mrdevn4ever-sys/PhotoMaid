import Foundation

/// Compiled with the actual four production Core files; emits review fixtures, no UIKit screenshot claim.
@main struct BlocksReviewProbe {
    struct State: Codable {
        let title: String
        let game: PhotoBlocksGame
        let activeCells: [PhotoBlocksCell]
        let ghostCells: [PhotoBlocksCell]
        init(title: String, game: PhotoBlocksGame) {
            self.title = title; self.game = game
            activeCells = game.active?.cells ?? []; ghostCells = game.ghost?.cells ?? []
        }
    }
    static func main() throws {
        let width = 9, height = 17
        var board = Array(repeating: Array<PhotoBlocksShape?>(repeating: nil, count: width), count: height)
        let fern = PhotoBlocksPiece(shape: .fern, origin: .init(0, 13))
        for y in 14..<height { board[y] = Array(repeating: .arch, count: width) }
        for cell in fern.cells { board[cell.y][cell.x] = nil }
        board[11][5] = .petal; board[12][5] = .petal; board[12][6] = .petal
        var game = PhotoBlocksGame(testBoard: board, active: fern, revealed: 8)
        var states = [State(title: "Vor dem 3-Reihen-Abschluss", game: game)]
        game.hardDrop()
        states.append(State(title: "Reihen-Animation (180 ms)", game: game))
        game.advance(0.18)
        states.append(State(title: "Foto entdeckt (2 Sekunden)", game: game))
        game.advance(2)
        states.append(State(title: "Level 2 · 10 % übernommen", game: game))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(states))
    }
}
