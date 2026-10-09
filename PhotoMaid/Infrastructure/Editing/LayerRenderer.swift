import CoreImage
import CoreText
import PhotoMaidCore
import UIKit

/// Zeichnet Ebenen (Text, Sticker, Zeichnung, Formen) – derselbe Code für Vorschau und Export. Größen relativ zur
/// kürzeren Bildkante (wie Android). Abdecken rechnet `EditRenderer` in die Pixel (nie nur überlagert).
enum LayerRenderer {
    static func draw(_ layers: [Layer], over img: CIImage, size: PxSize) -> CIImage {
        let visible = layers.filter { if case .redact = $0 { false } else { true } }
        guard !visible.isEmpty, size.width > 0, size.height > 0 else { return img }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width, height: size.height), format: format)
        let overlay = renderer.image { ctx in
            let c = ctx.cgContext
            let short = CGFloat(min(size.width, size.height))
            for l in visible {
                c.saveGState()
                switch l {
                case .text(let t): drawText(t, c, size, short)
                case .sticker(let s): drawSticker(s, c, size, short)
                case .draw(let d): drawStrokes(d.strokes, c, size, short)
                case .shape(let s): drawShape(s, c, size, short)
                case .redact: break
                }
                c.restoreGState()
            }
        }
        guard let cg = overlay.cgImage else { return img }
        return CIImage(cgImage: cg).composited(over: img)
    }

    static func color(_ argb: ARGB, opacity: Float = 1) -> UIColor {
        let c = ARGBColor.components(argb)
        return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a * opacity))
    }

    static func font(_ id: FontId, size: CGFloat) -> UIFont {
        switch id {
        case .sans: return .systemFont(ofSize: size, weight: .regular)
        case .sansBold: return .systemFont(ofSize: size, weight: .bold)
        case .black: return .systemFont(ofSize: size, weight: .black)
        case .condensed:
            let d = UIFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withSymbolicTraits(.traitCondensed)
            return d.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size, weight: .semibold)
        case .serif:
            let d = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return d.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .medium)
        case .handwriting: return UIFont(name: "Noteworthy-Bold", size: size) ?? .italicSystemFont(ofSize: size)
        case .casual:
            let d = UIFont.systemFont(ofSize: size, weight: .heavy).fontDescriptor.withDesign(.rounded)
            return d.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size, weight: .heavy)
        case .smallCaps:
            let base = UIFont.systemFont(ofSize: size, weight: .semibold)
            let d = base.fontDescriptor.addingAttributes([.featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kLowerCaseType, UIFontDescriptor.FeatureKey.selector: kLowerCaseSmallCapsSelector]]])
            return UIFont(descriptor: d, size: size)
        }
    }

    private static func drawText(_ l: TextLayer, _ c: CGContext, _ size: PxSize, _ short: CGFloat) {
        let fs = max(1, CGFloat(l.size) * short)
        let para = NSMutableParagraphStyle()
        para.alignment = switch l.align {
        case .start: .natural
        case .center: .center
        case .end: .right
        }
        var attrs: [NSAttributedString.Key: Any] = [.font: font(l.font, size: fs), .paragraphStyle: para,
                                                    .foregroundColor: color(l.color, opacity: l.opacity)]
        if l.style == .outline {
            attrs[.strokeColor] = color(l.accent, opacity: l.opacity)
            attrs[.strokeWidth] = -14.0
        }
        let text = NSAttributedString(string: l.text, attributes: attrs)
        let bounds = text.boundingRect(with: CGSize(width: CGFloat(size.width) * 0.95, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral
        let pad = l.style == .pill ? fs * 0.45 : fs * 0.12
        c.translateBy(x: CGFloat(l.center.x) * CGFloat(size.width), y: CGFloat(l.center.y) * CGFloat(size.height))
        c.rotate(by: CGFloat(l.rotation) * .pi / 180)
        let box = CGRect(x: -bounds.width / 2 - pad, y: -bounds.height / 2 - pad, width: bounds.width + 2 * pad,
                         height: bounds.height + 2 * pad)
        switch l.style {
        case .pill:
            color(l.accent, opacity: l.opacity).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: box.height / 2).fill()
        case .fill:
            color(l.accent, opacity: l.opacity).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: fs * 0.2).fill()
        case .shadow:
            c.setShadow(offset: CGSize(width: 0, height: fs * 0.04), blur: fs * 0.10, color: UIColor.black.withAlphaComponent(0.6).cgColor)
        case .outline:
            break
        }
        text.draw(with: CGRect(x: -bounds.width / 2, y: -bounds.height / 2, width: bounds.width, height: bounds.height),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        if l.style == .outline {
            var fill = attrs
            fill[.strokeWidth] = nil
            fill[.strokeColor] = nil
            NSAttributedString(string: l.text, attributes: fill)
                .draw(with: CGRect(x: -bounds.width / 2, y: -bounds.height / 2, width: bounds.width, height: bounds.height),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    private static func drawSticker(_ l: StickerLayer, _ c: CGContext, _ size: PxSize, _ short: CGFloat) {
        let s = CGFloat(l.size) * short
        c.translateBy(x: CGFloat(l.center.x) * CGFloat(size.width), y: CGFloat(l.center.y) * CGFloat(size.height))
        c.rotate(by: CGFloat(l.rotation) * .pi / 180)
        let tint = color(l.color, opacity: l.opacity)
        func symbol(_ name: String) {
            let cfg = UIImage.SymbolConfiguration(pointSize: s * 0.8, weight: .bold)
            guard let img = UIImage(systemName: name, withConfiguration: cfg)?.withTintColor(tint, renderingMode: .alwaysOriginal)
            else { return }
            let r = CGRect(x: -img.size.width / 2, y: -img.size.height / 2, width: img.size.width, height: img.size.height)
            img.draw(in: r)
        }
        switch l.kind {
        case .emoji:
            let text = NSAttributedString(string: l.value.isEmpty ? "⭐️" : l.value,
                                          attributes: [.font: UIFont.systemFont(ofSize: s * 0.86)])
            let b = text.size()
            text.draw(at: CGPoint(x: -b.width / 2, y: -b.height / 2))
        case .arrow: symbol("arrow.right")
        case .heart: symbol("heart.fill")
        case .star: symbol("star.fill")
        case .check: symbol("checkmark")
        case .cross: symbol("xmark")
        case .bubble: symbol("bubble.left.fill")
        case .circle:
            tint.setStroke()
            let p = UIBezierPath(ovalIn: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
            p.lineWidth = max(2, s * 0.06)
            p.stroke()
        case .sparkle: symbol("sparkles")
        case .date:
            let h = s * 0.8
            let text = NSAttributedString(string: l.value, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: h * 0.62, weight: .bold), .foregroundColor: tint])
            let b = text.size()
            text.draw(at: CGPoint(x: -b.width / 2, y: -b.height / 2))
        }
    }

    private static func path(_ pts: [NormPoint], _ size: PxSize) -> UIBezierPath {
        let p = UIBezierPath()
        guard let first = pts.first else { return p }
        p.move(to: CGPoint(x: CGFloat(first.x) * CGFloat(size.width), y: CGFloat(first.y) * CGFloat(size.height)))
        if pts.count == 1 { p.addLine(to: CGPoint(x: CGFloat(first.x) * CGFloat(size.width) + 0.1, y: CGFloat(first.y) * CGFloat(size.height))) }
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: CGFloat(q.x) * CGFloat(size.width), y: CGFloat(q.y) * CGFloat(size.height))) }
        return p
    }

    private static func drawStrokes(_ strokes: [DrawStroke], _ c: CGContext, _ size: PxSize, _ short: CGFloat) {
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        for s in strokes {
            let p = path(s.points, size)
            p.lineWidth = max(1, CGFloat(s.width) * short)
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            switch s.brush {
            case .pen:
                color(s.color).setStroke()
                p.stroke()
            case .marker:
                color(s.color, opacity: 0.45).setStroke()
                p.stroke(with: .normal, alpha: 1)
            case .neon:
                c.saveGState()
                c.setShadow(offset: .zero, blur: p.lineWidth * 1.6, color: color(s.color).cgColor)
                color(s.color).setStroke()
                p.stroke()
                c.restoreGState()
                UIColor.white.withAlphaComponent(0.85).setStroke()
                p.lineWidth = max(1, p.lineWidth * 0.35)
                p.stroke()
            case .eraser:
                p.stroke(with: .clear, alpha: 1)
            }
        }
        c.endTransparencyLayer()
    }

    private static func drawShape(_ l: ShapeLayer, _ c: CGContext, _ size: PxSize, _ short: CGFloat) {
        let a = CGPoint(x: CGFloat(l.start.x) * CGFloat(size.width), y: CGFloat(l.start.y) * CGFloat(size.height))
        let b = CGPoint(x: CGFloat(l.end.x) * CGFloat(size.width), y: CGFloat(l.end.y) * CGFloat(size.height))
        let col = color(l.color, opacity: l.opacity)
        let w = max(1, CGFloat(l.width) * short)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        let p: UIBezierPath
        switch l.kind {
        case .rect: p = UIBezierPath(rect: rect)
        case .ellipse: p = UIBezierPath(ovalIn: rect)
        case .line:
            p = UIBezierPath()
            p.move(to: a); p.addLine(to: b)
        case .arrow:
            p = UIBezierPath()
            p.move(to: a); p.addLine(to: b)
            let ang = atan2(b.y - a.y, b.x - a.x), head = w * 4
            p.move(to: b); p.addLine(to: CGPoint(x: b.x - head * cos(ang - .pi / 7), y: b.y - head * sin(ang - .pi / 7)))
            p.move(to: b); p.addLine(to: CGPoint(x: b.x - head * cos(ang + .pi / 7), y: b.y - head * sin(ang + .pi / 7)))
        }
        p.lineWidth = w
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        if l.filled && (l.kind == .rect || l.kind == .ellipse) { col.setFill(); p.fill() }
        col.setStroke()
        p.stroke()
    }
}
