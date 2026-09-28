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

/// Größe lokaler Videos über öffentliche API (AVURLAsset → Dateigröße), ohne Netzwerk.
/// Nicht lokal verfügbare Videos bleiben „Größe unbekannt“.
enum VideoSizeProbe {
    static func size(assetID: String) async -> KnownSize {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return .unknown }
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = false
        o.version = .original
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: o) { @Sendable av, _, _ in
                guard let url = (av as? AVURLAsset)?.url,
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    cont.resume(returning: .unknown); return
                }
                cont.resume(returning: .known(Int64(size)))
            }
        }
    }
}
