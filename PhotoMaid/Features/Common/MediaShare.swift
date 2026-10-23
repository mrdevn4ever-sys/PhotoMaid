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
    /// Medien, die sich nicht vorbereiten ließen (gezählt, nie geschätzt). Geteilt wird trotzdem der Rest.
    var failed = 0
}

/// Teilen von Medien über das System-Teilen-Blatt. Originale aus iCloud-Fotos werden dafür geladen (wie in der Fotos-App).
/// Teilen ist nie eine Entscheidung und ändert nichts am Prüfstand.
///
/// Jedes Medium bekommt einen eigenen Ordner (gleiche Originalnamen überschreiben sich nie). Fotos und Live Photos
/// (Standbild) über die Bilddaten der aktuellen Fassung; Videos als Datei-Kopie, Zeitlupen u. Ä. (PhotoKit liefert eine
/// Komposition statt einer Datei) gerendert; als letzter Ausweg die Ressource selbst (Bearbeitung vor Original).
enum MediaShare {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
    }

    /// Höchstens so viele Medien gleichzeitig (iCloud-Downloads parallel, Speicher begrenzt).
    private static let parallel = 3

    /// Einzelne Medien (Feed, Betrachter): der Reihe nach, ohne Fortschritt.
    static func prepare(_ ids: [String]) async -> MediaShareItem? {
        removeStale()
        var urls: [URL] = []
        for id in ids {
            if let url = await export(id) { urls.append(url) }
        }
        guard !urls.isEmpty, !Task.isCancelled else {
            remove(urls)
            return nil
        }
        return MediaShareItem(items: urls, cleanup: urls, failed: ids.count - urls.count)
    }

    /// Mehrere Medien mit Fortschritt (`progress(fertig, gesamt)` auf dem Main Actor). Reihenfolge bleibt erhalten.
    /// Misslingt ein Teil (z. B. ohne Verbindung zu iCloud), wird der Rest geteilt und `failed` gezählt.
    /// `nil` = nichts gelungen oder abgebrochen (angefangene Dateien werden entfernt).
    @MainActor
    static func prepare(_ ids: [String], progress: (Int, Int) -> Void) async -> MediaShareItem? {
        removeStale()
        let total = ids.count
        var results = [URL?](repeating: nil, count: total)
        var done = 0
        progress(0, total)
        await withTaskGroup(of: (Int, URL?).self) { group in
            var next = 0
            while next < min(parallel, total) {
                let index = next
                let id = ids[index]
                group.addTask { (index, await MediaShare.export(id)) }
                next += 1
            }
            while let result = await group.next() {
                results[result.0] = result.1
                done += 1
                progress(done, total)
                guard !Task.isCancelled else { continue }
                if next < total {
                    let index = next
                    let id = ids[index]
                    group.addTask { (index, await MediaShare.export(id)) }
                    next += 1
                }
            }
        }
        let urls = results.compactMap { $0 }
        guard !urls.isEmpty, !Task.isCancelled else {
            remove(urls)
            return nil
        }
        return MediaShareItem(items: urls, cleanup: urls, failed: total - urls.count)
    }

    /// Alte Teilen-Dateien entfernen.
    static func cleanupAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Dateien eines Teilens entfernen (samt eigenem Ordner), sobald das Teilen-Blatt fertig ist.
    static func remove(_ urls: [URL]) {
        let root = directory.standardizedFileURL.path
        for url in urls {
            let folder = url.deletingLastPathComponent()
            if folder.standardizedFileURL.path.hasPrefix(root + "/") {
                try? FileManager.default.removeItem(at: folder)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Reste früherer Teilen-Vorgänge (älter als ein Tag) entfernen – laufende bleiben unberührt.
    private static func removeStale() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let limit = Date().addingTimeInterval(-24 * 3600)
        let entries = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for url in entries {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < limit { try? fm.removeItem(at: url) }
        }
    }

    // MARK: Ein Medium

    /// Eine Datei für ein Medium in einem eigenen Ordner, sonst `nil` (nicht zugänglich, Download gescheitert, abgebrochen).
    static func export(_ id: String) async -> URL? {
        guard !Task.isCancelled, let asset = PhotoLibraryService.phAsset(id) else { return nil }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return nil }
        let box = UncheckedBox(asset)
        let stem = stemName(asset)
        let url: URL?
        if asset.mediaType == .video {
            url = await exportVideo(box, folder: folder, stem: stem)
        } else {
            url = await exportPhoto(box, folder: folder, stem: stem)
        }
        if url == nil || Task.isCancelled {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        return url
    }

    /// Originalname ohne Endung (z. B. „IMG_0042“); die Endung kommt vom tatsächlichen Format.
    private static func stemName(_ asset: PHAsset) -> String {
        let name = PHAssetResource.assetResources(for: asset)
            .first { $0.type == .photo || $0.type == .video }?.originalFilename ?? ""
        let stem = (name as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: "_")
        return stem.isEmpty ? AppConfig.brandName + "-" + String(UUID().uuidString.prefix(8)) : stem
    }

    private static func exportPhoto(_ box: UncheckedBox<PHAsset>, folder: URL, stem: String) async -> URL? {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.version = .current
        o.deliveryMode = .highQualityFormat
        let result: ShareImageData? = await photoKitRequest { (shot: PhotoKitOneShot<ShareImageData>) in
            PHImageManager.default().requestImageDataAndOrientation(for: box.value, options: o) { @Sendable data, uti, _, _ in
                shot.finish(data.map { ShareImageData(data: $0, uti: uti) })
            }
        }
        if let result {
            let ext = result.uti.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"
            let target = folder.appendingPathComponent(stem + "." + ext)
            do {
                try result.data.write(to: target, options: .atomic)
                return target
            } catch {
                try? FileManager.default.removeItem(at: target)
            }
        }
        guard !Task.isCancelled else { return nil }
        return await writeResource(box, types: [.fullSizePhoto, .photo], folder: folder, stem: stem)
    }

    private static func exportVideo(_ box: UncheckedBox<PHAsset>, folder: URL, stem: String) async -> URL? {
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = true
        o.version = .current
        o.deliveryMode = .highQualityFormat
        let av: UncheckedBox<AVAsset>? = await photoKitRequest { (shot: PhotoKitOneShot<UncheckedBox<AVAsset>>) in
            PHImageManager.default().requestAVAsset(forVideo: box.value, options: o) { @Sendable asset, _, _ in
                shot.finish(asset.map { UncheckedBox($0) })
            }
        }
        if let av, !Task.isCancelled {
            if let file = (av.value as? AVURLAsset)?.url, file.isFileURL {
                let ext = file.pathExtension.isEmpty ? "mov" : file.pathExtension
                let target = folder.appendingPathComponent(stem + "." + ext)
                do {
                    try FileManager.default.copyItem(at: file, to: target)
                    return target
                } catch {
                    try? FileManager.default.removeItem(at: target)
                }
            } else {
                // Komposition (z. B. Zeitlupe): so rendern, wie die Fotos-App das Video zeigt.
                let target = folder.appendingPathComponent(stem + ".mov")
                if await render(av, to: target) { return target }
            }
        }
        guard !Task.isCancelled else { return nil }
        return await writeResource(box, types: [.fullSizeVideo, .video], folder: folder, stem: stem)
    }

    private static func render(_ asset: UncheckedBox<AVAsset>, to url: URL) async -> Bool {
        guard let session = AVAssetExportSession(asset: asset.value, presetName: AVAssetExportPresetHighestQuality) else {
            return false
        }
        let box = UncheckedBox(session)
        do {
            try await box.value.export(to: url, as: .mov)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    /// Letzter Ausweg: die Ressource selbst (bearbeitete Fassung vor Original), bei Bedarf aus iCloud.
    private static func writeResource(_ box: UncheckedBox<PHAsset>, types: [PHAssetResourceType], folder: URL,
                                      stem: String) async -> URL? {
        let resources = PHAssetResource.assetResources(for: box.value)
        var chosen: PHAssetResource?
        for type in types where chosen == nil {
            chosen = resources.first { $0.type == type }
        }
        guard let resource = chosen else { return nil }
        let ext = (resource.originalFilename as NSString).pathExtension
        let target = folder.appendingPathComponent(ext.isEmpty ? stem : stem + "." + ext)
        let o = PHAssetResourceRequestOptions()
        o.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: o)
            return target
        } catch {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
    }

    /// Startet einen PhotoKit-Request und wartet auf genau ein Ergebnis. Abbruch der Aufgabe beendet den Request und
    /// setzt sofort mit `nil` fort – unabhängig davon, ob PhotoKit danach noch antwortet.
    private static func photoKitRequest<T: Sendable>(_ start: (PhotoKitOneShot<T>) -> PHImageRequestID) async -> T? {
        let shot = PhotoKitOneShot<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
                guard shot.attach(cont) else {
                    cont.resume(returning: nil)
                    return
                }
                shot.started(start(shot))
            }
        } onCancel: {
            shot.cancel()
        }
    }
}

