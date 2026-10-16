import CoreTransferable
import ImageIO
import Observation
import PhotoMaidCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// PhotosPicker grants access to the chosen files; this path never requests library-wide access.
struct SnakePickedFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let bytes = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard bytes > 0, bytes <= 100 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnakePhotoImports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: received.file, to: target)
            do {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
                return Self(url: target)
            } catch { try? FileManager.default.removeItem(at: target); throw error }
        }
    }
}

@MainActor @Observable
final class SnakePhotoLibrary {
    private(set) var selection = PhotoSnakeGallery()
    private var cachedImages: [String: UIImage] = [:]
    var images: [String: UIImage] {
        let permitted = Set(ids)
        return cachedImages.filter { permitted.contains($0.key) }
    }
    private(set) var revision = 0
    private(set) var busy = false
    private(set) var restored = false
    var error: String?
    @ObservationIgnored private let archive: PhotoSnakePhotoArchive?

    init(directory: URL? = nil) { archive = directory.map { PhotoSnakePhotoArchive(directory: $0) } }
    var ids: [String] { selection.photos.filter(Self.permitted).map { $0.id.uuidString } }
    private static func permitted(_ photo: PhotoSnakeGallery.Photo) -> Bool {
        VaultConcealment.shared.analysisReady && (photo.sourceAssetID.map { !VaultConcealment.shared.isConcealed($0) } ?? true)
    }
    func visibilityChanged() { revision += 1 }

    func restore() async {
        guard !restored, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            // Clean a file transfer interrupted by process termination, before accepting new imports.
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("SnakePhotoImports"))
            if let archive {
                let saved = try await archive.load()
                var loaded: [String: UIImage] = [:]
                for photo in saved.photos {
                    if let data = try await archive.image(photo.id), let image = Self.decodeThumbnail(data) {
                        loaded[photo.id.uuidString] = image
                    }
                }
                selection = saved; cachedImages = loaded; revision += 1
            }
            restored = true
        } catch { self.error = L("snake_gallery_error") }
    }

    func add(_ items: [PhotosPickerItem]) async {
        guard !busy else { return }
        await restore()
        guard restored else { return }
        busy = true; error = nil
        defer { busy = false; revision += 1 }
        var failed = false
        for item in items.prefix(PhotoSnakeGallery.maximumPhotos - selection.photos.count) {
            if Task.isCancelled { break }
            do {
                guard let file = try await item.loadTransferable(type: SnakePickedFile.self) else {
                    failed = true; continue
                }
                defer { try? FileManager.default.removeItem(at: file.url) }
                let data = try await Task.detached(priority: .userInitiated) {
                    try Self.thumbnail(file.url)
                }.value
                guard !Task.isCancelled, let image = Self.decodeThumbnail(data) else { failed = true; continue }
                let photo = PhotoSnakeGallery.Photo(sourceAssetID: item.itemIdentifier)
                guard Self.permitted(photo) else { failed = true; continue }
                if let archive { selection = try await archive.insert(data, photo: photo) }
                else { _ = selection.append(photo) }
                cachedImages[photo.id.uuidString] = image
            } catch { failed = true }
        }
        if failed { error = L("snake_photo_error") }
    }

    func remove(_ id: UUID) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false; revision += 1 }
        cachedImages.removeValue(forKey: id.uuidString)
        do {
            // A failed index write keeps a placeholder entry available for an explicit retry.
            if let archive { selection = try await archive.remove(id) }
            else { selection.remove(id) }
            cachedImages.removeValue(forKey: id.uuidString)
        } catch { self.error = L("snake_gallery_error") }
    }

    func move(from offsets: IndexSet, to destination: Int) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false; revision += 1 }
        do {
            if let archive { selection = try await archive.move(from: offsets, to: destination) }
            else { selection.move(from: offsets, to: destination) }
        } catch { self.error = L("snake_gallery_error") }
    }

    private static func decodeThumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...256).contains(width), (1...256).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    /// ImageIO downsamples HEIC/JPEG/PNG and applies EXIF before decoding; originals are never kept.
    nonisolated static func thumbnail(_ url: URL) throws -> Data {
        try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            let data = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
            guard CGImageDestinationFinalize(writer), data.length <= 262_144 else { throw CocoaError(.fileWriteUnknown) }
            return data as Data
        }
    }
}
