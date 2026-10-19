import AVFoundation
import Foundation
import Observation
import Photos
import PhotoMaidCore

/// Inventar aller verbundenen Quellen (nur im Speicher; Quelle der Wahrheit bleibt das Dateisystem).
@MainActor
@Observable
final class FileIndex {
    /// Ohne Dateien, die im Tresor liegen (E16).
    private(set) var entries: [FileEntry] = []
    /// Dateien im Tresor, deren Original noch in einem verbundenen Ordner liegt (nur zum Ausfiltern).
    private(set) var concealedReferences: Set<ItemReference> = []
    @ObservationIgnored private var all: [FileEntry] = []
    private(set) var isScanning = false
    private(set) var failedSources: [ConnectedSourceID] = []
    private(set) var scannedAt: Date?

    func scan(_ sources: ConnectedSourceStore) async {
        isScanning = true
        defer { isScanning = false }
        var all: [FileEntry] = []
        var failed: [ConnectedSourceID] = []
        for source in sources.sources {
            guard let root = sources.beginAccess(source.id) else { failed.append(source.id); continue }
            let id = source.id
            let result = await Task.detached(priority: .userInitiated) { try? FileScanner.scan(root: root, sourceID: id) }.value
            sources.endAccess(root)
            if let result { all.append(contentsOf: result) } else { failed.append(source.id) }
            if Task.isCancelled { break }
        }
        self.all = all
        applyConcealment()
        failedSources = failed
        scannedAt = Date()
    }

    /// Nach Änderungen am Tresor: Dateien im Tresor nicht zeigen, auch wenn das Original im verbundenen Ordner liegt.
    func applyConcealment() {
        let concealment = VaultConcealment.shared
        // An unidentified provider file cannot prove it is outside an existing private projection.
        let identifiable = concealment.isEmpty ? all : all.filter { $0.aliasKey != nil }
        let visible = concealment.visible(identifiable) { $0.aliasKey.map(VaultSnapshot.fileConcealmentKey) ?? "" }
        let hidden = visible.count == all.count ? [] : Set(all.map(\.reference)).subtracting(visible.map(\.reference))
        if visible != entries { entries = visible }
        if hidden != concealedReferences { concealedReferences = hidden }
    }
}
