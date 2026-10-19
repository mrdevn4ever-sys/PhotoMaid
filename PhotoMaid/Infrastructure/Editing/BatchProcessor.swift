import ImageIO
import Photos
import PhotoMaidCore
import UIKit
import UniformTypeIdentifiers

enum BatchProcessor {
    enum Failure: Error { case unavailable, render, write }

    static func imageData(_ id: String) async throws -> Data {
        guard let asset = PhotoLibraryService.phAsset(id) else { throw Failure.unavailable }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat
        let box = UncheckedBox(asset)
        let result: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: box.value, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let result, !Task.isCancelled, !VaultConcealment.shared.isConcealed(id) else { throw Failure.unavailable }
        return result
    }

    @MainActor
    static func process(app: AppModel, ids: [String], options: BatchOptions, recipe: EditRecipe? = nil) async -> BatchSummary {
        var summary = BatchSummary()
        for id in ids {
            guard let asset = app.asset(id), !asset.isVideo else { summary.skipped += 1; continue }
            do {
                let input = try await imageData(id)
                guard var image = EditRenderer.source(input) else { throw Failure.render }
                let metadata = EditRenderer.metadata(input)
                if let recipe { image = EditRenderer.shared.render(image, recipe: recipe) }
                if let edge = options.longEdge {
                    let current = max(image.extent.width, image.extent.height)
                    if current > CGFloat(edge) {
                        let scale = CGFloat(edge) / current
                        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    }
                }
                let format = options.tool == .convert ? options.format : EditFormat.forSource(uti: metadata?.uti)
                let strip = options.tool == .stripLocation || options.removeLocation
                let encodedQuality = Double(options.quality) / 100
                guard let output = EditRenderer.shared.encode(image, format: format, metadata: metadata?.props,
                                                               removeLocation: strip, quality: encodedQuality)
                else { throw Failure.render }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = EditNames.copyName(original: PhotoLibraryService.originalFilename(id), suffix: L("edit_copy_suffix"),
                                              fileExtension: format.fileExtension)
                let url = folder.appendingPathComponent(name)
                try output.write(to: url, options: .atomic)
                let request = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: false, creationDate: asset.creationDate,
                                                              latitude: strip ? nil : asset.latitude,
                                                              longitude: strip ? nil : asset.longitude, filename: name)
                let saved = await app.library.save(request)
                try? FileManager.default.removeItem(at: folder)
                guard case .saved(let newID) = saved else { throw Failure.write }
                let kind: EditKind = options.tool == .convert ? .convert : (options.tool == .resize && recipe == nil ? .compress : .edit)
                _ = await EditSaver.finish(app: app, original: asset, newID: newID, mode: .copy, video: false,
                                           kind: kind, sources: [id], bytes: Int64(output.count))
                let before: Int64?
                let measured = await app.sizer.size(of: asset)
                if case .known(let bytes) = measured { before = bytes } else { before = nil }
                summary = summary.adding(before: before, after: Int64(output.count))
            } catch {
                summary.failed += 1
            }
        }
        return summary
    }

    static func stitch(ids: [String]) async throws -> Data {
        let values = try await ids.asyncMap { try await imageData($0) }
        let images = values.compactMap { UIImage(data: $0)?.cgImage }
        guard images.count == ids.count, !images.isEmpty else { throw Failure.render }
        let sizes = images.map { PxSize($0.width, $0.height) }
        let plan = StitchPlan.layout(sizes)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(plan.size.width), height: CGFloat(plan.size.height)), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(plan.size.width), height: CGFloat(plan.size.height)))
            for index in images.indices {
                let place = plan.places[index]
                UIImage(cgImage: images[index]).draw(in: CGRect(x: 0, y: CGFloat(place.top),
                                                               width: CGFloat(place.width), height: CGFloat(place.height)))
            }
        }
        guard let data = rendered.jpegData(compressionQuality: 0.94) else { throw Failure.render }
        guard !Task.isCancelled, VaultConcealment.shared.visible(ids, id: { $0 }).count == ids.count else { throw Failure.unavailable }
        return data
    }

    static func gif(ids: [String], maxEdge: Int, delay: Double) async throws -> Data {
        let values = try await ids.asyncMap { try await imageData($0) }
        let images = values.compactMap { UIImage(data: $0)?.cgImage }
        guard let first = images.first, images.count == ids.count else { throw Failure.render }
        let frame = GifPlan.frame(firstW: first.width, firstH: first.height, maxEdge: maxEdge)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, images.count, nil) else {
            throw Failure.write
        }
        let gifProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(destination, gifProperties)
        for image in images {
            let place = GifPlan.place(srcW: image.width, srcH: image.height, frameW: frame.width, frameH: frame.height, fill: false)
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height))).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: CGFloat(frame.width), height: CGFloat(frame.height)))
                let rect = CGRect(x: CGFloat(place.0), y: CGFloat(place.1), width: CGFloat(place.2 - place.0),
                                  height: CGFloat(place.3 - place.1))
                UIImage(cgImage: image).draw(in: rect)
            }
            guard let cg = rendered.cgImage else { continue }
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(destination, cg, properties)
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure.write }
        guard !Task.isCancelled, VaultConcealment.shared.visible(ids, id: { $0 }).count == ids.count else { throw Failure.unavailable }
        return data as Data
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
