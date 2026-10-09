import Foundation

/// Mehrseitiges PDF aus Fotos und Kontaktbögen. Fotos werden nie verzerrt: eingepasst (ganzes Bild) oder beschnitten
/// (Feld gefüllt). Maße in PDF-Punkten (1/72 Zoll), Ursprung oben links (wie `UIGraphicsPDFRenderer`).
public enum PaperSize: String, Hashable, Codable, Sendable, CaseIterable {
    case a4 = "A4", letter = "LETTER", a5 = "A5"

    public var shortPt: Double {
        switch self {
        case .a4: 595.28
        case .letter: 612
        case .a5: 419.53
        }
    }

    public var longPt: Double {
        switch self {
        case .a4: 841.89
        case .letter: 792
        case .a5: 595.28
        }
    }
}

public enum PageOrientation: String, Hashable, Codable, Sendable, CaseIterable { case auto, portrait, landscape }

public enum PageMargin: String, Hashable, Codable, Sendable, CaseIterable {
    case none, small, normal
    public var pt: Double {
        switch self {
        case .none: 0
        case .small: 18
        case .normal: 36
        }
    }
}

/// Bilder je Seite; ab vier ist es ein Kontaktbogen.
public enum PerPage: Int, Hashable, Codable, Sendable, CaseIterable {
    case one = 1, two = 2, four = 4, six = 6, twelve = 12

    public var cols: Int {
        switch self {
        case .one, .two: 1
        case .four, .six: 2
        case .twelve: 3
        }
    }

    public var rows: Int {
        switch self {
        case .one: 1
        case .two, .four: 2
        case .six: 3
        case .twelve: 4
        }
    }

    public var count: Int { cols * rows }
    public var isContactSheet: Bool { count >= 4 }
}

public enum ImageFit: String, Hashable, Codable, Sendable, CaseIterable { case fit, fill }

/// Beschriftung unter jedem Bild – nur, was die App ohnehin kennt (Nummer, Dateiname, Datum).
public enum Caption: String, Hashable, Codable, Sendable, CaseIterable { case none, number, name, date }

public struct PdfOptions: Hashable, Codable, Sendable {
    public var paper = PaperSize.a4
    public var orientation = PageOrientation.auto
    public var margin = PageMargin.normal
    public var perPage = PerPage.one
    public var fit = ImageFit.fit
    public var caption = Caption.none
    /// Texterkennung als unsichtbare Textebene (iOS-Ergänzung; macht das PDF durchsuchbar).
    public var searchableText = false
    public init() {}
}

/// Rechteck in Punkten, Ursprung oben links.
public struct PtRect: Hashable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var aspect: Double { w / h }
}

/// Sichtbarer Ausschnitt der Quelle, normiert 0…1.
public struct Crop: Hashable, Sendable {
    public var left: Double, top: Double, right: Double, bottom: Double
    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
    public static let full = Crop(left: 0, top: 0, right: 1, bottom: 1)
    public var isFull: Bool { self == .full }
}

/// Ein Bild auf der Seite: `rect` = Zeichenfläche (Seitenverhältnis = Ausschnitt), `caption` = Feld für die Beschriftung.
public struct Placed: Hashable, Sendable {
    public let index: Int
    public let cell: PtRect
    public let rect: PtRect
    public let crop: Crop
    public let caption: PtRect?
}

public struct PdfPageLayout: Hashable, Sendable {
    public let widthPt: Double
    public let heightPt: Double
    public let items: [Placed]
}

/// Ausgerichtete Pixelmaße einer Quelle.
public struct SourceSize: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public var aspect: Double { Double(width) / Double(height) }
}

public enum PdfLayout {
    public static let gapPt = 10.0
    public static let captionPt = 16.0

    public static func pages(_ sources: [SourceSize], options o: PdfOptions) -> [PdfPageLayout] {
        guard !sources.isEmpty else { return [] }
        return stride(from: 0, to: sources.count, by: o.perPage.count).map { start in
            page(Array(start..<min(start + o.perPage.count, sources.count)), sources, o)
        }
    }

