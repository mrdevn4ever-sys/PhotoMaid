import Foundation

/// Normierter Punkt (0…1) im Ausgabebild.
public struct NormPoint: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float
    public init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
}

/// Pinselstrich (Ausgabekoordinaten 0…1, Radius relativ zur langen Kante, Härte 0…1).
public struct BrushStroke: Hashable, Codable, Sendable {
    public var points: [NormPoint]
    public var radius: Float
    public var hardness: Float = 0.5
    public var erase = false
    public init(points: [NormPoint], radius: Float, hardness: Float = 0.5, erase: Bool = false) {
        self.points = points
        self.radius = radius
        self.hardness = hardness
        self.erase = erase
    }
}

/// Maske einer lokalen Anpassung. Rein manuell (keine Erkennung).
public enum Mask: Hashable, Codable, Sendable {
    /// Ellipse um `center` mit Halbachsen relativ zur Bildbreite/-höhe, `feather` 0…1 weiche Kante.
    case radial(center: NormPoint, rx: Float, ry: Float, feather: Float, invert: Bool)
    /// Verlauf von `start` (voll) nach `end` (null).
    case linear(start: NormPoint, end: NormPoint)
    case brush(strokes: [BrushStroke])
}

/// Lokale Anpassung: Maske + Regler (nur punktweise Regler wirken lokal).
public struct LocalAdjustment: Hashable, Codable, Sendable, Identifiable {
    /// Stable across recipe copies, undo/redo and serialization; never an array position.
    public let id: UUID
    public var mask: Mask
    public var adjust: Adjustments
    public init(id: UUID = UUID(), mask: Mask, adjust: Adjustments = Adjustments()) {
        self.id = id
        self.mask = mask
        self.adjust = adjust
    }

    private enum CodingKeys: String, CodingKey { case id, mask, adjust }

    /// Older recipes have no identity. Assign it once while decoding, not while displaying.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mask = try c.decode(Mask.self, forKey: .mask)
        adjust = try c.decodeIfPresent(Adjustments.self, forKey: .adjust) ?? Adjustments()
    }
}
