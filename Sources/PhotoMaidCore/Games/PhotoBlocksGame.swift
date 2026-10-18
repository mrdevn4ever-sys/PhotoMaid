import Foundation

/// Simulation owns all transitions. Rendering/animation callbacks never change the board.
public struct PhotoBlocksGame: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case ready, playing, clearing, discovered, gameOver }
    public let width: Int
    public let height: Int
    public private(set) var board: [[PhotoBlocksShape?]]
    public private(set) var active: PhotoBlocksPiece?
    public private(set) var next: PhotoBlocksShape
    public private(set) var phase: Phase = .ready
    public private(set) var isPaused = false
    public private(set) var score = 0
    public private(set) var totalRows = 0
    public private(set) var level = 1
    public private(set) var revealedStrips = 0
    public private(set) var discoveredPhotos = 0
    public private(set) var clearedRows: [Int] = []
    public private(set) var piecesPlaced = 0
    private var carryRows = 0
    private var phaseTime: Double = 0
    private var fallTime: Double = 0
    private var lockTime: Double = 0
    private var lockResets = 0
    private var softDrop = false
    private var bag: [PhotoBlocksShape] = []
    private var random: PhotoBlocksRandom

    public init(width: Int = 9, height: Int = 17, seed: UInt64 = 1) {
        self.width = min(14, max(6, width)); self.height = min(28, max(12, height))
        board = Array(repeating: Array(repeating: nil, count: self.width), count: self.height)
        random = .init(state: seed); next = .pebble
        next = draw(); spawn()
    }

    public var progress: Double { Double(revealedStrips) / 10 }
    public var clearFraction: Double { phase == .clearing ? min(1, phaseTime / 0.18) : 0 }
    /// 0.88 s initially; asymptotic floor 0.16 s, with no sudden high-level speed jump.
    public var fallInterval: Double { 0.16 + 0.72 * pow(0.90, Double(min(level - 1, 1000))) }
    public var acceptsInput: Bool { phase == .playing && !isPaused }
    public var ghost: PhotoBlocksPiece? {
        guard var piece = active else { return nil }
        while fits(moved(piece, dx: 0, dy: 1)) { piece.origin.y += 1 }
        return piece
    }

    public mutating func start() { if phase == .ready { phase = .playing } }
    public mutating func pause() { setSoftDrop(false); if phase != .ready && phase != .gameOver { isPaused = true } }
    public mutating func resume() { isPaused = false; softDrop = false }
    public mutating func setSoftDrop(_ enabled: Bool) {
        let next = enabled && acceptsInput
        guard next != softDrop else { return }
        let before = softDrop ? min(0.045, fallInterval / 8) : fallInterval
        softDrop = next
        let after = softDrop ? min(0.045, fallInterval / 8) : fallInterval
        // Preserve fractional gravity progress, not accumulated seconds at the previous speed.
        fallTime = min(1, fallTime / before) * after
    }

    @discardableResult public mutating func move(_ dx: Int) -> Bool {
        guard acceptsInput, let active, abs(dx) == 1 else { return false }
        let candidate = moved(active, dx: dx, dy: 0)
        guard fits(candidate) else { return false }
        resetLockIfAllowed(); self.active = candidate; return true
    }

    @discardableResult public mutating func rotate() -> Bool {
        guard acceptsInput, let active else { return false }
        var candidate = active; candidate.rotation = (candidate.rotation + 1) % 4
        for offset in [PhotoBlocksCell(0, 0), .init(-1, 0), .init(1, 0), .init(-2, 0), .init(2, 0), .init(0, -1), .init(0, -2)] {
            let kicked = moved(candidate, dx: offset.x, dy: offset.y)
            if fits(kicked) { resetLockIfAllowed(); self.active = kicked; return true }
        }
        return false
    }

    @discardableResult public mutating func hardDrop() -> Bool {
        guard acceptsInput, let active, let ghost else { return false }
        score += max(0, ghost.origin.y - active.origin.y) // one point per dropped cell
        self.active = ghost; lock(); return true
    }

    /// Externally supplied monotonic delta; a suspension never catches up gravity on resume.
    public mutating func advance(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0, !isPaused else { return }
        switch phase {
        case .ready, .gameOver: return
        case .clearing:
            phaseTime += min(seconds, 3)
            if phaseTime >= 0.18 { finishClear() }
        case .discovered:
            phaseTime += min(seconds, 3)
            if phaseTime >= 2 { finishDiscovery() }
        case .playing:
            guard let active else { return }
            let delta = min(seconds, 0.25)
            let grounded = !fits(moved(active, dx: 0, dy: 1))
            if grounded {
                lockTime += delta
                if lockTime >= 0.40 { lock() }
            } else {
                lockTime = 0; fallTime += delta
                let interval = softDrop ? min(0.045, fallInterval / 8) : fallInterval
                while fallTime >= interval, let current = self.active {
                    fallTime -= interval
                    let candidate = moved(current, dx: 0, dy: 1)
                    guard fits(candidate) else { fallTime = 0; break }
                    self.active = candidate
                }
            }
        }
    }

    public func fits(_ piece: PhotoBlocksPiece) -> Bool {
        piece.cells.allSatisfy { cell in
            (0..<width).contains(cell.x) && (0..<height).contains(cell.y) && board[cell.y][cell.x] == nil
        }
    }

    private func moved(_ piece: PhotoBlocksPiece, dx: Int, dy: Int) -> PhotoBlocksPiece {
        var copy = piece; copy.origin.x += dx; copy.origin.y += dy; return copy
    }
    private mutating func resetLockIfAllowed() {
        if let active, !fits(moved(active, dx: 0, dy: 1)), lockResets < 8 {
            lockTime = 0; lockResets += 1
        }
    }
    private mutating func draw() -> PhotoBlocksShape {
        if bag.isEmpty { bag = PhotoBlocksShape.allCases; random.shuffle(&bag) }
        return bag.removeLast()
    }
    private mutating func spawn() {
        let shape = next; next = draw()
        let columns = (shape.cells().map(\.x).max() ?? 0) + 1
        let piece = PhotoBlocksPiece(shape: shape, origin: .init((width - columns) / 2, 0))
        fallTime = 0; lockTime = 0; lockResets = 0; softDrop = false
        if fits(piece) { active = piece } else { active = nil; phase = .gameOver }
    }
    private mutating func lock() {
        guard let active, fits(active) else { return }
        for cell in active.cells { board[cell.y][cell.x] = active.shape }
        self.active = nil; softDrop = false; piecesPlaced += 1
        score += 5
        clearedRows = board.indices.filter { board[$0].allSatisfy { $0 != nil } }
        if clearedRows.isEmpty { spawn() }
        else { phase = .clearing; phaseTime = 0 }
    }
    private mutating func finishClear() {
        let count = clearedRows.count
        let removed = Set(clearedRows)
        board = board.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        board.insert(contentsOf: Array(repeating: Array(repeating: nil, count: width), count: count), at: 0)
        totalRows += count
        // Own modest scoring: 40 / 120 / 240 / 400 …, +10% per level, capped at 2x.
        let base = 20 * count * (count + 1)
        score += base * (10 + min(10, level - 1)) / 10
        revealedStrips += count; clearedRows = []; phaseTime = 0
        if revealedStrips >= 10 {
            carryRows = revealedStrips - 10; revealedStrips = 10
            discoveredPhotos += 1; phase = .discovered
        } else { phase = .playing; spawn() }
    }
    private mutating func finishDiscovery() {
        level += 1; revealedStrips = carryRows; carryRows = 0
        phaseTime = 0; phase = .playing; spawn()
    }

    /// No images or identifiers in a snapshot. Reject malformed local data before touching arrays.
    public var isValidSnapshot: Bool {
        (6...14).contains(width) && (12...28).contains(height) && board.count == height &&
        board.allSatisfy { $0.count == width } && (0...9_000_000_000_000_000).contains(score) &&
        totalRows >= 0 && (1...100_000_000).contains(level) &&
        discoveredPhotos == (phase == .discovered ? level : level - 1) &&
        totalRows == (level - 1) * 10 + revealedStrips + carryRows &&
        (0...10).contains(revealedStrips) && (0...4).contains(carryRows) &&
        (0...1_000_000_000_000).contains(piecesPlaced) && (0...8).contains(lockResets) &&
        [phaseTime, fallTime, lockTime].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 10 } &&
        bag.count <= PhotoBlocksShape.allCases.count && Set(bag).count == bag.count &&
        clearedRows.count <= 5 && Set(clearedRows).count == clearedRows.count &&
        clearedRows.allSatisfy { (0..<height).contains($0) } &&
        (active.map { (0..<4).contains($0.rotation) && (0..<width).contains($0.origin.x) &&
            (0..<height).contains($0.origin.y) && fits($0) } ?? true) &&
        ((phase == .ready || phase == .playing) == (active != nil)) &&
        (phase == .clearing ? !clearedRows.isEmpty && clearedRows == board.indices.filter { board[$0].allSatisfy { $0 != nil } } : clearedRows.isEmpty) &&
        (phase == .discovered ? revealedStrips == 10 : revealedStrips < 10)
    }

    // Internal fixtures use the exact production rules; no cheat interface is exposed to the app.
    init(testBoard: [[PhotoBlocksShape?]], active: PhotoBlocksPiece, revealed: Int = 0, level: Int = 1) {
        self.init(width: testBoard[0].count, height: testBoard.count)
        board = testBoard; self.active = active; phase = .playing
        revealedStrips = revealed; self.level = level; discoveredPhotos = level - 1
        totalRows = (level - 1) * 10 + revealed
    }
}