    private static func page(_ chunk: [Int], _ sources: [SourceSize], _ o: PdfOptions) -> PdfPageLayout {
        let landscape: Bool
        switch o.orientation {
        case .portrait: landscape = false
        case .landscape: landscape = true
        // Automatisch: ein Bild je Seite folgt dem Bild, sonst Hochformat.
        case .auto: landscape = o.perPage == .one && sources[chunk[0]].aspect > 1
        }
        let w = landscape ? o.paper.longPt : o.paper.shortPt
        let h = landscape ? o.paper.shortPt : o.paper.longPt
        let m = o.margin.pt
        // Im Querformat Spalten und Zeilen tauschen, damit die Felder nicht unnötig schmal werden.
        let cols = landscape ? o.perPage.rows : o.perPage.cols
        let rows = landscape ? o.perPage.cols : o.perPage.rows
        let gap = o.perPage == .one ? 0 : gapPt
        let cellW = (w - 2 * m - gap * Double(cols - 1)) / Double(cols)
        let cellH = (h - 2 * m - gap * Double(rows - 1)) / Double(rows)
        let items = chunk.enumerated().map { slot, i -> Placed in
            let cell = PtRect(x: m + Double(slot % cols) * (cellW + gap), y: m + Double(slot / cols) * (cellH + gap),
                              w: cellW, h: cellH)
            let capH = o.caption == .none ? 0 : captionPt
            let area = PtRect(x: cell.x, y: cell.y, w: cell.w, h: cell.h - capH)
            let (rect, crop) = place(sources[i], area: area, fit: o.fit)
            return Placed(index: i, cell: cell, rect: rect, crop: crop,
                          caption: capH > 0 ? PtRect(x: cell.x, y: cell.y + cell.h - capH, w: cell.w, h: capH) : nil)
        }
        return PdfPageLayout(widthPt: w, heightPt: h, items: items)
    }

    /// Einpassen: größtes Rechteck mit dem Seitenverhältnis der Quelle, mittig. Füllen: ganze Fläche, Quelle beschnitten.
    public static func place(_ src: SourceSize, area: PtRect, fit: ImageFit) -> (PtRect, Crop) {
        switch fit {
        case .fit:
            let s = min(area.w / Double(src.width), area.h / Double(src.height))
            let dw = Double(src.width) * s, dh = Double(src.height) * s
            return (PtRect(x: area.x + (area.w - dw) / 2, y: area.y + (area.h - dh) / 2, w: dw, h: dh), .full)
        case .fill:
            let a = area.aspect
            let crop: Crop
            if src.aspect > a {
                let keep = a / src.aspect
                crop = Crop(left: (1 - keep) / 2, top: 0, right: (1 + keep) / 2, bottom: 1)
            } else {
                let keep = src.aspect / a
                crop = Crop(left: 0, top: (1 - keep) / 2, right: 1, bottom: (1 + keep) / 2)
            }
            return (area, crop)
        }
    }

    /// Pixel für die Ausgabe: `dpi` bezogen auf die Zeichenfläche, nie mehr als der sichtbare Ausschnitt hergibt.
    public static func pixels(for rect: PtRect, src: SourceSize, crop: Crop, dpi: Int = 200) -> PxSize {
        let availW = Double(src.width) * (crop.right - crop.left)
        let availH = Double(src.height) * (crop.bottom - crop.top)
        let wantW = rect.w / 72 * Double(dpi)
        let s = min(1, wantW / availW)
        return PxSize(max(1, Int((availW * s).rounded())), max(1, Int((availH * s).rounded())))
    }
}

/// Free / Pro – ausprobieren (Vorschau) ist immer frei.
public enum PdfRules {
    public static let freeMax = 10
    public static let proMax = 200
    public static func maxImages(pro: Bool) -> Int { pro ? proMax : freeMax }
    /// Kontaktbögen (ab 4 je Seite) speichern mit Pro, wie der A4-Druck der Collage.
    public static func needsPro(_ o: PdfOptions, count: Int) -> Bool { o.perPage.isContactSheet || count > freeMax }

    /// Dateiname ohne Pfadzeichen; leer → Vorgabe.
    public static func fileName(_ raw: String, fallback: String) -> String {
        let bad = Set("\\/:*?\"<>|")
        var clean = String(String(raw.trimmingCharacters(in: .whitespaces).unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init).filter { !bad.contains($0) })
            .prefix(80))
        while let f = clean.first, f == "." || f == " " { clean.removeFirst() }
        while let l = clean.last, l == "." || l == " " { clean.removeLast() }
        let base = clean.isEmpty ? fallback : clean
        return base.lowercased().hasSuffix(".pdf") ? base : base + ".pdf"
    }
}
