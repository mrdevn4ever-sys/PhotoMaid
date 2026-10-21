import Foundation

/// Liest SVG-Pfaddaten (`d`) der Artefakt-Symbole in einfache Zeichenbefehle (absolute Koordinaten, nur Linien und
/// kubische Kurven). Unterstützt M L H V C S Q T A Z, jeweils groß und klein. Reine Geometrie, ohne UI.
enum SVGCommand: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)
    case close
}

enum SVGPathParser {
    static func parse(_ d: String) -> [SVGCommand] {
        var scanner = Tokenizer(d)
        var out: [SVGCommand] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character = "M"

        while let next = scanner.peek() {
            if next.isLetter {
                command = next
                scanner.advance()
            } else if command == "Z" || command == "z" {
                break // Zahlen ohne Befehl nach Z: ungültig, abbrechen
            }
            let rel = command.isLowercase
            func pt() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var cubicControl: CGPoint?
            var quadControl: CGPoint?
            switch command {
            case "M", "m":
                guard let p = pt() else { return out }
                out.append(.move(p)); current = p; start = p
                command = rel ? "l" : "L" // weitere Paare = Linien
            case "L", "l":
                guard let p = pt() else { return out }
                out.append(.line(p)); current = p
            case "H", "h":
                guard let x = scanner.number() else { return out }
                current = CGPoint(x: rel ? current.x + x : x, y: current.y); out.append(.line(current))
            case "V", "v":
                guard let y = scanner.number() else { return out }
                current = CGPoint(x: current.x, y: rel ? current.y + y : y); out.append(.line(current))
            case "C", "c":
                guard let c1 = pt(), let c2 = pt(), let p = pt() else { return out }
                out.append(.cubic(c1, c2, p)); current = p; cubicControl = c2
            case "S", "s":
                let c1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = pt(), let p = pt() else { return out }
                out.append(.cubic(c1, c2, p)); current = p; cubicControl = c2
            case "Q", "q":
                guard let q = pt(), let p = pt() else { return out }
                out.append(quad(from: current, q, p)); current = p; quadControl = q
            case "T", "t":
                let q = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let p = pt() else { return out }
                out.append(quad(from: current, q, p)); current = p; quadControl = q
            case "A", "a":
                guard let rx = scanner.number(), let ry = scanner.number(), let rot = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let p = pt() else { return out }
                out += arc(from: current, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                current = p
            case "Z", "z":
                out.append(.close); current = start
            default:
                return out
            }
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
        }
        return out
    }

    private static func quad(from p0: CGPoint, _ q: CGPoint, _ p: CGPoint) -> SVGCommand {
        .cubic(CGPoint(x: p0.x + 2 / 3 * (q.x - p0.x), y: p0.y + 2 / 3 * (q.y - p0.y)),
               CGPoint(x: p.x + 2 / 3 * (q.x - p.x), y: p.y + 2 / 3 * (q.y - p.y)), p)
    }

    /// Bogen nach SVG 1.1 F.6.5 (Endpunkt → Mittelpunkt), in Kurven bis 90°.
    static func arc(from p1: CGPoint, to p2: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat,
                    large: Bool, sweep: Bool) -> [SVGCommand] {
        if p1 == p2 { return [] }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { return [.line(p2)] }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : (max(0, num) / den).squareRoot()
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p1.x + p2.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p1.y + p2.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        var out: [SVGCommand] = []
        var t = theta1
        func point(_ a: CGFloat) -> CGPoint {
            let x = rx * cos(a), y = ry * sin(a)
            return CGPoint(x: cosP * x - sinP * y + cx, y: sinP * x + cosP * y + cy)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            let x = -rx * sin(a), y = ry * cos(a)
            return CGPoint(x: cosP * x - sinP * y, y: sinP * x + cosP * y)
        }
        for i in 0..<segments {
            let t2 = t + step
            let a = point(t), b = i == segments - 1 ? p2 : point(t2)
            let da = derivative(t), db = derivative(t2)
            out.append(.cubic(CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                               CGPoint(x: b.x - k * db.x, y: b.y - k * db.y), b))
            t = t2
        }
        return out
    }

    private struct Tokenizer {
        let chars: [Character]
        var i = 0
        init(_ s: String) { chars = Array(s) }

        mutating func skip() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        mutating func peek() -> Character? {
            skip()
            return i < chars.count ? chars[i] : nil
        }

        mutating func advance() { i += 1 }

        /// Bogen-Flags dürfen ohne Trenner stehen („a2 2 0 1 1…“, „0 0 1-1.82…“).
        mutating func flag() -> Bool? {
            skip()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
            defer { i += 1 }
            return chars[i] == "1"
        }

        mutating func number() -> CGFloat? {
            skip()
            var s = ""
            var seenDot = false, seenExp = false
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == ".", !seenDot, !seenExp { seenDot = true; s.append(c); i += 1 }
                else if (c == "e" || c == "E"), !seenExp, !s.isEmpty {
                    seenExp = true; s.append(c); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
                } else { break }
            }
            guard let v = Double(s) else { return nil }
            return CGFloat(v)
        }
    }
}
