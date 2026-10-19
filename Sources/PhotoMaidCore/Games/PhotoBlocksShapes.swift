import Foundation

public struct PhotoBlocksCell: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

/// Four-square pieces, implemented as grid geometry. Old raw values retain their original
/// footprints so an existing saved round is not reinterpreted or discarded after updating.
public enum PhotoBlocksShape: Int, Codable, CaseIterable, Sendable {
    case pebble, shoot, arch, petal, bough, fern
    case square, line, cornerLeft, cornerRight, crown, stepLeft, stepRight

    public static let playableShapes: [Self] = [.square, .line, .cornerLeft, .cornerRight, .crown, .stepLeft, .stepRight]
    public var isLegacy: Bool { rawValue <= Self.fern.rawValue }

    public func cells(rotation: Int = 0) -> [PhotoBlocksCell] {
        var cells: [PhotoBlocksCell] = switch self {
        case .pebble: [.init(0, 0), .init(1, 0)]
        case .shoot: [.init(0, 0), .init(0, 1), .init(1, 1)]
        case .arch: [.init(0, 0), .init(2, 0), .init(0, 1), .init(1, 1), .init(2, 1)]
        case .petal: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1), .init(0, 2)]
        case .bough: [.init(0, 0), .init(0, 1), .init(0, 2), .init(1, 2), .init(2, 2)]
        case .fern: [.init(0, 0), .init(0, 1), .init(1, 1), .init(0, 2), .init(0, 3)]
        case .square: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)]
        case .line: [.init(0, 0), .init(0, 1), .init(0, 2), .init(0, 3)]
        case .cornerLeft: [.init(0, 0), .init(0, 1), .init(0, 2), .init(1, 2)]
        case .cornerRight: [.init(1, 0), .init(1, 1), .init(1, 2), .init(0, 2)]
        case .crown: [.init(0, 0), .init(1, 0), .init(2, 0), .init(1, 1)]
        case .stepLeft: [.init(1, 0), .init(2, 0), .init(0, 1), .init(1, 1)]
        case .stepRight: [.init(0, 0), .init(1, 0), .init(1, 1), .init(2, 1)]
        }
        for _ in 0..<((rotation % 4 + 4) % 4) {
            cells = cells.map { .init(-$0.y, $0.x) }
            let minX = cells.map(\.x).min() ?? 0, minY = cells.map(\.y).min() ?? 0
            cells = cells.map { .init($0.x - minX, $0.y - minY) }
        }
        return cells
    }
}

public struct PhotoBlocksPiece: Codable, Equatable, Sendable {
    public var shape: PhotoBlocksShape
    public var rotation: Int
    public var origin: PhotoBlocksCell
    public init(shape: PhotoBlocksShape, rotation: Int = 0, origin: PhotoBlocksCell) {
        self.shape = shape; self.rotation = (rotation % 4 + 4) % 4; self.origin = origin
    }
    public var cells: [PhotoBlocksCell] {
        shape.cells(rotation: rotation).map { .init($0.x + origin.x, $0.y + origin.y) }
    }
}

/// Explicit seeded PRNG, including its persisted state, makes bags and continuations reproducible.
struct PhotoBlocksRandom: Codable, Equatable, Sendable {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func shuffle<T>(_ values: inout [T]) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            values.swapAt(index, Int(next() % UInt64(index + 1)))
        }
    }
}
