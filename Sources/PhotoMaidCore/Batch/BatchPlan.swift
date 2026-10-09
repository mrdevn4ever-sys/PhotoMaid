import Foundation

/// Stapel-Werkzeuge. Jede Datei wird als neue Datei geschrieben; Originale bleiben, außer der Nutzer wählt anders.
public enum BatchTool: String, Hashable, Codable, Sendable, CaseIterable { case resize, convert, stripLocation }

public struct BatchOptions: Hashable, Codable, Sendable {
    public var tool: BatchTool
    /// Längste Kante (nur verkleinern), `nil` = Originalgröße.
    public var longEdge: Int? = 2048
    public var quality = 85
    public var format = EditFormat.jpeg
    /// Standort zusätzlich entfernen (bei „Standort entfernen“ immer).
    public var removeLocation = false
    /// Originale danach mit einer Systembestätigung in „Zuletzt gelöscht“ (Standard aus).
    public var trashOriginals = false

    public init(tool: BatchTool) { self.tool = tool }
}

public enum BatchRules {
    /// Free: so viele Dateien je Durchgang; Pro/Test: unbegrenzt.
    public static let freeLimit = Capabilities.freeBatchLimit
    public static let longEdges = [4096, 2048, 1080]
    public static let qualities = [90, 80, 70]

    /// Wirklich etwas zu tun? Verkleinern nur, wenn die Kante größer ist; sonst übersprungen (keine sinnlose Kopie).
    public static func needsWork(_ o: BatchOptions, width: Int, height: Int, uti: String?, hasLocation: Bool) -> Bool {
        switch o.tool {
        case .resize: return o.longEdge.map { max(width, height) > $0 } ?? false
        case .convert: return EditFormat.forSource(uti: uti) != o.format || (uti ?? "").lowercased() != o.format.utType
        case .stripLocation: return hasLocation
        }
    }
}

/// Ergebnis ehrlich: Größen nur gemessen, unbekannte gezählt; „frei“ erst, wenn Originale wirklich weg sind.
public struct BatchSummary: Hashable, Sendable {
    public var done = 0
    public var skipped = 0
    public var failed = 0
    public var beforeBytes: Int64 = 0
    public var afterBytes: Int64 = 0
    public var unknownSizes = 0
    public var originalsTrashed = 0

    public init() {}

    /// Unbekannte Größe: nur gezählt, nie in die Bilanz.
    public func adding(before: Int64?, after: Int64?) -> BatchSummary {
        var s = self
        s.done += 1
        if let before, let after { s.beforeBytes += before; s.afterBytes += after } else { s.unknownSizes += 1 }
        return s
    }

    /// Nach dem Leeren von „Zuletzt gelöscht“ frei werdender Platz: nur wenn ALLE Originale dort liegen und alle Größen
    /// bekannt sind; sonst 0. Immer als „noch nicht frei“ beschriftet.
    public var freedLaterBytes: Int64 {
        done == 0 || originalsTrashed < done || unknownSizes > 0 ? 0 : max(0, beforeBytes - afterBytes)
    }
}

/// Screenshots untereinander: gemeinsame Breite = schmalstes Bild (nie hochskaliert), proportional, max. Höhe.
public enum StitchPlan {
    public struct Place: Hashable, Sendable {
        public let top: Int
        public let width: Int
        public let height: Int
    }

    public static let maxHeight = 20_000

    public static func layout(_ sizes: [PxSize]) -> (size: PxSize, places: [Place]) {
        precondition(!sizes.isEmpty)
        var w = max(1, sizes.map(\.width).min()!)
        func heights(_ w: Int) -> [Int] { sizes.map { max(1, Int((Double($0.height) * Double(w) / Double($0.width)).rounded())) } }
        var hs = heights(w)
        let total = hs.reduce(0, +)
        if total > maxHeight {
            let f = Double(maxHeight) / Double(total)
            w = max(1, Int((Double(w) * f).rounded()))
            hs = heights(w)
        }
        var top = 0
        let places = hs.map { h -> Place in defer { top += h }; return Place(top: top, width: w, height: h) }
        return (PxSize(w, top), places)
    }
}

/// GIF: Rahmengröße, Platzierung je Bild (einpassen/füllen, nie verzerrt), Bildzeiten aus einem Video.
public enum GifPlan {
    public static let sizes = [480, 720]
    public static let maxFrames = 90
    public static let maxVideoMs: Int64 = 10_000

    public static func frame(firstW: Int, firstH: Int, maxEdge: Int) -> PxSize {
        let s = min(1, Double(maxEdge) / Double(max(firstW, firstH)))
        return PxSize(max(2, Int((Double(firstW) * s).rounded())), max(2, Int((Double(firstH) * s).rounded())))
    }

    /// Zielrechteck (l, t, r, b) im Rahmen; bei `fill` größer als der Rahmen (Rand wird abgeschnitten).
    public static func place(srcW: Int, srcH: Int, frameW: Int, frameH: Int, fill: Bool) -> (Int, Int, Int, Int) {
        let sx = Double(frameW) / Double(srcW), sy = Double(frameH) / Double(srcH)
        let s = fill ? max(sx, sy) : min(sx, sy)
        let w = Int((Double(srcW) * s).rounded()), h = Int((Double(srcH) * s).rounded())
        let l = (frameW - w) / 2, t = (frameH - h) / 2
        return (l, t, l + w, t + h)
    }

    /// Zeitpunkte (ms) für ein Video-GIF: gleichmäßig mit `fps`, höchstens `maxFrames` und `maxVideoMs`.
    public static func videoTimes(startMs: Int64, endMs: Int64, fps: Int) -> [Int64] {
        let end = min(endMs, startMs + maxVideoMs)
        let stepMs = 1000.0 / Double(min(max(fps, 1), 30))
        var out: [Int64] = []
        var t = Double(startMs)
        while t < Double(end) && out.count < maxFrames {
            out.append(Int64(t.rounded()))
            t += stepMs
        }
        return out
    }
}
