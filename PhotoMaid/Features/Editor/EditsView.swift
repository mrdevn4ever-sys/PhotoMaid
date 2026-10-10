import PhotoMaidCore
import SwiftUI

/// „Bearbeitet“: alles, was im Editor/Studio gespeichert wurde (neueste zuerst, nur auf diesem iPhone gespeichert).
struct EditsView: View {
    @Environment(AppModel.self) private var app
    @State private var records: [EditRecord] = []

    var body: some View {
        List {
            Section {
                Text(key: "edits_intro").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
            if records.isEmpty {
                EmptyState(symbol: "pencil.and.outline", title: L("edits_empty_title"), message: L("edits_empty_text"))
                    .listRowBackground(Color.clear)
            }
            ForEach(records) { r in
                row(r)
                    .swipeActions {
                        // Nur der Listeneintrag verschwindet; das gespeicherte Foto/Video bleibt in der Fotos-App.
                        Button { forget(r) } label: { Label(L("edits_forget"), systemImage: "minus.circle") }
                            .tint(AppColors.textSecondary)
                    }
            }
        }
        .appPage()
        .navigationTitle(L("edits_title"))
        .task(id: app.library.changeToken) { records = app.kv?.get(StoreKeys.edits) ?? [] }
    }

    private func forget(_ r: EditRecord) {
        records.removeAll { $0.id == r.id }
        try? app.kv?.set(StoreKeys.edits, records)
    }

    private func row(_ r: EditRecord) -> some View {
        let exists = app.asset(r.newId) != nil
        let original = r.sourceId.isEmpty ? nil : app.asset(r.sourceId)
        let badge: String = switch r.kind {
        case .collage: L("edits_badge_collage")
        case .merge, .slideshow: L("edits_badge_movie")
        case .compress: L("edits_badge_resized")
        case .convert: L("edits_badge_converted")
        case .frame: L("edits_badge_frame")
        case .cutout: L("edits_badge_cutout")
        case .gif: "GIF"
        case .pdf: "PDF"
        case .edit: r.mode == .replace ? L("edits_badge_replaced") : L("edits_badge_copy")
        }
        let status: String? = if r.kind == .collage {
            LP("edits_collage_from", r.count)
        } else if !exists {
            L("edits_result_gone")
        } else if r.sourceId.isEmpty {
            nil
        } else if original != nil {
            L("edits_orig_present")
        } else {
            L("edits_orig_trashed_ios")
        }
        return Button {
            if exists { app.fullScreen = .viewer(ids: [r.newId], index: 0) }
        } label: {
            HStack(spacing: AppSpacing.s) {
                AssetThumbnail(assetID: r.newId, side: 56)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        BadgeText(text: badge, tint: r.mode == .replace ? AppColors.amber : AppColors.accentFill)
                        if r.video { Image(systemName: "video").font(.caption) }
                    }
                    Text(verbatim: DateText.longWithTime(Date(timeIntervalSince1970: Double(r.atMs) / 1000)))
                        .font(AppTypography.footnote)
                    if let status { Text(verbatim: status).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary) }
                }
                Spacer(minLength: 0)
            }
            .opacity(exists ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }
}
