import PhotoMaidCore
import SwiftUI

/// Speicherübersicht: A Gerät (Systemwerte), B für PhotoMaid sichtbar (gemessen, „mind.“ bei Unbekanntem),
/// C nicht sichtbar (keine Größe behauptet). Bleibt auf dem Gerät.
struct StorageView: View {
    @Environment(AppModel.self) private var app
    @State private var device: DeviceCapacity?
    @State private var tallies: [StorageCategory: SizeTally] = [:]
    @State private var measuring = false

    var body: some View {
        List {
            Section(L("storage_a")) {
                if let d = device {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(verbatim: SizeText.bytes(d.usedBytes)).font(AppTypography.metric)
                        Text(verbatim: L("storage_used_of", SizeText.bytes(d.totalBytes))).font(AppTypography.footnote)
                        ProgressView(value: d.totalBytes > 0 ? Double(d.usedBytes) / Double(d.totalBytes) : 0)
                        Text(verbatim: L("storage_available", SizeText.bytes(d.availableForImportantUsageBytes)))
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(key: "storage_unavailable")
                }
            }
            Section {
                row("photo", L("cat_photos"), tallies[.photos])
                row("camera.viewfinder", L("storage_of_which_screens"), tallies[.screenshots], indent: true)
                row("video", L("cat_videos"), tallies[.videos])
                if !app.sources.sources.isEmpty { row("folder", L("storage_connected_folders"), tallies[.connectedFiles]) }
                if measuring { ProgressView() }
            } header: {
                Text(key: "storage_b")
            } footer: {
                Text(key: "storage_b_footer")
            }
            Section(L("storage_c")) {
                Text(key: "storage_c_text").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
            Section {
                Label(L("storage_local"), systemImage: "lock.shield").font(AppTypography.footnote)
            }
        }
        .appPage()
        .navigationTitle(L("storage_overview"))
        .task {
            device = DeviceStorage.read()
            await measure()
        }
    }

    private func row(_ symbol: String, _ title: String, _ t: SizeTally?, indent: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: symbol).padding(.leading, indent ? AppSpacing.l : 0)
            Spacer()
            if let t {
                Text(verbatim: LP("storage_value_items", t.totalCount, t.totalCount, SizeText.tally(t)))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary).monospacedDigit()
            }
        }
        .frame(minHeight: AppSpacing.minTouch)
    }

    private func measure() async {
        measuring = true
        defer { measuring = false }
        let media = app.visibleMedia
        var sizes = await app.sizer.cachedSizes(media)
        publish(media, sizes)
        var i = 0
        while i < media.count && !Task.isCancelled {
            let j = min(media.count, i + 60)
            for (k, v) in await app.sizes(Array(media[i..<j])) { sizes[k] = v }
            publish(media, sizes)
            i = j
        }
    }

    private func publish(_ media: [MediaAsset], _ sizes: [String: KnownSize]) {
        var photos = SizeTally(), videos = SizeTally(), screens = SizeTally()
        for a in media {
            let s = sizes[a.id] ?? .unknown
            if a.isVideo { videos.add(s) } else { photos.add(s) }
            if a.kind == .screenshot { screens.add(s) }
        }
        tallies[.photos] = photos
        tallies[.videos] = videos
        tallies[.screenshots] = screens
        tallies[.connectedFiles] = SizeTally(app.files.entries.map(\.size))
    }
}
