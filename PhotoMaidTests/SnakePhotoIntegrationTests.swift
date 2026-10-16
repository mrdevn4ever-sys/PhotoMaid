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
        #expect(decoded.size.height > decoded.size.width && decoded.imageOrientation == .up)
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
