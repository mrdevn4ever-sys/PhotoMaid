/// Discrete, deterministic Snake rules. No clocks, pictures, permissions or photo decisions live here.
public struct PhotoSnakeGame: Equatable, Sendable {
    public struct Cell: Hashable, Sendable {
        public let x: Int
        public let y: Int
        public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    }

    public enum Direction: String, CaseIterable, Sendable {
        case up, right, down, left
        public var opposite: Self {
            switch self { case .up: .down; case .right: .left; case .down: .up; case .left: .right }
        }
        fileprivate var delta: Cell {
            switch self { case .up: Cell(0, -1); case .right: Cell(1, 0); case .down: Cell(0, 1); case .left: Cell(-1, 0) }
        }
    }
    public enum Mode: String, CaseIterable, Codable, Sendable { case classic, relaxed }
    public enum Status: Sendable { case playing, lost, won }
    public enum Event: Sendable { case moved, collected, lost, won, ignored }

    public let width: Int
    public let height: Int
    public let mode: Mode
    public private(set) var body: [Cell]
    public private(set) var direction = Direction.right
    public private(set) var food: Cell?
    public private(set) var score = 0
    public private(set) var status = Status.playing
    private var turns: [Direction] = []
    private var randomState: UInt64

    public var nextDirection: Direction { turns.first ?? direction }

    public init?(width: Int = 12, height: Int = 16, mode: Mode = .classic,
                 seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        guard (4...24).contains(width), (4...24).contains(height) else { return nil }
        self.width = width; self.height = height; self.mode = mode
        body = [Cell(width / 2, height / 2), Cell(width / 2 - 1, height / 2), Cell(width / 2 - 2, height / 2)]
        randomState = seed
        food = nil
        placeFood()
    }

    /// Buffer up to two actual corners, validating against the preceding queued turn. Rapid input can never
    /// reverse directly into the neck or build an unbounded backlog.
    @discardableResult public mutating func turn(_ proposed: Direction) -> Bool {
        let previous = turns.last ?? direction
        guard status == .playing, turns.count < 2, proposed != previous, proposed != previous.opposite else { return false }
        turns.append(proposed)
        return true
    }

    @discardableResult public mutating func step() -> Event {
        guard status == .playing else { return .ignored }
        if !turns.isEmpty { direction = turns.removeFirst() }
        let delta = direction.delta
        var next = Cell(body[0].x + delta.x, body[0].y + delta.y)
        if mode == .relaxed {
            next = Cell((next.x + width) % width, (next.y + height) % height)
        } else if next.x < 0 || next.x >= width || next.y < 0 || next.y >= height {
            status = .lost; return .lost
        }
        let eats = next == food
        // Moving into the departing tail is legal, unless eating keeps that tail in place.
        let occupied = eats ? body[...] : body.dropLast()
        guard !occupied.contains(next) else { status = .lost; return .lost }
        body.insert(next, at: 0)
        if eats {
            score += 1
            placeFood()
            return status == .won ? .won : .collected
        }
        body.removeLast()
        return .moved
    }

    private mutating func placeFood() {
        let occupied = Set(body)
        let free = (0..<height).flatMap { y in (0..<width).map { Cell($0, y) } }.filter { !occupied.contains($0) }
        guard !free.isEmpty else { food = nil; status = .won; return }
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        food = free[Int(randomState % UInt64(free.count))]
    }
}
