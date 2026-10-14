import PhotoMaidCore
import SwiftUI

/// Speicherübersicht: A Gerät (Systemwerte), B für PhotoMaid sichtbar (gemessen, „mind.“ bei Unbekanntem),
/// C nicht sichtbar (keine Größe behauptet). Bleibt auf dem Gerät.
struct StorageView: View {
    @Environment(AppModel.self) private var app
    @State private var device: DeviceCapacity?
    @State private var measuring = SizeMeasuring.shared

    var body: some View {
        let tallies = currentTallies()
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
                if measuring.running && measuring.total > 0 {
                    ProgressView(value: Double(measuring.done), total: Double(max(1, measuring.total))) {
                        Text(verbatim: L("large_measuring", measuring.done, measuring.total)).font(AppTypography.caption)
                            .monospacedDigit()
                    }
                }
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
            // App-weiter Mess-Auftrag: parallel, Videos zuerst, läuft weiter, wenn diese Seite verlassen wird.
            measuring.ensure(app.visibleMedia, sizer: app.sizer)
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

    /// Summen aus den Messungen. Noch nicht Gemessenes zählt wie Unbekanntes: die Summe heißt dann „mind.“ –
    /// nie geschätzt, nie 0.
    private func currentTallies() -> [StorageCategory: SizeTally] {
        var photos = SizeTally(), videos = SizeTally(), screens = SizeTally()
        let records = measuring.records
        for a in app.visibleMedia {
            let s = records[a.id].flatMap { $0.isCurrent(modified: a.modificationDate) ? $0.size : nil } ?? .unknown
            if a.isVideo { videos.add(s) } else { photos.add(s) }
            if a.kind == .screenshot { screens.add(s) }
        }
        return [.photos: photos, .videos: videos, .screenshots: screens,
                .connectedFiles: SizeTally(app.files.entries.map(\.size))]
    }
}
