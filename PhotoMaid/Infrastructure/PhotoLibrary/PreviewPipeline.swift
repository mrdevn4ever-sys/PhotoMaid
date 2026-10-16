import AVFoundation
import Foundation
import Photos
import UIKit

/// Ergebnis einer Vorschauanfrage. Nicht lokal verfügbar ≠ gelöscht.
enum PreviewResult: Sendable {
    case image(UIImage)
    case notLocallyAvailable
    case failed
}

/// Stufenweise Vorschau wie in der Fotos-App: erst die schnell verfügbare (ggf. unscharfe) Fassung, danach die volle
/// Qualität – bei Bedarf automatisch aus iCloud. `progress` kommt nur, während aus iCloud geladen wird.
enum PreviewUpdate: Sendable {
    case image(UIImage, isFinal: Bool)
    case progress(Double)
    case failed(inCloud: Bool)
}

/// Begrenzte Preview-Pipeline: Auflösung an sichtbare Fläche × Display-Skalierung,
/// Puffer für vorheriges/aktuelles/wenige nächste Items, keine Originale im RAM.
/// Medien aus iCloud-Fotos werden wie in der Fotos-App automatisch geladen (nur Download aus der eigenen Mediathek).
@MainActor
final class PreviewPipeline {
    private let manager: PHCachingImageManager
    private var cachedIDs: Set<String> = []
    private var cachedSize: CGSize = .zero
    /// Vorhalten der Nachbarn: seriell (Freigeben vor Vorhalten), nie auf dem Hauptthread.
    private let cacheQueue = DispatchQueue(label: "PhotoMaid.preview.cache", qos: .userInitiated)

    init(manager: PHCachingImageManager) { self.manager = manager }

    static func targetSize(for viewSize: CGSize, scale: CGFloat) -> CGSize {
        // Obergrenze verhindert riesige Bitmaps (Panoramen); Aspect Fit bleibt erhalten.
        let maxSide: CGFloat = 2800
        var w = viewSize.width * scale, h = viewSize.height * scale
        let m = max(w, h)
        if m > maxSide { w *= maxSide / m; h *= maxSide / m }
        return CGSize(width: max(1, w.rounded()), height: max(1, h.rounded()))
    }

