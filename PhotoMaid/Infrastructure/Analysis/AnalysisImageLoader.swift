import Foundation
import ImageIO
import Network
import Photos
import PhotoMaidCore
import UIKit

/// PhotoKit has no per-request cellular switch. We admit cloud work only on an unmetered Wi-Fi path,
/// and cancel when that changes. Photos' system settings still govern bytes during a network handover.
final class AnalysisNetwork: @unchecked Sendable {
    static let shared = AnalysisNetwork()
    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private var ready = false
    var permitsCloud: Bool { lock.withLock { ready } }
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock {
                self.ready = path.status == .satisfied && path.usesInterfaceType(.wifi)
                    && !path.isExpensive && !path.isConstrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "PhotoMaid.analysis.network", qos: .utility))
    }
}

struct AnalysisImage: @unchecked Sendable {
    let image: CGImage
    let orientation: CGImagePropertyOrientation
}
enum AnalysisImageOutcome: Sendable {
    case image(AnalysisImage), cloud, quality, failed, timedOut, network, cancelled, privateItem
}
private struct AnalysisManager: @unchecked Sendable { let value: PHImageManager }
private final class AnalysisRequestClock: @unchecked Sendable {
    let lock = NSLock()
    var watchdog: AnalysisWatchdog
    var degraded = false
    var cloud = false
    init(cloud: Bool) { watchdog = AnalysisWatchdog(now: ProcessInfo.processInfo.systemUptime, cloud: cloud) }
}

enum AnalysisImageLoader {
    /// No requestImageDataAndOrientation, original-resolution request, or plaintext temporary file.
    static func load(id: String, kind: AnalysisKind, allowCloud: Bool,
                     progress: @escaping @Sendable (Double) -> Void) async -> AnalysisImageOutcome {
        let gate = AnalysisOneShot<AnalysisImageOutcome>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.observe { continuation.resume(returning: $0) }
                guard !gate.isCompleted else { return }
                guard VaultConcealment.shared.analysisReady, !VaultConcealment.shared.isConcealed(id) else {
                    gate.finish(.privateItem); return
                }
                guard !allowCloud || AnalysisNetwork.shared.permitsCloud else { gate.finish(.network); return }
                guard let asset = PhotoLibraryService.phAsset(id) else { gate.finish(.failed); return }
                let clock = AnalysisRequestClock(cloud: allowCloud)
                let manager = AnalysisManager(value: PHImageManager.default())
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = allowCloud
                options.isSynchronous = false
                options.version = .current
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.progressHandler = { value, error, stop, _ in
                    if gate.isCompleted { stop.pointee = true; return }
                    if allowCloud && !AnalysisNetwork.shared.permitsCloud {
                        stop.pointee = true; gate.finish(.network); return
                    }
                    if error != nil { stop.pointee = true; gate.finish(.failed); return }
                    clock.lock.withLock { clock.watchdog.update(value, now: ProcessInfo.processInfo.systemUptime) }
                    progress(value)
                }
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
                timer.setEventHandler { [weak gate] in
                    guard let gate, !gate.isCompleted else { return }
                    if allowCloud && !AnalysisNetwork.shared.permitsCloud { gate.finish(.network); return }
                    if !VaultConcealment.shared.analysisReady || VaultConcealment.shared.isConcealed(id) {
                        gate.finish(.privateItem); return
                    }
                    let status = clock.lock.withLock {
                        (clock.watchdog.expired(now: ProcessInfo.processInfo.systemUptime), clock.degraded, clock.cloud)
                    }
                    if status.0 {
                        gate.finish(!allowCloud && status.2 ? .cloud : (status.1 ? .quality : .timedOut))
                    }
                }
                timer.resume()
                gate.onFinish { timer.cancel() }
                let nativeEdge = max(asset.pixelWidth, asset.pixelHeight)
                let minimumEdge = max(1, min(kind.pixelLimit, nativeEdge))
                let request = manager.value.requestImage(for: asset,
                    targetSize: CGSize(width: CGFloat(kind.pixelLimit), height: CGFloat(kind.pixelLimit)),
                    contentMode: .aspectFit, options: options) { image, info in
                    guard !gate.isCompleted else { return }
                    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true { gate.finish(.cancelled); return }
                    let inCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue == true
                    if inCloud { clock.lock.withLock { clock.cloud = true } }
                    // A network-required result is pending work, not a successful negative result.
                    if image == nil, inCloud, !allowCloud { gate.finish(.cloud); return }
                    if info?[PHImageErrorKey] != nil { gate.finish(.failed); return }
                    let degraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
                    if degraded { clock.lock.withLock { clock.degraded = true }; return }
                    if let image, let cg = image.cgImage {
                        // A soft thumbnail must never be labelled an out-of-focus source photograph.
                        guard max(cg.width, cg.height) >= Int(Double(minimumEdge) * 0.9),
                              (kind != .blurry || max(cg.width, cg.height) >= 512) else { gate.finish(.quality); return }
                        guard VaultConcealment.shared.analysisReady, !VaultConcealment.shared.isConcealed(id) else {
                            gate.finish(.privateItem); return
                        }
                        gate.finish(.image(AnalysisImage(image: cg, orientation: orientation(image.imageOrientation))))
                    } else if inCloud { gate.finish(.cloud) }
                    else { gate.finish(.failed) }
                }
                // A callback or cancellation can finish before requestImage returns its identifier.
                gate.onFinish { manager.value.cancelImageRequest(request) }
            }
        } onCancel: { gate.finish(.cancelled) }
    }
    private static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
