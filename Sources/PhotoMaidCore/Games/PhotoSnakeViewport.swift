/// Photo-sized cells. Dimensions stay fixed during an active round, including resizing.
public struct PhotoSnakeViewport: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            columns = 12; rows = 16; return
        }
        let inset = PhotoSnakeLayout.edgeInset(width: width, height: height)
        let w = max(1, width - 2 * inset), h = max(1, height - 2 * inset)
        // Keep the improved 44–50pt photos, now touching with a controlled 12.5% overlap.
        let cell = max(PhotoSnakeLayout.minimumPitch, max(w, h) / 24)
        columns = min(24, max(4, Int((w / cell).rounded(.down))))
        rows = min(24, max(4, Int((h / cell).rounded(.down))))
    }
}