    private func options(allowNetwork: Bool = true) -> PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = allowNetwork
        o.deliveryMode = .highQualityFormat // genau ein Callback
        o.resizeMode = .fast
        o.version = .current
        return o
    }

    /// Für Feed und Betrachter: zuerst die schnelle Fassung, dann die volle Qualität (auch aus iCloud).
    private func progressiveOptions() -> PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        o.version = .current
        return o
    }

    /// Keep the four-item swipe cache local and small. The *visible* image still
    /// uses progressiveImage(), including its full-quality/iCloud loading path.
    /// Prefetching offscreen originals from iCloud wastes bandwidth and memory.
    nonisolated private static func cacheOptions() -> PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = false
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        o.version = .current
        return o
    }

    /// Stufenweise Vorschau wie in der Fotos-App, in zwei Schritten:
    /// 1. Nur was auf dem iPhone liegt (ohne Netz): erscheint sofort, auch wenn das Original in iCloud liegt.
    /// 2. Fehlt die volle Qualität lokal, wird sie aus iCloud geladen (`progress`). Gelingt das nicht (offline,
    ///    mobile Daten für Fotos aus), meldet der Strom `.failed(inCloud: true)` – die Vorschau aus Schritt 1 bleibt.
    /// Abbruch des Tasks bricht beide PhotoKit-Requests (und einen laufenden Download) ab.
    /// PhotoKit-Abfrage und Anfragen laufen abseits des Hauptthreads: Lädt Fotos gerade viel aus iCloud, kann schon
    /// das Nachschlagen eines Mediums warten – das darf das Wischen nie anhalten.
    func progressiveImage(for assetID: String, targetSize: CGSize) -> AsyncStream<PreviewUpdate> {
        let managerBox = UncheckedBox(manager)
        return AsyncStream { cont in
            let requests = RequestIDs()
            cont.onTermination = { @Sendable _ in
                for id in requests.terminate() { managerBox.value.cancelImageRequest(id) }
            }
            Task.detached(priority: .userInitiated) {
                guard !requests.isTerminated else { return }
                guard let asset = PhotoLibraryService.phAsset(assetID) else { // Tresor-Medien: nie
                    cont.yield(.failed(inCloud: false))
                    cont.finish()
                    return
                }
                Self.startProgressive(asset: UncheckedBox(asset), manager: managerBox, targetSize: targetSize,
                                      cont: cont, requests: requests)
            }
        }
    }

    nonisolated private static func startProgressive(asset assetBox: UncheckedBox<PHAsset>,
                                                     manager managerBox: UncheckedBox<PHCachingImageManager>,
                                                     targetSize: CGSize, cont: AsyncStream<PreviewUpdate>.Continuation,
                                                     requests: RequestIDs) {
        let local = PHImageRequestOptions()
        local.isNetworkAccessAllowed = false
        local.deliveryMode = .opportunistic
        local.resizeMode = .fast
        local.version = .current
        let first = managerBox.value.requestImage(for: assetBox.value, targetSize: targetSize, contentMode: .aspectFit,
                                                  options: local) { @Sendable image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if let image {
                cont.yield(.image(image, isFinal: !degraded))
                if !degraded { cont.finish() }
                return
            }
            if degraded { return }
            if (info?[PHImageCancelledKey] as? Bool) == true { cont.finish(); return }
            guard (info?[PHImageResultIsInCloudKey] as? Bool) == true else {
                cont.yield(.failed(inCloud: false))
                cont.finish()
                return
            }
            guard !requests.isTerminated else { cont.finish(); return }
            // Schritt 2: volle Qualität aus iCloud.
            let remote = PHImageRequestOptions()
            remote.isNetworkAccessAllowed = true
            remote.deliveryMode = .highQualityFormat // genau ein Callback
            remote.resizeMode = .fast
            remote.version = .current
            remote.progressHandler = { @Sendable progress, _, _, _ in cont.yield(.progress(progress)) }
            cont.yield(.progress(0))
            let second = managerBox.value.requestImage(for: assetBox.value, targetSize: targetSize,
                                                       contentMode: .aspectFit, options: remote) { @Sendable image, info in
                if let image {
                    cont.yield(.image(image, isFinal: true))
                } else if (info?[PHImageCancelledKey] as? Bool) != true {
                    cont.yield(.failed(inCloud: true))
                }
                cont.finish()
            }
            requests.add(second) { managerBox.value.cancelImageRequest($0) }
        }
        requests.add(first) { managerBox.value.cancelImageRequest($0) }
    }

    /// Lädt eine Vorschau in einem Schritt (volle Qualität, bei Bedarf aus iCloud). Abbruch des Tasks bricht den
    /// PhotoKit-Request ab.
    func image(for assetID: String, targetSize: CGSize, allowNetwork: Bool = true,
               contentMode: PHImageContentMode = .aspectFit) async -> PreviewResult {
        guard let asset = PhotoLibraryService.phAsset(assetID) else { return .failed }
        let box = RequestBox()
        let managerBox = UncheckedBox(manager)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<PreviewResult, Never>) in
                let id = manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode,
                                              options: options(allowNetwork: allowNetwork)) { @Sendable image, info in
                    if let image { cont.resume(returning: .image(image)); return }
                    let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    cont.resume(returning: inCloud ? .notLocallyAvailable : .failed)
                }
                box.set(id)
            }
        } onCancel: {
            if let id = box.id { managerBox.value.cancelImageRequest(id) }
        }
    }

    /// Alles Vorgehaltene vergessen (z. B. nachdem Medien in den Tresor gelegt wurden).
    func forgetCache() {
        let managerBox = UncheckedBox(manager)
        cacheQueue.async { managerBox.value.stopCachingImagesForAllAssets() }
        cachedIDs = []
    }

    /// Vorheriges, aktuelles und wenige nächste Items vorhalten (auch aus iCloud vorladen); Rest freigeben.
    func updateCache(window ids: [String], targetSize: CGSize) {
        // Previews under the top card never need full-resolution bitmaps.
        let longSide = max(targetSize.width, targetSize.height)
        let cacheSize: CGSize
        if longSide > 1280 {
            let factor = 1280 / longSide
            cacheSize = CGSize(width: max(1, (targetSize.width * factor).rounded()),
                               height: max(1, (targetSize.height * factor).rounded()))
        } else {
            cacheSize = targetSize
        }
        let wanted = Set(ids)
        let resetAll = cacheSize != cachedSize
        if resetAll {
            cachedIDs = []
            cachedSize = cacheSize
        }
        let add = wanted.subtracting(cachedIDs), remove = cachedIDs.subtracting(wanted)
        guard resetAll || !add.isEmpty || !remove.isEmpty else { return }
        cachedIDs = wanted
        // PhotoKit-Abfragen und Vorhalten in fester Reihenfolge abseits des Hauptthreads (nach jedem Wisch).
        let managerBox = UncheckedBox(manager)
        cacheQueue.async {
            func fetch(_ s: Set<String>) -> [PHAsset] {
                guard !s.isEmpty else { return [] }
                var out: [PHAsset] = []
                let ids = Array(VaultConcealment.shared.visible(s))
                guard !ids.isEmpty else { return [] }
                PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in out.append(a) }
                return out
            }
            let options = PreviewPipeline.cacheOptions()
            if resetAll { managerBox.value.stopCachingImagesForAllAssets() }
            if !remove.isEmpty {
                managerBox.value.stopCachingImages(for: fetch(remove), targetSize: cacheSize, contentMode: .aspectFit,
                                                   options: options)
            }
            if !add.isEmpty {
                managerBox.value.startCachingImages(for: fetch(add), targetSize: cacheSize, contentMode: .aspectFit,
                                                    options: options)
            }
        }
    }

    /// Video als PlayerItem; liegt es nur in iCloud, streamt PhotoKit es (wie die Fotos-App).
    func playerItem(for assetID: String, allowNetwork: Bool = true) async -> PlayerItemResult {
        guard let asset = PhotoLibraryService.phAsset(assetID) else { return .failed }
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = allowNetwork
        o.deliveryMode = .automatic
        o.version = .current
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: o) { @Sendable item, info in
                if let item { cont.resume(returning: .item(UncheckedBox(item))); return }
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                cont.resume(returning: inCloud ? .notLocallyAvailable : .failed)
            }
        }
    }
}

enum PlayerItemResult: Sendable {
    case item(UncheckedBox<AVPlayerItem>)
    case notLocallyAvailable
    case failed
}

/// Transporthülle für nicht-Sendable-Objekte, die genau einmal übergeben werden.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: PHImageRequestID?
    var id: PHImageRequestID? { lock.withLock { _id } }
    func set(_ id: PHImageRequestID) { lock.withLock { _id = id } }
}

/// Laufende Requests eines Vorschau-Stroms. Nach dem Ende hinzugekommene werden sofort abgebrochen.
private final class RequestIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [PHImageRequestID] = []
    private var terminated = false

    func add(_ id: PHImageRequestID, cancel: (PHImageRequestID) -> Void) {
        let late = lock.withLock { () -> Bool in
            if terminated { return true }
            ids.append(id)
            return false
        }
        if late { cancel(id) }
    }

    var isTerminated: Bool { lock.withLock { terminated } }

    func terminate() -> [PHImageRequestID] {
        lock.withLock {
            terminated = true
            defer { ids = [] }
            return ids
        }
    }
}
