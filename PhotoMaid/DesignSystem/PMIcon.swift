import SwiftUI

/// Strich-Symbole des Artefakts (24 × 24, Strich 2, runde Enden), 1:1 aus dessen SVG-Daten. Nur Dekoration:
/// Bedienelemente tragen ihre eigene Beschriftung.
enum PMIconName: CaseIterable, Sendable {
    case gear, arrowRight, sparkles, chevronRight, chevronLeft, trash, clock, cup, image, chat, crown, close, search
    case plus, check, heart, share, albumAdd, pencil, more, play, undo, vaultDial, lock, calendar, bell, cloud, shield
    case file, house, grid, layers, wand, history, filter, bars, duplicates, series, folder, pie, blur, similar, textDoc
    case motif, video, slideshow, pdf, scan, gif, resize, convert, locationOff, stitch, photos

    fileprivate var glyphs: [PMGlyph] {
        switch self {
        case .gear:
            [.circle(12, 12, 3), .path("M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z")]
        case .arrowRight: [.path("M5 12h14"), .path("M13 6l6 6-6 6")]
        case .sparkles:
            [.path("M12 3l1.9 5.6L19.5 10l-5.6 1.9L12 17.5l-1.9-5.6L4.5 10l5.6-1.4z"),
             .path("M19 17l.7 1.8 1.8.7-1.8.7L19 22l-.7-1.8-1.8-.7 1.8-.7z")]
        case .chevronRight: [.path("M9 6l6 6-6 6")]
        case .chevronLeft: [.path("M15 6l-6 6 6 6")]
        case .trash: [.path("M3 6h18"), .path("M8 6V4h8v2"), .path("M6 6l1 14h10l1-14")]
        case .clock: [.circle(12, 12, 9), .path("M12 7v5l3 2")]
        case .cup: [.path("M4 9h13v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5z"), .path("M17 10h1.5a2.5 2.5 0 0 1 0 5H17"), .path("M8 3v3M12 3v3")]
        case .image: [.rect(3, 5, 18, 14, 3), .circle(9, 10, 1.6), .path("M21 16l-5-5-8 8")]
        case .chat: [.path("M21 12a9 9 0 0 1-13.5 7.8L3 21l1.3-4.4A9 9 0 1 1 21 12z")]
        case .crown: [.path("M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z")]
        case .close: [.path("M6 6l12 12M18 6L6 18")]
        case .search: [.circle(11, 11, 7), .path("M20 20l-4-4")]
        case .plus: [.path("M12 5v14M5 12h14")]
        case .check: [.path("M5 12.5l4.5 4.5L19 7.5")]
        case .heart: [.path("M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z")]
        case .share: [.path("M12 3v12"), .path("M7 8l5-5 5 5"), .path("M5 13v6h14v-6")]
        case .albumAdd: [.rect(3, 6, 14, 14, 3), .path("M7 3h11a3 3 0 0 1 3 3v11"), .path("M10 10v6M7 13h6")]
        case .pencil: [.path("M4 20h4L19 9l-4-4L4 16z"), .path("M14 6l4 4")]
        case .more: [.circle(5, 12, 1.8), .circle(12, 12, 1.8), .circle(19, 12, 1.8)]
        case .play: [.path("M7 4l13 8-13 8z")]
        case .undo: [.path("M9 14L4 9l5-5"), .path("M4 9h10a6 6 0 0 1 0 12h-3")]
        case .vaultDial: [.circle(12, 12, 9), .circle(12, 12, 3.5), .path("M12 3v3M12 18v3M3 12h3M18 12h3")]
        case .lock: [.rect(5, 10, 14, 10, 2.5), .path("M8 10V7a4 4 0 0 1 8 0v3")]
        case .calendar: [.rect(3, 5, 18, 16, 3), .path("M3 10h18M8 3v4M16 3v4")]
        case .bell: [.path("M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"), .path("M10 21h4")]
        case .cloud: [.path("M17.5 19a4.5 4.5 0 1 0-1.2-8.8A6 6 0 0 0 4.5 12 3.5 3.5 0 0 0 6 19z")]
        case .shield: [.path("M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7z")]
        case .file: [.path("M6 3h9l4 4v14H6z"), .path("M15 3v4h4")]
        case .house: [.path("M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z")]
        case .grid: [.rect(3, 3, 7, 7, 2), .rect(14, 3, 7, 7, 2), .rect(3, 14, 7, 7, 2), .rect(14, 14, 7, 7, 2)]
        case .layers: [.path("M12 3l9 5-9 5-9-5z"), .path("M3 13l9 5 9-5")]
        case .wand:
            [.path("M4 20l10-10"), .path("M14 4l1 2 2 1-2 1-1 2-1-2-2-1 2-1z"),
             .path("M19 11l.6 1.4L21 13l-1.4.6L19 15l-.6-1.4L17 13l1.4-.6z")]
        case .history: [.path("M3 12a9 9 0 1 0 3-6.7L3 8"), .path("M3 3v5h5"), .path("M12 7v5l3 2")]
        case .filter: [.path("M4 6h16M7 12h10M10 18h4")]
        case .bars: [.path("M4 20h16M6 16V8M10 16V4M14 16v-6M18 16v-9")]
        case .duplicates: [.path("M8 8h11v11H8zM5 16V5h11")]
        case .series: [.path("M3 6h6v12H3zM9 6h6v12H9zM15 6h6v12h-6z")]
        case .folder: [.path("M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z")]
        case .pie: [.path("M12 3a9 9 0 1 0 9 9h-9z")]
        case .blur: [.path("M3 12h4M17 12h4M12 3v4M12 17v4M8 8l-2-2M18 18l-2-2M16 8l2-2M6 18l2-2")]
        case .similar: [.path("M4 6h10v10H4zM10 10h10v10H10")]
        case .textDoc: [.path("M6 3h9l4 4v14H6zM9 12h7M9 16h5")]
        case .motif: [.path("M3 18l5-7 4 5 3-4 6 6z"), .circle(8, 7, 2)]
        case .video: [.path("M4 6h12v12H4zM16 10l5-3v10l-5-3")]
        case .slideshow: [.path("M3 5h18v14H3zM10 9l5 3-5 3z")]
        case .pdf: [.path("M6 3h9l4 4v14H6zM9 13h7M9 17h5")]
        case .scan: [.path("M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3M7 12h10")]
        case .gif: [.path("M4 5h16v14H4zM8 10h3M8 14h2M14 10v4M17 10h-1v4")]
        case .resize: [.path("M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7")]
        case .convert: [.path("M4 7h13l-3-3M20 17H7l3 3")]
        case .locationOff: [.path("M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12zM4 4l16 16")]
        case .stitch: [.path("M7 3h10v8H7zM7 13h10v8H7z")]
        case .photos: [.rect(3, 5, 18, 14, 3), .circle(9, 10, 1.6), .path("M21 16l-5-5-8 8")]
        }
    }

