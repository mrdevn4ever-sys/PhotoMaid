import Foundation

public enum PhotoSnakeSpeed: String, CaseIterable, Codable, Sendable {
    case gentle, normal, fast
    public var interval: Double { switch self { case .gentle: 0.32; case .normal: 0.22; case .fast: 0.14 } }
}

/// Personal records contain numbers and rule categories only, never photo identifiers or images.
public struct PhotoGameRecords: Codable, Equatable, Sendable {
    public struct MemoryCategory: Codable, Hashable, Sendable {
        public let pairs: Int
        public let usesPhotos: Bool
        public let manualMismatch: Bool
        public init(pairs: Int, usesPhotos: Bool, manualMismatch: Bool = false) {
            self.pairs = pairs; self.usesPhotos = usesPhotos; self.manualMismatch = manualMismatch
        }
        fileprivate var isValid: Bool { (2...PhotoMemoryGame.maximumPairs).contains(pairs) }
    }
    public struct SnakeCategory: Codable, Hashable, Sendable {
        public let mode: PhotoSnakeGame.Mode
        public let speed: PhotoSnakeSpeed
        public let stepMode: Bool
        public let width: Int
        public let height: Int
        public init(mode: PhotoSnakeGame.Mode, speed: PhotoSnakeSpeed, stepMode: Bool,
                    width: Int = 12, height: Int = 16) {
            self.mode = mode; self.speed = speed; self.stepMode = stepMode
            self.width = width; self.height = height
        }
        fileprivate var isValid: Bool { (4...24).contains(width) && (4...24).contains(height) }
    }
    public struct MemoryRecord: Codable, Equatable, Sendable {
        public let category: MemoryCategory
        public let seconds: Double
    }
    public struct SnakeRecord: Codable, Equatable, Sendable {
        public let category: SnakeCategory
        public let eaten: Int
    }
    public private(set) var memory: [MemoryRecord] = []
    public private(set) var snake: [SnakeRecord] = []

    public init() {}

    public func memoryBest(for category: MemoryCategory) -> Double? { memory.first { $0.category == category }?.seconds }
    public func snakeBest(for category: SnakeCategory) -> Int? { snake.first { $0.category == category }?.eaten }

    /// A partial or abandoned Memory round can never produce a time record.
    @discardableResult public mutating func recordMemory(_ game: PhotoMemoryGame, seconds: Double,
                                                        usesPhotos: Bool, manualMismatch: Bool = false) -> Bool {
        guard game.isFinished else { return false }
        return considerMemory(.init(category: .init(pairs: game.pairCount, usesPhotos: usesPhotos,
                                                    manualMismatch: manualMismatch), seconds: seconds))
    }

    /// Save at each collected picture, so leaving a round never loses an earned personal record.
    @discardableResult public mutating func recordSnake(_ game: PhotoSnakeGame, speed: PhotoSnakeSpeed,
                                                       stepMode: Bool) -> Bool {
        considerSnake(.init(category: .init(mode: game.mode, speed: speed, stepMode: stepMode,
                                           width: game.width, height: game.height), eaten: game.score))
    }

    private mutating func considerMemory(_ record: MemoryRecord) -> Bool {
        guard record.category.isValid, record.seconds.isFinite, record.seconds > 0 else { return false }
        if let previous = memoryBest(for: record.category), previous <= record.seconds { return false }
        memory.removeAll { $0.category == record.category }; memory.append(record)
        return true
    }

    private mutating func considerSnake(_ record: SnakeRecord) -> Bool {
        guard record.category.isValid, record.eaten > 0,
              record.eaten <= record.category.width * record.category.height - 3 else { return false }
        if let previous = snakeBest(for: record.category), previous >= record.eaten { return false }
        snake.removeAll { $0.category == record.category }; snake.append(record)
        return true
    }

    private enum CodingKeys: String, CodingKey { case memory, snake }
    public init(from decoder: any Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        for record in try data.decodeIfPresent([MemoryRecord].self, forKey: .memory) ?? [] { _ = considerMemory(record) }
        for record in try data.decodeIfPresent([SnakeRecord].self, forKey: .snake) ?? [] { _ = considerSnake(record) }
    }
}

/// A monotonic, externally clocked stopwatch; sleeping, background time and wall-clock edits are irrelevant.
public struct PhotoGameStopwatch: Equatable, Sendable {
    public private(set) var hasStarted = false
    private var accumulated: Double = 0
    private var startedAt: Double?
    public var isRunning: Bool { startedAt != nil }

    public init() {}

    public func elapsed(at instant: Double) -> Double {
        guard let startedAt, instant.isFinite else { return accumulated }
        return accumulated + max(0, instant - startedAt)
    }

    public mutating func resume(at instant: Double) {
        guard instant.isFinite, startedAt == nil else { return }
        hasStarted = true; startedAt = instant
    }

    public mutating func pause(at instant: Double) {
        accumulated = elapsed(at: instant); startedAt = nil
    }

    public mutating func reset() { self = .init() }
}
