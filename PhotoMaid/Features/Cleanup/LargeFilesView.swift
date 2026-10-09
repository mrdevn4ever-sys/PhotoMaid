import PhotoMaidCore
import SwiftUI

/// Große Dateien: nur gemessene Größen ab der Schwelle (Einstellung). Unbekannte Größen werden getrennt gezählt,
/// nie geschätzt. Öffnen führt in denselben Feed (Entscheidung nur per Geste).
struct LargeFilesView: View {
    @Environment(AppModel.self) private var app
    @State private var sizes: [String: KnownSize] = [:]
    @State private var progress: (Int, Int)?
    @State private var threshold: Int = 100

    private static let choices = [25, 50, 100, 250, 500, 1000]

    var body: some View {
        let limit = Int64(threshold) * 1_000_000
        let open = Set(app.pending.map(\.localIdentifier))
        let candidates = app.cleanupMedia.filter { open.contains($0.id) }
        let large = candidates.compactMap { a -> (MediaAsset, Int64)? in
            guard let b = sizes[a.id]?.bytes, b >= limit else { return nil }
            return (a, b)
        }.sorted { $0.1 > $1.1 }
        let unknown = candidates.filter { sizes[$0.id] != nil && sizes[$0.id]?.bytes == nil }.count
        let fileLarge = app.files.entries.filter { ($0.size.bytes ?? 0) >= limit }
        List {
            Section {
                Picker(L("large_filter"), selection: $threshold) {
                    ForEach(Self.choices, id: \.self) { Text(verbatim: SizeText.bytes(Int64($0) * 1_000_000)).tag($0) }
                }
                if let progress {
                    ProgressView(value: Double(progress.0), total: Double(max(1, progress.1))) {
                        Text(key: "col_counting").font(AppTypography.caption)
                    }
                }
            } footer: {
                Text(verbatim: L("large_footnote", threshold))
            }
            if large.isEmpty && fileLarge.isEmpty && progress == nil {
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
            if unknown > 0 {
                Section {
                    Text(verbatim: L("large_unknown_header", unknown))
                } footer: {
                    Text(key: "large_unknown_footer")
                }
            }
        }
        .appPage()
        .navigationTitle(L("large_files"))
        .onAppear { threshold = app.settings.largeFileThresholdMB }
        .onChange(of: threshold) { _, v in app.updateSettings { $0.largeFileThresholdMB = v } }
        .task(id: app.cleanupMedia.count) { await measure() }
    }

    /// Videos zuerst (meist am größten), dann Fotos. Zwischenspeicher je Medium + Änderungsdatum.
    private func measure() async {
        let open = Set(app.pending.map(\.localIdentifier))
        let list = app.cleanupMedia.filter { open.contains($0.id) }.sorted { ($0.isVideo ? 0 : 1) < ($1.isVideo ? 0 : 1) }
        var out = await app.sizer.cachedSizes(list)
        sizes = out
        progress = (0, list.count)
        var i = 0
        while i < list.count && !Task.isCancelled {
            let j = min(list.count, i + 40)
            for (k, v) in await app.sizes(Array(list[i..<j])) { out[k] = v }
            sizes = out
            progress = (j, list.count)
            i = j
        }
        progress = nil
    }
}
