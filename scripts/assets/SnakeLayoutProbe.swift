import Foundation

/// Local design evidence only. Compile with the actual four Core sources; no Apple SDK or app host.
@main struct SnakeLayoutProbe {
    static func main() throws {
        typealias Cell = PhotoSnakeGame.Cell
        var results = [[String: Any]]()
        for (w, h) in [(367.0, 560.0), (394, 760), (432, 850), (736, 1024)] {
            let grid = PhotoSnakeViewport(width: w, height: h)
            let layout = PhotoSnakeLayout(width: w, height: h, columns: grid.columns, rows: grid.rows)
            let width = grid.columns, height = grid.rows
            // These viewports have even widths. Build a cycle along columns so odd row counts
            // remain adjacent too; reject a bad fixture instead of rendering a collided snapshot.
            var cycle = (0..<height).map { Cell(0, $0) }
            for x in 1..<width {
                cycle += (x.isMultiple(of: 2) ? Array(1..<height) : Array((1..<height).reversed())).map { Cell(x, $0) }
            }
            cycle += (1..<width).reversed().map { Cell($0, 0) }
            guard var game = PhotoSnakeGame(width: width, height: height, mode: .relaxed, seed: 47) else { fatalError() }
            _ = game.faceBeforeFirstStep((width / 2).isMultiple(of: 2) ? .down : .up)
            var motion = PhotoSnakeMotion(game: game)
            var index = cycle.firstIndex(of: game.body[0])!
            for _ in 0..<200_000 {
                precondition(game.status == .playing, "Design fixture must be an actual live round")
                let next = cycle[(index + 1) % cycle.count], head = game.body[0]
                _ = game.turn(next.x > head.x ? .right : next.x < head.x ? .left : next.y > head.y ? .down : .up)
                let event = game.step(); motion.advance(to: game, event: event)
                index = (index + 1) % cycle.count
                if game.body.count >= 18 && game.direction == .down && event == .moved { break }
            }
            // Completed growth, at a fractional step through the real motion history.
            let points = motion.points(progress: 0.5)
            let lines = motion.lines(progress: 0.5, samples: points)
            results.append(["width": w, "height": h, "columns": width, "rows": height,
                "pitch": layout.pitch, "photoSide": layout.photoSide, "border": layout.borderWidth,
                "direction": game.direction.rawValue, "bodyCount": game.body.count,
                "points": points.map { let p = motion.wrapped($0); return [p.x, p.y] },
                "lines": lines.map { [$0.a.x, $0.a.y, $0.b.x, $0.b.y] }])
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
