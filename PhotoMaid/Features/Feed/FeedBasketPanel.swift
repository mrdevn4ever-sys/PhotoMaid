import PhotoMaidCore
import SwiftUI

/// Live, reversible PhotoMaid basket beside the feed. Permanent cleanup stays in the existing confirmation flow.
struct FeedBasketPanel: View {
    @Environment(AppModel.self) private var app
    let openTrash: () -> Void

    private var photos: [MediaAsset] {
        let items = app.read.basket.filter { $0.item.provider == .photoLibrary }
        let ids = Set(items.map { $0.item.localIdentifier })
        var marked: [String: Date] = [:]
        for event in app.read.events where event.to.disposition == .markedForCleanup && ids.contains(event.item.localIdentifier) {
            marked[event.item.localIdentifier] = max(marked[event.item.localIdentifier] ?? .distantPast, event.at)
        }
        return app.visibleMedia.filter { ids.contains($0.id) }.sorted {
            (marked[$0.id] ?? .distantPast) > (marked[$1.id] ?? .distantPast)
        }.prefix(40).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Label(L("feed_view_basket"), systemImage: "trash").font(AppTypography.headline)
                Spacer()
                Text(verbatim: CountText.number(app.read.basket.count)).font(AppTypography.metricSmall)
            }
            Text(key: "basket_intro").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            ScrollView {
                if photos.isEmpty {
                    Image(systemName: "tray").font(.largeTitle).foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.xxl)
                }
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppSpacing.s) {
                    ForEach(photos) { asset in
                        VStack(spacing: AppSpacing.xxs) {
                            Button(action: openTrash) {
                                AssetCell(assetID: asset.id).aspectRatio(1, contentMode: .fit)
                                    .clipShape(.rect(cornerRadius: AppRadii.small))
                            }
                            .buttonStyle(.plain).accessibilityLabel(Text(verbatim: MediaInfoLine.describe(asset)))
                            Button { Task { await app.decide(asset.reference, .unmark) } } label: {
                                Label(L("put_back"), systemImage: "arrow.uturn.backward")
                                    .font(AppTypography.caption).frame(minHeight: AppSpacing.minTouch)
                            }
                            .buttonStyle(.plain).tint(AppColors.accent)
                        }
                    }
                }
            }
            Button(action: openTrash) { Label(L("feed_view_basket"), systemImage: "arrow.up.forward.app") }
                .buttonStyle(.glassProminent).frame(maxWidth: .infinity)
        }
        .padding(AppSpacing.m)
        .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
        .accessibilityIdentifier("feed.basketPanel")
    }
}
