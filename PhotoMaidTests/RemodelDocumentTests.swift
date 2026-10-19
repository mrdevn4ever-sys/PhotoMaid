import Foundation
import PDFKit
import Testing
import UIKit
@testable import PhotoMaid

/// Native integration tests. Require Apple's SDK; source parsing is NOT execution.
struct RemodelDocumentTests {
    @Test @MainActor
    func savedPdfIsDurableAndReadable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = onePagePdf()
        let output = try PdfServices.saveDocument(data, documentsDirectory: folder)
        #expect(output.deletingLastPathComponent().lastPathComponent == "PhotoMaid")
        #expect(try Data(contentsOf: output) == data)
        let reopened = try #require(PDFDocument(url: output))
        #expect(reopened.pageCount == 1)
    }

    @Test @MainActor
    func consecutiveSavesNeverOverwriteExistingDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = onePagePdf()
        let first = try PdfServices.saveDocument(data, documentsDirectory: folder)
        let second = try PdfServices.saveDocument(data, documentsDirectory: folder)
        #expect(first != second)
        #expect(try Data(contentsOf: first) == data)
        #expect(try Data(contentsOf: second) == data)
    }

    @Test @MainActor
    func emptyDocumentFailsBeforeCreatingOutput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            _ = try PdfServices.saveDocument(Data(), documentsDirectory: folder)
            Issue.record("Empty PDF must not report a saved file")
        } catch PdfServices.Failure.write {
            #expect(FileManager.default.fileExists(atPath: folder.path) == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    private func onePagePdf() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
            .pdfData { context in context.beginPage() }
    }
}
