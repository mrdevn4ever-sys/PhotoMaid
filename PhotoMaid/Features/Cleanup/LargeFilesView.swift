import PhotoMaidCore
import SwiftUI

/// Große Dateien ab der Schwelle (Einstellung): gemessene Größen; wo iOS keine Größe nennt (nur in iCloud, nicht
/// lesbar), die Schätzung aus den eigenen Messungen – immer als „ca.“ und mit iCloud-Symbol (E17), nie 0. Was noch
/// nicht gemessen ist, heißt so. Gemessen wird app-weit im Hintergrund (`SizeMeasuring`), Videos zuerst.
/// Öffnen führt in denselben Feed (Entscheidung nur per Geste).
struct LargeFilesView: View {
    @Environment(AppModel.self) private var app
    @State private var measuring = SizeMeasuring.shared
    @State private var threshold: Int = 100

    private static let choices = [25, 50, 100, 250, 500, 1000]

    private struct Entry {
        let asset: MediaAsset
        let size: SizeValue
        let inCloud: Bool
    }

    private struct Summary {
        var large: [Entry] = []
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
                if let b = r.bytes, b >= limit { s.large.append(Entry(asset: a, size: .exact(b), inCloud: false)) }
            case .notLocal, .unreadable:
                if r.state == .notLocal { s.counts.notLocal += 1 } else { s.counts.unreadable += 1 }
                let estimate = app.estimator.estimate(a.estimateInput)
                if estimate >= limit {
                    s.large.append(Entry(asset: a, size: .approximate(estimate), inCloud: r.state == .notLocal))
                }
            }
        }
        s.large.sort { $0.size.bytes > $1.size.bytes }
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
                        app.open(FeedRequest(.items(large.map(\.asset.reference), titleKey: "large_files")))
                    } label: {
                        Label(L("today_start_cta"), systemImage: "rectangle.stack")
                    }
                    ForEach(large, id: \.asset.id) { e in
                        Button {
                            let refs = large.map(\.asset.reference)
                            app.open(FeedRequest(.items(Array(refs.drop(while: { $0 != e.asset.reference })), titleKey: "large_files")))
                        } label: {
                            HStack(spacing: AppSpacing.s) {
                                AssetThumbnail(assetID: e.asset.id, side: 56)
                                VStack(alignment: .leading) {
                                    Text(verbatim: MediaInfoLine.describe(e.asset)).font(AppTypography.subheadline).lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(verbatim: SizeText.value(e.size)).font(AppTypography.headline).monospacedDigit()
                                        if e.inCloud {
                                            Image(systemName: "icloud").font(AppTypography.footnote)
                                                .foregroundStyle(AppColors.textSecondary)
                                                .accessibilityLabel(Text(key: "large_in_icloud_a11y"))
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(verbatim: SizeText.value(SizeSum(large.map(\.size)).value) + " " + LP("large_in_files", large.count))
                } footer: {
                    if large.contains(where: { $0.size.isApproximate }) { Text(key: "size_approx_note") }
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
                } footer: {
                    Text(key: "large_icloud_footer")
                }
            }
            if s.counts.unreadable > 0 {
                Section {
                    Text(verbatim: L("large_unreadable", s.counts.unreadable))
                } footer: {
                    Text(key: "large_unreadable_footer")
                }
            }
        }
        .appPage()
        .navigationTitle(L("large_files"))
        .onAppear { threshold = app.settings.largeFileThresholdMB }
        .onChange(of: threshold) { _, v in app.updateSettings { $0.largeFileThresholdMB = v } }
        .task(id: app.cleanupMedia.count) {
            measuring.ensure(openCandidates, sizer: app.sizer)
            await app.refreshSizeEstimator()
        }
    }
}
