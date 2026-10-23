import ImageIO
import PDFKit
import PhotoMaidCore
import UIKit

enum PdfServices {
    enum Failure: Error, Equatable { case noImages, render, write, unsupportedFile, tooLarge }

    /// Read provider files while their security scope is open. Coordination materializes
    /// iCloud items. Return owned PDF bytes, never provider URLs. A failed selection is atomic.
    static func importedData(from urls: [URL]) throws -> [Data] {
        guard !urls.isEmpty else { throw Failure.noImages }
        var total = 0
        return try urls.map { url in
            try Task.checkCancellation()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var read: Result<Data, Error>?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                read = Result {
                    let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 100 * 1_024 * 1_024 else { throw Failure.tooLarge }
                    return try Data(contentsOf: readable)
                }
            }
            if let coordinationError { throw coordinationError }
            guard let read else { throw Failure.render }
            let data = try read.get()
            total += data.count
            guard total <= 256 * 1_024 * 1_024 else { throw Failure.tooLarge }
            return try autoreleasepool { try pdfData(fromFileData: data) }
        }
    }

    static func pdfData(fromFileData data: Data) throws -> Data {
        if let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0 { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_480,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { throw Failure.unsupportedFile }
        // Fit the complete, orientation-correct image on A4. Never stretch or upscale it.
        let landscape = cg.width > cg.height
        let paper = CGRect(x: 0, y: 0, width: landscape ? 841.89 : 595.28, height: landscape ? 595.28 : 841.89)
        let printable = paper.insetBy(dx: 18, dy: 18)
        let scale = min(1, printable.width / CGFloat(cg.width), printable.height / CGFloat(cg.height))
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        return UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
            context.beginPage()
            UIImage(cgImage: cg).draw(in: CGRect(x: paper.midX - size.width / 2, y: paper.midY - size.height / 2,
                                                width: size.width, height: size.height))
        }
    }

    /// Durable, user-visible storage: Files → On My iPhone → PhotoMaid → PhotoMaid.
    /// Only generated PDFs live here. Encrypted vault data stays in Application Support.
    /// A unique file name prevents an older PDF from being overwritten.
    static func saveDocument(_ data: Data, documentsDirectory: URL? = nil) throws -> URL {
        guard !data.isEmpty else { throw Failure.write }
        let documents: URL
        if let documentsDirectory {
            documents = documentsDirectory
        } else {
            documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        }
        let folder = documents.appendingPathComponent(AppConfig.brandName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = "\(AppConfig.brandName)-\(UUID().uuidString.prefix(8)).pdf"
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        let recordedSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard recordedSize == data.count else { throw Failure.write }
        return url
    }

    static func fromPhotos(ids: [String], options: PdfOptions) async throws -> URL {
        let data = try await ids.asyncMapPdf { try await BatchProcessor.imageData($0) }
        let images = data.compactMap(UIImage.init(data:))
        guard images.count == ids.count, !images.isEmpty else { throw Failure.noImages }
        let sizes = images.map { SourceSize(width: Int($0.size.width * $0.scale), height: Int($0.size.height * $0.scale)) }
        let pages = PdfLayout.pages(sizes, options: options)
        let first = pages[0]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: CGFloat(first.widthPt), height: CGFloat(first.heightPt)))
        let pdf = renderer.pdfData { context in
            for page in pages {
                context.beginPage(withBounds: CGRect(x: 0, y: 0, width: CGFloat(page.widthPt), height: CGFloat(page.heightPt)), pageInfo: [:])
                for placed in page.items {
                    let source = images[placed.index]
                    guard let cg = source.cgImage else { continue }
                    let crop = placed.crop
                    let rect = CGRect(x: CGFloat(crop.left * Double(cg.width)),
                                      y: CGFloat(crop.top * Double(cg.height)),
                                      width: CGFloat((crop.right - crop.left) * Double(cg.width)),
                                      height: CGFloat((crop.bottom - crop.top) * Double(cg.height))).integral
                    guard let cropped = cg.cropping(to: rect) else { continue }
                    let destination = CGRect(x: CGFloat(placed.rect.x), y: CGFloat(placed.rect.y),
                                             width: CGFloat(placed.rect.w), height: CGFloat(placed.rect.h))
                    UIImage(cgImage: cropped).draw(in: destination)
                }
            }
        }
        return try saveDocument(pdf)
    }

    /// Preview and export share the exact page plan. Source documents stay immutable.
    static func composed(documents: [PDFDocument], pages: [PdfPageRef]) throws -> PDFDocument {
        let output = PDFDocument()
        for ref in pages {
            guard documents.indices.contains(ref.document), let source = documents[ref.document].page(at: ref.page),
                  let copy = source.copy() as? PDFPage else { throw Failure.render }
            copy.rotation = ref.rotationDegrees(base: source.rotation)
            output.insert(copy, at: output.pageCount)
        }
        // PDFPage.copy() retains native backing from its source. A PDFView may still be
        // rendering the previous plan while the next plan rotates another copy. Reopen
        // a serialized snapshot so each visible document owns independent CGPDF backing.
        guard output.pageCount > 0, let data = output.dataRepresentation(),
              let snapshot = PDFDocument(data: data), snapshot.pageCount == pages.count else { throw Failure.write }
        return snapshot
    }

    static func edited(documents: [PDFDocument], pages: [PdfPageRef]) throws -> URL {
        let output = try composed(documents: documents, pages: pages)
        guard let data = output.dataRepresentation() else { throw Failure.write }
        return try saveDocument(data)
    }
}

private extension Array {
    func asyncMapPdf<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
