import AVFoundation
import Foundation
import PhotoMaidCore
import UniformTypeIdentifiers

/// Speichern aus dem Editor im Tresor: dieselbe Darstellung wie außerhalb (ein Rezept, ein Export), aber das Ergebnis
/// geht nur in den Tresor – kein Fotos-App-Eintrag, kein „Behalten“ im Verlauf, keine Liste „Bearbeitet“.
/// „Ersetzen“ legt das Original in den Tresor-Papierkorb (wiederherstellbar).
@MainActor
enum VaultEditSaver {
    static func savePhoto(itemID: String, sourceName: String?, data: Data, recipe: EditRecipe, mode: SaveMode,
                          removeLocation: Bool, unlimited: Bool, lease: VaultSessionLease) async throws -> VaultEditResult {
        let rendered = await Task.detached(priority: .userInitiated) { () -> (Data, EditFormat)? in
            guard let src = EditRenderer.source(data) else { return nil }
            let meta = EditRenderer.metadata(data)
            let format = EditFormat.forSource(uti: meta?.uti)
            let out = EditRenderer.shared.render(src, recipe: recipe)
            guard let encoded = EditRenderer.shared.encode(out, format: format, metadata: meta?.props, removeLocation: removeLocation)
            else { return nil }
            return (encoded, format)
        }.value
        guard let rendered else { throw EditSaveError.render }
        let (encoded, format) = rendered
        let name = EditNames.copyName(original: sourceName, suffix: L("edit_copy_suffix"), fileExtension: format.fileExtension)
        return try await VaultStore.shared.addEditedMedia(.data(encoded), video: false, uti: format.utType, filename: name,
                                                          basedOn: itemID, removeLocation: removeLocation,
                                                          replace: mode == .replace, unlimited: unlimited, lease: lease)
    }

    /// Video in die geschützte Temp-Ablage der Sitzung exportieren, verschlüsselt ablegen, Klartext sofort löschen.
    static func saveVideo(itemID: String, sourceName: String?, avAsset: AVAsset, info: VideoInfo, project: VideoProject,
                          mode: SaveMode, unlimited: Bool, lease: VaultSessionLease) async throws -> VaultEditResult {
        let vault = VaultStore.shared
        let folder = try vault.editTempFolder(lease: lease)
        defer { try? FileManager.default.removeItem(at: folder) }
        vault.beginEditWork()
        defer { vault.endEditWork() }
        let base = (EditNames.copyName(original: sourceName, suffix: L("edit_copy_suffix"), fileExtension: "x") as NSString)
            .deletingPathExtension
        let source = UncheckedBox(avAsset)
        let url = try await ExportCoordinator.shared.run(title: L("vid_export_running"), vaultOwned: true) { progress in
            try lease.check()
            return try await VideoExportJob.renderEdit(asset: source.value, info: info, project: project, folder: folder,
                                                       baseName: base, isolated: true, progress: progress)
        }
        return try await vault.addEditedMedia(.file(url), video: true, uti: UTType.videoIdentifier(for: url),
                                              filename: url.lastPathComponent, basedOn: itemID, removeLocation: false,
                                              replace: mode == .replace, unlimited: unlimited, lease: lease)
    }

    /// Videos aus dem Tresor zu einem Film zusammenfügen (gleicher Export wie „Video zusammenfügen“ im Studio). Das
    /// Ergebnis liegt im Ordner des ersten Clips, ohne Standort; die Quellen bleiben unverändert.
    static func saveMovie(project: VideoProject, assets: [String: AVAsset], infos: [String: VideoInfo], frame: VSize,
                          basedOn firstID: String, unlimited: Bool, lease: VaultSessionLease) async throws -> VaultEditResult {
        let vault = VaultStore.shared
        let folder = try vault.editTempFolder(lease: lease)
        defer { try? FileManager.default.removeItem(at: folder) }
        vault.beginEditWork()
        defer { vault.endEditWork() }
        let boxedAssets = UncheckedBox(assets)
        let url = try await ExportCoordinator.shared.run(title: L("movie_running"), vaultOwned: true) { progress in
            try lease.check()
            return try await VideoExportJob.renderMovie(project: project, assets: boxedAssets.value, infos: infos,
                                                        frame: frame, fps: 30, musicURL: nil, allowNetwork: false,
                                                        folder: folder, baseName: AppConfig.brandName, isolated: true,
                                                        progress: progress)
        }
        return try await vault.addEditedMedia(.file(url), video: true, uti: UTType.videoIdentifier(for: url),
                                              filename: url.lastPathComponent, basedOn: firstID, removeLocation: true,
                                              replace: false, unlimited: unlimited, lease: lease)
    }

    /// Standbild zur Quellzeit als neues Foto im Tresor (Aufnahmezeit = Video + Zeitpunkt).
    static func saveFrame(itemID: String, sourceName: String?, avAsset: AVAsset, info: VideoInfo, project: VideoProject,
                          sourceMs: Int64, unlimited: Bool, lease: VaultSessionLease) async throws -> VaultEditResult {
        let source = UncheckedBox(avAsset)
        let data = await Task.detached(priority: .userInitiated) {
            await VideoExportJob.renderFrame(asset: source.value, info: info, project: project, sourceMs: sourceMs)
        }.value
        guard let data else { throw EditSaveError.render }
        let name = EditNames.copyName(original: sourceName, suffix: L("vid_frame_suffix"), fileExtension: "jpg")
        return try await VaultStore.shared.addEditedMedia(.data(data), video: false, uti: UTType.jpeg.identifier,
                                                          filename: name, basedOn: itemID, creationOffsetMs: sourceMs, frame: true,
                                                          removeLocation: false, replace: false, unlimited: unlimited,
                                                          lease: lease)
    }

    /// Hinweistext für Fehler beim Speichern im Tresor.
    static func message(for error: any Error) -> String {
        switch error {
        case is CancellationError: L("export_cancelled")
        case ExportCoordinator.Failure.expired: L("export_expired")
        case ExportCoordinator.Failure.busy: L("export_busy")
        case VaultEditError.limit: L("vault_limit_reached", VaultPolicy.freeItemLimit)
        case VaultCryptoError.authentication: L("vault_error_generic")
        default: L("edit_err_save")
        }
    }
}
