import PDFKit
import SwiftUI
import VisionKit

struct DocumentScannerHost: UIViewControllerRepresentable {
    @Environment(AppModel.self) private var app

    func makeCoordinator() -> Coordinator { Coordinator(app: app) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let app: AppModel
        init(app: AppModel) { self.app = app }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { app.fullScreen = nil }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            app.showError(L("pdf_failed")); app.fullScreen = nil
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let document = PDFDocument()
            for index in 0..<scan.pageCount {
                if let page = PDFPage(image: scan.imageOfPage(at: index)) { document.insert(page, at: document.pageCount) }
            }
            guard let data = document.dataRepresentation() else { app.showError(L("pdf_failed")); return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            do {
                try data.write(to: url, options: .atomic)
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.completionWithItemsHandler = { [weak self] _, _, _, _ in
                    Task { @MainActor in self?.app.fullScreen = nil }
                }
                controller.present(share, animated: true)
                app.showToast(L("pdf_saved"))
                return
            }
            catch { app.showError(L("pdf_failed")) }
            app.fullScreen = nil
        }
    }
}
