import Photos
import PhotoMaidCore
import SwiftUI

/// Identische Kopien (Pro): byte-gleich per SHA-256 auf diesem iPhone. Ähnliche Bilder zählen nicht.
/// Live Photos, bearbeitete Medien und RAW+JPEG werden nicht verglichen (mehrere Ressourcen), sondern gezählt.
/// Gewählte Kopien kommen nur in den PhotoMaid-Papierkorb – nichts wird gelöscht.
struct DuplicatesView: View {
    @Environment(AppModel.self) private var app
    @State private var result: DuplicateScanResult?
    @State private var progress: DuplicateScanProgress?
    @State private var selection: [String: Set<ItemReference>] = [:]
    @State private var scanTask: Task<Void, Never>?
    @State private var failed = false

    var body: some View {
        List {
            Section {
                Text(key: "dup_explain").font(AppTypography.subheadline)
                Text(key: "dup_how").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                if !app.capabilities.exactDuplicates {
                    PrimaryButton(title: L("pro_view")) { app.navigate(.pro) }
                } else if progress != nil {
                    ProgressPanel(title: L("dup_checking"), fraction: progress.map { Double($0.processed) / Double(max(1, $0.total)) },
                                  detail: progress.map { "\($0.processed) / \($0.total)" }) { scanTask?.cancel() }
                        .listRowBackground(Color.clear)
                } else {
                    PrimaryButton(title: L(result == nil ? "dup_start" : "dup_again"), symbol: "magnifyingglass") { start() }
                }
            }
            if let result {
                if result.groups.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: L("dup_none"), message: L("dup_none_message"))
                        .listRowBackground(Color.clear)
                } else {
                    let total = result.groups.reduce(Int64(0)) { $0 + $1.extraCopiesBytes }
                    Section {
                        ForEach(result.groups) { group in groupRow(group) }
                    } header: {
                        Text(verbatim: L("dup_header", result.groups.reduce(0) { $0 + $1.members.count }, SizeText.bytes(total)))
                    } footer: {
                        Text(verbatim: L("dup_footer", SizeText.bytes(selectedBytes(result))))
                    }
                    Section {
                        PrimaryButton(title: LP("dup_move", selectedCount), role: .destructive) { Task { await moveSelected() } }
                            .disabled(selectedCount == 0)
                            .listRowBackground(Color.clear)
                    }
                }
                if !result.notComparable.isEmpty || !result.notChecked.isEmpty {
                    Section {
                        if !result.notComparable.isEmpty { Text(verbatim: LP("dup_not_comparable", result.notComparable.count)) }
                        if !result.notChecked.isEmpty { Text(verbatim: LP("dup_not_local", result.notChecked.count)) }
                    }
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                }
            }
            if failed {
                Text(key: "error_title").foregroundStyle(AppColors.cleanup)
            }
        }
        .appPage()
        .navigationTitle(L("duplicates"))
        .onDisappear { scanTask?.cancel() }
    }

    private var selectedCount: Int { selection.values.reduce(0) { $0 + $1.count } }

    private func selectedBytes(_ r: DuplicateScanResult) -> Int64 {
        r.groups.reduce(Int64(0)) { $0 + $1.selectedBytes(selection[$1.id] ?? []) }
    }

    private func groupRow(_ g: DuplicateGroup) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(g.members, id: \.self) { m in
                    let trash = selection[g.id]?.contains(m) == true
                    Button {
                        var s = selection[g.id] ?? []
                        if trash { s.remove(m) } else { s.insert(m) }
                        // Mindestens eine Kopie bleibt immer.
                        if g.isValidSelection(s) { selection[g.id] = s }
                    } label: {
                        VStack(spacing: 4) {
                            if m.provider == .photoLibrary {
                                AssetThumbnail(assetID: m.localIdentifier, side: 72)
                            } else {
                                Image(systemName: "doc").font(.title).frame(width: 72, height: 72)
                            }
                            Text(key: trash ? "dup_selected_trash" : "dup_will_keep")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(trash ? AppColors.cleanup : AppColors.success)
                        }
                        .opacity(trash ? 0.7 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(Text(key: trash ? "dup_selected_trash" : "dup_will_keep"))
                }
            }
        }
    }

    private func start() {
        guard WorkUnitGrant.begin(requires: \.exactDuplicates, in: app.capabilities, now: Date()) != nil else {
            app.navigate(.pro)
            return
        }
        failed = false
        let media = app.cleanupMedia
        let files = app.files.entries
        progress = DuplicateScanProgress(processed: 0, total: 1)
        scanTask = Task {
            let sizes = await app.sizes(media)
            let candidates = await Task.detached(priority: .userInitiated) { () -> [DuplicateCandidate] in
                var out: [DuplicateCandidate] = []
                for a in media {
                    guard let asset = PhotoLibraryService.phAsset(a.id) else { continue }
                    let comparable = PHAssetResource.assetResources(for: asset).count == 1
                    out.append(DuplicateCandidate(item: a.reference, size: sizes[a.id] ?? .unknown, isComparable: comparable))
                }
                for f in files { out.append(DuplicateCandidate(item: f.reference, size: f.size, aliasKey: f.aliasKey)) }
                return out
            }.value
            let provider = CombinedByteProvider(photos: app.bytes, files: app.files.entries, sources: app.sources)
            let reporter = ProgressReporter()
            let watch = Task { @MainActor in
                while !Task.isCancelled {
                    if let p = reporter.latest { progress = p }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let scanned: DuplicateScanResult? = await Task.detached(priority: .userInitiated) {
                try? DuplicateFinder().scan(candidates, source: provider) { reporter.set($0) }
            }.value
            watch.cancel()
            provider.close()
            progress = nil
            guard !Task.isCancelled else { return }
            if let scanned {
                result = scanned
                // Vorauswahl: die älteste Kopie bleibt, die übrigen sind für den Papierkorb gewählt.
                var sel: [String: Set<ItemReference>] = [:]
                for g in scanned.groups {
                    let keep = g.members.min { (app.asset($0.localIdentifier)?.creationDate ?? .distantFuture) < (app.asset($1.localIdentifier)?.creationDate ?? .distantFuture) } ?? g.members[0]
                    sel[g.id] = g.defaultSelection(keeping: keep)
                }
                selection = sel
            } else {
                failed = true
            }
        }
    }

    private func moveSelected() async {
        let items = selection.values.flatMap { $0 }
        _ = await app.decideMany(items, .markForCleanup)
        Haptics.success()
        app.showToast(LP("dup_move", items.count), actionTitle: L("feed_view_basket")) { app.navigate(.trash) }
        selection = [:]
        result = nil
    }
}

/// Fortschritt aus dem Hintergrund-Scan an die Oberfläche geben.
final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: DuplicateScanProgress?
    func set(_ p: DuplicateScanProgress) { lock.withLock { value = p } }
    var latest: DuplicateScanProgress? { lock.withLock { value } }
}

/// Fotos über PhotoKit-Ressourcen, Dateien über die verbundenen Ordner (Zugriff wird für die Dauer geöffnet).
final class CombinedByteProvider: ByteSourceProvider, @unchecked Sendable {
    private let photos: PhotoResourceByteProvider
    private let files: ConnectedSourceByteProvider
    private let openRoots: [URL]

    @MainActor
    init(photos: PhotoResourceByteProvider, files entries: [FileEntry], sources: ConnectedSourceStore) {
        self.photos = photos
        var roots: [ConnectedSourceID: URL] = [:]
        for s in sources.sources { if let url = sources.beginAccess(s.id) { roots[s.id] = url } }
        openRoots = Array(roots.values)
        files = ConnectedSourceByteProvider(roots: roots, entries: entries)
        self.sourcesRef = sources
    }

    private weak var sourcesRef: ConnectedSourceStore?

    func openStream(for item: ItemReference) throws -> (any ByteStream)? {
        item.provider == .photoLibrary ? try photos.openStream(for: item) : try files.openStream(for: item)
    }

    @MainActor
    func close() {
        for url in openRoots { sourcesRef?.endAccess(url) }
    }
}
