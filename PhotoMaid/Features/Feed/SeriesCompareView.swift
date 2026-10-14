import PhotoMaidCore
import SwiftUI

/// Fotoserie vergleichen (Pro): kurz hintereinander aufgenommen – nie „ähnlich“ oder „bestes Foto“.
/// Erst „n behalten · m in den Papierkorb“ entscheidet (ein Befehl je Medium). Nichts wird gelöscht.
/// Auch für „Ähnliche Aufnahmen“ aus der Analyse (eigener Titel/Untertitel, ebenfalls nie „bestes Foto“).
struct SeriesCompareView: View {
    let members: [MediaAsset]
    let title: String
    let subtitle: String
    let confirm: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keep: Set<String>
    @State private var focus: String

    init(members: [MediaAsset], title: String? = nil, subtitle: String? = nil, confirm: @escaping (Set<String>) -> Void) {
        self.members = members
        self.title = title ?? L("series_title")
        self.subtitle = subtitle ?? L("series_subtitle", members.count)
        self.confirm = confirm
        _keep = State(initialValue: Set(members.map(\.id)))
        _focus = State(initialValue: members.first?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.s) {
                Text(verbatim: subtitle)
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                ZStack {
                    AppColors.stage
                    LargePreview(assetID: focus)
                }
                .clipShape(.rect(cornerRadius: AppRadii.card))
                .frame(maxHeight: .infinity)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(members) { a in
                            let kept = keep.contains(a.id)
                            Button { focus = a.id } label: {
                                AssetThumbnail(assetID: a.id, side: 76)
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            if kept { keep.remove(a.id) } else { keep.insert(a.id) }
                                        } label: {
                                            Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(kept ? AppColors.accentFill : .white)
                                                .background(Circle().fill(.black.opacity(0.35)))
                                                .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(Text(key: "series_keep_toggle"))
                                        .accessibilityValue(Text(key: kept ? "series_state_keep" : "series_state_trash"))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: AppRadii.thumb)
                                            .strokeBorder(focus == a.id ? AppColors.accent : .clear, lineWidth: 3)
                                    }
                                    .opacity(kept ? 1 : 0.55)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                Text(key: "series_hint").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: L("series_confirm", keep.count, members.count - keep.count)) {
                    confirm(keep)
                    dismiss()
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                Text(key: "series_footer").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, AppSpacing.pageMargin)
            }
            .padding(.vertical, AppSpacing.s)
            .background(AppBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } } }
        }
    }
}

/// Großes, eingepasstes Vorschaubild (nur lokal vorhandene Daten).
struct LargePreview: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var scale
    let assetID: String
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: assetID) {
                let size = PreviewPipeline.targetSize(for: geo.size, scale: scale)
                if case .image(let img) = await app.previews.image(for: assetID, targetSize: size) {
                    image = img
                } else {
                    image = await ThumbnailLoader.shared.image(assetID, size: CGSize(width: 600, height: 600))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
