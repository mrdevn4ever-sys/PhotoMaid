import PhotoMaidCore
import SwiftUI
import VisionKit

struct StudioView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var drafts: [CollageProject] = []
    @State private var pickingCollage = false
    @State private var draftToDelete: CollageProject?
    @State private var showGames = false

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] :
            [GridItem(.adaptive(minimum: 152), spacing: AppSpacing.s)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(key: "tab_studio").pageTitle().accessibilityAddTraits(.isHeader)
                    Text(key: "studio_intro").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, AppSpacing.xs)
                collageHero
                creationSection
                PMCardRow(icon: .cup, tint: AppColors.later, tile: AppColors.pauseStroke, title: L("games_choose"),
                          subtitle: L("art_games_list"), subtitleColor: AppColors.pauseText,
                          background: AppColors.pauseSurface, stroke: AppColors.pauseStroke, radius: AppRadii.card) {
                    showGames = true
                }
                .accessibilityIdentifier("studio.games")
                toolsSection
                draftsSection
                savedSection
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
        }
        .appPage()
        .statusBarBackdrop()
        .navigationTitle(L("tab_studio"))
        .toolbar(.hidden, for: .navigationBar)
        .gamesCover(isPresented: $showGames)
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

    /// Collage als große Karte mit den neuesten echten Fotos (Artefakt).
    private var collageHero: some View {
        let ids = Array(app.cleanupMedia.lazy.filter { $0.kind == .photo }.prefix(4).map(\.id))
        return Button { pickingCollage = true } label: {
            HStack(spacing: AppSpacing.m) {
                LazyVGrid(columns: [GridItem(.fixed(50), spacing: 4), GridItem(.fixed(50), spacing: 4)], spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        Group {
                            if i < ids.count { AssetCell(assetID: ids[i]) } else { AppColors.control }
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(key: "studio_create_header").eyebrow()
                    Text(key: "studio_collage").font(PMFont.heading(26)).foregroundStyle(AppColors.textPrimary)
                    Text(key: "studio_collage_sub").font(PMFont.text(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.sheet))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.sheet).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
            .contentShape(.rect(cornerRadius: AppRadii.sheet))
        }
        .buttonStyle(PMPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("studio.create.studio_collage")
    }

    private var creationSection: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.s) {
            studioTile(.video, AppColors.cleanup, "movie_title", "movie_studio_sub") { app.navigate(.movie(ids: []), in: .studio) }
                .accessibilityIdentifier("studio.create.movie_title")
            studioTile(.slideshow, AppColors.later, "movie_title_slideshow", "movie_slideshow_sub") {
                app.navigate(.movie(ids: []), in: .studio)
            }
            .accessibilityIdentifier("studio.create.movie_title_slideshow")
            studioTile(.pdf, AppColors.keep, "pdf_title", "pdf_studio_sub") { app.navigate(.pdfFromPhotos(ids: []), in: .studio) }
                .accessibilityIdentifier("studio.create.pdf_title")
            studioTile(.textDoc, AppColors.accent, "remodel_pdf_editor", "pdf_editor_subtitle") { app.navigate(.pdfStudio, in: .studio) }
                .accessibilityIdentifier("studio.pdfEditor")
            if VNDocumentCameraViewController.isSupported {
                studioTile(.scan, AppColors.success, "remodel_scanner", "art_scan_sub") { app.fullScreen = .scanner }
                    .accessibilityIdentifier("studio.scanner")
            }
            studioTile(.gif, AppColors.accent, "tools_gif", "tools_gif_sub") { app.navigate(.tools(.gif), in: .studio) }
                .accessibilityIdentifier("studio.tools.gif")
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(key: "tools_header").font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader).padding(.top, 6).padding(.horizontal, 4)
            VStack(spacing: 0) {
                studioRow(.resize, AppColors.keep, "tools_resize", "tools_resize_sub", route: .tools(.resize), id: "studio.tools.resize")
                studioRow(.convert, AppColors.success, "tools_convert", "tools_convert_sub", route: .tools(.convert), id: "studio.tools.convert")
                studioRow(.locationOff, AppColors.cleanup, "tools_location", "tools_location_sub", route: .tools(.removeLocation),
                          id: "studio.tools.location")
                studioRow(.stitch, AppColors.later, "tools_stitch", "tools_stitch_sub", route: .tools(.stitch), id: "studio.tools.stitch")
                studioRow(.filter, AppColors.accent, "remodel_batch_edit", "tools_batch_intro", route: .tools(.batchEdit),
                          id: "studio.tools.batch")
                studioRow(.series, AppColors.keep, "wf_title", "wf_studio_sub", route: .workflows, id: "studio.workflows")
                studioRow(.folder, AppColors.success, "archive_title", "archive_studio_sub", route: .archive(ids: []),
                          id: "studio.archive", last: true)
            }
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
            .clipShape(.rect(cornerRadius: AppRadii.card))
        }
    }

    private var savedSection: some View {
        Button { app.navigate(.edits, in: .studio) } label: {
            HStack(spacing: 14) {
                PMIcon(.check, size: 22).foregroundStyle(AppColors.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key: "studio_saved_header").font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                    Text(key: "studio_saved_sub").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: AppSpacing.xs)
                PMIcon(.chevronRight, size: 18).foregroundStyle(AppColors.textTertiary).flipsForRightToLeftLayoutDirection(true)
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(PMPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("studio.saved")
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

    private func studioTile(_ icon: PMIconName, _ tint: Color, _ title: String, _ subtitle: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                PMIcon(icon, size: 19)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(PMTile.background(for: tint), in: .rect(cornerRadius: AppRadii.small))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key: title).font(PMFont.text(.semibold, 15, relativeTo: .headline)).foregroundStyle(AppColors.textPrimary)
                    Text(key: subtitle).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
            .contentShape(.rect(cornerRadius: AppRadii.card))
        }
        .buttonStyle(PMPressStyle())
        .accessibilityElement(children: .combine)
    }

    /// Werkzeug-Zeile ohne Kachel: farbiges Strich-Symbol, Titel, Untertitel, Pfeil (Artefakt).
    private func studioRow(_ icon: PMIconName, _ tint: Color, _ title: String, _ subtitle: String, route: Route, id: String,
                           last: Bool = false) -> some View {
        Button { app.navigate(route, in: .studio) } label: {
            HStack(spacing: 14) {
                PMIcon(icon, size: 22).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                    Text(key: subtitle).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppSpacing.xs)
                PMIcon(.chevronRight, size: 18).foregroundStyle(AppColors.textTertiary).flipsForRightToLeftLayoutDirection(true)
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(AppColors.surfaceStroke).frame(height: 1) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(PMPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
