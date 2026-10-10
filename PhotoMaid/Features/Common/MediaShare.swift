import AVFoundation
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Sendable, weil `prepare` nicht isoliert läuft und das Ergebnis auf den Main Actor zurückgibt.
struct MediaShareItem: Identifiable, Sendable {
    let id = UUID()
    let items: [URL]
    let cleanup: [URL]
}

/// Teilen von Medien über das System-Teilen-Blatt. Nur lokal vorhandene Originale (kein heimlicher iCloud-Download).
/// Teilen ist nie eine Entscheidung und ändert nichts am Prüfstand.
enum MediaShare {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
    }

    static func prepare(_ ids: [String]) async -> MediaShareItem? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for id in ids {
            guard let asset = PhotoLibraryService.phAsset(id) else { continue }
            if let url = await export(asset) { urls.append(url) }
        }
        guard !urls.isEmpty else { return nil }
        return MediaShareItem(items: urls, cleanup: urls)
    }

    /// Alte Teilen-Dateien entfernen (beim Start und nach dem Teilen).
    static func cleanupAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func export(_ asset: PHAsset) async -> URL? {
        let name = PHAssetResource.assetResources(for: asset).first { $0.type == .photo || $0.type == .video }?
            .originalFilename ?? UUID().uuidString
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let box = UncheckedBox(asset)
        if asset.mediaType == .video {
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = false
            o.version = .current
            let source: URL? = await withCheckedContinuation { cont in
                PHImageManager.default().requestAVAsset(forVideo: box.value, options: o) { @Sendable av, _, _ in
                    cont.resume(returning: (av as? AVURLAsset)?.url)
                }
            }
            guard let source else { return nil }
            let target = folder.appendingPathComponent(source.lastPathComponent.isEmpty ? name : source.lastPathComponent)
            do { try FileManager.default.copyItem(at: source, to: target) } catch { return nil }
            return target
        }
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = false
        o.version = .current
        o.deliveryMode = .highQualityFormat
        let result: (Data, String?)? = await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: box.value, options: o) { @Sendable data, uti, _, _ in
                cont.resume(returning: data.map { ($0, uti) })
            }
        }
        guard let result else { return nil }
        let (data, uti) = result
        var fileName = name
        if let uti, let ext = UTType(uti)?.preferredFilenameExtension {
            fileName = (name as NSString).deletingPathExtension + "." + ext
        }
        let target = folder.appendingPathComponent(fileName)
        do { try data.write(to: target, options: .atomic) } catch { return nil }
        return target
    }
}

/// System-Teilen-Blatt.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onFinish?() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
