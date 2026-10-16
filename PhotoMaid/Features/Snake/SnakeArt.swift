import PhotoMaidCore
import SpriteKit
import UIKit

@MainActor
enum SnakeArt {
    static let atlases = ["SnakeHeads", "SnakeBody", "SnakeFood", "SnakeUI"].map(SKTextureAtlas.init(named:))
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
        for atlas in atlases { for name in atlas.textureNames { _ = texture(name.replacingOccurrences(of: ".png", with: "")) } }
    }
    static func preload() async {
        await SKTextureAtlas.preloadTextureAtlases(atlases)
        warmTextures()
    }
}

/// A single 256px texture per selected photo, shared by every corresponding body sprite.
@MainActor
final class SnakePhotoTextureComposer {
    private var cache: [String: SKTexture] = [:]
    private(set) var compositionCount = 0
    func synchronize(ids: [String], images: [String: UIImage]) {
        let visible = Set(ids)
        cache = cache.filter { visible.contains($0.key) }
        for id in ids where cache[id] == nil {
            guard let image = images[id] else { continue }
            cache[id] = Self.compose(image); compositionCount += 1
        }
    }
    func texture(_ id: String?) -> SKTexture {
        id.flatMap { cache[$0] } ?? SnakeArt.texture("segment_placeholder")
    }
    func removeAll() { cache.removeAll(keepingCapacity: false) }
    static func compose(_ image: UIImage) -> SKTexture {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let result = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { context in
            let circle = CGRect(x: 48, y: 48, width: 160, height: 160)
            context.cgContext.saveGState()
            UIBezierPath(ovalIn: circle).addClip()
            let scale = max(circle.width / max(1, image.size.width), circle.height / max(1, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: 128 - size.width / 2, y: 128 - size.height / 2, width: size.width, height: size.height))
            context.cgContext.restoreGState()
            SnakeArt.image("segment_ring").draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        let texture = SKTexture(image: result); texture.filteringMode = .linear
        return texture
    }
}
