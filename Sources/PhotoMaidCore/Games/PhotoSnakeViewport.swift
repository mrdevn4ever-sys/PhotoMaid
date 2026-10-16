/// A nearly square cell grid that fills the current window. Dimensions stay fixed during an active round.
public struct PhotoSnakeViewport: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            columns = 12; rows = 16; return
        }
        let cell = max(36, max(width, height) / 24)
        columns = min(24, max(4, Int((width / cell).rounded())))
        rows = min(24, max(4, Int((height / cell).rounded())))
    }
}
