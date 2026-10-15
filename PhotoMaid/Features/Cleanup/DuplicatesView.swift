import Photos
import PhotoMaidCore
import SwiftUI

/// Identische Kopien (Pro): byte-gleich per SHA-256 auf diesem iPhone. Ähnliche Bilder zählen nicht.
/// Live Photos, bearbeitete Medien und RAW+JPEG werden nicht verglichen (mehrere Ressourcen), sondern gezählt.
/// Gewählte Kopien kommen nur in den PhotoMaid-Papierkorb – nichts wird gelöscht.
/// Der Suchlauf gehört `DuplicateScanner` und läuft weiter, wenn diese Seite verlassen wird.
struct DuplicatesView: View {
    @Environment(AppModel.self) private var app
    @State private var scanner = DuplicateScanner.shared

    var body: some View {
        List {
            Section {
                Text(key: "dup_explain").font(AppTypography.subheadline)
                Text(key: "dup_how").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                if !app.capabilities.exactDuplicates {
                    PrimaryButton(title: L("pro_view")) { app.navigate(.pro) }
                } else if scanner.isRunning {
                    ProgressPanel(title: L(scanner.phase == .comparing ? "dup_checking" : "dup_measuring"),
                                  fraction: scanner.total > 0 ? Double(scanner.done) / Double(scanner.total) : nil,
                                  detail: scanner.total > 0 ? "\(scanner.done) / \(scanner.total)" : nil) { scanner.cancel() }
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("duplicates.progress")
                } else {
                    PrimaryButton(title: L(scanner.result == nil ? "dup_start" : "dup_again"), symbol: "magnifyingglass") { start() }
                }
            }
            if let result = scanner.result {
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
            if scanner.failed {
                Text(key: "error_title").foregroundStyle(AppColors.cleanup)
            }
        }
        .appPage()
        .navigationTitle(L("duplicates"))
    }

    private var selectedCount: Int { scanner.selection.values.reduce(0) { $0 + $1.count } }

    private func selectedBytes(_ r: DuplicateScanResult) -> Int64 {
        r.groups.reduce(Int64(0)) { $0 + $1.selectedBytes(scanner.selection[$1.id] ?? []) }
    }

    private func groupRow(_ g: DuplicateGroup) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(g.members, id: \.self) { m in
                    let trash = scanner.selection[g.id]?.contains(m) == true
                    Button {
                        var s = scanner.selection[g.id] ?? []
                        if trash { s.remove(m) } else { s.insert(m) }
                        // Mindestens eine Kopie bleibt immer.
                        if g.isValidSelection(s) { scanner.selection[g.id] = s }
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
        scanner.start(app: app)
    }

    private func moveSelected() async {
        let items = scanner.selection.values.flatMap { $0 }
        _ = await app.decideMany(items, .markForCleanup)
        Haptics.success()
        app.showToast(LP("dup_move", items.count), actionTitle: L("feed_view_basket")) { app.navigate(.trash) }
        scanner.clear()
    }
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
