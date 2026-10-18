import PhotoMaidCore
import SpriteKit
import SwiftUI
import UIKit

/// UIKit owns a synchronous SpriteKit view. Only the scene advances the existing discrete model.
struct PhotoSnakeBoard: UIViewRepresentable {
    let model: PhotoSnakeModel
    let active: Bool
    let reduceMotion: Bool

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.preferredFramesPerSecond = 60
        view.isAsynchronous = false
        view.ignoresSiblingOrder = true
        view.allowsTransparency = true
        view.clipsToBounds = true
        view.backgroundColor = .clear
        let scene = PhotoSnakeScene(model: model)
        scene.scaleMode = .resizeFill
        scene.reduceMotion = reduceMotion
        view.presentScene(scene)
        return view
    }
    func updateUIView(_ view: SKView, context: Context) {
        guard let scene = view.scene as? PhotoSnakeScene else { return }
        scene.reduceMotion = reduceMotion
        if model.memorySuspended { scene.releasePhotoTextures() }
        else { scene.refreshTextures() }
        view.isPaused = !active || model.memorySuspended
        if view.isPaused { scene.resetClock() }
    }
    static func dismantleUIView(_ view: SKView, coordinator: Void) {
        view.isPaused = true; view.presentScene(nil)
    }
}

@MainActor
final class PhotoSnakeScene: SKScene {
    private static let colors: [PhotoSnakeCharacter: UIColor] = [
        .snake: UIColor(red: 0.24, green: 0.56, blue: 0.14, alpha: 1),
        .dragon: .systemOrange, .dino: .systemTeal, .monster: .systemYellow
    ]
    private let model: PhotoSnakeModel
    private let composer = SnakePhotoTextureComposer()
    private let field = SKNode()
    private let boundary = SKShapeNode()
    private let gridLines = SKShapeNode()
    private let bodyLine = SKShapeNode()
    private let highlight = SKShapeNode()
    private let head = SKSpriteNode()
    private let previousHead = SKSpriteNode()
    private var headCopies: [SKSpriteNode] = []
    private var previousHeadCopies: [SKSpriteNode] = []
    private let food = SKSpriteNode()
    private let sparkle = SKSpriteNode()
    private var segments: [SKSpriteNode] = []
    private var wraps: [SKSpriteNode] = []
    private var round: UUID?
    private var serial = 0
    private var facing = -1
    private var motion: PhotoSnakeMotion?
    private var progress = 1.0
    private var previousTime: Double?
    private var animationTime = 0.0
    private var eatingAt: Double?
    private var collisionAt: Double?
    private var turnAge = 1.0
    private var angleFrom = 0.0
    private var angleTo = 0.0
    private var angle = 0.0
    private var fromDirection = PhotoSnakeGame.Direction.right
    private var toDirection = PhotoSnakeGame.Direction.right
    private var textureSignature = ""
    private var fieldSize = CGSize.zero
    private var gridColumns = 0
    private var gridRows = 0
    private var pendingFood: PhotoSnakeGame.Cell?
    private var cachedFoodScore = 0
    var reduceMotion = false

    init(model: PhotoSnakeModel) {
        self.model = model
        super.init(size: CGSize(width: 432, height: 576))
        SnakeArt.warmTextures()
        backgroundColor = .clear
        addChild(field)
        boundary.strokeColor = .white.withAlphaComponent(0.24)
        boundary.fillColor = UIColor(red: 0.045, green: 0.16, blue: 0.09, alpha: 0.96)
        boundary.lineWidth = 1; boundary.zPosition = 0; field.addChild(boundary)
        gridLines.strokeColor = .white.withAlphaComponent(0.06)
        gridLines.lineWidth = 1; gridLines.zPosition = 0.5; field.addChild(gridLines)
        for line in [bodyLine, highlight] {
            line.lineCap = .round; line.lineJoin = .round; line.isAntialiased = true
            line.fillColor = .clear; field.addChild(line)
        }
        bodyLine.zPosition = 1; highlight.zPosition = 2
        previousHead.zPosition = 5.9; field.addChild(previousHead)
        head.zPosition = 6; field.addChild(head)
        food.zPosition = 3; field.addChild(food)
        sparkle.zPosition = 7; sparkle.isHidden = true; field.addChild(sparkle)
        refreshTextures()
    }
    required init?(coder aDecoder: NSCoder) { return nil }
    func resetClock() { previousTime = nil }
    func releasePhotoTextures() {
        guard !textureSignature.isEmpty else { return }
        for node in segments + wraps { node.texture = composer.texture(nil) }
        composer.removeAll(); textureSignature = ""
        let retained = max(0, (model.game?.body.count ?? 1) - 1)
        for node in segments.dropFirst(retained) { node.removeFromParent() }
        segments = Array(segments.prefix(retained))
    }

