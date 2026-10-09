import Foundation

// Lokale Bildanalyse (nur iOS, Entscheidung E7): Gruppierung und Schwellen. Die Merkmale (Feature-Print-Abstand,
// Schärfewert, Ästhetik-Wert) liefert Vision auf dem Gerät; hier liegt nur die Logik. Ergebnisse sind Vorschläge zum
// Durchsehen – nie eine Entscheidung, nie eine Löschung.

/// Ein analysiertes Foto.
public struct AnalyzedPhoto: Hashable, Sendable {
    public let id: String
    public let takenAt: Date?
    /// Schärfewert (Varianz der Kanten, höher = schärfer); `nil` = nicht gemessen.
    public let sharpness: Double?

    public init(id: String, takenAt: Date?, sharpness: Double? = nil) {
        self.id = id
        self.takenAt = takenAt
        self.sharpness = sharpness
    }
}

public enum SimilarPhotos {
    /// Abstand zweier Feature-Prints (Vision `distance(to:)`), unter dem zwei Fotos als „ähnlich aussehend“ gelten.
    public static let defaultThreshold: Float = 0.45
    /// Nur Fotos innerhalb dieses Zeitfensters werden verglichen (spart Rechenzeit; Serien liegen zeitlich nah).
    public static let defaultWindow: TimeInterval = 10 * 60
    public static let minGroupSize = 2

    /// Gruppen (Zusammenhangskomponenten) aus paarweisen Abständen. `distance` wird nur für Paare im Zeitfenster
    /// aufgerufen; Fotos ohne Datum werden nicht verglichen. Gruppen nach Aufnahmezeit, Mitglieder ebenso.
    public static func groups(_ photos: [AnalyzedPhoto], threshold: Float = defaultThreshold,
                              window: TimeInterval = defaultWindow,
                              distance: (AnalyzedPhoto, AnalyzedPhoto) -> Float?) -> [[AnalyzedPhoto]] {
        let dated = photos.filter { $0.takenAt != nil }.sorted { ($0.takenAt!, $0.id) < ($1.takenAt!, $1.id) }
        var parent = Array(dated.indices)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for i in dated.indices {
            var j = i + 1
            while j < dated.count, dated[j].takenAt!.timeIntervalSince(dated[i].takenAt!) <= window {
                if let d = distance(dated[i], dated[j]), d <= threshold {
                    let a = find(i), b = find(j)
                    if a != b { parent[max(a, b)] = min(a, b) }
                }
                j += 1
            }
        }
        var comps: [Int: [AnalyzedPhoto]] = [:]
        for i in dated.indices { comps[find(i), default: []].append(dated[i]) }
        return comps.values.filter { $0.count >= minGroupSize }
            .sorted { ($0[0].takenAt!, $0[0].id) < ($1[0].takenAt!, $1[0].id) }
    }

    /// Vorschlag „dieses behalten“ in einer Gruppe: das schärfste gemessene Foto; ohne Messung keins (nie raten).
    public static func sharpest(_ group: [AnalyzedPhoto]) -> String? {
        let measured = group.filter { $0.sharpness != nil }
        guard measured.count == group.count, let best = measured.max(by: { $0.sharpness! < $1.sharpness! }) else { return nil }
        // Nur, wenn es deutlich schärfer ist (≥ 15 %) – sonst kein Vorschlag.
        let others = measured.filter { $0.id != best.id }.map { $0.sharpness! }
        guard let second = others.max(), best.sharpness! >= second * 1.15 else { return nil }
        return best.id
    }
}

public enum BlurryPhotos {
    /// Schwelle für „möglicherweise unscharf“ (Varianz des Laplace-Filters auf 0…1-Helligkeit, Vorschaubild 512 px).
    public static let defaultThreshold = 0.0009

    public enum Verdict: Hashable, Sendable {
        case possiblyBlurry
        case sharp
        /// Nicht gemessen (z. B. nur in iCloud) – zählt nie als unscharf.
        case unknown
    }

    public static func verdict(_ sharpness: Double?, threshold: Double = defaultThreshold) -> Verdict {
        guard let s = sharpness else { return .unknown }
        return s < threshold ? .possiblyBlurry : .sharp
    }

    /// Varianz eines Laplace-Filters über Helligkeitswerte (Zeilen von oben, `w` × `h`, Werte 0…1).
    /// Gleiche Formel wie die Core-Image-Umsetzung in der App (Tests auf Linux).
    public static func laplacianVariance(_ luma: [Float], w: Int, h: Int) -> Double {
        guard w >= 3, h >= 3, luma.count >= w * h else { return 0 }
        var sum = 0.0, sumSq = 0.0
        var n = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = luma[y * w + x]
                let l = Double(luma[y * w + x - 1] + luma[y * w + x + 1] + luma[(y - 1) * w + x] + luma[(y + 1) * w + x] - 4 * c)
                sum += l; sumSq += l * l; n += 1
            }
        }
        let mean = sum / Double(n)
        return sumSq / Double(n) - mean * mean
    }
}

/// Kategorien als Filter (Vision `ClassifyImageRequest`): nur Kennungen mit ausreichender Sicherheit, abgebildet auf
/// wenige verständliche Gruppen. Nie automatische Aktion.
public enum PhotoCategory: String, Hashable, Codable, Sendable, CaseIterable {
    case documents, screenshotsText, food, animals, nature, people, vehicles, other

    public static let minConfidence: Float = 0.6

    /// Vision-Kennungen (Taxonomie von `ClassifyImageRequest`) → Gruppe. Unbekannt → `nil`.
    public static func of(identifier: String) -> PhotoCategory? {
        let id = identifier.lowercased()
        let map: [(PhotoCategory, [String])] = [
            (.documents, ["document", "receipt", "paper", "text", "handwriting", "printed_page", "menu", "poster"]),
            (.food, ["food", "dish", "meal", "dessert", "drink", "beverage", "fruit", "vegetable", "baked_goods", "pizza"]),
            (.animals, ["animal", "dog", "cat", "bird", "pet", "mammal", "fish", "horse", "insect"]),
            (.nature, ["landscape", "mountain", "beach", "sky", "forest", "flower", "plant", "tree", "sunset", "water", "outdoor"]),
            (.people, ["people", "person", "portrait", "selfie", "crowd", "child", "baby", "wedding"]),
            (.vehicles, ["car", "vehicle", "bicycle", "motorcycle", "train", "airplane", "boat", "bus", "truck"]),
        ]
        for (cat, words) in map where words.contains(where: { id == $0 || id.hasPrefix($0 + "_") || id.hasSuffix("_" + $0) }) {
            return cat
        }
        return nil
    }

    /// Beste Gruppe aus (Kennung, Sicherheit)-Paaren; unter der Mindestsicherheit keine.
    public static func best(_ observations: [(identifier: String, confidence: Float)]) -> PhotoCategory? {
        observations.filter { $0.confidence >= minConfidence }
            .sorted { $0.confidence > $1.confidence }
            .lazy.compactMap { of(identifier: $0.identifier) }.first
    }
}
