import PhotoMaidCore
import SwiftUI
import UIKit

/// Laufende Mini-Szene der Spiele (Nutzer, 22.10.2026: „Vielleicht mehr game-mäßig, damit klar ist, um was es geht? Zu
/// statisch“): groß oben auf jeder Startseite, als festes Bild auf den Karten in „Kurze Pause“. Zeigt in einer Schleife, wie
/// gespielt wird – bei Paare werden Karten aufgedeckt und Paare gefunden, die Foto-Snake frisst und wächst um ein Foto,
/// bei Foto Blocks verschwinden volle Reihen und legen ein Foto frei. Nur Ansicht: gezeichnete Beispielbilder statt
/// Mediathek-Fotos, keine Eingabe, kein Spielstand. Zeichnet nur bei aktiver App; bei „Bewegung reduzieren“ steht ein
/// fester Moment.
struct GameShowcase: View {
    enum Kind: Equatable {
        case pairs
        case snake(PhotoSnakeCharacter, night: Bool)
        case blocks
    }

    let kind: Kind
    var compact = false
    /// Aus: ein festes Bild der Szene (Karten in „Kurze Pause“ – dort bewegt sich nichts, die Bewegung zeigt die
    /// Startseite des Spiels; laufende Szenen in den Spielknöpfen hielten die App für XCUITest dauerhaft beschäftigt).
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date.now
    @State private var resting = false

    var body: some View {
        let art = ShowcaseArt.make(kind)
        let radius: CGFloat = compact ? 16 : 24
        let still = reduceMotion || !animated
        TimelineView(.animation(minimumInterval: compact ? 1.0 / 20 : 1.0 / 30,
                                paused: still || scenePhase != .active || resting)) { timeline in
            let time = max(0, timeline.date.timeIntervalSince(start))
            Canvas { context, size in
                let scene = ShowcaseScene(size: size, compact: compact, still: still, art: art)
                switch kind {
                case .pairs: scene.pairs(time, &context)
                case .snake(let character, _): scene.snake(time, &context, character: character)
                case .blocks: scene.blocks(time, &context)
                }
            }
        }
        .background {
            // Feste Ebene: das große Wiesenbild wird nicht in jedem Bild neu gezeichnet.
            if let background = art.background {
                background.resizable().scaledToFill().overlay(Color.black.opacity(0.08))
            }
        }
        .clipShape(.rect(cornerRadius: radius))
        .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .environment(\.layoutDirection, .leftToRight) // Fingerrichtungen im Spiel sind physisch, auch in RTL.
        .accessibilityHidden(true)
        .task(id: scenePhase == .active) {
            // Läuft nach dem Erscheinen eine Minute und ruht dann auf dem letzten Bild: spart Akku, und die App wird
            // wieder ruhig. Erneutes Öffnen oder Rückkehr in die App startet sie neu.
            guard !still else { return }
            resting = false
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { resting = true }
        }
    }
}

/// Bilder einer Szene, einmal auf dem Hauptthread erzeugt; die Szene zeichnet sie nur noch.
@MainActor
private struct ShowcaseArt {
    var photos: [Image] = []
    var boardPhoto: Image?
    var background: Image?
    var head: Image?
    var eatingHead: Image?
    var food: [Image] = []
    let cardBack = Image(systemName: "photo.on.rectangle.angled").resizable()
    let check = Image(systemName: "checkmark").resizable()
    let hand = Image(systemName: "hand.point.up.left.fill").resizable()
    let star = Image(systemName: "sparkle").resizable()

    static func make(_ kind: GameShowcase.Kind) -> ShowcaseArt {
        var art = ShowcaseArt()
        art.photos = (0..<ShowcasePhotos.count).map { Image(uiImage: ShowcasePhotos.image($0, size: CGSize(width: 120, height: 120))) }
        switch kind {
        case .pairs:
            break
        case .snake(let character, let night):
            // Wenige Bilder aus dem Snake-Atlas (jedes kostet eine Umwandlung): Kopf in Ruhe und beim Fressen – die
            // vier Richtungen sind gedrehte Fassungen desselben Bildes –, drei Sorten Futter; die Wiese direkt.
            let forest = night ? "bg_forest_night" : "bg_forest_day"
            art.background = Image(uiImage: UIImage(named: forest) ?? SnakeArt.image(forest))
            art.head = Image(uiImage: SnakeArt.headImage(character))
            art.eatingHead = Image(uiImage: SnakeArt.image(
                PhotoSnakeHeadAnimation.overheadTexture(character: character, pose: .eat, direction: .up)))
            art.food = (0..<3).map { Image(uiImage: SnakeArt.image(PhotoSnakeFood.mixed.texture(score: $0))) }
        case .blocks:
            art.boardPhoto = Image(uiImage: ShowcasePhotos.image(0, size: CGSize(width: 150, height: 200)))
        }
        return art
    }
}

