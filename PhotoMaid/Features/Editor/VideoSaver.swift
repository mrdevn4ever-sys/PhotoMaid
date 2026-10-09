import AVFoundation
import Foundation
import PhotoMaidCore

/// Speichern aus dem Video-Editor: immer neue Datei (nie überschreiben), gespeicherte Fassung = „Behalten“. „Ersetzen“
/// legt das Original erst nach Systembestätigung in „Zuletzt gelöscht“. Standbild = neues Foto. Ton = M4A über „Dateien“.
@MainActor
enum VideoSaver {
    static func save(app: AppModel, assetID: String, avAsset: AVAsset, info: VideoInfo, project: VideoProject,
                     mode: SaveMode) async throws -> EditSaveOutcome {
        guard let asset = app.library.asset(assetID) else { throw EditSaveError.gone }
        let name = PhotoLibraryService.originalFilename(assetID)
        let base = (EditNames.copyName(original: name, suffix: L("edit_copy_suffix"), fileExtension: "x") as NSString)
            .deletingPathExtension
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = UncheckedBox(avAsset)
        let url = try await ExportCoordinator.shared.run(title: L("vid_export_running")) { progress in
            try await VideoExportJob.renderEdit(asset: source.value, info: info, project: project, folder: folder,
                                                baseName: base, progress: progress)
        }
        let bytes = VideoExportJob.fileSize(url)
        let req = PhotoLibraryService.SaveRequest(
            fileURL: url, isVideo: true, creationDate: asset.creationDate, latitude: asset.latitude,
            longitude: asset.longitude, favorite: mode == .replace && asset.isFavorite, albumID: nil,
            filename: url.lastPathComponent)
        guard case .saved(let newID) = await app.library.save(req) else { throw EditSaveError.write }
        return await EditSaver.finish(app: app, original: asset, newID: newID, mode: mode == .replace ? .replace : .copy,
                                      video: true, kind: .edit, bytes: bytes)
    }

    /// Standbild zur Quellzeit als neues Foto (Aufnahmezeit = Video + Zeitpunkt). Das Video bleibt unverändert.
    static func saveFrame(app: AppModel, assetID: String, avAsset: AVAsset, info: VideoInfo, project: VideoProject,
                          sourceMs: Int64) async throws {
        guard let asset = app.library.asset(assetID) else { throw EditSaveError.gone }
        let source = UncheckedBox(avAsset)
        let data = await Task.detached(priority: .userInitiated) {
            await VideoExportJob.renderFrame(asset: source.value, info: info, project: project, sourceMs: sourceMs)
        }.value
        guard let data else { throw EditSaveError.render }
        let fileName = EditNames.copyName(original: PhotoLibraryService.originalFilename(assetID), suffix: L("vid_frame_suffix"),
                                          fileExtension: "jpg")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw EditSaveError.write
        }
        let created = asset.creationDate.map { $0.addingTimeInterval(Double(sourceMs) / 1000) }
        let req = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: false, creationDate: created,
                                                  latitude: asset.latitude, longitude: asset.longitude, favorite: false,
                                                  albumID: nil, filename: fileName)
        guard case .saved(let newID) = await app.library.save(req) else { throw EditSaveError.write }
        _ = await EditSaver.finish(app: app, original: asset, newID: newID, mode: .copy, video: false, kind: .frame,
                                   bytes: Int64(data.count))
    }

    /// Ton allein als M4A im Zwischenspeicher – der Nutzer wählt danach selbst den Ort in „Dateien“.
    static func exportAudio(app: AppModel, assetID: String, avAsset: AVAsset, info: VideoInfo,
                            project: VideoProject) async throws -> URL {
        let base = (EditNames.copyName(original: PhotoLibraryService.originalFilename(assetID), suffix: L("vid_audio_suffix"),
                                       fileExtension: "x") as NSString).deletingPathExtension
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString)", isDirectory: true)
        let source = UncheckedBox(avAsset)
        return try await ExportCoordinator.shared.run(title: L("vid_audio_running")) { progress in
            try await VideoExportJob.renderAudio(asset: source.value, info: info, project: project, folder: folder,
                                                 baseName: base, progress: progress)
        }
    }
}
