import AVFoundation
import Foundation
import Photos
import PhotoMaidCore

/// Misst Mediengrößen nur über öffentliche APIs:
/// - Videos: Datei des lokalen Originals (`requestAVAsset` → `URLResourceValues.fileSize`), plus übrige Ressourcen.
/// - Fotos: Bytes aller lokalen Ressourcen per `PHAssetResourceManager.requestData` (Original, Bearbeitung, Live-Video,
///   RAW) – dasselbe, was „Löschen“ auf diesem Gerät frei machen kann.
/// Nie geschätzt, nie 0 für unbekannt. Unterschieden wird aber, WARUM unbekannt: nur in iCloud („iPhone-Speicher
/// optimieren“ – iOS nennt die Größe ohne Download nicht öffentlich) oder lokal nicht lesbar. Beides wird gespeichert
/// und erst nach einer Wartezeit erneut geprüft (`SizeInventory`), damit nicht jedes Öffnen tausende Anfragen startet.
/// Ablage: SQLite (`SizeIndexDatabase`), Einträge einzeln und gebündelt geschrieben – nicht mehr als ein großer Block.
/// Mehrere Messungen dürfen gleichzeitig laufen (der Actor wartet während PhotoKit liest).
actor MediaSizer {
    private var stored: [String: SizeRecord] = [:]
    private var loaded = false
    private var legacy: [String: SizeCacheEntry]
    private var dirty: [String: SizeRecord] = [:]
    private let db: SizeIndexDatabase?

    /// `legacy`: Einträge des früheren Zwischenspeichers (nur bekannte Größen) werden einmalig übernommen.
    /// Gelesen wird erst beim ersten Zugriff – außerhalb des Hauptthreads (kein Ruckeln beim App-Start).
    init(db: SizeIndexDatabase?, legacy: [String: SizeCacheEntry]) {
        self.db = db
        self.legacy = legacy
    }

    private func ensureLoaded() {
        if !loaded { load() }
    }

    private func load() {
        loaded = true
        var all = (try? db?.all()) ?? [:]
        var migrated: [String: SizeRecord] = [:]
        let now = Date()
        for (id, entry) in legacy where all[id] == nil {
            let record = SizeRecord(modified: entry.modified, state: .known, bytes: entry.bytes, checkedAt: now)
            all[id] = record
            migrated[id] = record
        }
        legacy = [:]
        if !migrated.isEmpty { try? db?.upsert(migrated) }
        stored = all
    }

    /// Nur Zwischenspeicher, ohne zu messen.
    func cached(_ id: String, modified: Date?) -> KnownSize {
        ensureLoaded()
        guard let r = stored[id], r.isCurrent(modified: modified), !VaultConcealment.shared.isConcealed(id) else { return .unknown }
        return r.size
    }

    func cachedSizes(_ assets: [MediaAsset]) -> [String: KnownSize] {
        var out: [String: KnownSize] = [:]
        for a in assets { out[a.id] = cached(a.id, modified: a.modificationDate) }
        return out
    }

    /// Gespeicherte Messungen (auch „nur in iCloud“/„nicht lesbar“), nur für aktuelle, sichtbare Medien.
    func records(for assets: [MediaAsset]) -> [String: SizeRecord] {
        ensureLoaded()
        var out: [String: SizeRecord] = [:]
        for a in assets {
            if let r = stored[a.id], r.isCurrent(modified: a.modificationDate), !VaultConcealment.shared.isConcealed(a.id) {
                out[a.id] = r
            }
        }
        return out
    }

    func size(of asset: MediaAsset) async -> KnownSize {
        await measured(asset).size
    }

    /// Messung (oder gültiger gespeicherter Stand). `prefetched`: bereits geladenes PHAsset (Abfragen in Paketen).
    func measured(_ asset: MediaAsset, prefetched: UncheckedBox<PHAsset>? = nil) async -> SizeRecord {
        ensureLoaded()
        let now = Date()
        if let r = stored[asset.id], !SizeInventory.needsMeasure(InventoryItem(asset), record: r, now: now) { return r }
        guard let probe = await Self.probe(asset.id, box: prefetched, isVideo: asset.isVideo) else {
            // Nicht (mehr) vorhanden, im Tresor oder abgebrochen: nichts speichern.
            return SizeRecord(modified: asset.modificationDate, state: .unreadable, checkedAt: now)
        }
        var record = SizeRecord(modified: asset.modificationDate, state: probe.state, bytes: probe.bytes, checkedAt: now)
        if let old = stored[asset.id], old.isCurrent(modified: asset.modificationDate), old.state == .known,
           record.state == .known, old.bytes == record.bytes {
            record.partialHash = old.partialHash
            record.fullHash = old.fullHash
        }
        stored[asset.id] = record
        dirty[asset.id] = record
        if dirty.count >= 100 { flush() }
        return record
    }

    /// Mehrere messen, mit Fortschritt. Abbruch über die Task.
    func sizes(of assets: [MediaAsset], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [String: KnownSize] {
        var out: [String: KnownSize] = [:]
        for (i, a) in assets.enumerated() {
            if Task.isCancelled { break }
            out[a.id] = await size(of: a)
            progress?(i + 1, assets.count)
        }
        flush()
        return out
    }

    /// Prüfsummen aus der Duplikatsuche merken (nur, solange das Medium unverändert ist).
    func storeHashes(_ updates: [String: DuplicateHashes]) {
        ensureLoaded()
        for (id, h) in updates {
            guard var r = stored[id], r.state == .known, r.isCurrent(modified: h.modified) else { continue }
            if let p = h.partial { r.partialHash = p }
            if let f = h.full { r.fullHash = f }
            stored[id] = r
            dirty[id] = r
        }
        flush()
    }

    func flush() {
        guard !dirty.isEmpty else { return }
        let pending = dirty.filter { !VaultConcealment.shared.isConcealed($0.key) }
        dirty = [:]
        try? db?.upsert(pending)
    }

    // MARK: Messung

    private struct Probe: Sendable {
        let state: MeasureState
        let bytes: Int64?
    }

    private enum Part: Sendable {
        case bytes(Int64)
        case notLocal
        case failed
    }

    /// `nil` = Medium nicht gefunden (gelöscht, im Tresor) oder abgebrochen.
    private static func probe(_ id: String, box: UncheckedBox<PHAsset>?, isVideo: Bool) async -> Probe? {
        guard !VaultConcealment.shared.isConcealed(id), let asset = box?.value ?? PhotoLibraryService.phAsset(id) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return Probe(state: .unreadable, bytes: nil) }
        var total: Int64 = 0
        for r in resources {
            if Task.isCancelled { return nil }
            let part: Part
            if isVideo && (r.type == .video || r.type == .fullSizeVideo) && r === resources.first(where: { $0.type == .video }) {
                part = await videoFileSize(asset)
            } else {
                part = await streamedSize(r)
            }
            switch part {
            case .bytes(let b): total += b
            case .notLocal: return Probe(state: .notLocal, bytes: nil)
            case .failed: return Task.isCancelled ? nil : Probe(state: .unreadable, bytes: nil)
            }
        }
        return Probe(state: .known, bytes: total)
    }

    /// Größe der lokalen Originaldatei eines Videos (ohne Netzwerk, ohne die Daten zu lesen). Fällt auf das Streamen
    /// zurück, wenn PhotoKit keine Datei-URL liefert (z. B. Slow-Motion als Komposition).
    private static func videoFileSize(_ asset: PHAsset) async -> Part {
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = false
        o.version = .original
        o.deliveryMode = .highQualityFormat
        let box = UncheckedBox(asset)
        let fromURL: Part? = await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: box.value, options: o) { @Sendable av, _, info in
                if let url = (av as? AVURLAsset)?.url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    cont.resume(returning: .bytes(Int64(size))); return
                }
                let inCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue == true
                cont.resume(returning: av == nil && inCloud ? .notLocal : nil)
            }
        }
        if let fromURL { return fromURL }
        guard let r = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .video }) else { return .failed }
        return await streamedSize(r)
    }

    /// Zählt die Bytes einer Ressource beim Lesen (keine Kopie im Speicher). Liegt sie nur in iCloud, meldet PhotoKit
    /// „Netzwerkzugriff nötig“ – das wird als „nur in iCloud“ gespeichert, jeder andere Fehler als „nicht lesbar“.
    private static func streamedSize(_ resource: PHAssetResource) async -> Part {
        let o = PHAssetResourceRequestOptions()
        o.isNetworkAccessAllowed = false
        let counter = ByteCounter()
        let box = UncheckedBox(resource)
        return await withCheckedContinuation { cont in
            PHAssetResourceManager.default().requestData(for: box.value, options: o) { @Sendable data in
                counter.add(Int64(data.count))
            } completionHandler: { @Sendable error in
                guard let error else { cont.resume(returning: .bytes(counter.total)); return }
                let ns = error as NSError
                let notLocal = ns.domain == PHPhotosErrorDomain && ns.code == PHPhotosError.Code.networkAccessRequired.rawValue
                cont.resume(returning: notLocal ? .notLocal : .failed)
            }
        }
    }
}

/// Vorbereitete Prüfsummen für `MediaSizer.storeHashes` (mit Änderungsdatum zur Gültigkeitsprüfung).
struct DuplicateHashes: Sendable {
    let modified: Date?
    var partial: String?
    var full: String?
}

extension InventoryItem {
    init(_ a: MediaAsset) {
        self.init(id: a.id, modified: a.modificationDate, isVideo: a.isVideo, width: a.pixelWidth, height: a.pixelHeight,
                  duration: a.duration)
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
