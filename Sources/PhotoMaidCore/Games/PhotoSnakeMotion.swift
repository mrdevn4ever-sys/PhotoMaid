import Foundation

/// Grid-centre history in unwrapped tile coordinates. Distances are measured along the legal
/// orthogonal route; photo centres never take a diagonal shortcut through an occupied tile.
public struct PhotoSnakeMotion: Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }
    public struct Line: Equatable, Sendable { public let a: Point; public let b: Point }
    private var history: [Point]
    private var travel = 0.0
    public private(set) var count: Int
    public let width: Int
    public let height: Int

    public init(game: PhotoSnakeGame) {
        width = game.width; height = game.height; count = game.body.count
        history = []
        for cell in game.body {
            var p = Point(Double(cell.x) + 0.5, Double(cell.y) + 0.5)
            if let previous = history.last, game.mode == .relaxed {
                p.x = previous.x + Self.wrappedDelta(p.x - previous.x, period: Double(width))
                p.y = previous.y + Self.wrappedDelta(p.y - previous.y, period: Double(height))
            }
            history.append(p)
        }
    }

    public mutating func advance(to game: PhotoSnakeGame, event: PhotoSnakeGame.Event) {
        guard let head = history.first, event != .ignored else { return }
        // A collision only animates to contact, never into the forbidden cell. The rules still own death.
        travel = event == .lost ? 0.45 : 1
        let delta: Point
        switch game.direction { case .up: delta = Point(0, -travel); case .right: delta = Point(travel, 0)
        case .down: delta = Point(0, travel); case .left: delta = Point(-travel, 0) }
        history.insert(Point(head.x + delta.x, head.y + delta.y), at: 0)
        count = game.body.count
        // Enough history for the longest board, including a growing tail and a partial impact step.
        if history.count > count + 4 { history.removeLast(history.count - count - 4) }
    }

    /// O(body + history), including 300+ segments; one forward cursor serves all arc-length samples.
    public func points(progress: Double) -> [Point] {
        let progress = progress.isFinite ? min(1, max(0, progress)) : 0
        let start = travel * (1 - progress)
        var cursor = 0, traversed = 0.0
        return (0..<count).map { index in
            let distance = start + Double(index)
            while cursor + 1 < history.count {
                let a = history[cursor], b = history[cursor + 1]
                let length = hypot(b.x - a.x, b.y - a.y)
                if traversed + length >= distance, length > 0 {
                    let f = (distance - traversed) / length
                    return Point(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)
                }
                traversed += length; cursor += 1
            }
            return history.last ?? Point(0.5, 0.5)
        }
    }

    /// Include every intervening corner in the connecting tube, rather than joining photo centres diagonally.
    public func route(progress: Double, samples: [Point]? = nil) -> [Point] {
        let samples = samples ?? points(progress: progress)
        guard let head = samples.first, let tail = samples.last else { return [] }
        let start = travel * (1 - min(1, max(0, progress.isFinite ? progress : 0)))
        let end = start + Double(max(0, count - 1))
        var distance = 0.0, route = [head]
        for i in 1..<history.count {
            let a = history[i - 1], b = history[i]
            distance += hypot(b.x - a.x, b.y - a.y)
            if distance > start, distance < end { route.append(b) }
        }
        route.append(tail)
        return route
    }

    public func wrapped(_ p: Point) -> Point {
        Point(Self.mod(p.x, Double(width)), Self.mod(p.y, Double(height)))
    }

    /// Split border crossings into two short visible edges. No line stretches across the entire board.
    public func lines(progress: Double, samples: [Point]? = nil) -> [Line] {
        let route = route(progress: progress, samples: samples)
        guard route.count > 1 else { return [] }
        var lines: [Line] = []
        for i in 1..<route.count {
            let a = wrapped(route[i - 1]), b = wrapped(route[i])
            let dx = b.x - a.x, dy = b.y - a.y
            if abs(dx) > Double(width) / 2 {
                let edge = dx > 0 ? 0.0 : Double(width)
                lines.append(Line(a: a, b: Point(edge, a.y)))
                lines.append(Line(a: Point(Double(width) - edge, b.y), b: b))
            } else if abs(dy) > Double(height) / 2 {
                let edge = dy > 0 ? 0.0 : Double(height)
                lines.append(Line(a: a, b: Point(a.x, edge)))
                lines.append(Line(a: Point(b.x, Double(height) - edge), b: b))
            } else { lines.append(Line(a: a, b: b)) }
        }
        return lines
    }
    private static func mod(_ n: Double, _ period: Double) -> Double {
        let value = n.truncatingRemainder(dividingBy: period)
        return value < 0 ? value + period : value
    }
    private static func wrappedDelta(_ n: Double, period: Double) -> Double {
        if n > period / 2 { return n - period }
        if n < -period / 2 { return n + period }
        return n
    }
}
