import Foundation

/// PDF Studio (iOS, Masterprompt §7): Seitenplan zum Sortieren, Drehen, Entfernen, Zusammenführen und Aufteilen.
/// Reine Rechnung – die App wendet den Plan mit PDFKit an. Nichts überschreibt die Quelle; Ergebnis ist eine neue Datei.
public struct PdfPageRef: Hashable, Codable, Sendable, Identifiable {
    /// Index der Quelldatei (beim Zusammenführen mehrere).
    public let document: Int
    /// Seitenindex in der Quelldatei (0-basiert).
    public let page: Int
    /// Zusätzliche Drehung in Vierteldrehungen im Uhrzeigersinn (0…3).
    public var quarterTurns: Int

    public init(document: Int, page: Int, quarterTurns: Int = 0) {
        self.document = document
        self.page = page
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    }

    public var id: String { "\(document):\(page)" }
    /// Drehung in Grad, wie `PDFPage.rotation` sie erwartet (Vielfaches von 90).
    public func rotationDegrees(base: Int) -> Int { (((base + quarterTurns * 90) % 360) + 360) % 360 }
}

public enum PdfEdit {
    /// Alle Seiten mehrerer Dokumente hintereinander (Zusammenführen).
    public static func merged(pageCounts: [Int]) -> [PdfPageRef] {
        pageCounts.enumerated().flatMap { d, n in (0..<max(0, n)).map { PdfPageRef(document: d, page: $0) } }
    }

    public static func move(_ pages: [PdfPageRef], from: Int, to: Int) -> [PdfPageRef] {
        guard pages.indices.contains(from), pages.indices.contains(to) else { return pages }
        var p = pages
        let e = p.remove(at: from)
        p.insert(e, at: to)
        return p
    }

    public static func rotate(_ pages: [PdfPageRef], at i: Int, clockwise: Bool = true) -> [PdfPageRef] {
        guard pages.indices.contains(i) else { return pages }
        var p = pages
        p[i].quarterTurns = (((p[i].quarterTurns + (clockwise ? 1 : -1)) % 4) + 4) % 4
        return p
    }

    /// Seite entfernen – nie die letzte (ein PDF braucht mindestens eine Seite).
    public static func remove(_ pages: [PdfPageRef], at indices: Set<Int>) -> [PdfPageRef] {
        let kept = pages.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
        return kept.isEmpty ? pages : kept
    }

    /// Seitenbereiche wie „1-3, 5, 8-“ (1-basiert, wie gedruckt) → 0-basierte Indizes in Reihenfolge, ohne Doppelte.
    /// `nil` bei ungültiger Eingabe oder Seiten außerhalb von 1…count.
    public static func parseRanges(_ text: String, count: Int) -> [Int]? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty, count > 0 else { return nil }
        var out: [Int] = []
        var seen = Set<Int>()
        for p in parts {
            let bounds = p.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let lo: Int, hi: Int
            switch bounds.count {
            case 1:
                guard let v = Int(bounds[0]) else { return nil }
                lo = v; hi = v
            case 2:
                guard let a = bounds[0].isEmpty ? 1 : Int(bounds[0]), let b = bounds[1].isEmpty ? count : Int(bounds[1])
                else { return nil }
                lo = a; hi = b
            default: return nil
            }
            guard lo >= 1, hi <= count, lo <= hi else { return nil }
            for v in lo...hi where seen.insert(v - 1).inserted { out.append(v - 1) }
        }
        return out
    }

    /// Aufteilen: je `pagesPerPart` Seiten eine Datei (letzte ggf. kürzer).
    public static func split(count: Int, pagesPerPart: Int) -> [Range<Int>] {
        guard count > 0, pagesPerPart > 0 else { return [] }
        return stride(from: 0, to: count, by: pagesPerPart).map { $0..<min($0 + pagesPerPart, count) }
    }
}
