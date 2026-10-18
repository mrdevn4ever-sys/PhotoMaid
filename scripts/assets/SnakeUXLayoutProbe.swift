import Foundation

/// Actual Core positions for static UX design review, not an iOS screenshot or performance test.
@main struct SnakeUXLayoutProbe {
    static func main() throws {
        typealias Cell = PhotoSnakeGame.Cell
        var results = [[String: Any]]()
        for (w, h) in [(320.0, 480.0), (367, 560), (394, 760), (432, 800), (736, 1024)] {
            let grid = PhotoSnakeViewport(width: w, height: h)
            let layout = PhotoSnakeLayout(width: w, height: h, columns: grid.columns, rows: grid.rows)
            let width = grid.columns, height = grid.rows
            // Transpose a column-based cycle when the even dimension is the height.
            // Every move must remain adjacent; never display a failed/teleported test fixture.
            let transpose = !width.isMultiple(of: 2)
            precondition(width.isMultiple(of: 2) || height.isMultiple(of: 2))
            let across = transpose ? height : width, down = transpose ? width : height
            func cell(_ x: Int, _ y: Int) -> Cell { transpose ? Cell(y, x) : Cell(x, y) }
            var cycle = (0..<down).map { cell(0, $0) }
            for x in 1..<across {
                cycle += (x.isMultiple(of: 2) ? Array(1..<down) : Array((1..<down).reversed())).map { cell(x, $0) }
            }
            cycle += (1..<across).reversed().map { cell($0, 0) }
            guard var game = PhotoSnakeGame(width: width, height: height, mode: .relaxed, seed: 47) else { fatalError() }
            let forward = (across / 2).isMultiple(of: 2)
            _ = game.faceBeforeFirstStep(transpose ? (forward ? .right : .left) : (forward ? .down : .up))
            var motion = PhotoSnakeMotion(game: game)
            var index = cycle.firstIndex(of: game.body[0])!
            for _ in 0..<200_000 {
                precondition(game.status == .playing)
                let next = cycle[(index + 1) % cycle.count], head = game.body[0]
                let distance = abs(next.x - head.x) + abs(next.y - head.y)
                precondition(distance == 1)
                _ = game.turn(next.x > head.x ? .right : next.x < head.x ? .left : next.y > head.y ? .down : .up)
                let event = game.step(); motion.advance(to: game, event: event)
                index = (index + 1) % cycle.count
                if game.body.count >= 18 && game.direction == .down && event == .moved { break }
            }
            let points = motion.points(progress: 0.5)
            let lines = motion.lines(progress: 0.5, samples: points)
            results.append(["width": w, "height": h, "columns": width, "rows": height,
                "pitch": layout.pitch, "photoSide": layout.photoSide, "border": layout.borderWidth,
                "gutter": layout.gutter, "headSide": layout.headSide,
                "direction": game.direction.rawValue, "score": game.score, "bodyCount": game.body.count,
                "points": points.map { let p = motion.wrapped($0); return [p.x, p.y] },
                "initialPoints": [[Double(width / 2) + 0.5, Double(height / 2) + 0.5],
                                  [Double(width / 2) - 0.5, Double(height / 2) + 0.5],
                                  [Double(width / 2) - 1.5, Double(height / 2) + 0.5]],
                "lines": lines.map { [$0.a.x, $0.a.y, $0.b.x, $0.b.y] }])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]))
    }
}
