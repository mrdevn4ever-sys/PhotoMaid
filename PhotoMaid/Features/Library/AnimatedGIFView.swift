import Foundation
import Photos
import SwiftUI
import UIKit
import WebKit

/// Animated image playback is opt-in for actual GIF resources. Normal photos continue
/// through the existing thumbnail/zoom pipeline; no automatic video conversion.
@MainActor
enum GIFPlayback {
    /// Ob ein Medium ein GIF ist, ändert sich nicht: einmal je Medium bei Fotos nachfragen (synchrone Abfrage der
    /// Ressourcen auf dem Hauptthread) statt bei jeder obersten Karte im Feed erneut (Wärme-Audit 22.10.2026).
    private static var known: [String: Bool] = [:]

    static func isGIF(_ id: String) -> Bool {
        if let cached = known[id] { return cached }
        // Nicht gefunden wird nicht gemerkt (ein Medium kann später auftauchen, z. B. nach dem Laden der Mediathek).
        guard let asset = PhotoLibraryService.phAsset(id) else { return false }
        let gif = asset.mediaType == .image && PHAssetResource.assetResources(for: asset).contains {
            $0.uniformTypeIdentifier.lowercased().contains("gif") ||
            $0.originalFilename.lowercased().hasSuffix(".gif")
        }
        if known.count >= 20_000 { known.removeAll() }
        known[id] = gif
        return gif
    }

    /// PhotoKit may need to fetch the current source from iCloud. Keep a strict byte cap:
    /// a huge GIF must fall back to its static thumbnail, never crash the viewer.
    static func data(for id: String) async -> Data? {
        guard isGIF(id), let asset = PhotoLibraryService.phAsset(id) else { return nil }
        let options = PHImageRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let box = UncheckedBox(asset)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(for: box.value, options: options) {
                @Sendable data, uti, _, _ in
                guard let data, data.count <= 32 * 1024 * 1024,
                      uti?.lowercased().contains("gif") == true,
                      data.starts(with: Array("GIF8".utf8)) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}

/// WebKit decodes and animates the original GIF without allocating a decoded
/// UIImage array containing every full-resolution frame.
struct AnimatedGIFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        return view
    }

    final class Coordinator {
        var currentDataHash: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // SwiftUI can reuse this view for a different media item: reload its GIF.
        let hash = data.hashValue
        guard context.coordinator.currentDataHash != hash else { return }
        context.coordinator.currentDataHash = hash
        uiView.load(data, mimeType: "image/gif", characterEncodingName: "utf-8",
                    baseURL: URL(fileURLWithPath: "/"))
    }
}