    /// Ausgefüllt statt gestrichen (Punkte, Abspielen).
    fileprivate var filledByDefault: Bool { self == .more || self == .play }

    fileprivate static let parsed: [PMIconName: [ParsedGlyph]] = {
        var out: [PMIconName: [ParsedGlyph]] = [:]
        for name in PMIconName.allCases {
            out[name] = name.glyphs.map { g -> ParsedGlyph in
                switch g {
                case .path(let d): return .commands(SVGPathParser.parse(d))
                case .circle(let x, let y, let r): return .circle(x, y, r)
                case .rect(let x, let y, let w, let h, let r): return .rect(x, y, w, h, r)
                }
            }
        }
        return out
    }()
}

fileprivate enum PMGlyph {
    case path(String)
    case circle(CGFloat, CGFloat, CGFloat)
    case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
}

fileprivate enum ParsedGlyph: Sendable {
    case commands([SVGCommand])
    case circle(CGFloat, CGFloat, CGFloat)
    case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
}

/// Form eines Symbols, auf den Rahmen skaliert (Ansichtsfeld 24 × 24).
struct PMIconShape: Shape {
    let name: PMIconName

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: ox + pt.x * s, y: oy + pt.y * s) }
        var path = Path()
        for glyph in PMIconName.parsed[name] ?? [] {
            switch glyph {
            case .commands(let cmds):
                for c in cmds {
                    switch c {
                    case .move(let pt): path.move(to: p(pt))
                    case .line(let pt): path.addLine(to: p(pt))
                    case .cubic(let c1, let c2, let pt): path.addCurve(to: p(pt), control1: p(c1), control2: p(c2))
                    case .close: path.closeSubpath()
                    }
                }
            case .circle(let x, let y, let r):
                path.addEllipse(in: CGRect(x: ox + (x - r) * s, y: oy + (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            case .rect(let x, let y, let w, let h, let r):
                path.addRoundedRect(in: CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s),
                                    cornerSize: CGSize(width: r * s, height: r * s))
            }
        }
        return path
    }
}

/// Symbol in Vordergrundfarbe: Strich 2 (bezogen auf 24 pt), wahlweise gefüllt (Favorit, Punkte).
struct PMIcon: View {
    let name: PMIconName
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2
    var filled = false

    init(_ name: PMIconName, size: CGFloat = 20, lineWidth: CGFloat = 2, filled: Bool = false) {
        self.name = name
        self.size = size
        self.lineWidth = lineWidth
        self.filled = filled
    }

    var body: some View {
        ZStack {
            if filled || name.filledByDefault { PMIconShape(name: name).fill() }
            if !name.filledByDefault {
                PMIconShape(name: name)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
