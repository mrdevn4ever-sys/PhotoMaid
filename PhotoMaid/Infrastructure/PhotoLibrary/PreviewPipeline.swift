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
    func progressiveImage(for assetID: String, targetSize: CGSize,
                          allowNetwork: Bool = true) -> AsyncStream<PreviewUpdate> {
        #if QA_FIXTURES && targetEnvironment(simulator)
        if slowForTesting.contains(assetID) { return AsyncStream { $0.yield(.progress(0)) } }
        if unavailableForTesting.contains(assetID) || posterlessForTesting.contains(assetID) {
            return AsyncStream { $0.yield(.failed(inCloud: false)); $0.finish() }
        }
        #endif
        let managerBox = UncheckedBox(manager)
        return AsyncStream { cont in
            let task = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { cont.finish(); return }
                guard let asset = PhotoLibraryService.phAsset(assetID) else {
                    cont.yield(.failed(inCloud: false)); cont.finish(); return
                }
                guard !Task.isCancelled else { cont.finish(); return }
                let assetBox = UncheckedBox(asset)
                let updates = Self.requestProgressiveImage(allowNetwork: allowNetwork, request: { options, result in
                    managerBox.value.requestImage(for: assetBox.value, targetSize: targetSize,
                                                  contentMode: .aspectFit, options: options, resultHandler: result)
                }, cancel: { managerBox.value.cancelImageRequest($0) })
                for await update in updates {
                    guard !Task.isCancelled else { break }
                    cont.yield(update)
                }
                cont.finish()
            }
            cont.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    typealias ImageRequest = @Sendable (PHImageRequestOptions,
                                       @escaping @Sendable (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID

    /// The callback seam is also used by native tests for real PhotoKit callback orderings.
    /// An absent cloud flag is not evidence that a network-enabled request cannot recover the image.
    nonisolated static func requestProgressiveImage(allowNetwork: Bool, request: @escaping ImageRequest,
                                                    cancel: @escaping @Sendable (PHImageRequestID) -> Void) -> AsyncStream<PreviewUpdate> {
        AsyncStream { cont in
            let requests = RequestIDs()
            cont.onTermination = { @Sendable _ in for id in requests.terminate() { cancel(id) } }
            let local = PHImageRequestOptions()
            local.isNetworkAccessAllowed = false
            local.deliveryMode = .opportunistic
            local.resizeMode = .fast
            local.version = .current
            let first = request(local) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                guard requests.acceptLocal(terminal: !degraded || cancelled) else { return }
                if cancelled { cont.finish(); return }
                if let image {
                    cont.yield(.image(image, isFinal: !degraded))
                    if !degraded { cont.finish() }
                    return
                }
                if degraded { return }
                let inCloud = isCloudFailure(info)
                guard allowNetwork else {
                    cont.yield(.failed(inCloud: inCloud)); cont.finish(); return
                }
                guard !requests.isTerminated else { cont.finish(); return }
                let remote = PHImageRequestOptions()
                remote.isNetworkAccessAllowed = true
                remote.deliveryMode = .highQualityFormat
                remote.resizeMode = .fast
                remote.version = .current
                remote.progressHandler = { @Sendable progress, _, _, _ in cont.yield(.progress(progress)) }
                cont.yield(.progress(0))
                let second = request(remote) { image, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if let image { cont.yield(.image(image, isFinal: !degraded)) }
                    if degraded { return }
                    if image == nil, (info?[PHImageCancelledKey] as? Bool) != true {
                        cont.yield(.failed(inCloud: inCloud || isCloudFailure(info)))
                    }
                    cont.finish()
                }
                requests.add(second, cancel: cancel)
            }
            requests.add(first, cancel: cancel)
        }
    }

    nonisolated private static func isCloudFailure(_ info: [AnyHashable: Any]?) -> Bool {
        if (info?[PHImageResultIsInCloudKey] as? Bool) == true { return true }
        guard let error = info?[PHImageErrorKey] as? NSError else { return false }
        return (error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.Code.networkAccessRequired.rawValue)
            || (error.domain == NSURLErrorDomain && error.code != NSURLErrorCancelled)
    }

    /// One full-quality request; cancellation completes immediately even if PhotoKit never calls back.
    func image(for assetID: String, targetSize: CGSize, allowNetwork: Bool = true,
               contentMode: PHImageContentMode = .aspectFit) async -> PreviewResult {
        #if QA_FIXTURES && targetEnvironment(simulator)
        if unavailableForTesting.contains(assetID) || posterlessForTesting.contains(assetID) { return .failed }
        #endif
        let asset = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.phAsset(assetID).map(UncheckedBox.init)
        }.value
        guard let asset, !Task.isCancelled else { return .failed }
        let managerBox = UncheckedBox(manager)
        let requestOptions = UncheckedBox(options(allowNetwork: allowNetwork))
        return await PhotoRequest<PreviewResult>.perform(cancelledValue: .failed,
                                          cancel: { managerBox.value.cancelImageRequest($0) }) { result in
            managerBox.value.requestImage(for: asset.value, targetSize: targetSize, contentMode: contentMode,
                                          options: requestOptions.value) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if let image { result(.image(image)) }
                else { result(Self.isCloudFailure(info) ? .notLocallyAvailable : .failed) }
            }
        }
    }

    #if QA_FIXTURES && targetEnvironment(simulator)
    /// Explicit fault injection for disposable simulator tests. Never compiled into a TestFlight build.
    var unavailableForTesting: Set<String> = []
    var posterlessForTesting: Set<String> = []
    var slowForTesting: Set<String> = []
    #endif

    /// Alles Vorgehaltene vergessen (z. B. nachdem Medien in den Tresor gelegt wurden).
    func forgetCache() {
        let managerBox = UncheckedBox(manager)
        cacheQueue.async { managerBox.value.stopCachingImagesForAllAssets() }
        cachedIDs = []
    }

    /// Lokale Nachbarvorschauen vorhalten; nur das sichtbare Medium darf iCloud laden.
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
        #if QA_FIXTURES && targetEnvironment(simulator)
        if unavailableForTesting.contains(assetID) { return .failed }
        #endif
        let asset = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.phAsset(assetID).map(UncheckedBox.init)
        }.value
        guard let asset, !Task.isCancelled else { return .failed }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        options.deliveryMode = .automatic
        options.version = .current
        let requestOptions = UncheckedBox(options), managerBox = UncheckedBox(manager)
        return await PhotoRequest<PlayerItemResult>.perform(cancelledValue: .failed,
                                          cancel: { managerBox.value.cancelImageRequest($0) }) { result in
            managerBox.value.requestPlayerItem(forVideo: asset.value, options: requestOptions.value) { item, info in
                if let item { result(.item(UncheckedBox(item))) }
                else { result(Self.isCloudFailure(info) ? .notLocallyAvailable : .failed) }
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

/// Laufende Requests eines Vorschau-Stroms. Nach dem Ende hinzugekommene werden sofort abgebrochen.
private final class RequestIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [PHImageRequestID] = []
    private var terminated = false
    private var localFinished = false

    func acceptLocal(terminal: Bool) -> Bool {
        lock.withLock {
            guard !terminated, !localFinished else { return false }
            if terminal { localFinished = true }
            return true
        }
    }

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
