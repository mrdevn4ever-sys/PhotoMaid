import PhotoMaidCore
import SwiftUI

struct StudioView: View {
    @Environment(AppModel.self) private var app
    @State private var drafts: [CollageProject] = []
    @State private var pickingCollage = false
    @State private var draftToDelete: CollageProject?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                Text(key: "studio_intro").font(AppTypography.body).foregroundStyle(AppColors.textSecondary)
                SectionHeader(title: L("studio_create_header"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 154, maximum: 260))], spacing: AppSpacing.s) {
                    studioButton("rectangle.3.group", "studio_collage", "studio_collage_sub") { pickingCollage = true }
                    studioButton("film.stack", "movie_title", "movie_studio_sub") { app.navigate(.movie(ids: []), in: .studio) }
                    studioButton("play.rectangle", "movie_title_slideshow", "movie_slideshow_sub") { app.navigate(.movie(ids: []), in: .studio) }
                    studioButton("wand.and.stars", "tools_header", "tools_resize_sub") { app.navigate(.tools(.resize), in: .studio) }
                    studioButton("arrow.triangle.branch", "wf_title", "wf_studio_sub") { app.navigate(.workflows, in: .studio) }
                    studioButton("doc.richtext", "pdf_title", "pdf_studio_sub") { app.navigate(.pdfFromPhotos(ids: []), in: .studio) }
                    studioButton("paintbrush", "studio_saved_header", "studio_saved_sub") { app.navigate(.edits, in: .studio) }
                    studioButton("externaldrive", "archive_title", "archive_studio_sub") { app.navigate(.archive(ids: []), in: .studio) }
                }
                if !drafts.isEmpty {
                    SectionHeader(title: L("studio_drafts_header"))
                    ForEach(drafts) { draft in
                        HStack(spacing: AppSpacing.xs) {
                            Button { app.navigate(.collage(draftID: UUID(uuidString: draft.id)), in: .studio) } label: {
                                NavRow(symbol: "rectangle.3.group", title: L("studio_collage"),
                                       subtitle: LP("studio_draft_collage", draft.items.count), showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            Button { draftToDelete = draft } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppColors.cleanup)
                                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(key: "studio_draft_delete"))
                        }
                        .contextMenu {
                            Button(role: .destructive) { draftToDelete = draft } label: {
                                Label(L("studio_draft_delete"), systemImage: "trash")
                            }
                        }
                    }
                    Text(key: "studio_drafts_free_note").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(AppSpacing.pageMargin)
        }
        .appPage()
        .navigationTitle(L("tab_studio"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { app.navigate(.settings) } label: { Image(systemName: "gearshape") } } }
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

    private func studioButton(_ symbol: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Image(systemName: symbol).font(.title2).foregroundStyle(AppColors.accent)
                    Text(key: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                    Text(key: subtitle).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
    }
}
