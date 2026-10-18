import Foundation

/// One recognizer owns tap, axis-locked drag and release-time flick classification.
public struct PhotoBlocksInput: Sendable {
    public enum Action: Equatable, Sendable { case left, right, rotate, softDrop(Bool), hardDrop }
    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var anchorX: Double = 0
    private var lastY: Double = 0
    private var lastTime: Double = 0
    private var velocityY: Double = 0
    private var maxDistance: Double = 0
    private var dropping = false
    private var engaged = false
    private var movedHorizontally = false
    public init() {}

    public mutating func changed(x: Double, y: Double, time: Double, cellSize: Double) -> [Action] {
        guard [x, y, time, cellSize].allSatisfy(\.isFinite), cellSize > 0 else { return [] }
        if !engaged { engaged = true; lastTime = time }
        let dt = time - lastTime
        if dt > 0.001 { velocityY = (y - lastY) / dt }
        lastY = y; lastTime = time; maxDistance = max(maxDistance, hypot(x, y))
        if axis == nil, max(abs(x), abs(y)) >= 12 {
            if abs(x) >= abs(y) * 1.15 { axis = .horizontal }
            else if abs(y) >= abs(x) * 1.15 { axis = .vertical }
        }
        var result: [Action] = []
        if axis == .horizontal {
            let step = max(18, cellSize * 0.65)
            if !movedHorizontally, abs(x) >= 12 {
                result.append(x < 0 ? .left : .right); anchorX = x < 0 ? -12 : 12; movedHorizontally = true
            }
            while abs(x - anchorX) >= step, result.count < 14 {
                let right = x > anchorX; result.append(right ? .right : .left); anchorX += right ? step : -step
            }
        } else if axis == .vertical {
            let enabled = y >= 18
            if enabled != dropping { dropping = enabled; result.append(.softDrop(enabled)) }
        }
        return result
    }

    public mutating func ended(x: Double, y: Double, duration: Double, time: Double, cellSize: Double) -> [Action] {
        let oldTime = lastTime
        var result = changed(x: x, y: y, time: time, cellSize: cellSize)
        let average = duration > 0 ? y / duration : 0
        // A flick requires both distance and speed. A long/slow drag never becomes an accidental hard drop.
        if axis == .vertical, y >= 56, duration <= 0.55,
           max(average, time - oldTime <= 0.08 ? velocityY : 0) >= 650 {
            result.append(.hardDrop)
        } else if axis == nil, maxDistance < 10, duration >= 0, duration <= 0.28 {
            result.append(.rotate)
        }
        if dropping { result.append(.softDrop(false)) }
        self = .init(); return result
    }
    public mutating func cancel() { self = .init() }
}