/// Gezeichnete Beispielbilder (kleine Landschaften wie das Foto-Symbol) – Illustration, keine Medien des Nutzers.
@MainActor
private enum ShowcasePhotos {
    static let count = 6
    private static var cache: [String: UIImage] = [:]
    /// Himmel oben, Himmel unten, Sonne/Mond, Berge, Hügel, Nacht.
    private static let palettes: [(UInt32, UInt32, UInt32, UInt32, UInt32, Bool)] = [
        (0xFF8A5B, 0xFFD58A, 0xFFF4D6, 0xC0567E, 0x6E2C5C, false),
        (0x4FB6EC, 0xC5ECFF, 0xFFFFFF, 0x3D7FB8, 0x1D4E7A, false),
        (0x8FD6A6, 0xEAF7CC, 0xFFF2A8, 0x3F8F5B, 0x1E5C38, false),
        (0x8C7BF0, 0xF4BCDF, 0xFFF0F6, 0x5A4BB2, 0x33286E, false),
        (0xF6AE5F, 0xFDE8B6, 0xFFFFFF, 0xD9813A, 0x99501F, false),
        (0x1A2752, 0x4A64A0, 0xF6F1D2, 0x2D3F72, 0x121B3A, true)
    ]

    static func image(_ index: Int, size: CGSize) -> UIImage {
        let key = "\(index)-\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }
        let p = palettes[index % palettes.count]
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            let w = size.width, h = size.height
            let sky = [UIColor(hex: p.0).cgColor, UIColor(hex: p.1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h * 0.75), options: [.drawsAfterEndLocation])
            }
            if p.5 {
                UIColor.white.withAlphaComponent(0.8).setFill()
                for (x, y) in [(0.14, 0.14), (0.3, 0.3), (0.46, 0.12), (0.88, 0.2), (0.56, 0.36)] {
                    cg.fillEllipse(in: CGRect(x: w * x, y: h * y, width: max(1.5, w * 0.018), height: max(1.5, w * 0.018)))
                }
            }
            let r = min(w, h) * 0.11
            UIColor(hex: p.2).setFill()
            cg.fillEllipse(in: CGRect(x: w * 0.68 - r, y: h * 0.3 - r, width: 2 * r, height: 2 * r))
            UIColor(hex: p.3).setFill()
            let back = UIBezierPath()
            back.move(to: CGPoint(x: 0, y: h * 0.72))
            back.addLine(to: CGPoint(x: w * 0.28, y: h * 0.44))
            back.addLine(to: CGPoint(x: w * 0.52, y: h * 0.66))
            back.addLine(to: CGPoint(x: w * 0.76, y: h * 0.4))
            back.addLine(to: CGPoint(x: w, y: h * 0.62))
            back.addLine(to: CGPoint(x: w, y: h))
            back.addLine(to: CGPoint(x: 0, y: h))
            back.close(); back.fill()
            UIColor(hex: p.4).setFill()
            let front = UIBezierPath()
            front.move(to: CGPoint(x: 0, y: h * 0.84))
            front.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), controlPoint: CGPoint(x: w * 0.45, y: h * 0.64))
            front.addLine(to: CGPoint(x: w, y: h))
            front.addLine(to: CGPoint(x: 0, y: h))
            front.close(); front.fill()
        }
        cache[key] = image
        return image
    }
}

// MARK: - Szenen

private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
/// Weicher Übergang 0 → 1.
private func smooth(_ x: Double) -> Double { let t = clamp01(x); return t * t * (3 - 2 * t) }
/// 0 → 1 → 0 über das Fenster 0…1.
private func bump(_ x: Double) -> Double { x <= 0 || x >= 1 ? 0 : sin(.pi * x) }
private func square(_ center: CGPoint, _ side: CGFloat) -> CGRect {
    CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
}

