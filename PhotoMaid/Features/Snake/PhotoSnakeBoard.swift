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
    private let bodyLine = SKShapeNode()
    private let highlight = SKShapeNode()
    private let head = SKSpriteNode()
    private var headCopies: [SKSpriteNode] = []
    private let tail = SKSpriteNode()
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
    private var textureSignature = ""
    private var fieldSize = CGSize.zero
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
        boundary.fillColor = UIColor(red: 0.07, green: 0.21, blue: 0.10, alpha: 0.24)
        boundary.lineWidth = 1; boundary.zPosition = 0; field.addChild(boundary)
        for line in [bodyLine, highlight] {
            line.lineCap = .round; line.lineJoin = .round; line.isAntialiased = true
            line.fillColor = .clear; field.addChild(line)
        }
        bodyLine.zPosition = 1; highlight.zPosition = 2
        tail.texture = SnakeArt.texture("body_tail"); tail.zPosition = 2; field.addChild(tail)
        head.zPosition = 6; field.addChild(head)
        food.zPosition = 3; field.addChild(food)
        sparkle.zPosition = 7; sparkle.isHidden = true; field.addChild(sparkle)
        refreshTextures()
    }
    required init?(coder aDecoder: NSCoder) { return nil }
    func resetClock() { previousTime = nil }
    func releasePhotoTextures() {
        guard !textureSignature.isEmpty else { return }
        for node in segments + wraps { node.texture = SnakeArt.texture("segment_placeholder") }
        composer.removeAll(); textureSignature = ""
        let retained = max(0, (model.game?.body.count ?? 1) - 1)
        for node in segments.dropFirst(retained) { node.removeFromParent() }
        segments = Array(segments.prefix(retained))
    }

    func refreshTextures() {
        // This runs only on SwiftUI invalidation, never in update(_:). Composition is keyed by photo ID.
        let ids = model.pictureIDs
        let signature = "\(model.roundID)-\(model.gallery.revision)-\(model.usesSavedPhotos)-\(ids.joined(separator: ","))"
        guard signature != textureSignature else { return }
        textureSignature = signature
        composer.synchronize(ids: ids, images: model.visibleImages)
        for (index, node) in segments.enumerated() { node.texture = texture(at: index + 1) }
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
            refreshTextures()
        }
        if facing != model.facingRevision, serial == 0, model.stepSerial == 0 {
            facing = model.facingRevision
            motion = PhotoSnakeMotion(game: game)
            angle = rotation(game.direction); angleFrom = angle; angleTo = angle
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
        angle = reduceMotion ? angleTo : PhotoSnakeHeadAnimation.shortestAngle(from: angleFrom, to: angleTo, fraction: turnAge / 0.13)
        render()
    }

    private func beginStep() {
        guard let game = model.game else { return }
        // Step-mode input can arrive between display frames. Rebase on its authoritative origin if needed.
        if model.stepSerial != serial + 1, let origin = model.stepOrigin { motion = PhotoSnakeMotion(game: origin) }
        if serial == 0, let origin = model.stepOrigin { motion = PhotoSnakeMotion(game: origin) }
        motion?.advance(to: game, event: model.lastEvent)
        serial = model.stepSerial; progress = 0
        angleFrom = angle; angleTo = rotation(game.direction); turnAge = 0
    }

    private var cell: CGFloat {
        guard let game = model.game else { return 1 }
        return min(size.width / CGFloat(game.width), size.height / CGFloat(game.height))
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
        let c = cell
        field.position = CGPoint(x: (size.width - CGFloat(game.width) * c) / 2,
                                 y: (size.height - CGFloat(game.height) * c) / 2)
        let nextFieldSize = CGSize(width: CGFloat(game.width) * c, height: CGFloat(game.height) * c)
        if nextFieldSize != fieldSize {
            fieldSize = nextFieldSize
            boundary.path = CGPath(roundedRect: CGRect(origin: .zero, size: fieldSize).insetBy(dx: 0.5, dy: 0.5),
                                   cornerWidth: 8, cornerHeight: 8, transform: nil)
        }
        let points = motion.points(progress: progress)
        let path = CGMutablePath()
        for line in motion.lines(progress: progress) { path.move(to: position(line.a)); path.addLine(to: position(line.b)) }
        bodyLine.path = path; highlight.path = path
        bodyLine.strokeColor = Self.colors[model.preferences.character] ?? .systemGreen
        bodyLine.lineWidth = c * 0.69
        highlight.strokeColor = .white.withAlphaComponent(0.12); highlight.lineWidth = c * 0.34
        var wrapCount = 0
        for (index, point) in points.enumerated().dropFirst() {
            let node = sprite(&segments, at: index - 1, z: 4)
            node.isHidden = false; node.texture = texture(at: index)
            // The actual circle occupies 160/256 of the transparent sprite.
            let growing = (model.lastEvent == .collected || model.lastEvent == .won) && progress < 1 && index == points.count - 1
            let scale = growing && !reduceMotion ? CGFloat(progress) : 1
            node.zPosition = growing ? 3.9 : 4
            node.size = CGSize(width: c * 1.28 * scale, height: c * 1.28 * scale)
            node.position = position(motion.wrapped(point))
            for offset in edgeOffsets(node.position, radius: c * 0.45, game: game) {
                let copy = sprite(&wraps, at: wrapCount, z: 4); wrapCount += 1
                copy.isHidden = false; copy.texture = node.texture; copy.size = node.size; copy.zPosition = node.zPosition
                copy.position = CGPoint(x: node.position.x + offset.x, y: node.position.y + offset.y)
            }
        }
        for node in segments.dropFirst(max(0, points.count - 1)) { node.isHidden = true }
        for node in wraps.dropFirst(wrapCount) { node.isHidden = true }
        if let last = points.last {
            tail.position = position(motion.wrapped(last)); tail.size = CGSize(width: c * 1.25, height: c * 1.25)
            if points.count > 1 {
                let before = points[points.count - 2]
                tail.zRotation = CGFloat(atan2(last.y - before.y, before.x - last.x))
            }
        }
        let frame = PhotoSnakeHeadAnimation.frame(character: model.preferences.character, time: animationTime,
            eating: eatingAt.map { animationTime - $0 }, collision: collisionAt.map { animationTime - $0 },
            sleeping: !model.running && model.started && game.status == .playing,
            danger: danger(game), lookingLeft: turnAge < 0.12 ? (game.direction == .left || game.direction == .up) : nil,
            reduceMotion: reduceMotion)
        head.texture = SnakeArt.texture(frame.texture)
        head.size = CGSize(width: c * 1.55, height: c * 1.55)
        head.zRotation = CGFloat(angle); head.setScale(frame.scale)
        if let first = points.first { head.position = position(motion.wrapped(first)) }
        let headOffsets = edgeOffsets(head.position, radius: c * 0.53, game: game)
        for (index, offset) in headOffsets.enumerated() {
            let copy = sprite(&headCopies, at: index, z: 6)
            copy.isHidden = false; copy.texture = head.texture; copy.size = head.size
            copy.zRotation = head.zRotation; copy.setScale(frame.scale)
            copy.position = CGPoint(x: head.position.x + offset.x, y: head.position.y + offset.y)
        }
        for copy in headCopies.dropFirst(headOffsets.count) { copy.isHidden = true }
        food.isHidden = pendingFood == nil
        if let pendingFood {
            food.position = position(pendingFood)
            food.texture = SnakeArt.texture(model.preferences.food.texture(score: cachedFoodScore))
            let pulse = reduceMotion ? 1 : 1 + 0.035 * sin(animationTime * 3)
            food.size = CGSize(width: c * 1.1 * pulse, height: c * 1.1 * pulse)
        }
        if let eatingAt, animationTime - eatingAt < 0.24, !reduceMotion {
            let age = max(0, animationTime - eatingAt)
            let index = min(4, Int(age / 0.06) + 1)
            sparkle.texture = SnakeArt.texture(String(format: "fx_collect_%02d", index))
            sparkle.size = CGSize(width: c * 2, height: c * 2); sparkle.isHidden = false
        } else { sparkle.isHidden = true }
    }
    private func edgeOffsets(_ p: CGPoint, radius: CGFloat, game: PhotoSnakeGame) -> [CGPoint] {
        guard game.mode == .relaxed else { return [] }
        let w = CGFloat(game.width) * cell, h = CGFloat(game.height) * cell
        var offsets: [CGPoint] = []
        if p.x < radius { offsets.append(CGPoint(x: w, y: 0)) }
        if p.x > w - radius { offsets.append(CGPoint(x: -w, y: 0)) }
        if p.y < radius { offsets.append(CGPoint(x: 0, y: h)) }
        if p.y > h - radius { offsets.append(CGPoint(x: 0, y: -h)) }
        // At a corner the sprite can cross two edges at once; include the diagonal copy too.
        if offsets.count == 2 { offsets.append(CGPoint(x: offsets[0].x + offsets[1].x, y: offsets[0].y + offsets[1].y)) }
        return offsets
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
