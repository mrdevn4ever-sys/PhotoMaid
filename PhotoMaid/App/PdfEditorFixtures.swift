#if QA_FIXTURES && targetEnvironment(simulator)
import PDFKit
import UIKit

/// Only generated, labelled QA files. UI tests use the production coordinated import path.
@MainActor enum PdfEditorFixtures {
    static func files() throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QA-PDF-Editor", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pdf = folder.appendingPathComponent("QA-Two-Pages.pdf")
        let image = folder.appendingPathComponent("QA-Image.png")
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 560)
        let bytes = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for (index, color) in [UIColor.systemBlue, UIColor.systemTeal].enumerated() {
                context.beginPage()
                color.setFill()
                context.cgContext.fill(CGRect(x: 24, y: 24, width: 352, height: 220))
                ("QA · PDF \(index + 1)" as NSString).draw(at: CGPoint(x: 24, y: 280),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 32)])
                ("PhotoMaid PDF editing test" as NSString).draw(at: CGPoint(x: 24, y: 340),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        try bytes.write(to: pdf, options: .atomic)
        let png = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 400)).pngData { context in
            UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
            ("QA · IMAGE" as NSString).draw(at: CGPoint(x: 70, y: 150),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 56), .foregroundColor: UIColor.white])
        }
        try png.write(to: image, options: .atomic)
        return [pdf, image]
    }
}
#endif