private extension GraphicsContext {
    /// Zeichnet unverzerrt: `fill` füllt (vorher beschneiden), sonst eingepasst.
    func drawImage(_ image: ResolvedImage, in rect: CGRect, fill: Bool) {
        let natural = image.size
        guard natural.width > 0, natural.height > 0, rect.width > 0, rect.height > 0 else { return }
        let scale = fill ? max(rect.width / natural.width, rect.height / natural.height)
            : min(rect.width / natural.width, rect.height / natural.height)
        let w = natural.width * scale, h = natural.height * scale
        draw(image, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }
}

/// Ablauf von Paare: welche Karte wann aufgedeckt, zugedeckt und gefunden wird.
private struct PairsScript {
    let columns: Int
    let faces: [Int]
    let shown: [[(up: Double, down: Double)]]
    let matched: [Double]
    let taps: [(card: Int, at: Double)]
    let mismatch: (cards: [Int], from: Double, to: Double)?
    let celebrate: (from: Double, to: Double)
    let loop: Double
    let still: Double

    var rows: Int { faces.count / columns }

    /// 0 = Rückseite, 1 = Foto.
    func face(_ card: Int, _ t: Double) -> Double {
        var value = 0.0
        for span in shown[card] where t >= span.up {
            value = t < span.down ? clamp01((t - span.up) / 0.3) : 1 - clamp01((t - span.down) / 0.3)
        }
        return value
    }

    /// Acht Karten, ein Fehlversuch, dann alle vier Paare.
    static let full = PairsScript(
        columns: 4, faces: [0, 2, 1, 3, 3, 0, 2, 1],
        shown: [[(0.4, 9.4)], [(5.2, 9.45)], [(1.9, 3.3), (4.4, 9.5)], [(6.6, 9.55)],
                [(2.5, 3.3), (7.2, 9.6)], [(1.0, 9.65)], [(5.8, 9.7)], [(3.8, 9.75)]],
        matched: [1.3, 6.1, 4.7, 7.5, 7.5, 1.3, 6.1, 4.7],
        taps: [(0, 0.4), (5, 1.0), (2, 1.9), (4, 2.5), (7, 3.8), (2, 4.4), (1, 5.2), (6, 5.8), (3, 6.6), (4, 7.2)],
        mismatch: ([2, 4], 2.85, 3.25), celebrate: (7.6, 9.3), loop: 10.4, still: 8.2)
    /// Klein auf der Spielkarte: vier Karten, zwei Paare.
    static let compact = PairsScript(
        columns: 2, faces: [0, 1, 1, 0],
        shown: [[(0.4, 4.2)], [(1.9, 4.25)], [(2.5, 4.3)], [(1.0, 4.35)]],
        matched: [1.3, 2.8, 2.8, 1.3], taps: [], mismatch: nil, celebrate: (3.0, 3.9), loop: 5.2, still: 3.4)
}

/// Rundweg der Schlange auf einem Raster mit fünf Reihen (Zellkoordinaten, geschlossen).
private struct SnakeTrack {
    let vertices: [CGPoint]
    let lengths: [Double]
    /// Freie Stelle für den wischenden Finger.
    let pocket: CGPoint
    var length: Double { lengths.last ?? 1 }

    init(columns: Int) {
        let c0 = 1, c3 = max(2, columns - 2)
        let raw: [(Int, Int)]
        if c3 - c0 >= 5 {
            let c1 = c0 + (c3 - c0) / 3, c2 = c0 + 2 * (c3 - c0) / 3
            raw = [(c0, 1), (c3, 1), (c3, 3), (c2, 3), (c2, 2), (c1, 2), (c1, 3), (c0, 3), (c0, 1)]
            pocket = CGPoint(x: Double(c1 + c2) / 2, y: 3.1)
        } else {
            raw = [(c0, 1), (c3, 1), (c3, 3), (c0, 3), (c0, 1)]
            pocket = CGPoint(x: Double(c0 + c3) / 2, y: 2)
        }
        vertices = raw.map { CGPoint(x: Double($0.0), y: Double($0.1)) }
        var total = 0.0
        var lengths = [0.0]
        for i in 1..<vertices.count {
            total += abs(vertices[i].x - vertices[i - 1].x) + abs(vertices[i].y - vertices[i - 1].y)
            lengths.append(total)
        }
        self.lengths = lengths
    }

    func point(_ distance: Double) -> (point: CGPoint, direction: PhotoSnakeGame.Direction) {
        var d = distance.truncatingRemainder(dividingBy: length)
        if d < 0 { d += length }
        var i = 1
        while i < lengths.count - 1, d >= lengths[i] { i += 1 }
        let a = vertices[i - 1], b = vertices[i]
        let span = max(0.0001, lengths[i] - lengths[i - 1])
        let f = min(1, max(0, (d - lengths[i - 1]) / span))
        let direction: PhotoSnakeGame.Direction = b.x > a.x ? .right : (b.x < a.x ? .left : (b.y > a.y ? .down : .up))
        return (CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), direction)
    }
}

