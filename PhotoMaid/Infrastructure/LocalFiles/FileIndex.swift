import AVFoundation
import Foundation
import Observation
import Photos
import PhotoMaidCore

/// Inventar aller verbundenen Quellen (nur im Speicher; Quelle der Wahrheit bleibt das Dateisystem).
@MainActor
@Observable
final class FileIndex {
    private(set) var entries: [FileEntry] = []
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
        entries = all
        failedSources = failed
        scannedAt = Date()
    }
}
