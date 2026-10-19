import PhotoMaidCore
import SwiftUI
import VisionKit

struct StudioView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var drafts: [CollageProject] = []
    @State private var pickingCollage = false
    @State private var draftToDelete: CollageProject?

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] :
            [GridItem(.adaptive(minimum: 152), spacing: AppSpacing.s)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                FeatureHeader(title: L("tab_studio"), subtitle: L("studio_intro")) { app.navigate(.settings) }
                creationSection
                toolsSection
                documentsSection
                savedSection
                draftsSection
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
        }
        .appPage()
        .navigationTitle(L("tab_studio"))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $pickingCollage) {
            StudioMediaPicker(allowsVideos: false, limit: CollageProject.max) { ids in
                StudioHandoff.shared.ids = ids
                app.navigate(.collage(draftID: nil), in: .studio)
            }
        }
        .onAppear { drafts = app.kv?.get(StoreKeys.collageDrafts) ?? [] }
        .confirmationDialog(L("studio_draft_delete"), isPresented: Binding(get: { draftToDelete != nil },
                                                                           set: { if !$0 { draftToDelete = nil } }),
                            titleVisibility: .visible, presenting: draftToDelete) { draft in
            Button(L("studio_draft_delete"), role: .destructive) { deleteDraft(draft) }
            Button(L("cancel"), role: .cancel) {}
        } message: { _ in
            Text(key: "studio_draft_delete_text")
        }
    }

    /// Entfernt nur den Entwurf (Layout und Auswahl); Fotos und gespeicherte Collagen bleiben unverändert.
    private func deleteDraft(_ draft: CollageProject) {
        drafts.removeAll { $0.id == draft.id }
        try? app.kv?.set(StoreKeys.collageDrafts, drafts)
        draftToDelete = nil
    }

    private var creationSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: L("studio_create_header"))
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.s) {
                studioButton("rectangle.3.group", "studio_collage", "studio_collage_sub") { pickingCollage = true }
                studioButton("film.stack", "movie_title", "movie_studio_sub") { app.navigate(.movie(ids: []), in: .studio) }
                studioButton("play.rectangle", "movie_title_slideshow", "movie_slideshow_sub") { app.navigate(.movie(ids: []), in: .studio) }
                studioButton("doc.richtext", "pdf_title", "pdf_studio_sub") { app.navigate(.pdfFromPhotos(ids: []), in: .studio) }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: L("tools_header"))
            RowGroup {
                studioRow("arrow.down.right.and.arrow.up.left", "tools_resize", "tools_resize_sub", route: .tools(.resize), id: "studio.tools.resize")
                SwiftUI.Divider().padding(.leading, 52)
                studioRow("arrow.triangle.2.circlepath", "tools_convert", "tools_convert_sub", route: .tools(.convert), id: "studio.tools.convert")
                SwiftUI.Divider().padding(.leading, 52)
                studioRow("location.slash", "tools_location", "tools_location_sub", route: .tools(.removeLocation), id: "studio.tools.location")
                SwiftUI.Divider().padding(.leading, 52)
                studioRow("rectangle.stack", "tools_stitch", "tools_stitch_sub", route: .tools(.stitch), id: "studio.tools.stitch")
                SwiftUI.Divider().padding(.leading, 52)
                studioRow("photo.stack", "tools_gif", "tools_gif_sub", route: .tools(.gif), id: "studio.tools.gif")
                SwiftUI.Divider().padding(.leading, 52)
                studioRow("slider.horizontal.3", "remodel_batch_edit", "tools_resize_sub", route: .tools(.batchEdit), id: "studio.tools.batch")
                SwiftUI.Divider().padding(.leading, 52)
                studioRow("arrow.triangle.branch", "wf_title", "wf_studio_sub", route: .workflows, id: "studio.workflows")
                SwiftUI.Divider().padding(.leading, 52)
                studioRow("externaldrive", "archive_title", "archive_studio_sub", route: .archive(ids: []), id: "studio.archive")
            }
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: L("kind_document"))
            RowGroup {
                Button { app.navigate(.pdfStudio, in: .studio) } label: {
                    NavRow(symbol: "doc.text", title: L("remodel_pdf_editor"), subtitle: L("pdf_editor_subtitle"))
                }
                .buttonStyle(FeaturePressStyle())
                .accessibilityIdentifier("studio.pdfEditor")
                if VNDocumentCameraViewController.isSupported {
                    SwiftUI.Divider().padding(.leading, 52)
                    Button { app.fullScreen = .scanner } label: {
                        NavRow(symbol: "doc.viewfinder", title: L("remodel_scanner"))
                    }
                    .buttonStyle(FeaturePressStyle())
                    .accessibilityIdentifier("studio.scanner")
                }
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: L("studio_saved_header"))
            RowGroup {
                studioRow("paintbrush", "studio_saved_header", "studio_saved_sub", route: .edits, id: "studio.saved")
            }
        }
    }

    @ViewBuilder private var draftsSection: some View {
        if !drafts.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                SectionHeader(title: L("studio_drafts_header"))
                RowGroup {
                    ForEach(drafts) { draft in
                        HStack(spacing: AppSpacing.xs) {
                            Button { app.navigate(.collage(draftID: UUID(uuidString: draft.id)), in: .studio) } label: {
                                NavRow(symbol: "rectangle.3.group", title: L("studio_collage"),
                                       subtitle: LP("studio_draft_collage", draft.items.count), showsChevron: true)
                            }
                            .buttonStyle(FeaturePressStyle())
                            .accessibilityIdentifier("studio.draft." + draft.id)
                            Button { draftToDelete = draft } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppColors.cleanup)
                                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(key: "studio_draft_delete"))
                            .accessibilityIdentifier("studio.draft.delete." + draft.id)
                        }
                        .contextMenu {
                            Button(role: .destructive) { draftToDelete = draft } label: {
                                Label(L("studio_draft_delete"), systemImage: "trash")
                            }
                        }
                        if draft.id != drafts.last?.id { SwiftUI.Divider().padding(.leading, 52) }
                    }
                }
                Text(key: "studio_drafts_free_note").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func studioButton(_ symbol: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        FeatureActionTile(symbol: symbol, title: L(title), subtitle: L(subtitle), action: action)
            .accessibilityIdentifier("studio.create." + title)
    }

    private func studioRow(_ symbol: String, _ title: String, _ subtitle: String, route: Route, id: String) -> some View {
        Button { app.navigate(route, in: .studio) } label: {
            NavRow(symbol: symbol, title: L(title), subtitle: L(subtitle))
        }
        .buttonStyle(FeaturePressStyle())
        .accessibilityIdentifier(id)
    }
}