    func refreshTextures() {
        // SwiftUI invalidation and a new round synchronize once. Normal frame updates only look up cached textures.
        let ids = model.pictureIDs
        let signature = "\(model.roundID)-\(model.gallery.revision)-\(model.usesSavedPhotos)-\(ids.joined(separator: ","))"
        textureSignature = signature
        // A reloaded UIImage may replace the same photo ID. The composer checks weak image identity
        // as well as the ID, so it neither serves an old photo nor recomposes unchanged thumbnails.
        composer.synchronize(ids: ids, images: model.visibleImages)
        for (index, node) in segments.enumerated() {
            let image = texture(at: index + 1)
            if node.texture !== image { node.texture = image }
        }
    }

    nonisolated override func update(_ currentTime: TimeInterval) {
        // isAsynchronous=false keeps SpriteKit's UIKit frame callbacks on the main thread.
        MainActor.assumeIsolated { frame(currentTime) }
    }

    private func frame(_ time: Double) {
        guard let game = model.game else { return }
        let elapsed = previousTime.map { max(0, time - $0) } ?? 0
        previousTime = time
        // No bulk catch-up after interruptions; pause instead of advancing unseen game steps.
        if elapsed > 0.3 { model.pause(); return }
        let dt = min(elapsed, 1.0 / 20)
        animationTime += dt
        if round != model.roundID {
            round = model.roundID; serial = 0; facing = -1
            motion = PhotoSnakeMotion(game: model.stepOrigin ?? game)
            progress = 1; collisionAt = nil; eatingAt = nil
            cachedFoodScore = (model.stepOrigin ?? game).score
            pendingFood = (model.stepOrigin ?? game).food
            angle = rotation((model.stepOrigin ?? game).direction); angleFrom = angle; angleTo = angle
            fromDirection = (model.stepOrigin ?? game).direction; toDirection = fromDirection
            refreshTextures()
        }
        if facing != model.facingRevision, serial == 0, model.stepSerial == 0 {
            facing = model.facingRevision
            motion = PhotoSnakeMotion(game: game)
            angle = rotation(game.direction); angleFrom = angle; angleTo = angle
            fromDirection = game.direction; toDirection = game.direction
            pendingFood = game.food
        }
        if model.stepSerial != serial { beginStep() }
        var carry = 0.0
        if progress < 1, model.running || model.game?.status != .playing {
            let advanced = progress + dt / model.speed.interval
            carry = max(0, advanced - 1)
            progress = min(1, advanced)
            if progress >= 1 {
                if model.lastEvent == .collected || model.lastEvent == .won {
                    eatingAt = animationTime
                    model.audio.play(.collect, enabled: model.preferences.sound)
                    if model.newBest { model.audio.play(.new_record, enabled: model.preferences.sound) }
                    if model.preferences.haptics { Haptics.commit() }
                    if let collected = pendingFood { sparkle.position = position(collected) }
                }
                if model.lastEvent == .lost {
                    collisionAt = animationTime
                    model.audio.play(.game_over, enabled: model.preferences.sound)
                    if model.preferences.haptics { Haptics.warning() }
                }
                pendingFood = model.game?.food; cachedFoodScore = model.game?.score ?? 0
                model.finishPresentation()
            }
        }
        if progress >= 1, model.running, !model.stepMode {
            model.tick()
            if model.stepSerial != serial { beginStep(); progress = min(1, carry) }
        }
        turnAge += dt
        let turn = min(1, max(0, turnAge / 0.13))
        let eased = turn * turn * (3 - 2 * turn)
        angle = reduceMotion ? angleTo : PhotoSnakeHeadAnimation.shortestAngle(from: angleFrom, to: angleTo, fraction: eased)
        render()
    }

    private func beginStep() {
        guard let game = model.game else { return }
        // Step-mode input can arrive between display frames. Rebase on its authoritative origin if needed.
        if model.stepSerial != serial + 1, let origin = model.stepOrigin { motion = PhotoSnakeMotion(game: origin) }
        if serial == 0, let origin = model.stepOrigin { motion = PhotoSnakeMotion(game: origin) }
        motion?.advance(to: game, event: model.lastEvent)
        serial = model.stepSerial; progress = 0
        if toDirection != game.direction {
            fromDirection = toDirection; toDirection = game.direction
            angleFrom = angle; angleTo = rotation(game.direction); turnAge = 0
        }
    }

