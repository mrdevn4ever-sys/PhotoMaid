import Foundation

/// Bild- und Videobearbeitung im Tresor (Nutzerwunsch 21.10.2026): Die bearbeitete Fassung ist ein neues Medium im
/// Tresor – nie in der Fotos-App, nie unter „Bearbeitet“, nie im Verlauf. Sie hat keine Kennung in der Fotos-App
/// (`sourceID`/`originalID` leer), verbirgt oder zeigt dort also nichts.
public enum VaultEdit {
    /// Neue Fassung neben dem Original: gleicher Ordner und Aufnahmezeitpunkt (bei Standbildern plus Videozeit),
    /// Standort nur ohne „Standort entfernen“, Favorit nur beim Ersetzen.
    public static func item(from original: VaultItem, id: String, kind: VaultMediaKind, resource: VaultResource,
                            addedMs: Int64, creationOffsetMs: Int64 = 0, removeLocation: Bool, replace: Bool,
                            duration: Double, pixelWidth: Int, pixelHeight: Int, thumbnail: String?) -> VaultItem {
        VaultItem(id: id, kind: kind, folderID: original.folderID, resources: [resource],
                  creationMs: original.creationMs.map { $0 + creationOffsetMs }, addedMs: addedMs,
                  latitude: removeLocation ? nil : original.latitude, longitude: removeLocation ? nil : original.longitude,
                  isFavorite: replace && original.isFavorite, duration: duration, pixelWidth: pixelWidth,
                  pixelHeight: pixelHeight, thumbnail: thumbnail, sourceID: nil, originalID: nil)
    }
}

extension VaultSnapshot {
    /// Bearbeitete Fassung ablegen. „Ersetzen“ legt das Original im selben Schreibvorgang in den Tresor-Papierkorb
    /// (wiederherstellbar, nie endgültig gelöscht).
    public mutating func addEdited(_ item: VaultItem, replacing originalID: String?, nowMs: Int64) throws {
        media.add(item)
        guard let originalID, originalID != item.id else { return }
        for old in media.remove(ids: [originalID]) {
            workspace.mediaTrash.append(VaultTrashedMedia(id: old.id, deletedMs: nowMs,
                                                          encodedItem: try JSONEncoder().encode(old)))
        }
    }
}
