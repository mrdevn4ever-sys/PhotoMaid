import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct PhotoSnakeGalleryTests {
    @Test func galleryHandlesZeroOneTenAndOneHundredPhotosAndCyclesInChosenOrder() throws {
        var gallery = PhotoSnakeGallery()
        #expect(gallery.photo(at: 0) == nil)
        let photos = (0..<101).map { _ in PhotoSnakeGallery.Photo() }
        for (index, photo) in photos.enumerated() {
            let added = gallery.append(photo)
            #expect(added == (index < 100))
            if [0, 9, 99].contains(index) { #expect(gallery.photos.count == index + 1) }
        }
        let duplicate = gallery.append(photos[0])
        #expect(!duplicate)
        for index in 0..<350 { #expect(gallery.photo(at: index) == photos[index % 100].id) }
        gallery.move(from: IndexSet([0, 2]), to: 5)
        #expect(gallery.photos.prefix(5).map(\.id) == [photos[1], photos[3], photos[4], photos[0], photos[2]].map(\.id))
        let before = gallery
        gallery.move(from: IndexSet(integer: 1000), to: 0)
        #expect(gallery == before)
        gallery.remove(photos[0].id)
        #expect(!gallery.photos.contains(photos[0]))
        let order = gallery.order(shuffled: true, seed: 7)
        #expect(order == gallery.order(shuffled: true, seed: 7))
        #expect(Set(order) == Set(gallery.photos.map(\.id)))
        #expect(order != gallery.order(shuffled: false, seed: 7))
        #expect(try JSONDecoder().decode(PhotoSnakeGallery.self, from: JSONEncoder().encode(gallery)) == gallery)
    }
    @Test func thumbnailsAndOrderSurviveNewArchiveInstancesAndRemovalDeletesBytes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = PhotoSnakePhotoArchive(directory: folder)
        #expect(try await archive.load().photos.isEmpty)
        let a = PhotoSnakeGallery.Photo(), b = PhotoSnakeGallery.Photo()
        _ = try await archive.insert(Data([1,2,3]), photo: a)
        _ = try await archive.insert(Data([4,5,6]), photo: b)
        _ = try await archive.move(from: IndexSet(integer: 0), to: 2)
        let reopened = PhotoSnakePhotoArchive(directory: folder)
        #expect(try await reopened.load().photos.map(\.id) == [b.id, a.id])
        #expect(try await reopened.image(a.id) == Data([1,2,3]))
        _ = try await reopened.remove(a.id)
        #expect(try await reopened.image(a.id) == nil)
        #expect(try await reopened.load().photos.map(\.id) == [b.id])
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(a.id.uuidString + ".jpg").path))
    }
    @Test func archiveRejectsOversizedInputAndCleansCrashOrphansButToleratesMissingImages() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = PhotoSnakePhotoArchive(directory: folder)
        _ = try await archive.load()
        await #expect(throws: PhotoSnakePhotoArchive.Failure.self) {
            _ = try await archive.insert(Data(repeating: 0, count: 262_145), photo: .init())
        }
        let photo = PhotoSnakeGallery.Photo()
        _ = try await archive.insert(Data([1]), photo: photo)
        let imageURL = folder.appendingPathComponent(photo.id.uuidString + ".jpg")
        try FileManager.default.removeItem(at: imageURL)
        #expect(try await archive.image(photo.id) == nil)
        #expect(try await archive.load().photos.count == 1)
        let orphan = folder.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([2]).write(to: orphan)
        _ = try await archive.load()
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        try Data("invalid".utf8).write(to: folder.appendingPathComponent("selection.json"))
        await #expect(throws: (any Error).self) { _ = try await archive.load() }
    }
    @Test func archiveRejectsSymlinkedPhotoReads() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = PhotoSnakePhotoArchive(directory: folder)
        _ = try await archive.load()
        let secret = folder.appendingPathComponent("outside.data")
        try Data([8]).write(to: secret)
        let photo = PhotoSnakeGallery.Photo()
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(photo.id.uuidString + ".jpg"), withDestinationURL: secret)
        await #expect(throws: PhotoSnakePhotoArchive.Failure.self) { _ = try await archive.image(photo.id) }
    }
}
