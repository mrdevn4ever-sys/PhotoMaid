import PhotoMaidCore
import SwiftUI

struct PdfFromPhotosView: View {
    @Environment(AppModel.self) private var app
    let initialIDs: [String]
    @State private var ids: [String] = []
    @State private var options = PdfOptions()
    @State private var picker = false
    @State private var exportURL: URL?
    @State private var exporting = false

    var body: some View {
        Form {
            Section {
                Button { picker = true } label: { Label(L("pdf_pick"), systemImage: "photo.on.rectangle.angled") }
                    .accessibilityIdentifier("pdf.photosChoose")
                NavigationLink {
                    PdfStudioView(importOnAppear: true)
                } label: { Label(L("pdf_files_create"), systemImage: "folder") }
                    .accessibilityIdentifier("pdf.fromFiles")
                Text(verbatim: LP("pdf_photos", ids.count))
            }
            Section {
                Picker(L("pdf_paper"), selection: $options.paper) {
                    Text(verbatim: "A4").tag(PaperSize.a4)
                    Text(verbatim: "A5").tag(PaperSize.a5)
                    Text(key: "pdf_paper_letter").tag(PaperSize.letter)
                }
                Picker(L("pdf_orientation"), selection: $options.orientation) {
                    Text(key: "pdf_orient_auto").tag(PageOrientation.auto)
                    Text(key: "pdf_orient_portrait").tag(PageOrientation.portrait)
                    Text(key: "pdf_orient_landscape").tag(PageOrientation.landscape)
                }
                Picker(L("pdf_per_page"), selection: $options.perPage) {
                    ForEach(PerPage.allCases, id: \.self) { Text(verbatim: String($0.rawValue)).tag($0) }
                }
                Picker(L("pdf_margin"), selection: $options.margin) {
                    Text(key: "pdf_margin_none").tag(PageMargin.none)
                    Text(key: "pdf_margin_small").tag(PageMargin.small)
                    Text(key: "pdf_margin_normal").tag(PageMargin.normal)
                }
                Picker(L("pdf_fit"), selection: $options.fit) {
                    Text(key: "pdf_fit").tag(ImageFit.fit)
                    Text(key: "pdf_fill").tag(ImageFit.fill)
                }
            }
            Button { Task { await render() } } label: { Label(L("pdf_save"), systemImage: "doc.badge.plus") }
                .buttonStyle(.glassProminent).disabled(ids.isEmpty || exporting)
            if let exportURL { ShareLink(item: exportURL) { Label(L("pdf_share"), systemImage: "square.and.arrow.up") } }
            Text(key: "pdf_privacy").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
        }
        .appPage().navigationTitle(L("pdf_title"))
        .overlay { if exporting { LoadingState(message: L("pdf_running")).background(.ultraThinMaterial) } }
        .sheet(isPresented: $picker) {
            StudioMediaPicker(allowsVideos: false, limit: PdfRules.maxImages(pro: app.capabilities.hasProToolsAccess),
                              initial: Set(ids)) { ids = $0 }
        }
        .onAppear { if ids.isEmpty { ids = initialIDs.filter { app.asset($0)?.isVideo == false } } }
    }

    private func render() async {
        if PdfRules.needsPro(options, count: ids.count) && !app.capabilities.hasProToolsAccess { app.navigate(.pro); return }
        exporting = true
        defer { exporting = false }
        do {
            let saved = try await PdfServices.fromPhotos(ids: ids, options: options)
            exportURL = saved
            // pdf_saved has a positional filename placeholder in all localizations.
            // Never show success before the document was durably written.
            app.showToast(L("pdf_saved", saved.lastPathComponent))
        } catch {
            Diagnostics.error(.pdf, "pdf-create-save-failed", error)
            app.showError(L("pdf_failed"))
        }
    }
}
