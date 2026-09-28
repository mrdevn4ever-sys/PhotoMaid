import CryptoKit
import Foundation
import Photos
import PhotoMaidCore

/// Streaming-SHA-256 über die **einzige** Originalressource eines einfachen PhotoKit-Assets.
///
/// - Nur Assets mit genau einer Foto- bzw. Videoressource gelten als vergleichbar.
///   Live Photos, RAW+JPEG-Paare und bearbeitete Assets (zusätzliche Ressourcen) werden
///   separat als „nicht vergleichbar“ geführt.
/// - `isNetworkAccessAllowed = false`: iCloud-Originale werden nicht heimlich geladen.
/// - Keine private Größenabfrage: Die Größe ergibt sich aus den tatsächlich gestreamten Bytes.
struct PhotoResourceHasher: Sendable {
    struct Fingerprint: Sendable, Hashable {
        let sha256: String
        let bytes: Int64
    }

    enum Outcome: Sendable {
        case hashed(Fingerprint)
        case notComparable
        case notLocallyAvailable
        case failed
    }

    static func comparableResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard resources.count == 1, let r = resources.first else { return nil }
        switch r.type {
        case .photo, .video: return r
        default: return nil
        }
    }

    func hash(assetID: String) async -> Outcome {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return .failed }
        guard let resource = Self.comparableResource(for: asset) else { return .notComparable }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let state = HashState()
        let manager = PHAssetResourceManager.default()
        let managerBox = UncheckedBox(manager)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Outcome, Never>) in
                let id = manager.requestData(for: resource, options: options) { @Sendable chunk in
                    state.update(chunk)
                } completionHandler: { @Sendable error in
                    if let error = error as NSError? {
                        // PHPhotosError.networkAccessRequired: nur in iCloud vorhanden.
                        if error.domain == PHPhotosErrorDomain, error.code == PHPhotosError.Code.networkAccessRequired.rawValue {
                            cont.resume(returning: .notLocallyAvailable)
                        } else {
                            cont.resume(returning: .failed)
                        }
                        return
                    }
                    cont.resume(returning: .hashed(state.finish()))
                }
                state.requestID = id
            }
        } onCancel: {
            if let id = state.requestID { managerBox.value.cancelDataRequest(id) }
        }
    }
}

private final class HashState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasher = SHA256()
    private var count: Int64 = 0
    private var _requestID: PHAssetResourceDataRequestID?

    var requestID: PHAssetResourceDataRequestID? {
        get { lock.withLock { _requestID } }
        set { lock.withLock { _requestID = newValue } }
    }

    func update(_ data: Data) {
        lock.withLock { hasher.update(data: data); count += Int64(data.count) }
    }

    func finish() -> PhotoResourceHasher.Fingerprint {
        lock.withLock {
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return .init(sha256: digest, bytes: count)
        }
    }
}
