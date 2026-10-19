import ImageIO
import PDFKit
import PhotoMaidCore
import UIKit
import XCTest
@testable import PhotoMaid

@MainActor final class PdfEditorTests: XCTestCase {
    private func document(_ labels: [String]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 420)).pdfData { context in
            for label in labels {
                context.beginPage()
                (label as NSString).draw(at: CGPoint(x: 24, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PDF-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMixedProviderFilesCreatePDFInSelectionOrderWithoutChangingSources() async throws {
        let root = try directory()
        let pdf = root.appendingPathComponent("source.pdf")
        let image = root.appendingPathComponent("image.png")
        let original = document(["FIRST", "SECOND"])
        try original.write(to: pdf)
        let png = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 200)).pngData { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
        }
        try png.write(to: image)
        let model = PdfEditorModel()
        try await model.importFiles([pdf, image])
        XCTAssertEqual(model.pages.count, 3)
        XCTAssertTrue(model.preview?.page(at: 0)?.string?.contains("FIRST") == true)
        XCTAssertTrue(model.preview?.page(at: 1)?.string?.contains("SECOND") == true)
        let bounds = try XCTUnwrap(model.preview?.page(at: 2)?.bounds(for: .mediaBox))
        XCTAssertGreaterThan(bounds.width, bounds.height)
        XCTAssertEqual(try Data(contentsOf: pdf), original)
        XCTAssertEqual(try Data(contentsOf: image), png)
        XCTAssertFalse(model.isImporting)
    }

    func testPreviewAndSavedCopyFollowRotationReorderAndRemoval() throws {
        let original = document(["FIRST", "SECOND", "THIRD"])
        let model = PdfEditorModel()
        try model.append([original])
        try model.rotateFocused()
        try model.moveFocused(by: 2)
        XCTAssertEqual(model.focusedIndex, 2)
        XCTAssertTrue(model.preview?.page(at: 2)?.string?.contains("FIRST") == true)
        XCTAssertEqual(model.preview?.page(at: 2)?.rotation, 90)
        model.focusedID = model.pages[0].id
        try model.removeFocused()
        let url = try model.save()
        defer { try? FileManager.default.removeItem(at: url) }
        let saved = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(saved.pageCount, 2)
        for index in 0..<saved.pageCount {
            XCTAssertEqual(saved.page(at: index)?.string, model.preview?.page(at: index)?.string)
            XCTAssertEqual(saved.page(at: index)?.rotation, model.preview?.page(at: index)?.rotation)
        }
        XCTAssertEqual(PDFDocument(data: original)?.page(at: 0)?.rotation, 0)
        XCTAssertTrue(saved.page(at: 0)?.string?.contains("THIRD") == true)
    }

    func testMultiSelectionUsesPageIdentityAfterReorder() throws {
        let model = PdfEditorModel()
        try model.append([document(["FIRST", "SECOND", "THIRD", "FOURTH"])])
        model.selectedIDs = [model.pages[0].id, model.pages[2].id]
        try model.moveFocused(by: 3)
        try model.removeSelected()
        XCTAssertEqual(model.pages.count, 2)
        XCTAssertTrue(model.preview?.page(at: 0)?.string?.contains("SECOND") == true)
        XCTAssertTrue(model.preview?.page(at: 1)?.string?.contains("FOURTH") == true)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testBadSelectionIsAtomicAndKeepsPreviousSavedCopy() throws {
        let model = PdfEditorModel()
        try model.append([document(["KEEP"])])
        let url = try model.save()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try model.append([document(["DO NOT APPEND"]), Data("invalid".utf8)]))
        XCTAssertEqual(model.pages.count, 1)
        XCTAssertEqual(model.savedURL, url)
        XCTAssertTrue(model.preview?.page(at: 0)?.string?.contains("KEEP") == true)
    }

    func testUnavailableProviderFileLeavesEditorUsable() async throws {
        let model = PdfEditorModel()
        try model.append([document(["KEEP"])])
        let missing = try directory().appendingPathComponent("missing.pdf")
        do { try await model.importFiles([missing]); XCTFail("Missing files must report a failure") } catch { }
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.pages.count, 1)
        try model.rotateFocused()
        XCTAssertEqual(model.preview?.page(at: 0)?.rotation, 90)
    }

    func testLastPageAndAllSelectedPagesCannotBeDeleted() throws {
        let model = PdfEditorModel()
        try model.append([document(["KEEP"])])
        try model.removeFocused()
        model.selectedIDs = Set(model.pages.map(\.id))
        try model.removeSelected()
        XCTAssertEqual(model.pages.count, 1)
        XCTAssertEqual(model.preview?.pageCount, 1)
    }

    func testChangesInvalidateShareURLAndSearchUsesEditedPages() throws {
        let model = PdfEditorModel()
        try model.append([document(["FIRST", "SECOND"])])
        let url = try model.save()
        defer { try? FileManager.default.removeItem(at: url) }
        try model.removeFocused()
        XCTAssertNil(model.savedURL)
        XCTAssertEqual(model.preview?.findString("FIRST", withOptions: .caseInsensitive).count, 0)
        XCTAssertEqual(model.preview?.findString("SECOND", withOptions: .caseInsensitive).count, 1)
        XCTAssertNotNil(PDFDocument(url: url), "Previously exported copies remain durable")
    }

    func testAddingFilesPreservesExistingPageEditsAndOrder() throws {
        let model = PdfEditorModel()
        try model.append([document(["FIRST", "SECOND"])])
        try model.rotateFocused()
        try model.moveFocused(by: 1)
        try model.append([document(["THIRD"])])
        XCTAssertEqual(model.pages.map(\.id), ["0:1", "0:0", "1:0"])
        XCTAssertEqual(model.preview?.page(at: 1)?.rotation, 90)
        XCTAssertEqual(model.focusedIndex, 2)
    }

    func testUnchangedThumbnailsAreReusedWhileRotatedThumbnailUpdates() throws {
        let model = PdfEditorModel()
        try model.append([document(["FIRST", "SECOND"])])
        let firstID = model.pages[0].id
        let image = try XCTUnwrap(model.thumbnails[firstID])
        try model.moveFocused(by: 1)
        XCTAssertTrue(model.thumbnails[firstID] === image)
        try model.rotateFocused()
        XCTAssertFalse(model.thumbnails[firstID] === image)
    }

    func testImageEXIFOrientationIsAppliedBeforeChoosingPaper() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 200)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let pdf = try XCTUnwrap(PDFDocument(data: PdfServices.pdfData(fromFileData: bytes as Data)))
        let bounds = try XCTUnwrap(pdf.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertGreaterThan(bounds.height, bounds.width)
    }

    func testInvalidPagePlanFailsInsteadOfSilentlyDroppingPages() throws {
        let doc = try XCTUnwrap(PDFDocument(data: document(["FIRST"])))
        XCTAssertThrowsError(try PdfServices.composed(documents: [doc], pages: [PdfPageRef(document: 0, page: 2)]))
        XCTAssertThrowsError(try PdfServices.composed(documents: [doc], pages: []))
        XCTAssertThrowsError(try PdfServices.pdfData(fromFileData: Data("not an image".utf8)))
    }

    func testVisibleSnapshotOwnsIndependentNativePDFBacking() throws {
        let source = try XCTUnwrap(PDFDocument(data: document(["FIRST", "SECOND"])))
        let first = try PdfServices.composed(documents: [source], pages: PdfEdit.merged(pageCounts: [2]))
        let second = try PdfServices.composed(documents: [source], pages: [PdfPageRef(document: 0, page: 0, quarterTurns: 1)])
        let sourceBacking = try XCTUnwrap(source.page(at: 0)?.pageRef?.document)
        let firstBacking = try XCTUnwrap(first.page(at: 0)?.pageRef?.document)
        let secondBacking = try XCTUnwrap(second.page(at: 0)?.pageRef?.document)
        XCTAssertFalse(sourceBacking === firstBacking)
        XCTAssertFalse(firstBacking === secondBacking)
        XCTAssertEqual(first.page(at: 0)?.rotation, 0)
        XCTAssertEqual(second.page(at: 0)?.rotation, 90)
    }

    func testRenderingPreviousDocumentWhileRepeatedlyRotatingNextSnapshot() throws {
        let model = PdfEditorModel()
        try model.append([document(["FIRST", "SECOND"])])
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        view.autoScales = true
        view.document = model.preview
        let original = try XCTUnwrap(view.document)
        for _ in 0..<12 {
            try model.rotateFocused()
            view.layoutDocumentView()
            XCTAssertNotNil(original.page(at: 0)?.thumbnail(of: CGSize(width: 200, height: 280), for: .mediaBox))
            XCTAssertNotNil(model.preview?.page(at: 0)?.thumbnail(of: CGSize(width: 200, height: 280), for: .mediaBox))
            XCTAssertEqual(original.page(at: 0)?.rotation, 0)
        }
        XCTAssertEqual(model.preview?.page(at: 0)?.rotation, 0)
    }

    func testOversizedFilesAreRejectedBeforeReadingIntoMemory() throws {
        let url = try directory().appendingPathComponent("oversized.pdf")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 101 * 1_024 * 1_024)
        try handle.close()
        XCTAssertThrowsError(try PdfServices.importedData(from: [url])) { error in
            XCTAssertEqual(error as? PdfServices.Failure, .tooLarge)
        }
    }
}
