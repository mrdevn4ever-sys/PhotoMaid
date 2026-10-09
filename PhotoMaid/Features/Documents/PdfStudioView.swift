import PDFKit
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

struct PdfStudioView: View {
    @Environment(AppModel.self) private var app
    @State private var importing = false
    @State private var documents: [PDFDocument] = []
    @State private var pages: [PdfPageRef] = []
    @State private var selected = Set<Int>()
    @State private var query = ""
    @State private var matches = 0
    @State private var output: URL?

    var body: some View {
        List {
            Section {
                Button { importing = true } label: { Label(L("folder_open"), systemImage: "doc") }
                if !documents.isEmpty {
                    TextField(L("search"), text: $query).onSubmit { search() }
                    Text(verbatim: String(matches)).foregroundStyle(AppColors.textSecondary)
                }
            }
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                HStack {
                    Button { toggle(index) } label: { Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle") }
                    Text(verbatim: L("pdf_page_of", index + 1, pages.count))
                    Spacer()
                    Button { pages = PdfEdit.move(pages, from: index, to: max(0, index - 1)) } label: { Image(systemName: "arrow.up") }
                    Button { pages = PdfEdit.rotate(pages, at: index) } label: { Image(systemName: "rotate.right") }
                }
            }
            if !pages.isEmpty {
                Section {
                    Button(role: .destructive) { pages = PdfEdit.remove(pages, at: selected); selected.removeAll() } label: {
                        Label(L("remove"), systemImage: "trash")
                    }
                    Button { export() } label: { Label(L("pdf_save"), systemImage: "square.and.arrow.down") }
                    if let output { ShareLink(item: output) { Label(L("pdf_share"), systemImage: "square.and.arrow.up") } }
                }
            }
        }
        .appPage().navigationTitle(L("pdf_title"))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            documents = urls.compactMap(PDFDocument.init(url:))
            pages = PdfEdit.merged(pageCounts: documents.map(\.pageCount))
        }
    }

    private func toggle(_ index: Int) { if selected.contains(index) { selected.remove(index) } else { selected.insert(index) } }
    private func search() { matches = documents.reduce(0) { $0 + $1.findString(query, withOptions: .caseInsensitive).count } }
    private func export() { do { output = try PdfServices.edited(documents: documents, pages: pages) } catch { app.showError(L("pdf_failed")) } }
}