@MainActor
private struct ShowcaseScene {
    let size: CGSize
    let compact: Bool
    let still: Bool
    let art: ShowcaseArt

    private var bounds: CGRect { CGRect(origin: .zero, size: size) }

    // MARK: Paare

    func pairs(_ time: Double, _ ctx: inout GraphicsContext) {
        let script = compact ? PairsScript.compact : PairsScript.full
        let t = still ? script.still : time.truncatingRemainder(dividingBy: script.loop)
        if compact {
            ctx.fill(Path(bounds), with: .color(AppColors.pauseStroke))
        } else {
            ctx.fill(Path(bounds), with: .linearGradient(Gradient(colors: [AppColors.pauseSurface, AppColors.pauseGround]),
                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
        ctx.fill(Path(bounds), with: .radialGradient(Gradient(colors: [AppColors.accent.opacity(0.16), .clear]),
                                                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                    startRadius: 0, endRadius: max(size.width, size.height) * 0.6))
        let gap: CGFloat = compact ? 6 : 10
        let inset: CGFloat = compact ? 10 : 18
        let aspect: CGFloat = compact ? 1 : 0.78
        let columns = CGFloat(script.columns), rows = CGFloat(script.rows)
        let byHeight = (size.height - 2 * inset - gap * (rows - 1)) / rows
        let byWidth = (size.width - 2 * inset - gap * (columns - 1)) / columns / aspect
        let h = max(1, min(byHeight, byWidth)), w = h * aspect
        let origin = CGPoint(x: (size.width - (w * columns + gap * (columns - 1))) / 2,
                             y: (size.height - (h * rows + gap * (rows - 1))) / 2)
        func frame(_ card: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(card % script.columns) * (w + gap),
                   y: origin.y + CGFloat(card / script.columns) * (h + gap), width: w, height: h)
        }
        let photos = art.photos.map { ctx.resolve($0) }
        var back = ctx.resolve(art.cardBack)
        back.shading = .color(.white.opacity(0.9))
        var check = ctx.resolve(art.check)
        check.shading = .color(.white)
        for card in script.faces.indices {
            var rect = frame(card)
            if let miss = script.mismatch, miss.cards.contains(card), t > miss.from, t < miss.to {
                rect.origin.x += CGFloat(sin((t - miss.from) * 46) * 2.5) // kurzes Schütteln: kein Paar
            }
            let turn = script.face(card, t)
            let up = turn >= 0.5
            let found = up && t >= script.matched[card]
            let pop = found ? bump((t - script.matched[card]) / 0.35) * 0.08 : 0
            var layer = ctx
            layer.translateBy(x: rect.midX, y: rect.midY)
            layer.scaleBy(x: CGFloat(max(0.02, abs(cos(turn * .pi))) * (1 + pop)), y: CGFloat(1 + pop))
            let local = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let shape = Path(roundedRect: local, cornerRadius: compact ? 6 : 10)
            if up {
                var photo = layer
                photo.clip(to: shape)
                if !photos.isEmpty { photo.drawImage(photos[script.faces[card] % photos.count], in: local, fill: true) }
                if found {
                    layer.stroke(shape, with: .color(AppColors.success), lineWidth: compact ? 1.5 : 2.5)
                    let r: CGFloat = compact ? 6 : 10
                    let badge = CGRect(x: local.maxX - 2 * r - 3, y: local.maxY - 2 * r - 3, width: 2 * r, height: 2 * r)
                    layer.fill(Path(ellipseIn: badge), with: .color(AppColors.success))
                    layer.drawImage(check, in: badge.insetBy(dx: r * 0.5, dy: r * 0.5), fill: false)
                }
            } else {
                layer.fill(shape, with: .color(AppColors.accentFill))
                layer.stroke(shape, with: .color(.white.opacity(0.18)), lineWidth: 1)
                layer.drawImage(back, in: square(.zero, w * 0.42), fill: false)
            }
        }
        if !still, let first = script.taps.first, let last = script.taps.last {
            // Ein Finger tippt Karte für Karte an und gleitet dazwischen zur nächsten.
            let points = script.taps.map { CGPoint(x: frame($0.card).midX, y: frame($0.card).midY) }
            var tip = points[0]
            if let current = script.taps.lastIndex(where: { $0.at <= t }) {
                tip = points[current]
                if current + 1 < points.count {
                    let from = script.taps[current].at, to = script.taps[current + 1].at
                    let p = CGFloat(smooth((t - from - 0.15) / max(0.1, to - from - 0.3)))
                    tip = CGPoint(x: points[current].x + (points[current + 1].x - points[current].x) * p,
                                  y: points[current].y + (points[current + 1].y - points[current].y) * p)
                }
            }
            var press = 0.0
            for (index, tap) in script.taps.enumerated() {
                press = max(press, bump((t - tap.at + 0.1) / 0.2))
                let ripple = (t - tap.at) / 0.35
                if ripple > 0, ripple < 1 {
                    ctx.stroke(Path(ellipseIn: square(points[index], CGFloat(12 + 36 * ripple))),
                               with: .color(.white.opacity(0.6 * (1 - ripple))), lineWidth: 2)
                }
            }
            let opacity = min(clamp01((t - first.at + 0.45) / 0.3), clamp01((last.at + 0.5 - t) / 0.3))
            drawHand(at: tip, side: min(32, w * 0.62), press: press, opacity: opacity, in: ctx)
        }
        celebrate(t, from: script.celebrate.from, to: script.celebrate.to, in: &ctx)
    }

    // MARK: Foto-Snake

    func snake(_ time: Double, _ ctx: inout GraphicsContext, character: PhotoSnakeCharacter) {
        let cell = size.height / 5
        let columns = max(5, Int(size.width / max(1, cell)))
        let track = SnakeTrack(columns: columns)
        let loop = track.length
        let speed = compact ? 2.4 : 3.2
        let period = 2 * loop / speed // zwei Runden, dann beginnt die Schlange wieder kurz
        let tr = still ? period * 0.62 : time.truncatingRemainder(dividingBy: period)
        let head = speed * tr
        let foods = (compact ? [0.3, 0.8, 1.45] : [0.22, 0.52, 0.8, 1.36, 1.64, 1.92]).map { ($0 * loop).rounded() }
        let eaten = foods.filter { $0 <= head }.count
        let offset = (size.width - CGFloat(columns) * cell) / 2
        func place(_ p: CGPoint) -> CGPoint { CGPoint(x: offset + (p.x + 0.5) * cell, y: (p.y + 0.5) * cell) }

        if art.background == nil { // Die Wiese liegt sonst als feste Ebene dahinter.
            ctx.fill(Path(bounds), with: .color(Color(red: 0.16, green: 0.36, blue: 0.2)))
        }
        var layer = ctx
        layer.opacity = still ? 1 : min(clamp01(tr / 0.35), clamp01((period - tr) / 0.35))

        // Futter: immer nur das nächste, wie im Spiel.
        if eaten < foods.count, !art.food.isEmpty {
            let since = eaten == 0 ? head : head - foods[eaten - 1]
            let pulse = still ? 1 : 1 + 0.05 * sin(time * 5)
            let side = cell * 1.05 * CGFloat(smooth(since / 0.8) * pulse)
            if side > 1 {
                layer.drawImage(ctx.resolve(art.food[eaten % art.food.count]), in: square(place(track.point(foods[eaten]).point), side),
                                fill: false)
            }
        }

        // Körper: runde Fotos mit dünnem Rahmen, leicht überlappend; jedes Futter hängt ein Foto an.
        let spacing = 0.8
        let count = 2 + eaten
        let centers = (0...count).map { place(track.point(head - Double($0) * spacing).point) }
        var line = Path()
        line.move(to: centers[count])
        for index in stride(from: count - 1, through: 0, by: -1) { line.addLine(to: centers[index]) }
        let side = cell * 0.92
        layer.stroke(line, with: .color(Self.bodyColor(character)),
                     style: StrokeStyle(lineWidth: side * 0.42, lineCap: .round, lineJoin: .round))
        layer.stroke(line, with: .color(.white.opacity(0.14)),
                     style: StrokeStyle(lineWidth: side * 0.1, lineCap: .round, lineJoin: .round))
        let photos = art.photos.map { ctx.resolve($0) }
        for index in stride(from: count, through: 1, by: -1) where !photos.isEmpty {
            var s = side
            if index == count, eaten > 0 { s *= CGFloat(smooth((head - foods[eaten - 1]) / 0.8)) }
            guard s > 1 else { continue }
            let rect = square(centers[index], s)
            var photo = layer
            photo.clip(to: Path(ellipseIn: rect))
            photo.drawImage(photos[(index - 1) % photos.count], in: rect, fill: true)
            layer.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(.white.opacity(0.9)),
                         lineWidth: compact ? 1 : 1.5)
        }

        // Kopf: Maul auf kurz vor und nach dem Fressen.
        let now = track.point(head)
        let ahead = eaten < foods.count ? foods[eaten] - head : .infinity
        let behind = eaten > 0 ? head - foods[eaten - 1] : .infinity
        if let image = (ahead < 0.9 || behind < 0.35) ? (art.eatingHead ?? art.head) : art.head {
            let degrees: Double = switch now.direction {
            case .up: 0
            case .right: 90
            case .down: 180
            case .left: 270
            }
            var head = layer
            let center = place(now.point)
            head.translateBy(x: center.x, y: center.y)
            head.rotate(by: .degrees(degrees))
            head.drawImage(ctx.resolve(image), in: square(.zero, cell * 1.25), fill: false)
        }
        if !still, eaten > 0, behind / speed < 0.3 {
            // Kurzes Funkeln, wo gefressen wurde.
            let p = behind / speed / 0.3
            var star = ctx.resolve(art.star)
            star.shading = .color(AppColors.accent)
            let center = place(track.point(foods[eaten - 1]).point)
            for index in 0..<4 {
                let angle = Double(index) * .pi / 2 + .pi / 4
                let radius = cell * CGFloat(0.3 + 0.5 * p)
                layer.drawImage(star, in: square(CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                                         y: center.y + CGFloat(sin(angle)) * radius),
                                                 cell * CGFloat(0.45 * (1 - p))), fill: false)
            }
        }

        // Finger: wischt kurz vor jeder Kurve in die neue Richtung – so wird gesteuert.
        guard !compact, !still else { return }
        let lap = (head / loop).rounded(.down) * loop
        var corner: (distance: Double, direction: PhotoSnakeGame.Direction)?
        for index in 1..<track.lengths.count where lap + track.lengths[index] > head {
            corner = (lap + track.lengths[index], track.point(track.lengths[index] + 0.01).direction)
            break
        }
        guard let corner else { return }
        let p = 1 - (corner.distance - head) / 1.3
        guard p > 0, p < 1 else { return }
        let anchor = place(track.pocket)
        let vector: CGVector = switch corner.direction {
        case .up: CGVector(dx: 0, dy: -1)
        case .down: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        }
        let travel = cell * 0.6 * CGFloat(smooth(p / 0.8))
        let tip = CGPoint(x: anchor.x + vector.dx * travel, y: anchor.y + vector.dy * travel)
        swipeTrail(from: anchor, to: tip, opacity: bump(p) * layer.opacity, in: ctx)
        drawHand(at: tip, side: cell * 0.95, press: 0, opacity: bump(p) * layer.opacity, in: ctx)
    }

