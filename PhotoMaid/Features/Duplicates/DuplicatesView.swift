import Photos
import PhotoMaidCore
import SwiftUI

/// Scan exakter Duplikate: verbundene Dateien über `DuplicateFinder` (Größe → Teilhash → SHA-256),
/// Fotos/Videos über PhotoKit-Streaming nur für einfache Assets (Vorfilter: Typ, Pixelmaße, Dauer).
@MainActor
@Observable
final class DuplicateScanModel {
    private(set) var groups: [DuplicateGroup] = []
    private(set) var notComparable = 0
    private(set) var notLocal = 0
    private(set) var progress: Double = 0
    private(set) var isScanning = false
    private(set) var finishedAt: Date?
    var selection: [String: Set<ItemReference>] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(app: AppModel) {
        guard !isScanning, WorkUnitGrant.begin(requires: \.exactDuplicates, in: app.capabilities, now: Date()) != nil else { return }
        isScanning = true
        progress = 0
        // Die begonnene Arbeitseinheit läuft zu Ende, auch wenn die Vorschau währenddessen abläuft.
        task = Task { await run(app: app); isScanning = false; finishedAt = Date() }
    }

    func cancel() { task?.cancel() }

    private func run(app: AppModel) async {
        var found: [DuplicateGroup] = []
        var skipped = 0, cloud = 0

        // 1. Dateien aus verbundenen Quellen
        let index = FileIndex()
        await index.scan(app.sources)
        var roots: [ConnectedSourceID: URL] = [:]
        for s in app.sources.sources { if let u = app.sources.beginAccess(s.id) { roots[s.id] = u } }
        let entries = index.entries
        let candidates = entries.map { DuplicateCandidate(item: $0.reference, size: $0.size, aliasKey: $0.aliasKey) }
        let provider = ConnectedSourceByteProvider(roots: roots, entries: entries)
        if let r = try? await Task.detached(priority: .utility) { try DuplicateFinder().scan(candidates, source: provider) }.value {
            found += r.groups
            skipped += r.notComparable.count
        }
        for u in roots.values { app.sources.endAccess(u) }
        progress = 0.3

        // 2. Fotos/Videos: Vorfilter nach Typ/Pixelmaßen/Dauer (identische Bytes ⇒ identische Werte)
        let assets = app.photos.assets(.photos) + app.photos.assets(.videos)
        let buckets = Dictionary(grouping: assets) { "\($0.kind == .video)|\($0.pixelWidth)x\($0.pixelHeight)|\(Int($0.duration * 10))" }
            .values.filter { $0.count > 1 }
        let total = max(1, buckets.reduce(0) { $0 + $1.count })
        var done = 0
        let hasher = PhotoResourceHasher()
        for bucket in buckets {
            if Task.isCancelled { break }
            var byHash: [String: (Int64, [ItemReference])] = [:]
            for a in bucket {
                if Task.isCancelled { break }
                switch await hasher.hash(assetID: a.id) {
                case .hashed(let f): byHash[f.sha256, default: (f.bytes, [])].1.append(a.reference)
                case .notComparable: skipped += 1
                case .notLocallyAvailable: cloud += 1
                case .failed: break
                }
                done += 1
                progress = 0.3 + 0.7 * Double(done) / Double(total)
            }
            for (hash, v) in byHash where v.1.count > 1 && v.0 > 0 {
                found.append(DuplicateGroup(sha256: hash, sizeEach: v.0, members: v.1))
            }
        }
        groups = found.sorted { $0.extraCopiesBytes > $1.extraCopiesBytes }
        notComparable = skipped
        notLocal = cloud
        progress = 1
        for g in groups where selection[g.id] == nil {
            selection[g.id] = g.defaultSelection(keeping: g.members[0])
        }
    }
}

/// Screen 9 – Exakte Duplikate. Eine Kopie bleibt; andere ausdrücklich vormerken. Kein Auto-Delete.
struct DuplicatesView: View {
    @Environment(AppModel.self) private var app
    @State private var model = DuplicateScanModel()
    @State private var showPro = false