/// Reuses the app's KeyValueStore; the archive contains numerical puzzle state only.
public struct PhotoBlocksArchive: Codable, Equatable, Sendable {
    public var game: PhotoBlocksGame?
    public var best: Int
    public var discoveredImages: Int
    public var photoSeed: UInt64
    public var photoSource: PhotoBlocksPhotos.Source
    public init(game: PhotoBlocksGame? = nil, best: Int = 0, discoveredImages: Int = 0,
                photoSeed: UInt64 = 1, photoSource: PhotoBlocksPhotos.Source = .random) {
        self.game = game?.isValidSnapshot == true ? game : nil; self.best = max(0, best)
        self.discoveredImages = min(max(0, discoveredImages), self.game?.discoveredPhotos ?? 0)
        self.photoSeed = photoSeed; self.photoSource = photoSource
    }
    private enum CodingKeys: CodingKey { case game, best, discoveredImages, photoSeed, photoSource }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(game: try values.decodeIfPresent(PhotoBlocksGame.self, forKey: .game),
                  best: try values.decodeIfPresent(Int.self, forKey: .best) ?? 0,
                  discoveredImages: try values.decodeIfPresent(Int.self, forKey: .discoveredImages) ?? 0,
                  photoSeed: try values.decodeIfPresent(UInt64.self, forKey: .photoSeed) ?? 1,
                  photoSource: try values.decodeIfPresent(PhotoBlocksPhotos.Source.self, forKey: .photoSource) ?? .random)
    }
}