    private var cell: CGFloat {
        guard let game = model.game else { return 1 }
        return CGFloat(PhotoSnakeLayout(width: Double(size.width), height: Double(size.height),
                                       columns: game.width, rows: game.height).pitch)
    }
    private func position(_ p: PhotoSnakeMotion.Point) -> CGPoint {
        guard let game = model.game else { return .zero }
        return CGPoint(x: p.x * Double(cell), y: (Double(game.height) - p.y) * Double(cell))
    }
    private func position(_ p: PhotoSnakeGame.Cell) -> CGPoint { position(.init(Double(p.x) + 0.5, Double(p.y) + 0.5)) }
    private func texture(at index: Int) -> SKTexture {
        guard !model.strip.isEmpty else { return composer.texture(nil) }
        return composer.texture(model.strip[max(0, index - 1) % model.strip.count])
    }
    private func sprite(_ pool: inout [SKSpriteNode], at index: Int, z: CGFloat) -> SKSpriteNode {
        while pool.count <= index {
            let node = SKSpriteNode(); node.zPosition = z; field.addChild(node); pool.append(node)
        }
        return pool[index]
    }
    private func render() {
        guard let game = model.game, let motion else { return }
        let layout = PhotoSnakeLayout(width: Double(size.width), height: Double(size.height), columns: game.width, rows: game.height)
        let c = CGFloat(layout.pitch), photoSide = CGFloat(layout.photoSide)
        field.position = CGPoint(x: (size.width - CGFloat(game.width) * c) / 2,
                                 y: (size.height - CGFloat(game.height) * c) / 2)
        let nextFieldSize = CGSize(width: CGFloat(game.width) * c, height: CGFloat(game.height) * c)
        if nextFieldSize != fieldSize || gridColumns != game.width || gridRows != game.height {
            fieldSize = nextFieldSize
            gridColumns = game.width; gridRows = game.height
            boundary.path = CGPath(roundedRect: CGRect(origin: .zero, size: fieldSize).insetBy(dx: 0.5, dy: 0.5),
                                   cornerWidth: 8, cornerHeight: 8, transform: nil)
            let grid = CGMutablePath()
            for x in 1..<game.width {
                grid.move(to: CGPoint(x: CGFloat(x) * c, y: 0)); grid.addLine(to: CGPoint(x: CGFloat(x) * c, y: fieldSize.height))
            }
            for y in 1..<game.height {
                grid.move(to: CGPoint(x: 0, y: CGFloat(y) * c)); grid.addLine(to: CGPoint(x: fieldSize.width, y: CGFloat(y) * c))
            }
            gridLines.path = grid
        }
        let points = motion.points(progress: progress)
        let path = CGMutablePath()
        for line in motion.lines(progress: progress, samples: points) { path.move(to: position(line.a)); path.addLine(to: position(line.b)) }
        bodyLine.path = path; highlight.path = path
        bodyLine.strokeColor = Self.colors[model.preferences.character] ?? .systemGreen
        bodyLine.lineWidth = photoSide * 0.42
        highlight.strokeColor = .white.withAlphaComponent(0.14); highlight.lineWidth = photoSide * 0.10
        var wrapCount = 0
        for (index, point) in points.enumerated().dropFirst() {
            let node = sprite(&segments, at: index - 1, z: 4)
            let image = texture(at: index)
            if node.texture !== image { node.texture = image }
            let growing = (model.lastEvent == .collected || model.lastEvent == .won) && progress < 1 && index == points.count - 1
            let previous = points[index - 1]
            let distance = hypot(point.x - previous.x, point.y - previous.y) * layout.pitch
            let side = growing ? CGFloat(layout.growingSide(progress: progress, separation: distance)) : photoSide
            node.isHidden = side <= 0
            node.zPosition = CGFloat(PhotoSnakeLayout.segmentDepth(index: index))
            node.size = CGSize(width: side, height: side)
            let placements = placements(for: point, halfExtent: side / 2, game: game, motion: motion)
            node.position = placements[0].point; node.alpha = placements[0].alpha
            for placement in placements.dropFirst() where side > 0 {
                let copy = sprite(&wraps, at: wrapCount, z: 4); wrapCount += 1
                copy.isHidden = false; copy.texture = node.texture; copy.size = node.size; copy.zPosition = node.zPosition
                copy.position = placement.point; copy.alpha = placement.alpha
            }
        }
        for node in segments.dropFirst(max(0, points.count - 1)) { node.isHidden = true }
        for node in wraps.dropFirst(wrapCount) { node.isHidden = true }
        let frame = PhotoSnakeHeadAnimation.frame(character: model.preferences.character, time: animationTime,
            eating: eatingAt.map { animationTime - $0 }, collision: collisionAt.map { animationTime - $0 },
            sleeping: !model.running && model.started && game.status == .playing,
            danger: danger(game), lookingLeft: turnAge < 0.12 ? (game.direction == .left || game.direction == .up) : nil,
            reduceMotion: reduceMotion)
        if let first = points.first { renderHead(at: first, frame: frame, side: CGFloat(layout.headSide), game: game, motion: motion) }
        food.isHidden = pendingFood == nil
        if let pendingFood {
            food.position = position(pendingFood)
            food.texture = SnakeArt.texture(model.preferences.food.texture(score: cachedFoodScore))
            let pulse = reduceMotion ? 1 : 1 + 0.035 * sin(animationTime * 3)
            food.size = CGSize(width: photoSide * 1.15 * pulse, height: photoSide * 1.15 * pulse)
        }
        if let eatingAt, animationTime - eatingAt < 0.24, !reduceMotion {
            let age = max(0, animationTime - eatingAt)
            let index = min(4, Int(age / 0.06) + 1)
            sparkle.texture = SnakeArt.texture(String(format: "fx_collect_%02d", index))
            sparkle.size = CGSize(width: photoSide * 1.6, height: photoSide * 1.6); sparkle.isHidden = false
        } else { sparkle.isHidden = true }
    }
    private func placements(for p: PhotoSnakeMotion.Point, halfExtent: CGFloat, game: PhotoSnakeGame,
                            motion: PhotoSnakeMotion) -> [(point: CGPoint, alpha: CGFloat)] {
        let pixel = position(motion.wrapped(p))
        return PhotoSnakeLayout.placements(.init(Double(pixel.x), Double(pixel.y)),
            width: Double(fieldSize.width), height: Double(fieldSize.height),
            gutter: PhotoSnakeLayout(width: Double(size.width), height: Double(size.height),
                                     columns: game.width, rows: game.height).gutter,
            halfExtent: Double(halfExtent), wraps: game.mode == .relaxed)
            .map { (CGPoint(x: $0.centre.x, y: $0.centre.y), CGFloat($0.alpha)) }
    }

