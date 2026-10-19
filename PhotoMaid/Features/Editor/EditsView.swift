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
            ForEach(records) { r in row(r) }
        }
        .appPage()
        .navigationTitle(L("edits_title"))
        .task(id: app.library.changeToken) {
            records = VaultConcealment.shared.visible(app.kv?.get(StoreKeys.edits) ?? []) { $0.newId }
        }
        .onReceive(NotificationCenter.default.publisher(for: .analysisVisibilityChanged)) { _ in
            records = VaultConcealment.shared.visible(records) { $0.newId }
        }
    }

    private func row(_ r: EditRecord) -> some View {
        let exists = app.asset(r.newId) != nil
        let original = r.sourceId.isEmpty ? nil : app.asset(r.sourceId)
        let badge: String = switch r.kind {
        case .collage: L("edits_badge_collage")
        default: r.mode == .replace ? L("edits_badge_replaced") : L("edits_badge_copy")
        }
        let status: String? = if r.kind == .collage {
            LP("edits_collage_from", r.count)
        } else if r.sourceId.isEmpty || VaultConcealment.shared.isConcealed(r.sourceId) {
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
