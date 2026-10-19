import PhotoMaidCore
import SwiftUI

/// Erstellen, Werkzeuge und gespeicherte Arbeit sind getrennt, ohne Funktionen zu verstecken.
struct StudioView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var drafts: [CollageProject] = []
    @State private var pickingCollage = false

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 152), spacing: AppSpacing.s)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                FeatureHeader(title: L("tab_studio"), subtitle: L("studio_intro")) { app.navigate(.settings) }
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    SectionHeader(title: L("studio_create_header"))
                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.s) {
                        FeatureActionTile(symbol: "rectangle.3.group", title: L("studio_collage"), subtitle: L("studio_collage_sub")) {
                            pickingCollage = true
                        }
                        FeatureActionTile(symbol: "film.stack", title: L("movie_title"), subtitle: L("movie_studio_sub")) {
                            app.navigate(.movie(ids: []), in: .studio)
                        }
                        FeatureActionTile(symbol: "play.rectangle", title: L("movie_title_slideshow"), subtitle: L("movie_slideshow_sub")) {
                            app.navigate(.movie(ids: []), in: .studio)
                        }
                        FeatureActionTile(symbol: "doc.richtext", title: L("pdf_title"), subtitle: L("pdf_studio_sub")) {
                            app.navigate(.pdfFromPhotos(ids: []), in: .studio)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    SectionHeader(title: L("tools_header"))
                    RowGroup {
                        studioRow("wand.and.stars", "tools_header", "tools_resize_sub", route: .tools(.resize))
                        Divider().padding(.leading, 52)
                        studioRow("arrow.triangle.branch", "wf_title", "wf_studio_sub", route: .workflows)
                        Divider().padding(.leading, 52)
                        studioRow("externaldrive", "archive_title", "archive_studio_sub", route: .archive(ids: []))
                    }
                }
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    SectionHeader(title: L("studio_saved_header"))
                    RowGroup {
                        studioRow("paintbrush", "studio_saved_header", "studio_saved_sub", route: .edits)
                    }
                }
                if !drafts.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        SectionHeader(title: L("studio_drafts_header"))
                        RowGroup {
                            ForEach(drafts) { draft in
                                Button { app.navigate(.collage(draftID: UUID(uuidString: draft.id)), in: .studio) } label: {
                                    NavRow(symbol: "rectangle.3.group", title: L("studio_collage"),
                                           subtitle: LP("studio_draft_collage", draft.items.count))
                                }
                                .buttonStyle(FeaturePressStyle())
                            }
                        }
                        Text(key: "studio_drafts_free_note")
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
        }
        .appPage()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $pickingCollage) {
            StudioMediaPicker(allowsVideos: false, limit: CollageProject.max) { ids in
                StudioHandoff.shared.ids = ids
                app.navigate(.collage(draftID: nil), in: .studio)
            }
        }
        .onAppear { drafts = app.kv?.get(StoreKeys.collageDrafts) ?? [] }
    }

    private func studioRow(_ symbol: String, _ title: String, _ subtitle: String, route: Route) -> some View {
        Button { app.navigate(route, in: .studio) } label: {
            NavRow(symbol: symbol, title: L(title), subtitle: L(subtitle))
        }
        .buttonStyle(FeaturePressStyle())
    }
}
