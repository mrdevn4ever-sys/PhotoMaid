import Observation
import PDFKit
import PhotoMaidCore
import UIKit

/// One page plan drives the visible PDF, thumbnails, selection and saved copy.
@MainActor @Observable final class PdfEditorModel {
    private var documents: [PDFDocument] = []
    private(set) var pages: [PdfPageRef] = []
    private(set) var preview: PDFDocument?
    private(set) var thumbnails: [String: UIImage] = [:]
    private(set) var savedURL: URL?
    private(set) var isImporting = false
    var focusedID: String?
    var selectedIDs = Set<String>()

    var focusedIndex: Int { pages.firstIndex { $0.id == focusedID } ?? 0 }

    func importFiles(_ urls: [URL]) async throws {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let task = Task.detached(priority: .userInitiated) { try PdfServices.importedData(from: urls) }
        let data = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        try append(data)
    }

    func append(_ data: [Data]) throws {
        let additions = try data.map { bytes -> PDFDocument in
            guard let doc = PDFDocument(data: bytes), !doc.isLocked, doc.pageCount > 0 else {
                throw PdfServices.Failure.unsupportedFile
            }
            return doc
        }
        guard !additions.isEmpty else { throw PdfServices.Failure.noImages }
        let combined = documents + additions
        guard combined.reduce(0, { $0 + $1.pageCount }) <= 500 else { throw PdfServices.Failure.tooLarge }
        let addedPages = additions.enumerated().flatMap { offset, doc in
            (0..<doc.pageCount).map { PdfPageRef(document: documents.count + offset, page: $0) }
        }
        let plan = pages + addedPages
        let rendered = try PdfServices.composed(documents: combined, pages: plan)
        documents = combined
        commit(plan, rendered: rendered, focus: addedPages.first?.id)
    }

    func rotateFocused() throws { try apply(PdfEdit.rotate(pages, at: focusedIndex)) }
    func moveFocused(by offset: Int) throws {
        try apply(PdfEdit.move(pages, from: focusedIndex, to: focusedIndex + offset))
    }

    func removeFocused() throws {
        guard pages.count > 1 else { return }
        let index = focusedIndex
        let plan = PdfEdit.remove(pages, at: [index])
        try apply(plan, focus: plan[min(index, plan.count - 1)].id)
    }

    func removeSelected() throws {
        let indices = Set(pages.indices.filter { selectedIDs.contains(pages[$0].id) })
        let plan = PdfEdit.remove(pages, at: indices)
        let focus = plan.contains { $0.id == focusedID } ? focusedID : plan.first?.id
        try apply(plan, focus: focus)
        selectedIDs.removeAll()
    }

    func save() throws -> URL {
        let url = try PdfServices.edited(documents: documents, pages: pages)
        savedURL = url
        return url
    }

    private func apply(_ plan: [PdfPageRef], focus: String? = nil) throws {
        guard !plan.isEmpty, plan != pages else { return }
        let rendered = try PdfServices.composed(documents: documents, pages: plan)
        commit(plan, rendered: rendered, focus: focus ?? focusedID)
    }

    private func commit(_ plan: [PdfPageRef], rendered: PDFDocument, focus: String?) {
        let previous = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        var cached: [String: UIImage] = [:]
        for (index, ref) in plan.enumerated() {
            if previous[ref.id] == ref, let image = thumbnails[ref.id] { cached[ref.id] = image }
            else { cached[ref.id] = rendered.page(at: index)?.thumbnail(of: CGSize(width: 144, height: 192), for: .mediaBox) }
        }
        pages = plan
        selectedIDs.formIntersection(Set(plan.map(\.id)))
        preview = rendered
        thumbnails = cached
        focusedID = focus ?? plan.first?.id
        // A previously saved URL describes the old PDF, never the current edited preview.
        savedURL = nil
    }
}
