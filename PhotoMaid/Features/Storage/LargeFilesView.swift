import PhotoMaidCore
import SwiftUI

/// Screen 8 – Große Dateien. 100 MB voreingestellt und änderbar. Bekannte Größen absteigend,
/// unbekannte Größen separat (nie als 0 behandelt).
struct LargeFilesView: View {
    @Environment(AppModel.self) private var app
    @State private var index = FileIndex()
    @State private var videoSizes: [String: KnownSize] = [:]
    @State private var videos: [MediaAsset] = []
    @State private var sort: Sort = .largest
    @State private var scanning = false
    @State private var showPro = false

    enum Sort: Hashable { case largest, newest, oldest }

    struct Row: Identifiable {
        let id: ItemReference
        let title: String
        let size: KnownSize
        let date: Date?
        let isVideo: Bool
    }

    private var thresholdBytes: Int64 { Int64(app.settings.largeFileThresholdMB) * 1_000_000 }

    private var rows: [Row] {
        var out: [Row] = index.entries.map {
            Row(id: $0.reference, title: $0.name, size: $0.size, date: $0.modified, isVideo: false)
        }
        out += videos.map { v in
            Row(id: v.reference, title: String(localized: "Video"), size: videoSizes[v.id] ?? .unknown,
                date: v.creationDate, isVideo: true)
        }
        return out
    }

    private var known: [Row] {
        let list = rows.filter { ($0.size.bytes ?? -1) >= thresholdBytes }
        switch sort {
        case .largest: return list.sorted { ($0.size.bytes ?? 0) > ($1.size.bytes ?? 0) }
        case .newest: return list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .oldest: return list.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        }
    }

    private var unknown: [Row] { rows.filter { $0.size == .unknown } }

    var body: some View {
        List {
            Section {
                let tally = SizeTally(known.map(\.size))
                MetricCard(value: SizeText.tally(tally),
                           caption: Text("in \(known.count) großen Dateien"),
                           footnote: Text("Nur Dateien mit bekannter Größe ab \(app.settings.largeFileThresholdMB) MB. Kein Versprechen über freiwerdenden Speicher."))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                Stepper(value: Binding(get: { app.settings.largeFileThresholdMB },
                                       set: { v in app.updateSettings { $0.largeFileThresholdMB = v } }),
                        in: 10...5000, step: 50) {
                    Text("Filter: ab \(app.settings.largeFileThresholdMB) MB")
                }
                Picker("Sortierung", selection: $sort) {
                    Text("Größte").tag(Sort.largest)
                    Text("Neueste").tag(Sort.newest)
                    Text("Älteste").tag(Sort.oldest)
                }
                .pickerStyle(.segmented)
            }
            Section("Bekannte Größe") {
                ForEach(known) { row($0) }
                if known.isEmpty && !scanning { Text("Keine Dateien über dem Filterwert gefunden.").foregroundStyle(AppColors.textSecondary) }
            }
            if !unknown.isEmpty {
                Section {
                    ForEach(unknown.prefix(200)) { row($0) }
                } header: {
                    Text("Größe unbekannt (\(unknown.count))")
                } footer: {
                    Text("Z. B. Videos, die nur in iCloud liegen. PhotoMaid lädt sie nicht herunter.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Große Dateien"))
        .overlay { if scanning { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        scanning = true
        defer { scanning = false }
        await index.scan(app.sources)
        videos = app.photos.assets(.videos)
        // Videogrößen über öffentliche API, begrenzt und abbrechbar.
        for v in videos where videoSizes[v.id] == nil {
            if Task.isCancelled { break }
            videoSizes[v.id] = await VideoSizeProbe.size(assetID: v.id)
        }
    }

    private func row(_ r: Row) -> some View {
        HStack(spacing: AppSpacing.s) {
            if r.isVideo { ThumbnailView(assetID: r.id.localIdentifier).frame(width: 52, height: 52) }
            else { Image(systemName: "doc.fill").font(.title2).frame(width: 52, height: 52).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(AppTypography.subheadline.weight(.semibold)).lineLimit(1)
                if let d = r.date { Text(d.formatted(date: .abbreviated, time: .omitted)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary) }
            }
            Spacer()
            SizeText.size(r.size).font(AppTypography.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .swipeActions(allowsFullSwipe: false) {
            Button("Vormerken") { Task { await app.decide(r.id, .markForCleanup) } }.tint(AppColors.cleanup)
            Button("Behalten") { Task { await app.decide(r.id, .keep) } }.tint(AppColors.keep)
        }
    }
}

/// Screen 10 – Speicherübersicht. A: Gerät, B: erfasste Quellen, C: nicht einsehbar (nur textlich).
struct StorageInsightsView: View {
    @Environment(AppModel.self) private var app
    @State private var device: DeviceCapacity?
    @State private var counts: [MediaCategory: Int] = [:]
    @State private var index = FileIndex()

    var body: some View {
        List {
            Section {
                if let d = device {
                    MetricCard(value: Text(SizeText.bytes(d.usedBytes)),
                               caption: Text("von \(SizeText.bytes(d.totalBytes)) belegt"),
                               progress: d.totalBytes > 0 ? Double(d.usedBytes) / Double(d.totalBytes) : nil,
                               footnote: Text("\(SizeText.bytes(d.availableForImportantUsageBytes)) verfügbar (Systemwert)"))
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                } else {
                    Text("Gerätespeicher nicht verfügbar").foregroundStyle(AppColors.textSecondary)
                }
            } header: { Text("A · Gerät") }

            Section {
                row("photo", "Fotos", Text("\(counts[.photos] ?? 0) Elemente"))
                row("camera.viewfinder", "davon Screenshots", Text("\(counts[.screenshots] ?? 0) Elemente"))
                row("video.fill", "Videos", Text("\(counts[.videos] ?? 0) Elemente"))
                row("folder.fill", "Verbundene Ordner", SizeText.tally(SizeTally(index.entries.map(\.size))))
            } header: {
                Text("B · Für PhotoMaid sichtbar")
            } footer: {
                Text("Screenshots sind eine Teilmenge der Fotos. Große Dateien und Duplikate sind überlappende Ansichten und werden nicht addiert. Mediengrößen sind ohne vollständiges Einlesen nicht bekannt und werden deshalb nicht geschätzt.")
            }

            Section {
                Text("Andere Apps, System, iCloud-Inhalte und nicht freigegebene Ordner kann PhotoMaid nicht einsehen. Dafür zeigen wir bewusst keine Zahl.")
                    .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
            } header: { Text("C · Nicht einsehbar") }

            Section {
                Label("Alle Analysen laufen auf deinem Gerät.", systemImage: "checkmark.shield")
                    .foregroundStyle(AppColors.accent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Speicherübersicht"))
        .task {
            device = DeviceStorage.read()
            for c in MediaCategory.allCases { counts[c] = app.photos.count(c) }
            await index.scan(app.sources)
        }
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            value.foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
