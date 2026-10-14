import PhotoMaidCore
import SwiftUI

/// Große Dateien: nur gemessene Größen ab der Schwelle (Einstellung). Was noch nicht gemessen ist, heißt so – nicht
/// „unbekannt“. Unbekannt wird nach Grund getrennt gezeigt: nur in iCloud (iOS nennt die Größe ohne Download nicht) oder
/// nicht lesbar – nie geschätzt, nie 0. Gemessen wird app-weit im Hintergrund (`SizeMeasuring`), Videos zuerst.
/// Öffnen führt in denselben Feed (Entscheidung nur per Geste).
struct LargeFilesView: View {
    @Environment(AppModel.self) private var app
    @State private var measuring = SizeMeasuring.shared
    @State private var threshold: Int = 100

    private static let choices = [25, 50, 100, 250, 500, 1000]

    private struct Summary {
        var large: [(MediaAsset, Int64)] = []
        var cloudVideos: [MediaAsset] = []
        var counts = SizeCounts()
    }

    private var openCandidates: [MediaAsset] {
        let open = Set(app.pending.map(\.localIdentifier))
        return app.cleanupMedia.filter { open.contains($0.id) }
    }

    private func summarize(_ candidates: [MediaAsset], limit: Int64) -> Summary {
        var s = Summary()
        let records = measuring.records
        for a in candidates {
            guard let r = records[a.id], r.isCurrent(modified: a.modificationDate) else { s.counts.notMeasured += 1; continue }
            switch r.state {
            case .known:
                s.counts.known += 1
                if let b = r.bytes, b >= limit { s.large.append((a, b)) }
            case .notLocal:
                s.counts.notLocal += 1
                if a.isVideo { s.cloudVideos.append(a) }
            case .unreadable:
                s.counts.unreadable += 1
            }
        }
        s.large.sort { $0.1 > $1.1 }
        s.cloudVideos.sort { $0.duration > $1.duration }
        return s
    }

    var body: some View {
        let limit = Int64(threshold) * 1_000_000
        let s = summarize(openCandidates, limit: limit)
        let large = s.large
        let fileLarge = app.files.entries.filter { ($0.size.bytes ?? 0) >= limit }
        List {
            Section {
                Picker(L("large_filter"), selection: $threshold) {
                    ForEach(Self.choices, id: \.self) { Text(verbatim: SizeText.bytes(Int64($0) * 1_000_000)).tag($0) }
                }
                if measuring.running && measuring.total > 0 {
                    ProgressView(value: Double(measuring.done), total: Double(max(1, measuring.total))) {
                        Text(verbatim: L("large_measuring", measuring.done, measuring.total)).font(AppTypography.caption)
                            .monospacedDigit()
                    }
                } else if s.counts.notMeasured > 0 {
                    Button { measuring.ensure(openCandidates, sizer: app.sizer) } label: {
                        Label(L("large_measure_resume", s.counts.notMeasured), systemImage: "arrow.clockwise")
                    }
                }
            } footer: {
                Text(verbatim: L("large_footnote", threshold))
            }
            if large.isEmpty && fileLarge.isEmpty && !measuring.running && s.counts.notMeasured == 0 {
                EmptyState(symbol: "doc.badge.arrow.up", title: L("large_none"), message: L("large_none_message", threshold))
                    .listRowBackground(Color.clear)
            }
            if !large.isEmpty {
                Section {
                    Button {
                        app.open(FeedRequest(.items(large.map(\.0.reference), titleKey: "large_files")))
                    } label: {
                        Label(L("today_start_cta"), systemImage: "rectangle.stack")
                    }
                    ForEach(large, id: \.0.id) { a, bytes in
                        Button {
                            let refs = large.map(\.0.reference)
                            app.open(FeedRequest(.items(Array(refs.drop(while: { $0 != a.reference })), titleKey: "large_files")))
                        } label: {
                            HStack(spacing: AppSpacing.s) {
                                AssetThumbnail(assetID: a.id, side: 56)
                                VStack(alignment: .leading) {
                                    Text(verbatim: MediaInfoLine.describe(a)).font(AppTypography.subheadline).lineLimit(1)
                                    Text(verbatim: SizeText.bytes(bytes)).font(AppTypography.headline).monospacedDigit()
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    let total = large.reduce(Int64(0)) { $0 + $1.1 }
                    Text(verbatim: SizeText.bytes(total) + " " + LP("large_in_files", large.count))
                }
            }
            if !fileLarge.isEmpty {
                Section(L("files")) {
                    ForEach(fileLarge) { f in
                        HStack {
                            Image(systemName: "doc").foregroundStyle(AppColors.textSecondary)
                            Text(verbatim: f.name).lineLimit(1)
                            Spacer()
                            Text(verbatim: SizeText.size(f.size)).monospacedDigit()
                        }
                    }
                }
            }
            if s.counts.notLocal > 0 {
                Section {
                    Text(verbatim: L("large_icloud_header", s.counts.notLocal))
                    if !s.cloudVideos.isEmpty {
                        // Nach Länge, nicht nach Größe: die Größe ist unbekannt und wird nicht geschätzt.
                        Button {
                            app.open(FeedRequest(.items(s.cloudVideos.map(\.reference), titleKey: "large_files")))
                        } label: {
                            Label(L("large_icloud_videos", s.cloudVideos.count), systemImage: "video")
                        }
                    }
                } footer: {
                    Text(key: "large_icloud_footer")
                }
            }
            if s.counts.unreadable > 0 {
                Section {
                    Text(verbatim: L("large_unreadable", s.counts.unreadable))
                } footer: {
                    Text(key: "large_unknown_footer")
                }
            }
        }
        .appPage()
        .navigationTitle(L("large_files"))
        .onAppear { threshold = app.settings.largeFileThresholdMB }
        .onChange(of: threshold) { _, v in app.updateSettings { $0.largeFileThresholdMB = v } }
        .task(id: app.cleanupMedia.count) { measuring.ensure(openCandidates, sizer: app.sizer) }
    }
}
