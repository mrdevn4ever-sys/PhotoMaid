import Foundation

/// Shared point geometry for the renderer and Linux tests; never changes the Snake rules.
public struct PhotoSnakeLayout: Equatable, Sendable {
    public static let overlap = 0.125
    public static let minimumPitch = 44.0 * (1 - overlap)
    public static let photoFraction = 1 / (1 - overlap)
    public static let cornerFraction = 0.5
    public static let texturePixels = 256
    public static let borderPixels = 256.0 / 44.0
    public let pitch: Double
    public let photoSide: Double
    public let gutter: Double
    public var cornerRadius: Double { photoSide * Self.cornerFraction }
    public var borderWidth: Double { photoSide * Self.borderPixels / Double(Self.texturePixels) }
    public var headSide: Double { photoSide * 1.1 }

    public init(width: Double, height: Double, columns: Int, rows: Int) {
        let w = width.isFinite ? max(1, width) : 1
        let h = height.isFinite ? max(1, height) : 1
        gutter = Self.edgeInset(width: w, height: h)
        let available = min((w - 2 * gutter) / Double(max(1, columns)), (h - 2 * gutter) / Double(max(1, rows)))
        // The full, rotating atlas canvas (including the eating pulse) fits at every border.
        let headExtent = 1.1 * 1.06 * sqrt(2) / 2
        pitch = min(50 / Self.photoFraction, available, gutter / headExtent / Self.photoFraction)
        // A smaller resizable window can shrink a continuing round, never change its collisions.
        photoSide = pitch * Self.photoFraction
    }

    public static func edgeInset(width: Double, height: Double) -> Double {
        min(42, max(0, min(width, height)) / 6)
    }

    /// A stable order independent of frame timing or snake length, including portal copies.
    /// The segment nearer the head covers its successor, never the other way around.
    public static func segmentDepth(index: Int) -> Double { 5 - Double(max(1, index)) / 1024 }

    public func growingSide(progress: Double, separation: Double? = nil) -> Double {
        let p = progress.isFinite ? min(1, max(0, progress)) : 0
        // Grow beneath the departing tail, with the same small overlap as the rest of the body.
        let distance = separation.map { $0.isFinite ? max(0, $0) : 0 } ?? (p * pitch)
        return min(photoSide, max(0, 2 * distance / (1 - Self.overlap) - photoSide))
    }

    public static func roundedPhotosOverlap(_ a: PhotoSnakeMotion.Point, _ b: PhotoSnakeMotion.Point,
                                            side: Double, radius: Double, otherSide: Double? = nil) -> Bool {
        guard side > 0, (otherSide ?? side) > 0 else { return false }
        let r = min(side / 2, max(0, radius))
        let other = otherSide ?? side
        let r2 = other * (side > 0 ? r / side : 0)
        if r + r2 == 0 {
            return abs(a.x - b.x) < (side + other) / 2 && abs(a.y - b.y) < (side + other) / 2
        }
        let inner = (side + other) / 2 - r - r2
        let dx = max(0, abs(a.x - b.x) - inner)
        let dy = max(0, abs(a.y - b.y) - inner)
        return hypot(dx, dy) < r + r2 - 0.000001
    }

    /// A full-photo crossfade through the wrap portal, entirely inside the reserved gutter.
    /// No clipping mask, no squeezed photo, and no jump in visible position/opacity at the seam.
    public static func placements(_ p: PhotoSnakeMotion.Point, width: Double, height: Double,
                                  gutter: Double, halfExtent: Double, wraps: Bool) -> [Placement] {
        guard wraps else { return [Placement(centre: p, alpha: 1)] }
        let band = max(0, min(gutter - halfExtent - 0.000001, gutter * 0.4))
        guard band > 0 else { return [Placement(centre: p, alpha: 1)] }
        func axis(_ value: Double, period: Double) -> [(Double, Double)] {
            if value < band {
                let alpha = 0.5 + 0.5 * max(0, value) / band
                return [(value, alpha), (value + period, 1 - alpha)]
            }
            if value > period - band {
                let alpha = 0.5 + 0.5 * max(0, period - value) / band
                return [(value, alpha), (value - period, 1 - alpha)]
            }
            return [(value, 1)]
        }
        let xs = axis(p.x, period: width), ys = axis(p.y, period: height)
        return ys.flatMap { y in xs.map { x in Placement(centre: .init(x.0, y.0), alpha: x.1 * y.1) } }
    }
    public struct Placement: Equatable, Sendable {
        public let centre: PhotoSnakeMotion.Point
        public let alpha: Double
    }

    /// A centred aspect-fill crop, never a stretched image.
    public static func aspectFill(width: Double, height: Double, side: Double) -> Crop {
        let scale = max(side / max(1, width), side / max(1, height))
        let w = width * scale, h = height * scale
        return Crop(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)
    }
    public struct Crop: Equatable, Sendable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    /// Faces use normalized top-left image coordinates. Keep a small group together when it fits
    /// inside the circular photo; otherwise favour the largest face. No face means a centred crop.
    public static func photoCrop(width: Double, height: Double, side: Double, faces: [Crop]) -> Crop {
        let side = max(1, min(side, width, height))
        let valid = faces.filter { f in
            [f.x, f.y, f.width, f.height].allSatisfy(\.isFinite) &&
                f.x >= 0 && f.y >= 0 && f.width > 0 && f.height > 0 &&
                f.x + f.width <= 1.000001 && f.y + f.height <= 1.000001
        }
        var cx = width / 2, cy = height / 2
        if let largest = valid.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            let left = valid.map(\.x).min()!, top = valid.map(\.y).min()!
            let right = valid.map { $0.x + $0.width }.max()!, bottom = valid.map { $0.y + $0.height }.max()!
            let fits = hypot((right - left) * width, (bottom - top) * height) <= side * 0.82
            cx = (fits ? (left + right) / 2 : largest.x + largest.width / 2) * width
            cy = (fits ? (top + bottom) / 2 : largest.y + largest.height / 2) * height
        }
        return Crop(x: max(0, min(width - side, cx - side / 2)),
                    y: max(0, min(height - side, cy - side / 2)), width: side, height: side)
    }
}
