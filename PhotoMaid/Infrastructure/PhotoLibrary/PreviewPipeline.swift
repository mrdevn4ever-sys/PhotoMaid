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

/// Begrenzte Preview-Pipeline: Auflösung an sichtbare Fläche × Display-Skalierung,
/// Puffer für vorheriges/aktuelles/wenige nächste Items, keine Originale im RAM,
/// keine automatische iCloud-Freigabe.
@MainActor
final class PreviewPipeline {
    private let manager: PHCachingImageManager
    private var cachedIDs: Set<String> = []
    private var cachedSize: CGSize = .zero

    init(manager: PHCachingImageManager) { self.manager = manager }

    static func targetSize(for viewSize: CGSize, scale: CGFloat) -> CGSize {
        // Obergrenze verhindert riesige Bitmaps (Panoramen); Aspect Fit bleibt erhalten.
        let maxSide: CGFloat = 2800
        var w = viewSize.width * scale, h = viewSize.height * scale
        let m = max(w, h)
        if m > maxSide { w *= maxSide / m; h *= maxSide / m }
        return CGSize(width: max(1, w.rounded()), height: max(1, h.rounded()))
    }

    private func options() -> PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = false
        o.deliveryMode = .highQualityFormat // genau ein Callback
        o.resizeMode = .fast
        o.version = .current
        return o
    }

    /// Lädt eine Vorschau. Abbruch des Tasks bricht den PhotoKit-Request ab.
    func image(for assetID: String, targetSize: CGSize) async -> PreviewResult {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return .failed }
        let box = RequestBox()
        let managerBox = UncheckedBox(manager)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<PreviewResult, Never>) in
                let id = manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit,
                                              options: options()) { @Sendable image, info in
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

    /// Vorheriges, aktuelles und wenige nächste Items vorhalten; Rest freigeben.
    func updateCache(window ids: [String], targetSize: CGSize) {
        let wanted = Set(ids)
        if targetSize != cachedSize {
            manager.stopCachingImagesForAllAssets()
            cachedIDs = []
            cachedSize = targetSize
        }
        let add = wanted.subtracting(cachedIDs), remove = cachedIDs.subtracting(wanted)
        func fetch(_ s: Set<String>) -> [PHAsset] {
            guard !s.isEmpty else { return [] }
            var out: [PHAsset] = []
            PHAsset.fetchAssets(withLocalIdentifiers: Array(s), options: nil).enumerateObjects { a, _, _ in out.append(a) }
            return out
        }
        manager.stopCachingImages(for: fetch(remove), targetSize: targetSize, contentMode: .aspectFit, options: options())
        manager.startCachingImages(for: fetch(add), targetSize: targetSize, contentMode: .aspectFit, options: options())
        cachedIDs = wanted
    }

    /// Lokales Video als PlayerItem, ohne Netzwerkfreigabe.
    func playerItem(for assetID: String) async -> PlayerItemResult {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return .failed }
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = false
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
