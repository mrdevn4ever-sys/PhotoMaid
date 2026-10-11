import CoreImage
import Foundation
import Photos
import PhotoMaidCore
import UIKit

enum EditSaveOutcome: Equatable {
    case copy(newID: String, bytes: Int64?)
    /// Kopie gespeichert, Original liegt in „Zuletzt gelöscht“.
    case replaced(newID: String)
    /// Ersetzen gewählt, Löschen des Originals aber abgelehnt: beide bleiben.
    case replaceDeclined(newID: String)
    /// Original nicht destruktiv bearbeitet (in der Fotos-App rücksetzbar). E15.
    case editedOriginal
}

enum EditSaveError: Error { case gone, render, write, declined }

/// Speichern einer Bearbeitung: Export → neues Medium (nie Überschreiben) → bei „Ersetzen“ Original nach Systembestätigung
/// in „Zuletzt gelöscht“ → Ledger (gespeicherte Fassung = „Behalten“; ersetztes Original verlässt Papierkorb/Später)
/// → Liste „Bearbeitet“. „Original bearbeiten“ (E15) nur auf ausdrückliche Wahl.
@MainActor
enum EditSaver {
    static func savePhoto(app: AppModel, assetID: String, data: Data, recipe: EditRecipe, mode: SaveMode,
                          removeLocation: Bool) async throws -> EditSaveOutcome {
        guard let asset = app.library.asset(assetID) else { throw EditSaveError.gone }
        if mode == .editOriginal { return try await editOriginal(app: app, asset: asset, recipe: recipe) }
        let name = PhotoLibraryService.originalFilename(assetID)
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
        let fileName = EditNames.copyName(original: name, suffix: L("edit_copy_suffix"), fileExtension: format.fileExtension)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: .atomic)
        } catch {
            throw EditSaveError.write
        }
        let req = PhotoLibraryService.SaveRequest(
            fileURL: url, isVideo: false, creationDate: asset.creationDate,
            latitude: removeLocation ? nil : asset.latitude, longitude: removeLocation ? nil : asset.longitude,
            favorite: mode == .replace && asset.isFavorite, albumID: nil, filename: fileName)
        guard case .saved(let newID) = await app.library.save(req) else { throw EditSaveError.write }
        return await finish(app: app, original: asset, newID: newID, mode: mode, video: false, kind: .edit,
                            bytes: Int64(encoded.count))
    }

    /// Gemeinsamer Abschluss für Foto, Video, Collage, Film: Ledger, Liste „Bearbeitet“, ggf. Original ersetzen.
    static func finish(app: AppModel, original: MediaAsset?, newID: String, mode: SaveMode, video: Bool, kind: EditKind,
                       count: Int = 1, sources: [String]? = nil, bytes: Int64?) async -> EditSaveOutcome {
        // Ausdrücklich gespeichert = behalten (sonst erschiene die Fassung als neues offenes Medium).
        await app.decide(.photo(newID), .keep)
        var replaced = false
        if mode == .replace, let original {
            let outcome = await app.library.delete(ids: [original.id])
            switch outcome {
            case .succeeded, .partial: replaced = true
            default: replaced = false
            }
            if replaced {
                let r = app.record(original.reference)
                switch r.disposition {
                case .markedForCleanup: await app.decide(original.reference, .unmark)
                case .later: await app.decide(original.reference, .removeDeferral)
                default: break
                }
            }
        }
        remember(app: app, newID: newID, sourceID: original?.id, mode: replaced ? .replace : .copy, video: video,
                 kind: kind, count: count, sources: sources)
        app.reloadLibraryIfNeeded(force: true)
        if mode == .replace { return replaced ? .replaced(newID: newID) : .replaceDeclined(newID: newID) }
        return .copy(newID: newID, bytes: bytes)
    }

    /// Nur in die Liste „Bearbeitet“ eintragen (Stapelwerkzeuge und Abläufe: Behalten und Neuladen erledigt der Aufrufer).
    /// `sources`: alle Quellmedien (Collage, Film, GIF) – damit Kopien von Medien im Tresor erkannt werden (E16).
    static func remember(app: AppModel, newID: String, sourceID: String?, mode: SaveMode = .copy, video: Bool = false,
                         kind: EditKind, count: Int = 1, sources: [String]? = nil) {
        var list = app.kv?.get(StoreKeys.edits) ?? []
        list.insert(EditRecord(newId: newID, sourceId: sourceID ?? "", mode: mode, video: video,
                               atMs: Int64(Date().timeIntervalSince1970 * 1000), kind: kind, count: count,
                               sources: sources), at: 0)
        try? app.kv?.set(StoreKeys.edits, Array(list.prefix(500)))
    }

    /// Original nicht destruktiv bearbeiten: `PHContentEditingOutput` mit gerendertem Ergebnis und dem Rezept als
    /// Anpassungsdaten. iOS fragt selbst nach; in der Fotos-App jederzeit „Original wiederherstellen“.
    static func editOriginal(app: AppModel, asset: MediaAsset, recipe: EditRecipe) async throws -> EditSaveOutcome {
        guard let ph = PhotoLibraryService.phAsset(asset.id), ph.canPerform(.content) else { throw EditSaveError.gone }
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = { _ in false }
        let box = UncheckedBox(ph)
        let input: UncheckedBox<PHContentEditingInput>? = await withCheckedContinuation { cont in
            box.value.requestContentEditingInput(with: options) { @Sendable input, _ in
                cont.resume(returning: input.map(UncheckedBox.init))
            }
        }
        guard let input, let url = input.value.fullSizeImageURL else { throw EditSaveError.gone }
        let output = PHContentEditingOutput(contentEditingInput: input.value)
        let recipeData = (try? JSONEncoder().encode(recipe)) ?? Data()
        output.adjustmentData = PHAdjustmentData(formatIdentifier: "app.photomaid.recipe", formatVersion: "1", data: recipeData)
        let target = output.renderedContentURL
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let data = try? Data(contentsOf: url), let src = EditRenderer.source(data) else { return false }
            let out = EditRenderer.shared.render(src, recipe: recipe)
            let meta = EditRenderer.metadata(data)
            guard let jpeg = EditRenderer.shared.encode(out, format: .jpeg, metadata: meta?.props, removeLocation: false)
            else { return false }
            return (try? jpeg.write(to: target, options: .atomic)) != nil
        }.value
        guard ok else { throw EditSaveError.render }
        let changeBox = UncheckedBox((ph, output))
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest(for: changeBox.value.0).contentEditingOutput = changeBox.value.1
            }
        } catch let e as PHPhotosError where e.code == .userCancelled {
            throw EditSaveError.declined
        } catch {
            Diagnostics.error(.editor, "edit-original-failed", error)
            throw EditSaveError.write
        }
        await app.decide(asset.reference, .keep)
        app.reloadLibraryIfNeeded(force: true)
        return .editedOriginal
    }
}