/// Bilddaten der aktuellen Fassung samt Typkennung (für die Dateiendung).
private struct ShareImageData: Sendable {
    let data: Data
    let uti: String?
}

/// Ein PhotoKit-Request, der genau einmal fortsetzt: mit dem Ergebnis oder – bei Abbruch – mit `nil`.
private final class PhotoKitOneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var requestID: PHImageRequestID?
    private var cancelled = false

    /// `false`: schon abgebrochen – keinen Request starten.
    func attach(_ c: CheckedContinuation<T?, Never>) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            continuation = c
            return true
        }
    }

    func started(_ id: PHImageRequestID) {
        let cancelNow = lock.withLock { () -> Bool in
            requestID = id
            return cancelled
        }
        if cancelNow { PHImageManager.default().cancelImageRequest(id) }
    }

    func finish(_ value: T?) {
        let c = lock.withLock { () -> CheckedContinuation<T?, Never>? in
            let c = continuation
            continuation = nil
            return c
        }
        c?.resume(returning: value)
    }

    func cancel() {
        let state = lock.withLock { () -> (CheckedContinuation<T?, Never>?, PHImageRequestID?) in
            cancelled = true
            let c = continuation
            continuation = nil
            return (c, requestID)
        }
        if let id = state.1 { PHImageManager.default().cancelImageRequest(id) }
        state.0?.resume(returning: nil)
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
