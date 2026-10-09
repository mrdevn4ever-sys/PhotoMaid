import AVFoundation
import Foundation
import Photos
import PhotoMaidCore

/// Misst Mediengrößen nur über öffentliche APIs:
/// - Videos: Datei des lokalen Originals (`requestAVAsset` → `URLResourceValues.fileSize`), plus übrige Ressourcen.
/// - Fotos: Bytes aller lokalen Ressourcen per `PHAssetResourceManager.requestData` (Original, Bearbeitung, Live-Video,
///   RAW) – dasselbe, was „Löschen“ auf diesem Gerät frei machen kann.
/// Nicht lokal vorhanden (iCloud „Speicher optimieren“) oder Fehler → `.unknown`, nie 0, nie geschätzt.
/// Ergebnisse werden je Medium + Änderungsdatum zwischengespeichert (`StoreKeys.sizeCache`, nur lokal).
actor MediaSizer {
    private var cache: [String: SizeCacheEntry]
    private var dirty = false
    private let persist: @Sendable ([String: SizeCacheEntry]) async -> Void

    init(initial: [String: SizeCacheEntry], persist: @escaping @Sendable ([String: SizeCacheEntry]) async -> Void) {
        self.cache = initial
        self.persist = persist
    }

    /// Nur Zwischenspeicher, ohne zu messen.
    func cached(_ id: String, modified: Date?) -> KnownSize {
        if let e = cache[id], e.modified == modified { return .known(e.bytes) }
        return .unknown
    }

    func cachedSizes(_ assets: [MediaAsset]) -> [String: KnownSize] {
        var out: [String: KnownSize] = [:]
        for a in assets { out[a.id] = cached(a.id, modified: a.modificationDate) }
        return out
    }

    func size(of asset: MediaAsset) async -> KnownSize {
        if let e = cache[asset.id], e.modified == asset.modificationDate { return .known(e.bytes) }
        let measured = await Self.measure(asset.id, isVideo: asset.isVideo)
        if case .known(let b) = measured {
            cache[asset.id] = SizeCacheEntry(bytes: b, modified: asset.modificationDate)
            dirty = true
        }
        return measured
    }

    /// Mehrere messen, mit Fortschritt. Abbruch über die Task.
    func sizes(of assets: [MediaAsset], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [String: KnownSize] {
        var out: [String: KnownSize] = [:]
        for (i, a) in assets.enumerated() {
            if Task.isCancelled { break }
            out[a.id] = await size(of: a)
            progress?(i + 1, assets.count)
            if (i + 1) % 200 == 0 { await flush() }
        }
        await flush()
        return out
    }

    func flush() async {
        guard dirty else { return }
        dirty = false
        // Gelöschte Medien müssen nicht ewig im Speicher bleiben: auf die jüngsten 60 000 Einträge begrenzen.
        if cache.count > 60_000 { cache = Dictionary(uniqueKeysWithValues: cache.prefix(60_000).map { ($0.key, $0.value) }) }
        await persist(cache)
    }

    // MARK: Messung

    private static func measure(_ id: String, isVideo: Bool) async -> KnownSize {
        guard let asset = PhotoLibraryService.phAsset(id) else { return .unknown }
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return .unknown }
        var total: Int64 = 0
        for r in resources {
            if Task.isCancelled { return .unknown }
            let bytes: Int64?
            if isVideo && (r.type == .video || r.type == .fullSizeVideo) && r === resources.first(where: { $0.type == .video }) {
                bytes = await videoFileSize(asset)
            } else {
                bytes = await streamedSize(r)
            }
            guard let bytes else { return .unknown }
            total += bytes
        }
        return .known(total)
    }

    /// Größe der lokalen Originaldatei eines Videos (ohne Netzwerk). Fällt auf das Streamen zurück, wenn PhotoKit
    /// keine Datei-URL liefert (z. B. Slow-Motion als Komposition).
    private static func videoFileSize(_ asset: PHAsset) async -> Int64? {
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = false
        o.version = .original
        o.deliveryMode = .highQualityFormat
        let box = UncheckedBox(asset)
        let fromURL: Int64? = await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: box.value, options: o) { @Sendable av, _, _ in
                guard let url = (av as? AVURLAsset)?.url,
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: Int64(size))
            }
        }
        if let fromURL { return fromURL }
        guard let r = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .video }) else { return nil }
        return await streamedSize(r)
    }

    /// Zählt die Bytes einer Ressource beim Lesen (keine Kopie im Speicher). `nil`, wenn nicht lokal verfügbar.
    private static func streamedSize(_ resource: PHAssetResource) async -> Int64? {
        let o = PHAssetResourceRequestOptions()
        o.isNetworkAccessAllowed = false
        let counter = ByteCounter()
        let box = UncheckedBox(resource)
        return await withCheckedContinuation { cont in
            PHAssetResourceManager.default().requestData(for: box.value, options: o) { @Sendable data in
                counter.add(Int64(data.count))
            } completionHandler: { @Sendable error in
                cont.resume(returning: error == nil ? counter.total : nil)
            }
        }
    }
}

private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0
    func add(_ n: Int64) { lock.withLock { value += n } }
    var total: Int64 { lock.withLock { value } }
}

/// Liest die Bytes eines Mediums als Strom (Duplikate per SHA-256, Auslagern mit Prüfsumme). Nur lokal vorhandene Daten.
final class PhotoResourceByteProvider: ByteSourceProvider, @unchecked Sendable {
    func openStream(for item: ItemReference) throws -> (any ByteStream)? {
        guard item.provider == .photoLibrary, let asset = PhotoLibraryService.phAsset(item.localIdentifier) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let main = resources.first(where: { $0.type == .photo || $0.type == .video })
                ?? resources.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }) else { return nil }
        return ResourceStream(resource: main)
    }
}

/// Blockierender Leser über `PHAssetResourceManager` (läuft nur auf Hintergrund-Threads). Puffert höchstens einen Block.
final class ResourceStream: ByteStream, @unchecked Sendable {
    private let condition = NSCondition()
    private var chunks: [Data] = []
    private var finished = false
    private var failed = false
    private var requestID: PHAssetResourceDataRequestID?

    init(resource: PHAssetResource) {
        let o = PHAssetResourceRequestOptions()
        o.isNetworkAccessAllowed = false
        requestID = PHAssetResourceManager.default().requestData(for: resource, options: o) { [weak self] data in
            guard let self else { return }
            self.condition.lock()
            self.chunks.append(data)
            self.condition.signal()
            self.condition.unlock()
        } completionHandler: { [weak self] error in
            guard let self else { return }
            self.condition.lock()
            self.finished = true
            self.failed = error != nil
            self.condition.signal()
            self.condition.unlock()
        }
    }

    func read(maxLength: Int) throws -> Data {
        condition.lock()
        defer { condition.unlock() }
        while chunks.isEmpty && !finished { condition.wait() }
        if failed { throw ResourceStreamError.notAvailable }
        guard !chunks.isEmpty else { return Data() }
        var first = chunks.removeFirst()
        if first.count > maxLength {
            let rest = first.subdata(in: maxLength..<first.count)
            first = first.subdata(in: 0..<maxLength)
            chunks.insert(rest, at: 0)
        }
        return first
    }

    func close() {
        if let requestID { PHAssetResourceManager.default().cancelDataRequest(requestID) }
    }

    enum ResourceStreamError: Error { case notAvailable }
}
