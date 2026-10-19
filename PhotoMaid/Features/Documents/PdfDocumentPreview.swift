import PDFKit
import SwiftUI

/// Actual PDF text, zoom and scrolling. Page changes in either direction select the
/// same page in the editing strip. The document only changes after an edit.
struct PdfDocumentPreview: UIViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int
    var query: String = ""

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PdfFittingView()
        view.autoScales = true
        // Editing targets one explicit page. A continuous layout may report the next
        // portrait page as current after the selected page rotates to landscape.
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor = .secondarySystemBackground
        view.accessibilityIdentifier = "pdf.preview"
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        let changed = view.document !== document
        if changed { view.document = document }
        if let target = document.page(at: pageIndex), changed || view.currentPage !== target { view.go(to: target) }
        if changed || coordinator.query != query {
            coordinator.query = query
            view.highlightedSelections = query.isEmpty ? [] : document.findString(query, withOptions: .caseInsensitive)
        }
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        // Let PDFView release its document with its text/AX subviews. Clearing it here
        // tears the page tree out from under outstanding PDFKit accessibility work.
    }

    @MainActor final class Coordinator: NSObject {
        var parent: PdfDocumentPreview
        var isUpdating = false
        var query = ""

        init(_ parent: PdfDocumentPreview) { self.parent = parent }

        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged(_:)),
                                                  name: .PDFViewPageChanged, object: view)
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? PDFView,
                  let page = view.currentPage, let document = view.document else { return }
            let index = document.index(for: page)
            guard index != NSNotFound, index != parent.pageIndex else { return }
            parent.pageIndex = index
        }
    }
}

/// SwiftUI gives the view its final bounds after the initial PDF assignment. Refit
/// once for each window size, without resetting the user's zoom on ordinary updates.
final class PdfFittingView: PDFView {
    private var fittedSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard document != nil, bounds.width > 0, bounds.height > 0, bounds.size != fittedSize else { return }
        let fit = scaleFactorForSizeToFit
        guard fit.isFinite, fit > 0 else { return }
        fittedSize = bounds.size
        scaleFactor = fit
    }
}
