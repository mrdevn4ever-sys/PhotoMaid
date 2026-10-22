import PhotoMaidCore
import SwiftUI

/// Alle offenen Fotoserien (Pro): gleiche Art, höchstens 10 s Abstand, mindestens 3 – nur „kurz hintereinander
/// aufgenommen“. Erst „n behalten · m in den Papierkorb“ entscheidet (ein Befehl je Medium).
struct SeriesListView: View {
    @Environment(AppModel.self) private var app
    @State private var series: [[MediaAsset]]?
    @State private var open: SeriesSelection?

    struct SeriesSelection: Identifiable {
        let members: [MediaAsset]
        var id: String { members.map(\.id).joined(separator: ",") }
    }

    var body: some View {
        List {
            Section {
                Text(key: "tour_series_text").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                if !app.capabilities.seriesCompare {
                    PrimaryButton(title: L("pro_view")) { app.navigate(.pro) }
                }
            }
            if let series {
                if series.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: L("qa_all_done"), message: L("feed_empty_message"))
                        .listRowBackground(Color.clear)
                }
                ForEach(series, id: \.first!.id) { members in
                    Button {
                        if app.capabilities.seriesCompare { open = SeriesSelection(members: members) } else { app.navigate(.pro) }
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack(spacing: 2) {
                                ForEach(members.prefix(5)) { AssetThumbnail(assetID: $0.id, side: 56, cornerRadius: 4) }
                            }
                            Text(verbatim: [members.first?.creationDate.map(DateText.longWithTime), L("series_subtitle", members.count)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProgressView()
            }
        }
        .appPage()
        .navigationTitle(L("series_title"))
        .task(id: app.tabRecountKey("\(app.pending.count)-\(app.cleanupMedia.count)")) {
            guard !app.tabsCoveredByFeed else { return }
            await load()
        }
        .sheet(item: $open) { sel in
            SeriesCompareView(members: sel.members) { keep in Task { await confirm(sel.members, keep) } }
        }
    }

    private func load() async {
        let pending = Set(app.pending.map(\.localIdentifier))
        let media = app.cleanupMedia.filter { !$0.isVideo && pending.contains($0.id) }
        series = await Task.detached(priority: .userInitiated) { () -> [[MediaAsset]] in
            let byID = Dictionary(media.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let members = media.map { PhotoSeries.Member(id: $0.id, group: $0.kind == .screenshot ? "screenshots" : "camera",
                                                         takenAt: $0.creationDate) }
            return PhotoSeries.groups(members).map { g in g.compactMap { byID[$0.id] } }.filter { $0.count >= PhotoSeries.minSize }
        }.value
    }

    private func confirm(_ members: [MediaAsset], _ keep: Set<String>) async {
        let kept = members.filter { keep.contains($0.id) }.map(\.reference)
        let trash = members.filter { !keep.contains($0.id) }.map(\.reference)
        _ = await app.decideMany(kept, .keep)
        _ = await app.decideMany(trash, .markForCleanup)
        Haptics.success()
        app.showToast(L("series_done", kept.count, trash.count))
    }
}