    var body: some View {
        List {
            Section {
                SurfaceCard {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: "square.on.square.fill").font(.title).foregroundStyle(.indigo).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Exakte Duplikate finden").font(AppTypography.headline)
                                if !app.capabilities.exactDuplicates {
                                    Text("Pro").font(AppTypography.caption.weight(.bold)).padding(.horizontal, 6)
                                        .background(AppColors.warning.opacity(0.2), in: .capsule)
                                }
                            }
                            Text("Byte-identische Dateien per SHA-256, auf deinem Gerät. Gleiche Vorschaubilder allein gelten nicht als Duplikat.")
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if app.capabilities.exactDuplicates {
                    if model.isScanning {
                        ProgressView(value: model.progress) { Text("Prüfe …") }
                        Button("Abbrechen", role: .cancel) { model.cancel() }
                    } else {
                        Button(model.finishedAt == nil ? "Prüfung starten" : "Erneut prüfen") { model.start(app: app) }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    Button("PhotoMaid Pro ansehen") { showPro = true }.buttonStyle(.glassProminent)
                }
            }
            ForEach(model.groups) { group in groupSection(group) }
            if model.finishedAt != nil {
                Section {
                    if model.groups.isEmpty { Text("Keine exakten Duplikate gefunden.") }
                    if model.notComparable > 0 {
                        Text("\(model.notComparable) Elemente nicht vergleichbar (z. B. Live Photos, RAW+JPEG, bearbeitete Medien).")
                    }
                    if model.notLocal > 0 {
                        Text("\(model.notLocal) Elemente nur in iCloud – nicht geprüft.")
                    }
                }
                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Duplikate"))
        .sheet(isPresented: $showPro) { NavigationStack { ProView() }.environment(app) }
        .onDisappear { model.cancel() }
    }

    private func groupSection(_ g: DuplicateGroup) -> some View {
        let sel = model.selection[g.id] ?? []
        return Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(g.members, id: \.self) { m in
                        Button { toggle(g, m) } label: {
                            ZStack(alignment: .bottomTrailing) {
                                if m.provider == .photoLibrary {
                                    ThumbnailView(assetID: m.localIdentifier).frame(width: 88, height: 88)
                                } else {
                                    VStack {
                                        Image(systemName: "doc.fill").font(.title)
                                        Text((m.localIdentifier as NSString).lastPathComponent).font(.caption2).lineLimit(2)
                                    }
                                    .frame(width: 88, height: 88).background(AppColors.backgroundTint, in: .rect(cornerRadius: 10))
                                }
                                Image(systemName: sel.contains(m) ? "trash.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(sel.contains(m) ? AppColors.cleanup : AppColors.keep)
                                    .font(.title3).padding(4)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(sel.contains(m) ? "Kopie zum Vormerken ausgewählt" : "Wird behalten"))
                    }
                }
            }
            Button("\(sel.count) Kopien vormerken") {
                Task { for m in sel { await app.decide(m, .markForCleanup) } }
            }
            .disabled(!g.isValidSelection(sel) || sel.isEmpty)
        } header: {
            Text("\(g.members.count) identische Dateien · \(SizeText.bytes(g.totalBytes)) gesamt")
        } footer: {
            Text("Zusätzliche Kopien: höchstens \(SizeText.bytes(g.selectedBytes(sel))) ausgewählt. Das ist keine garantierte Speicherersparnis. Favoriten, Alben und Bearbeitungen können trotz gleicher Bytes relevant sein.")
        }
    }

    private func toggle(_ g: DuplicateGroup, _ m: ItemReference) {
        var sel = model.selection[g.id] ?? []
        if sel.contains(m) { sel.remove(m) } else { sel.insert(m) }
        if g.isValidSelection(sel) { model.selection[g.id] = sel } // mindestens eine Kopie bleibt
    }
}