    private func renderHead(at point: PhotoSnakeMotion.Point, frame: PhotoSnakeHeadAnimation.Frame,
                            side: CGFloat, game: PhotoSnakeGame, motion: PhotoSnakeMotion) {
        let currentTexture = SnakeArt.headTexture(character: model.preferences.character, pose: frame.pose, direction: toDirection)
        let previousTexture = SnakeArt.headTexture(character: model.preferences.character, pose: frame.pose, direction: fromDirection)
        let blend = reduceMotion || fromDirection == toDirection ? 1 : min(1, max(0, turnAge / 0.13))
        let relativeAngle = angle - rotation(toDirection)
        let halfExtent = Double(side) * frame.scale / 2 * (abs(cos(relativeAngle)) + abs(sin(relativeAngle)))
        let locations = placements(for: point, halfExtent: CGFloat(halfExtent), game: game, motion: motion)
        func draw(_ node: SKSpriteNode, image: SKTexture, direction: PhotoSnakeGame.Direction,
                  location: (point: CGPoint, alpha: CGFloat), opacity: Double) {
            node.isHidden = opacity <= 0
            if node.texture !== image { node.texture = image }
            node.size = CGSize(width: side, height: side); node.setScale(frame.scale)
            // Four independently drawn overhead views. Counter-rotate their base direction while
            // interpolating; crossfade the eye highlights so switching views never pops.
            node.zRotation = CGFloat(angle - self.rotation(direction))
            node.position = location.point; node.alpha = location.alpha * CGFloat(opacity)
        }
        draw(head, image: currentTexture, direction: toDirection, location: locations[0], opacity: blend)
        draw(previousHead, image: previousTexture, direction: fromDirection, location: locations[0], opacity: blend < 1 ? 1 : 0)
        for (index, location) in locations.dropFirst().enumerated() {
            draw(sprite(&headCopies, at: index, z: 6), image: currentTexture, direction: toDirection, location: location, opacity: blend)
            draw(sprite(&previousHeadCopies, at: index, z: 5.9), image: previousTexture, direction: fromDirection, location: location, opacity: blend < 1 ? 1 : 0)
        }
        for node in headCopies.dropFirst(locations.count - 1) { node.isHidden = true }
        for node in previousHeadCopies.dropFirst(locations.count - 1) { node.isHidden = true }
    }
    private func danger(_ game: PhotoSnakeGame) -> Bool {
        guard game.status == .playing, let head = game.body.first else { return false }
        let d = game.nextDirection
        let x = head.x + (d == .left ? -1 : d == .right ? 1 : 0)
        let y = head.y + (d == .up ? -1 : d == .down ? 1 : 0)
        if game.mode == .classic && (x < 0 || y < 0 || x >= game.width || y >= game.height) { return true }
        let next = PhotoSnakeGame.Cell((x + game.width) % game.width, (y + game.height) % game.height)
        return game.body.dropLast().contains(next)
    }
    private func rotation(_ direction: PhotoSnakeGame.Direction) -> Double {
        switch direction { case .right: 0; case .up: .pi / 2; case .left: .pi; case .down: -.pi / 2 }
    }
}
