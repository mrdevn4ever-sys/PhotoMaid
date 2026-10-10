import AVFoundation
import CoreImage
import Photos
import PhotoMaidCore
import UIKit

/// Eckdaten eines Videos (aus den Spurdaten; geschätzt wird nur die Bildrate, falls sie fehlt).
struct VideoInfo: Sendable, Equatable {
    /// Anzeigegröße (Drehung der Aufnahme schon berücksichtigt).
    let display: VSize
    let orientation: CGImagePropertyOrientation
    let fps: Float
    let hdr: Bool
    let hasAudio: Bool
    let durationMs: Int64
}

enum VideoError: Error { case missing, read, write, render, noAudio, cancelled }

/// Zugriff auf Videos der Mediathek: AVAsset (aktuelle Fassung, ohne Netzwerk außer auf Wunsch), Eckdaten,
/// genaue Einzelbilder und kleine Vorschaubilder für die Zeitleiste.
enum VideoSource {
    static func asset(_ id: String, allowNetwork: Bool = false) async -> AVAsset? {
        guard let ph = PhotoLibraryService.phAsset(id), ph.mediaType == .video else { return nil }
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = allowNetwork
        o.version = .current
        o.deliveryMode = .highQualityFormat
        let box = UncheckedBox(ph)
        let result: UncheckedBox<AVAsset>? = await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: box.value, options: o) { @Sendable av, _, _ in
                cont.resume(returning: av.map { UncheckedBox($0) })
            }
        }
        return result?.value
    }

    static func info(_ asset: AVAsset) async -> VideoInfo? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        guard let loaded = try? await track.load(.naturalSize, .preferredTransform, .nominalFrameRate) else { return nil }
        let (size, transform, fps) = loaded
        let characteristics = (try? await track.load(.mediaCharacteristics)) ?? []
        let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let duration = (try? await asset.load(.duration)) ?? .zero
        let o = orientation(transform)
        let natural = VSize(Int(abs(size.width).rounded()), Int(abs(size.height).rounded()))
        guard natural.width > 0, natural.height > 0 else { return nil }
        let display = swapsAxes(o) ? VSize(natural.height, natural.width) : natural
        return VideoInfo(display: display, orientation: o, fps: fps > 0 ? fps : 30,
                         hdr: characteristics.contains(.containsHDRVideo), hasAudio: !audio.isEmpty,
                         durationMs: Int64((duration.seconds * 1000).rounded()))
    }

    /// Drehung der Aufnahme aus der Spurmatrix (Standard: 0°, 90°, 180°, 270°; gespiegelt selten).
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        let a = t.a.rounded(), b = t.b.rounded(), c = t.c.rounded(), d = t.d.rounded()
        if a == 0 && b == 1 && c == -1 && d == 0 { return .right }
        if a == 0 && b == -1 && c == 1 && d == 0 { return .left }
        if a == -1 && b == 0 && c == 0 && d == -1 { return .down }
        if a == -1 && b == 0 && c == 0 && d == 1 { return .upMirrored }
        if a == 1 && b == 0 && c == 0 && d == -1 { return .downMirrored }
        if a == 0 && b == 1 && c == 1 && d == 0 { return .leftMirrored }
        if a == 0 && b == -1 && c == -1 && d == 0 { return .rightMirrored }
        return .up
    }

    static func swapsAxes(_ o: CGImagePropertyOrientation) -> Bool {
        switch o {
        case .left, .right, .leftMirrored, .rightMirrored: true
        default: false
        }
    }

    /// Genaues Bild zur Quellzeit (nicht das nächste Schlüsselbild), richtig gedreht. `maxEdge` nur für Vorschauen.
    static func frame(_ asset: AVAsset, sourceMs: Int64, maxEdge: CGFloat? = nil) async -> UncheckedBox<CGImage>? {
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        if let maxEdge {
            g.maximumSize = CGSize(width: maxEdge, height: maxEdge)
            g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
            g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        } else {
            g.requestedTimeToleranceBefore = .zero
            g.requestedTimeToleranceAfter = .zero
        }
        guard let result = try? await g.image(at: CMTime(value: max(0, sourceMs), timescale: 1000)) else { return nil }
        return UncheckedBox(result.image)
    }

    /// Für Aufrufer auf dem Main Actor, die das AVAsset halten: AVAsset ist nicht Sendable, ausgepackt wird erst hier.
    static func frame(_ asset: UncheckedBox<AVAsset>, sourceMs: Int64, maxEdge: CGFloat? = nil) async -> UncheckedBox<CGImage>? {
        await frame(asset.value, sourceMs: sourceMs, maxEdge: maxEdge)
    }

    static func thumbnails(_ asset: UncheckedBox<AVAsset>, durationMs: Int64, count: Int, height: CGFloat) async -> [UIImage] {
        await thumbnails(asset.value, durationMs: durationMs, count: count, height: height)
    }

    /// Kleine Bilder gleichmäßig über die ganze Dauer (Zeitleiste beim Kürzen).
    static func thumbnails(_ asset: AVAsset, durationMs: Int64, count: Int, height: CGFloat) async -> [UIImage] {
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: height * 2, height: height * 2)
        g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        var out: [UIImage] = []
        let n = max(1, count)
        for i in 0..<n {
            let ms = durationMs * Int64(i) / Int64(n) + durationMs / Int64(n * 2)
            if let r = try? await g.image(at: CMTime(value: ms, timescale: 1000)) { out.append(UIImage(cgImage: r.image)) }
        }
        return out
    }
}

extension CMTime {
    /// Millisekunden als CMTime (Zeitbasis 1000 – reicht für Schnitte und Blenden).
    static func ms(_ v: Int64) -> CMTime { CMTime(value: v, timescale: 1000) }
    var milliseconds: Int64 { isNumeric ? Int64((seconds * 1000).rounded()) : 0 }
}
