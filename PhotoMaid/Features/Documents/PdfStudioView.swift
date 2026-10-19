import PDFKit
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

struct PdfStudioView: View {
    @Environment(AppModel.self) private var app
    @State private var importing = false
    @State private var documents: [PDFDocument] = []
    @State private var pages: [PdfPageRef] = []
    @State private var selected = Set<String>()
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
                    Button { toggle(page.id) } label: {
                        Image(systemName: selected.contains(page.id) ? "checkmark.circle.fill" : "circle")
                            .frame(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch)
                    }
                    .accessibilityLabel(Text(key: "grid_select"))
                    .accessibilityAddTraits(selected.contains(page.id) ? .isSelected : [])
                    Text(verbatim: L("pdf_page_of", index + 1, pages.count))
                    Spacer()
                    Button { pages = PdfEdit.move(pages, from: index, to: max(0, index - 1)); output = nil } label: {
                        Image(systemName: "arrow.up").frame(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch)
                    }
                    .disabled(index == 0)
                    .accessibilityLabel(Text(key: "pdf_move_up"))
                    Button { pages = PdfEdit.rotate(pages, at: index); output = nil } label: {
                        Image(systemName: "rotate.right").frame(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch)
                    }
                    .accessibilityLabel(Text(key: "edit_rotate"))
                }
                .buttonStyle(.borderless)
            }
            if !pages.isEmpty {
                Section {
                    Button(role: .destructive) {
                        let indices = Set(pages.enumerated().filter { selected.contains($0.element.id) }.map(\.offset))
                        pages = PdfEdit.remove(pages, at: indices)
                        selected.removeAll()
                        output = nil
                    } label: {
                        Label(L("remove"), systemImage: "trash")
                    }
                    .disabled(selected.isEmpty || selected.count == pages.count)
                    Button { export() } label: { Label(L("pdf_save"), systemImage: "square.and.arrow.down") }
                    if let output { ShareLink(item: output) { Label(L("pdf_share"), systemImage: "square.and.arrow.up") } }
                }
            }
        }
        .appPage().navigationTitle(L("remodel_pdf_editor"))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            do {
                var imported: [PDFDocument] = []
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
                        throw PdfServices.Failure.noImages
                    }
                    imported.append(document)
                }
                guard !imported.isEmpty else { return }
                documents = imported
                pages = PdfEdit.merged(pageCounts: imported.map(\.pageCount))
                selected = []
                query = ""
                matches = 0
                output = nil
            } catch { app.showError(L("pdf_failed")) }
        }
    }

    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    private func search() { matches = documents.reduce(0) { $0 + $1.findString(query, withOptions: .caseInsensitive).count } }
    private func export() {
        do {
            let saved = try PdfServices.edited(documents: documents, pages: pages)
            output = saved
            app.showToast(L("pdf_saved", saved.lastPathComponent))
        } catch { app.showError(L("pdf_failed")) }
    }
}
