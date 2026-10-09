import AVFoundation
import CoreImage
import Foundation
import PhotoMaidCore

/// Rechenteil der Video-Exporte (außerhalb des Main Actors). Ergebnisse sind Dateien im Zwischenspeicher; gespeichert
/// wird danach über `PhotoLibraryService` (neues Medium, Original unverändert).
enum VideoExportJob {
    /// Bearbeitetes Einzelvideo. Nur gekürzt → ohne Neuberechnung; klappt das nicht, wird neu berechnet.
    static func renderEdit(asset: AVAsset, info: VideoInfo, project: VideoProject, folder: URL, baseName: String,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let clip = project.clips.first else { throw VideoError.missing }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if VideoEdit.isTrimOnly(project) {
            let fast = folder.appendingPathComponent(baseName + ".mov")
            do {
                try await VideoWriter.passthroughTrim(asset, startMs: clip.trimStartMs, endMs: clip.trimEndMs, to: fast,
                                                      progress: progress)
                return fast
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Diagnostics.error(.video, "passthrough-failed", error)
            }
        }
        let layout = VideoPlan.layout(display: info.display, clip: clip, project: project)
        let input = VideoBuilder.Input(project: project, assets: [clip.mediaId: asset], infos: [clip.mediaId: info],
                                       size: layout.output, fps: info.fps, forExport: true)
        let built = try await VideoBuilder.build(input)
        let url = folder.appendingPathComponent(baseName + ".mp4")
        let bitrate = project.targetBitrate ?? VideoPlan.videoBitrate(layout, fps: built.fps, profile: project.profile)
        try await VideoWriter.write(built, to: url, options: .init(videoBitrate: bitrate), progress: progress)
        return url
    }

    /// Nur der Ton als M4A (Schnitte, Tempo, Lautstärke, Blenden wie im Video).
    static func renderAudio(asset: AVAsset, info: VideoInfo, project: VideoProject, folder: URL, baseName: String,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let clip = project.clips.first else { throw VideoError.missing }
        guard info.hasAudio, !project.removeAudio, !clip.muted else { throw VideoError.noAudio }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = VideoBuilder.Input(project: project, assets: [clip.mediaId: asset], infos: [clip.mediaId: info],
                                       size: VSize(64, 64), fps: 30, forExport: true, includeLayers: false)
        let built = try await VideoBuilder.build(input)
        let url = folder.appendingPathComponent(baseName + ".m4a")
        try await VideoWriter.write(built, to: url, options: .init(videoBitrate: 0, audioOnly: true, fileType: .m4a),
                                    progress: progress)
        return url
    }

    /// Film/Diashow aus mehreren Clips (gemeinsame Ausgabegröße, Übergänge, Musik).
    static func renderMovie(project: VideoProject, assets: [String: AVAsset], infos: [String: VideoInfo], frame: VSize,
                            fps: Float, musicURL: URL?, allowNetwork: Bool, folder: URL, baseName: String,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = VideoBuilder.Input(project: project, assets: assets, infos: infos, size: frame, fps: fps, forExport: true,
                                       allowNetwork: allowNetwork, musicURL: musicURL)
        let built = try await VideoBuilder.build(input)
        let url = folder.appendingPathComponent(baseName + ".mp4")
        let bitrate = project.targetBitrate ?? movieBitrate(frame, fps: built.fps, profile: project.profile)
        try await VideoWriter.write(built, to: url, options: .init(videoBitrate: bitrate), progress: progress)
        return url
    }

    /// Standbild in voller Größe, wie das Bild im Video (Drehung, Ausschnitt, Format, Farbe, sichtbare Texte/Sticker).
    static func renderFrame(asset: AVAsset, info: VideoInfo, project: VideoProject, sourceMs: Int64) async -> Data? {
        guard let clip = project.clips.first, let cg = await VideoSource.frame(asset, sourceMs: sourceMs) else { return nil }
        var full = project
        full.profile = .high
        full.targetShortSide = nil
        let layout = VideoPlan.layout(display: info.display, clip: clip, project: full)
        let plan = RenderPlan(project: full, size: CGSize(width: layout.output.width, height: layout.output.height),
                              clips: [RenderPlan.Clip(clip: clip, recipe: VideoEdit.recipe(clip), orientation: .up, startMs: 0)],
                              includeLayers: true, allowNetwork: false)
        let outMs = VideoPlan.toOutputMs(clip, sourceMs: sourceMs) ?? 0
        let img = FrameComposer.compose(EditRenderer.source(cg.value), clip: plan.clips[0], plan: plan, outMs: outMs,
                                        fadeLayers: false)
        return EditRenderer.shared.encode(img, format: .jpeg, metadata: nil, removeLocation: true)
    }

    /// Wie `VideoPlan.videoBitrate`, für die gemeinsame Filmgröße.
    static func movieBitrate(_ frame: VSize, fps: Float, profile: ExportProfile) -> Int {
        let v = Double(frame.width) * Double(frame.height) * Double(min(max(fps, 1), 120)) * Double(profile.bitsPerPixel)
        return Int(min(max(v, 500_000), 120_000_000))
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
    }
}