    private static func bodyColor(_ character: PhotoSnakeCharacter) -> Color {
        switch character {
        case .snake: Color(red: 0.24, green: 0.56, blue: 0.14)
        case .dragon: Color(uiColor: .systemOrange)
        case .dino: Color(uiColor: .systemTeal)
        case .monster: Color(uiColor: .systemYellow)
        }
    }

    // MARK: Foto Blocks

    func blocks(_ time: Double, _ ctx: inout GraphicsContext) {
        let columns = 8, rows = 8
        let cycle = 2.4, finale = 2.2
        let t = still ? cycle * 2 + 0.8 : time.truncatingRemainder(dividingBy: cycle * 4 + finale)
        let inFinale = t >= cycle * 4
        let k = min(3, Int(t / cycle))
        let tc = inFinale ? cycle : t - Double(k) * cycle
        ctx.fill(Path(bounds), with: .color(compact ? AppColors.pauseStroke : AppColors.surface))
        let inset: CGFloat = compact ? 8 : 14
        let cell = max(1, (size.height - 2 * inset) / CGFloat(rows))
        let board = CGRect(x: (size.width - cell * CGFloat(columns)) / 2, y: (size.height - cell * CGFloat(rows)) / 2,
                           width: cell * CGFloat(columns), height: cell * CGFloat(rows))
        let boardShape = Path(roundedRect: board, cornerRadius: 4)
        ctx.fill(boardShape, with: .color(PhotoBlocksPalette.ink))

        // Foto wird wie im Spiel von oben freigelegt; ein Streifen ist schon frei, damit man sieht, worum es geht.
        let strips = inFinale ? 8 : 2 + 1.5 * Double(k) + 1.5 * smooth((tc - 1.25) / 0.35)
        let sinceFinale = t - cycle * 4
        // Heller als im Spiel (0,55), damit das Foto auch in der kleinen Szene erkennbar ist.
        let dim = inFinale ? 0.3 * (1 - smooth(sinceFinale / 0.4)) : 0.3
        let photoOpacity = inFinale ? 1 - smooth((sinceFinale - finale + 0.45) / 0.4) : (k == 0 && !still ? smooth(tc / 0.3) : 1)
        if photoOpacity > 0, let image = art.boardPhoto {
            var photo = ctx
            photo.clip(to: boardShape)
            photo.clip(to: Path(CGRect(x: board.minX, y: board.minY, width: board.width,
                                       height: board.height * CGFloat(strips) / CGFloat(rows))))
            photo.opacity = photoOpacity
            photo.drawImage(ctx.resolve(image), in: board, fill: true)
            photo.fill(Path(board), with: .color(.black.opacity(dim)))
        }
        if !inFinale {
            var grid = Path()
            for x in 1..<columns {
                grid.move(to: CGPoint(x: board.minX + CGFloat(x) * cell, y: board.minY))
                grid.addLine(to: CGPoint(x: board.minX + CGFloat(x) * cell, y: board.maxY))
            }
            for y in 1..<rows {
                grid.move(to: CGPoint(x: board.minX, y: board.minY + CGFloat(y) * cell))
                grid.addLine(to: CGPoint(x: board.maxX, y: board.minY + CGFloat(y) * cell))
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
        }
        ctx.stroke(boardShape, with: .color(.white.opacity(0.2)), lineWidth: 1)

        guard !inFinale else {
            celebrate(t, from: cycle * 4 + 0.2, to: cycle * 4 + finale - 0.3, in: &ctx)
            return
        }
        func cellRect(_ x: Double, _ y: Double) -> CGRect {
            CGRect(x: board.minX + CGFloat(x) * cell + 1, y: board.minY + CGFloat(y) * cell + 1, width: cell - 2, height: cell - 2)
        }
        let shapes = PhotoBlocksShape.playableShapes
        let gaps = [5, 1, 5, 1]
        let gap = gaps[k]
        let bottom = rows - 2
        let clear = clamp01((tc - 1.02) / 0.3)
        var layer = ctx
        layer.clip(to: boardShape)
        layer.opacity = 1 - clear
        if tc < 1.32 {
            // Zwei fast volle Reihen kommen von unten herein; die Lücke ist zwei Felder breit.
            let rise = 2 * (1 - smooth(tc / 0.3))
            for y in bottom..<rows {
                for x in 0..<columns where x != gap && x != gap + 1 {
                    drawBlock(cellRect(Double(x), Double(y) + rise),
                              color: PhotoBlocksPalette.color(shapes[(x * 3 + y * 5 + k) % shapes.count]), in: layer)
                }
            }
        }
        let direction = gap > 3 ? 1.0 : -1.0
        if tc >= 0.1, tc < 1.32 {
            let steps = tc < 0.45 ? 0 : Double(min(2, Int((tc - 0.45) / 0.12) + 1))
            let x = 3 + direction * steps
            let y = tc < 0.9 ? -1 + ((tc - 0.1) / 0.18).rounded(.down) : 3 + Double(bottom - 3) * smooth((tc - 0.9) / 0.1)
            if tc < 0.9 {
                // Schatten zeigt, wo der Stein landet.
                for dx in 0...1 {
                    for dy in bottom..<rows {
                        let ghost = Path(roundedRect: cellRect(x + Double(dx), Double(dy)), cornerRadius: max(2, cell * 0.19))
                        layer.stroke(ghost, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
            }
            let color = PhotoBlocksPalette.color(shapes[(k * 2 + 1) % shapes.count])
            for dx in 0...1 { for dy in 0...1 { drawBlock(cellRect(x + Double(dx), y + Double(dy)), color: color, in: layer) } }
        }
        if clear > 0, clear < 1 {
            let band = CGRect(x: board.minX, y: board.minY + CGFloat(bottom) * cell, width: board.width, height: 2 * cell)
            ctx.fill(Path(band), with: .color(PhotoBlocksPalette.accent.opacity((1 - clear) * 0.5)))
        }
        guard !compact else { return }

        // Links: der nächste Stein, wie im Spiel.
        let box = CGRect(x: board.minX - min(70, board.minX - 8), y: board.minY + 4, width: min(56, board.minX - 16), height: 56)
        if box.width >= 36 {
            ctx.fill(Path(roundedRect: box, cornerRadius: 12), with: .color(AppColors.control.opacity(0.6)))
            let next = PhotoBlocksPalette.color(shapes[(((k + 1) % 4) * 2 + 1) % shapes.count])
            let unit = min(14, box.width / 3.2)
            for dx in 0...1 {
                for dy in 0...1 {
                    drawBlock(CGRect(x: box.midX - unit + CGFloat(dx) * unit, y: box.midY - unit + CGFloat(dy) * unit,
                                     width: unit, height: unit).insetBy(dx: 0.5, dy: 0.5), color: next, in: ctx)
                }
            }
        }
        guard !still else { return }
        // Rechts: Finger wischt seitlich (bewegen), dann nach unten (absetzen).
        let anchor = CGPoint(x: board.maxX + max(34, (size.width - board.maxX) * 0.32), y: board.midY - cell)
        let side = (tc - 0.3) / 0.45
        let drop = (tc - 0.78) / 0.27
        if side > 0, side < 1 {
            let tip = CGPoint(x: anchor.x + CGFloat(direction) * 28 * CGFloat(smooth(side / 0.7)), y: anchor.y)
            swipeTrail(from: anchor, to: tip, opacity: bump(side), in: ctx)
            drawHand(at: tip, side: 30, press: 0, opacity: bump(side), in: ctx)
        } else if drop > 0, drop < 1 {
            let tip = CGPoint(x: anchor.x, y: anchor.y + 30 * CGFloat(smooth(drop / 0.6)))
            swipeTrail(from: anchor, to: tip, opacity: bump(drop), in: ctx)
            drawHand(at: tip, side: 30, press: 0, opacity: bump(drop), in: ctx)
        }
    }

    private func drawBlock(_ rect: CGRect, color: Color, in context: GraphicsContext) {
        let path = Path(roundedRect: rect, cornerRadius: max(2, rect.width * 0.2))
        context.fill(path, with: .linearGradient(Gradient(colors: [color, color.opacity(0.76)]), startPoint: rect.origin,
                                                 endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: compact ? 0.5 : 0.9)
        if !compact, rect.width > 10 {
            let glint = CGRect(x: rect.minX + 3, y: rect.minY + 2.5, width: rect.width - 6, height: 1.5)
            context.fill(Path(roundedRect: glint, cornerRadius: 0.75), with: .color(.white.opacity(0.32)))
        }
    }

    // MARK: Gemeinsam

    private func drawHand(at tip: CGPoint, side: CGFloat, press: Double, opacity: Double, in context: GraphicsContext) {
        guard opacity > 0.01 else { return }
        var layer = context
        layer.opacity = opacity
        layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2))
        var hand = layer.resolve(art.hand)
        hand.shading = .color(.white)
        let s = side * CGFloat(1 - 0.12 * press)
        // Die Fingerkuppe liegt oben links im Symbol.
        layer.drawImage(hand, in: CGRect(x: tip.x - s * 0.16, y: tip.y - s * 0.06, width: s, height: s), fill: false)
    }

    private func swipeTrail(from start: CGPoint, to end: CGPoint, opacity: Double, in context: GraphicsContext) {
        guard opacity > 0.01 else { return }
        var trail = Path()
        trail.move(to: start)
        trail.addLine(to: end)
        context.stroke(trail, with: .color(.white.opacity(0.5 * opacity)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    /// Funkeln, wenn alles gefunden bzw. das Foto ganz freigelegt ist.
    private func celebrate(_ t: Double, from: Double, to: Double, in ctx: inout GraphicsContext) {
        guard t > from, t < to else { return }
        let p = (t - from) / (to - from)
        var gold = ctx.resolve(art.star)
        gold.shading = .color(AppColors.accent)
        var white = ctx.resolve(art.star)
        white.shading = .color(.white)
        let spots: [(x: CGFloat, y: CGFloat, delay: Double)] = [
            (0.08, 0.2, 0), (0.92, 0.18, 0.15), (0.5, 0.08, 0.3), (0.14, 0.84, 0.1),
            (0.86, 0.86, 0.25), (0.3, 0.5, 0.4), (0.72, 0.46, 0.05)
        ]
        for (index, spot) in spots.enumerated() {
            let s = CGFloat(bump((p - spot.delay) / 0.6)) * (compact ? 12 : 22)
            guard s > 0.5 else { continue }
            ctx.drawImage(index.isMultiple(of: 2) ? gold : white,
                          in: square(CGPoint(x: spot.x * size.width, y: spot.y * size.height), s), fill: false)
        }
    }
}
