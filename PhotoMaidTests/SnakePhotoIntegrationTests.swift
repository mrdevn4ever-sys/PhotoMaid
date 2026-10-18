import ImageIO
import PhotoMaidCore
import SpriteKit
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PhotoMaid

/// Requires the iOS test host. Added here; never report these as run on Linux.
@MainActor struct SnakePhotoIntegrationTests {
    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
            UIColor.blue.setFill(); context.fill(CGRect(x: 400, y: 0, width: 400, height: 600))
        }
    }
    @Test func targetContainsAllAtlasesBackgroundsAndSounds() throws {
        let bundle = Bundle.main
        for atlas in SnakeArt.atlases { #expect(!atlas.textureNames.isEmpty) }
        for character in PhotoSnakeCharacter.allCases {
            for key in [character.idle, character.blink, character.eat, character.dead] {
                let size = SnakeArt.texture(key).size()
                // Packed atlas UV coordinates introduce sub-pixel floating-point roundoff.
                #expect(abs(size.width - 256) < 0.001 && abs(size.height - 256) < 0.001)
            }
        }
        for food in PhotoSnakeFood.allCases {
            let size = SnakeArt.texture(food.texture(score: 0)).size()
            #expect(abs(size.width - 256) < 0.001 && abs(size.height - 256) < 0.001)
        }
        for character in PhotoSnakeCharacter.allCases {
            for pose in PhotoSnakeHeadAnimation.Pose.allCases {
                for direction in PhotoSnakeGame.Direction.allCases {
                    let texture = SnakeArt.headTexture(character: character, pose: pose, direction: direction)
                    let size = texture.size()
                    #expect(abs(size.width - 256) < 0.001 && abs(size.height - 256) < 0.001)
                }
            }
        }
        for cue in SnakeAudio.Cue.allCases { #expect(bundle.url(forResource: "sfx_" + cue.rawValue, withExtension: "wav") != nil) }
        for name in ["bg_forest_day", "bg_forest_night", "bg_tile_forest", "bg_tile_night"] {
            #expect(UIImage(named: name, in: bundle, compatibleWith: nil) != nil)
        }
    }
    @Test func thumbnailAppliesEXIFAndCapsResolutionWithoutKeepingTheOriginal() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try #require(image().cgImage)
        let writer = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, source, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(writer))
        let data = try SnakePhotoLibrary.thumbnail(url)
        let decoded = try #require(UIImage(data: data))
        #expect(max(decoded.size.width, decoded.size.height) <= 256)
        #expect(decoded.size == CGSize(width: 256, height: 256) && decoded.imageOrientation == .up)
        let cg = try #require(decoded.cgImage)
        // EXIF rotation must happen before the square crop: the left/right split becomes top/bottom.
        let top = try pixel(cg, x: 128, y: 32), bottom = try pixel(cg, x: 128, y: 224)
        let left = try pixel(cg, x: 32, y: 128), right = try pixel(cg, x: 224, y: 128)
        #expect(abs(top[0] - bottom[0]) > 150)
        #expect(abs(left[0] - right[0]) < 30)
        #expect(data.count < 262_144)
    }
    @Test func textureIsComposedOnceReusedAndRemovedFromCache() {
        let composer = SnakePhotoTextureComposer()
        let photo = image()
        composer.synchronize(ids: ["chosen"], images: ["chosen": photo])
        let first = composer.texture("chosen")
        for _ in 0..<300 { composer.synchronize(ids: ["chosen"], images: ["chosen": photo]) }
        #expect(composer.compositionCount == 1)
        #expect(first === composer.texture("chosen"))
        #expect(first.size() == CGSize(width: 256, height: 256))
        composer.synchronize(ids: [], images: [:])
        #expect(composer.texture("chosen") !== first)
    }
    @Test func replacedImagesInvalidateTheTextureEvenWithTheSamePhotoID() {
        let composer = SnakePhotoTextureComposer()
        let firstImage = image(), replacement = image()
        composer.synchronize(ids: ["same"], images: ["same": firstImage])
        let first = composer.texture("same")
        composer.synchronize(ids: ["same"], images: ["same": replacement])
        #expect(composer.compositionCount == 2)
        #expect(composer.texture("same") !== first)
        composer.synchronize(ids: ["same"], images: [:])
        #expect(composer.texture("same") !== first)
    }
    @Test func roundPhotoUsesTheFullDiameterWithAThinBorder() throws {
        let cg = SnakePhotoTextureComposer.compose(image()).cgImage()
        #expect(try pixel(cg, x: 0, y: 0)[3] == 0)
        #expect(try pixel(cg, x: 16, y: 16)[3] == 0)
        #expect(try pixel(cg, x: 16, y: 128)[3] == 255)
        #expect(try pixel(cg, x: 128, y: 16)[3] == 255)
        #expect(try pixel(cg, x: 128, y: 128)[3] == 255)
    }
    @Test func panoramicPhotosRetainEnoughPixelsForASharpSquare() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let panorama = UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 256), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2048, height: 256))
            UIColor.green.setFill(); context.fill(CGRect(x: 896, y: 0, width: 256, height: 256))
        }
        try #require(panorama.jpegData(compressionQuality: 1)).write(to: url)
        let square = try #require(UIImage(data: SnakePhotoLibrary.thumbnail(url)))
        #expect(square.size == CGSize(width: 256, height: 256))
        let centre = try pixel(#require(square.cgImage), x: 128, y: 128)
        #expect(centre[1] > 200 && centre[0] < 40)
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try data.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        let offset = (y * image.width + x) * 4
        return Array(data[offset..<(offset + 4)]).map(Int.init)
    }
    @Test func restoringReorderingRemovingPhotosPreservesAnExistingPausedRound() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = PhotoSnakePhotoArchive(directory: folder)
        let input = folder.appendingPathComponent("input.jpg")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #require(image().jpegData(compressionQuality: 0.5)).write(to: input)
        let data = try SnakePhotoLibrary.thumbnail(input)
        try FileManager.default.removeItem(at: input)
        let a = PhotoSnakeGallery.Photo(), b = PhotoSnakeGallery.Photo(), c = PhotoSnakeGallery.Photo()
        for photo in [a, b, c] { _ = try await archive.insert(data, photo: photo) }
        let gallery = SnakePhotoLibrary(directory: folder)
        await gallery.restore()
        #expect(gallery.images.count == 3)
        let model = PhotoSnakeModel(gallery: gallery)
        model.startSaved(mode: .relaxed, speed: .normal, stepMode: true)
        model.swipe(.up); model.finishPresentation(); model.pause()
        let before = model.game, round = model.roundID
        await gallery.move(from: IndexSet(integer: 0), to: 3); model.applyGalleryChanges()
        #expect(model.pictureIDs == [b.id, c.id, a.id].map(\.uuidString))
        await gallery.remove(b.id); model.applyGalleryChanges()
        #expect(model.pictureIDs == [c.id, a.id].map(\.uuidString))
        #expect(gallery.images[b.id.uuidString] == nil)
        #expect(model.game == before && model.roundID == round && !model.running)
        model.swipe(.left)
        #expect(model.running && model.game?.direction == .left)
    }
    @Test func gameOverIsPresentedOnlyAfterTheVisibleImpactFinishes() throws {
        let model = PhotoSnakeModel()
        model.startMotifs(mode: .classic, speed: .normal, stepMode: true)
        model.swipe(.up)
        for _ in 0..<30 where model.game?.status == .playing { model.tick(); model.finishPresentation() }
        // Start a fresh round to inspect an unfinished collision explicitly.
        model.restart(); model.swipe(.up)
        for _ in 0..<30 where model.game?.status == .playing { model.tick() }
        #expect(model.game?.status == .lost && model.presentationPending)
        #expect(model.displayedStatus == .playing)
        model.finishPresentation()
        #expect(model.displayedStatus == .lost && !model.running)
    }
}
