import Foundation

/// Regler −100…+100 (Schärfe, Körnung 0…100). 0 = keine Änderung.
public struct Adjustments: Hashable, Codable, Sendable {
    public var brightness: Float = 0
    public var contrast: Float = 0
    public var saturation: Float = 0
    public var warmth: Float = 0
    public var sharpness: Float = 0
    public var exposure: Float = 0
    public var highlights: Float = 0
    public var shadows: Float = 0
    public var whites: Float = 0
    public var blacks: Float = 0
    public var tint: Float = 0
    public var vibrance: Float = 0
    public var vignette: Float = 0
    public var grain: Float = 0
    public var clarity: Float = 0
    /// Schärfen: Radius 0…100 (0 = automatisch nach Bildgröße) und Schwelle 0…100.
    public var sharpenRadius: Float = 0
    public var sharpenThreshold: Float = 0
    /// Rauschreduzierung 0…100 (iOS-Ergänzung, Masterprompt §4).
    public var noiseReduction: Float = 0

    public init() {}

    private static func nz(_ v: Float) -> Bool { abs(v) >= 0.5 }

    /// Punktweise Tonwert-/Farbänderung (unabhängig von Nachbarpixeln und Position).
    public var pointNeutral: Bool {
        ![brightness, contrast, saturation, warmth, exposure, highlights, shadows, whites, blacks, tint, vibrance]
            .contains(where: Self.nz)
    }
    /// Positionsabhängig (Vignette, Körnung).
    public var spatialNeutral: Bool { !Self.nz(vignette) && grain < 0.5 }
    public var detailNeutral: Bool { sharpness < 0.5 && !Self.nz(clarity) && noiseReduction < 0.5 }
    public var isNeutral: Bool { pointNeutral && spatialNeutral && detailNeutral }
    public var colorNeutral: Bool { pointNeutral && spatialNeutral }

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, warmth, sharpness, exposure, highlights, shadows, whites, blacks, tint,
             vibrance, vignette, grain, clarity, sharpenRadius, sharpenThreshold, noiseReduction
    }

    /// Fehlende Felder (ältere Sicherungen, Android-Vorlagen) = 0.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ k: CodingKeys) throws -> Float { try c.decodeIfPresent(Float.self, forKey: k) ?? 0 }
        brightness = try f(.brightness); contrast = try f(.contrast); saturation = try f(.saturation)
        warmth = try f(.warmth); sharpness = try f(.sharpness); exposure = try f(.exposure)
        highlights = try f(.highlights); shadows = try f(.shadows); whites = try f(.whites); blacks = try f(.blacks)
        tint = try f(.tint); vibrance = try f(.vibrance); vignette = try f(.vignette); grain = try f(.grain)
        clarity = try f(.clarity); sharpenRadius = try f(.sharpenRadius); sharpenThreshold = try f(.sharpenThreshold)
        noiseReduction = try f(.noiseReduction)
    }
}
