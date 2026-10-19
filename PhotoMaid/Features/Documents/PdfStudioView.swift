import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PdfStudioView: View {
    @Environment(AppModel.self) private var app
    var importOnAppear = false
    @State private var editor = PdfEditorModel()
    @State private var importing = false
    @State private var initialImportAttempted = false
    @State private var request: ImportRequest?
    @State private var searching = false
    @State private var selecting = false
    @State private var query = ""

    private struct ImportRequest: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let document = editor.preview {
                if searching {
                    TextField(L("search"), text: $query)
                        .textFieldStyle(.roundedBorder).padding(.horizontal).padding(.bottom, 8)
                        .accessibilityIdentifier("pdf.search")
                    Text(verbatim: String(query.isEmpty ? 0 : document.findString(query, withOptions: .caseInsensitive).count))
                        .font(AppTypography.caption)
                }
                PdfDocumentPreview(document: document, pageIndex: Binding(
                    get: { editor.focusedIndex },
                    set: { if editor.pages.indices.contains($0) { editor.focusedID = editor.pages[$0].id } }
                ), query: query)
                // PDFKit's text/AX layer must not keep pages from the previous document
                // while a rotation/reorder installs a different page tree.
                .id(ObjectIdentifier(document))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                pageStrip
                editActions
                if let saved = editor.savedURL {
                    ShareLink(item: saved) { Label(L("pdf_share"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent).padding(.bottom, 8)
                        .accessibilityIdentifier("pdf.share")
                }
            } else {
                ContentUnavailableView {
                    Label(L("remodel_pdf_editor"), systemImage: "doc.richtext")
                } description: {
                    Text(key: "pdf_files_hint")
                } actions: {
                    Button { importing = true } label: { Label(L("pdf_files_choose"), systemImage: "folder") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("pdf.import")
                }
            }
        }
        .appPage().navigationTitle(L(importOnAppear ? "pdf_title" : "remodel_pdf_editor")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editor.preview != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { searching.toggle(); if !searching { query = "" } } label: { Label(L("search"), systemImage: "magnifyingglass") }
                        Button { selecting.toggle(); editor.selectedIDs.removeAll() } label: {
                            Label(L(selecting ? "done" : "pdf_pages_select"), systemImage: "checkmark.circle")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel(Text(key: "pdf_editor_actions"))
                    .accessibilityIdentifier("pdf.actions")
                    Button { importing = true } label: { Image(systemName: "doc.badge.plus") }
                        .accessibilityLabel(Text(key: "pdf_files_add")).accessibilityIdentifier("pdf.add")
                    Button { perform { let url = try editor.save(); app.showToast(L("pdf_saved", url.lastPathComponent)) } } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel(Text(key: "pdf_save")).accessibilityIdentifier("pdf.save")
                }
            }
        }
        .disabled(editor.isImporting)
        .overlay { if editor.isImporting { LoadingState(message: L("pdf_running")).background(.regularMaterial) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): if !urls.isEmpty { request = ImportRequest(urls: urls) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { report(error) }
            }
        }
        .task(id: request?.id) {
            guard let request else { return }
            do { try await editor.importFiles(request.urls) }
            catch is CancellationError { }
            catch { report(error) }
        }
        .task {
            guard !initialImportAttempted else { return }
            initialImportAttempted = true
            if importOnAppear { importing = true }
            #if QA_FIXTURES && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-pdf-editor-fixtures") {
                // One owning startup task: do not change the sibling task's ID
                // while SwiftUI is still installing its initial task modifiers.
                do { try await editor.importFiles(PdfEditorFixtures.files()) }
                catch is CancellationError { initialImportAttempted = false }
                catch { report(error) }
            }
            #endif
        }
    }

    private var pageStrip: some View {
        VStack(spacing: 4) {
            Text(verbatim: L("pdf_page_of", editor.focusedIndex + 1, editor.pages.count))
                .font(AppTypography.caption).padding(.top, 8).accessibilityIdentifier("pdf.pageCount")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(editor.pages.enumerated()), id: \.element.id) { index, ref in
                            Button {
                                editor.focusedID = ref.id
                                if selecting {
                                    if !editor.selectedIDs.insert(ref.id).inserted { editor.selectedIDs.remove(ref.id) }
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    if let image = editor.thumbnails[ref.id] {
                                        Image(uiImage: image).resizable().scaledToFit().frame(width: 52, height: 64)
                                    }
                                    HStack(spacing: 4) {
                                        if selecting { Image(systemName: editor.selectedIDs.contains(ref.id) ? "checkmark.circle.fill" : "circle") }
                                        Text(verbatim: String(index + 1))
                                    }.font(AppTypography.caption)
                                }
                                .padding(5).frame(minWidth: 64, minHeight: 84)
                                .background(editor.focusedID == ref.id ? AppColors.accent.opacity(0.15) : AppColors.surface,
                                            in: .rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                                    editor.focusedID == ref.id ? AppColors.accent : AppColors.surfaceStroke,
                                    lineWidth: editor.focusedID == ref.id ? 2 : 1))
                            }
                            .buttonStyle(.plain).id(ref.id)
                            .accessibilityLabel(Text(verbatim: L("pdf_page_of", index + 1, editor.pages.count)))
                            .accessibilityValue(Text(verbatim: "\(ref.id);rotation=\(ref.quarterTurns * 90)"))
                            .accessibilityAddTraits(editor.focusedID == ref.id ? .isSelected : [])
                            .accessibilityIdentifier("pdf.page.\(index)")
                        }
                    }.padding(.horizontal)
                }
                .frame(height: 100)
                .onChange(of: editor.focusedID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: editor.pages) { _, _ in
                    if let id = editor.focusedID { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background(AppColors.surface)
    }

    private var editActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }.padding(8)
            ScrollView(.horizontal) { HStack(spacing: 8) { actionButtons }.padding(8) }
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).background(AppColors.surface)
    }

    @ViewBuilder private var actionButtons: some View {
        editButton("arrow.up", "pdf_page_earlier", "pdf.earlier", disabled: editor.focusedIndex == 0) {
            try editor.moveFocused(by: -1)
        }
        editButton("rotate.right", "pdf_page_rotate", "pdf.rotate") { try editor.rotateFocused() }
        editButton("arrow.down", "pdf_page_later", "pdf.later", disabled: editor.focusedIndex == editor.pages.count - 1) {
            try editor.moveFocused(by: 1)
        }
        editButton("trash", "remove", "pdf.remove", disabled: editor.pages.count <= 1 || (selecting && (editor.selectedIDs.isEmpty || editor.selectedIDs.count == editor.pages.count))) {
            if selecting { try editor.removeSelected() } else { try editor.removeFocused() }
        }
    }

    private func editButton(_ symbol: String, _ label: String, _ id: String, disabled: Bool = false,
                            action: @escaping () throws -> Void) -> some View {
        Button { perform(action) } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                Text(verbatim: L(label)).font(AppTypography.caption).fixedSize()
            }.frame(minWidth: 48, minHeight: 44)
                .padding(6)
                .background(AppColors.accent.opacity(0.12), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain).foregroundStyle(AppColors.accent).disabled(disabled).opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(Text(verbatim: L(label))).accessibilityIdentifier(id)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { report(error) }
    }

    private func report(_ error: Error) {
        Diagnostics.error(.pdf, "pdf-editor-failed", error)
        let key: String
        switch error as? PdfServices.Failure {
        case .tooLarge: key = "pdf_files_large"
        case .unsupportedFile: key = "pdf_files_failed"
        default: key = "pdf_failed"
        }
        app.showError(L(key))
    }
}
