import PDFKit
import PhotoMaidCore
import UIKit

enum PdfServices {
    enum Failure: Error { case noImages, render, write }

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
        let folder = documents.appendingPathComponent("PhotoMaid", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = "PhotoMaid-\(UUID().uuidString.prefix(8)).pdf"
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

    static func edited(documents: [PDFDocument], pages: [PdfPageRef]) throws -> URL {
        let output = PDFDocument()
        for ref in pages {
            guard documents.indices.contains(ref.document), let source = documents[ref.document].page(at: ref.page),
                  let copy = source.copy() as? PDFPage else { continue }
            copy.rotation = ref.rotationDegrees(base: source.rotation)
            output.insert(copy, at: output.pageCount)
        }
        guard output.pageCount > 0, let data = output.dataRepresentation() else { throw Failure.write }
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
