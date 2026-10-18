import PhotoMaidCore
import SpriteKit
import UIKit

@MainActor
enum SnakeArt {
    static let atlases = ["SnakeHeads", "SnakeBody", "SnakeFood", "SnakeUI", "SnakeTopDown"].map(SKTextureAtlas.init(named:))
    private static var textures: [String: SKTexture] = [:]
    private static var images: [String: UIImage] = [:]
    static func texture(_ name: String) -> SKTexture {
        if let cached = textures[name] { return cached }
        let atlas = atlases.first { $0.textureNames.contains(name) || $0.textureNames.contains(name + ".png") }
        let texture = atlas?.textureNamed(name) ?? SKTexture(imageNamed: name)
        texture.filteringMode = .linear; textures[name] = texture
        return texture
    }
    static func image(_ name: String) -> UIImage {
        if let image = images[name] { return image }
        let image = UIImage(cgImage: texture(name).cgImage())
        images[name] = image; return image
    }
    static func warmTextures() {
        // Original kit heads remain available, but the active renderer uses the overhead atlas.
        for atlas in atlases.dropFirst() { for name in atlas.textureNames { _ = texture(name.replacingOccurrences(of: ".png", with: "")) } }
    }
    static func preload() async {
        await SKTextureAtlas.preloadTextureAtlases(Array(atlases.dropFirst()))
        warmTextures()
    }
    static func headTexture(character: PhotoSnakeCharacter, pose: PhotoSnakeHeadAnimation.Pose,
                            direction: PhotoSnakeGame.Direction) -> SKTexture {
        texture(PhotoSnakeHeadAnimation.overheadTexture(character: character, pose: pose, direction: direction))
    }
    static func headImage(_ character: PhotoSnakeCharacter) -> UIImage {
        image(PhotoSnakeHeadAnimation.overheadTexture(character: character, pose: .idle, direction: .up))
    }
}

/// A single 256px texture per selected photo, shared by every corresponding body sprite.
@MainActor
final class SnakePhotoTextureComposer {
    private struct Entry {
        weak var image: UIImage?
        let texture: SKTexture
    }
    private var cache: [String: Entry] = [:]
    private let placeholder: SKTexture
    private(set) var compositionCount = 0
    init() { placeholder = Self.composePlaceholder() }
    func synchronize(ids: [String], images: [String: UIImage]) {
        let visible = Set(ids)
        cache = cache.filter { visible.contains($0.key) && images[$0.key] != nil }
        for id in ids {
            guard let image = images[id] else { continue }
            guard cache[id]?.image !== image else { continue }
            cache[id] = Entry(image: image, texture: Self.compose(image)); compositionCount += 1
        }
    }
    func texture(_ id: String?) -> SKTexture {
        id.flatMap { cache[$0]?.texture } ?? placeholder
    }
    func removeAll() { cache.removeAll(keepingCapacity: false) }
    static func compose(_ image: UIImage) -> SKTexture {
        let pixels = min(image.cgImage?.width ?? Int(image.size.width * image.scale),
                         image.cgImage?.height ?? Int(image.size.height * image.scale))
        let result = renderTile(pixels: max(1, min(PhotoSnakeLayout.texturePixels, pixels))) { context, bounds in
            context.cgContext.saveGState()
            UIBezierPath(ovalIn: bounds).addClip()
            context.cgContext.interpolationQuality = .high
            let crop = PhotoSnakeLayout.aspectFill(width: Double(image.size.width), height: Double(image.size.height), side: Double(bounds.width))
            image.draw(in: CGRect(x: CGFloat(crop.x), y: CGFloat(crop.y), width: CGFloat(crop.width), height: CGFloat(crop.height)))
            context.cgContext.restoreGState()
        }
        let texture = SKTexture(image: result); texture.filteringMode = .linear
        return texture
    }
    private static func composePlaceholder() -> SKTexture {
        let result = renderTile { _, bounds in
            UIColor(red: 0.12, green: 0.30, blue: 0.20, alpha: 1).setFill()
            UIBezierPath(ovalIn: bounds).fill()
            UIImage(systemName: "photo", withConfiguration: UIImage.SymbolConfiguration(pointSize: 100, weight: .medium))?
                .withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal)
                .draw(in: bounds.insetBy(dx: 62, dy: 62))
        }
        let texture = SKTexture(image: result); texture.filteringMode = .linear; return texture
    }
    private static func renderTile(pixels: Int = PhotoSnakeLayout.texturePixels,
                                   _ draw: (UIGraphicsImageRendererContext, CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        format.preferredRange = .standard
        let side = CGFloat(pixels)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            draw(context, bounds)
            let border = side * CGFloat(PhotoSnakeLayout.borderPixels / Double(PhotoSnakeLayout.texturePixels))
            let outline = UIBezierPath(ovalIn: bounds.insetBy(dx: border / 2, dy: border / 2))
            UIColor(red: 0.36, green: 0.65, blue: 0.28, alpha: 1).setStroke()
            outline.lineWidth = border; outline.stroke()
        }
    }
}
