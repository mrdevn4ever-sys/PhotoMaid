import Foundation

/// Ein verschlüsselter Schnappschuss für Medien, Notizen, Dateien und den Tresor-Papierkorb: eine Wahrheit, ein
/// atomarer Schreibvorgang (nie zwei unabhängig geschriebene Inhaltsverzeichnisse). Version 1 ist das reine
/// Medien-Inhaltsverzeichnis früherer Builds; es wird beim Öffnen ohne Verlust übernommen.
public struct VaultSnapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 2
    public var version = VaultSnapshot.currentVersion
    /// Steigt mit jedem gespeicherten Schnappschuss und macht ältere Notiz-Journale ungültig.
    public var sequence: UInt64 = 0
    public var media: VaultIndex
    public var workspace: VaultWorkspace

    public init(sequence: UInt64 = 0, media: VaultIndex = VaultIndex(), workspace: VaultWorkspace = VaultWorkspace()) {
        self.sequence = sequence
        self.media = media
        self.workspace = workspace
    }

    /// Liest Version 1 (nur Medien) und Version 2. Unbekannte Versionen werden abgelehnt, nie geraten.
    public static func decode(_ data: Data) throws -> VaultSnapshot {
        struct Header: Decodable { let version: Int? }
        let decoder = JSONDecoder()
        switch try decoder.decode(Header.self, from: data).version ?? VaultIndex.currentVersion {
        case VaultIndex.currentVersion:
            return VaultSnapshot(media: try decoder.decode(VaultIndex.self, from: data))
        case currentVersion:
            return try decoder.decode(VaultSnapshot.self, from: data)
        default:
            throw VaultWorkspaceError.unsupportedVersion
        }
    }

    /// Medien im Tresor einschließlich Tresor-Papierkorb.
    public var allMedia: [VaultItem] {
        media.items + workspace.mediaTrash.compactMap { try? JSONDecoder().decode(VaultItem.self, from: $0.encodedItem) }
    }

    /// Belegte Plätze für das Free-Limit (der Tresor-Papierkorb zählt mit, bis er endgültig geleert ist).
    public var mediaSlotsUsed: Int { media.items.count + workspace.mediaTrash.count }

    /// Kennungen der Originale aller Medien im Tresor, auch im Tresor-Papierkorb (für die Verbergen-Liste).
    public var originalIDs: Set<String> { Set(allMedia.flatMap(\.concealmentIDs)) }

    /// Schlüssel für die Verbergen-Liste einer Datei aus einem verbundenen Ordner (System-Datei-ID).
    public static func fileConcealmentKey(_ sourceKey: String) -> String { "file:" + sourceKey }

    /// Originale von Dateien im Tresor (auch im Tresor-Papierkorb), die PhotoMaid in verbundenen Ordnern nicht zeigt.
    public var fileConcealmentKeys: Set<String> {
        Set(workspace.files.compactMap { $0.sourceKey.map(Self.fileConcealmentKey) })
    }

    /// Medien endgültig aus dem Tresor-Papierkorb entfernen. Ihre Dateien und Vorschaubilder werden nur vorgemerkt und
    /// erst nach dem gespeicherten Schnappschuss physisch gelöscht. Liefert die entfernten Medien (deren Originale
    /// zeigt PhotoMaid danach wieder).
    public mutating func purgeTrashedMedia(_ ids: Set<String>) throws -> [VaultItem] {
        let selected = workspace.mediaTrash.filter { ids.contains($0.id) }
        guard selected.count == ids.count else { throw VaultWorkspaceError.notInTrash }
        let items = try selected.map { try JSONDecoder().decode(VaultItem.self, from: $0.encodedItem) }
        for item in items {
            workspace.pendingObjectPurges.formUnion(item.resources.map(\.file).filter(VaultWorkspace.isOpaqueName))
            if let thumb = item.thumbnail, VaultWorkspace.isOpaqueName(thumb) { workspace.pendingThumbnailPurges.insert(thumb) }
        }
        workspace.mediaTrash.removeAll { ids.contains($0.id) }
        return items
    }

    /// Den ganzen Tresor-Papierkorb in einem Schritt endgültig leeren – alles oder nichts. Notizen zuerst, damit
    /// Dateien frei werden, die nur noch an gelöschten Notizen hingen. Liefert die entfernten Medien.
    public mutating func emptyTrash() throws -> [VaultItem] {
        try workspace.permanentlyRemove(Set(workspace.notes.filter { $0.trashedMs != nil }.map(\.id)), scope: .notes)
        try workspace.permanentlyRemove(Set(workspace.files.filter { $0.trashedMs != nil }.map(\.id)), scope: .files)
        return try purgeTrashedMedia(Set(workspace.mediaTrash.map(\.id)))
    }

    public func validate() throws {
        guard version == Self.currentVersion, media.version == VaultIndex.currentVersion,
              Set(media.items.map(\.id)).count == media.items.count,
              Set(media.folders.map(\.id)).count == media.folders.count else { throw VaultWorkspaceError.invalidData }
        try workspace.validate()
        var all = media.items
        for archived in workspace.mediaTrash {
            let item = try JSONDecoder().decode(VaultItem.self, from: archived.encodedItem)
            guard item.id == archived.id, !media.items.contains(where: { $0.id == item.id }) else {
                throw VaultWorkspaceError.invalidData
            }
            all.append(item)
        }
        for item in all {
            guard !item.resources.isEmpty,
                  item.resources.allSatisfy({ VaultPathRules.isComponent($0.file) && $0.size >= 0 }),
                  item.thumbnail.map(VaultPathRules.isComponent) ?? true else { throw VaultWorkspaceError.invalidData }
        }
        let active = Set(all.flatMap(\.resources).map(\.file) + workspace.files.map(\.objectName))
        guard active.isDisjoint(with: workspace.pendingObjectPurges),
              Set(all.compactMap(\.thumbnail)).isDisjoint(with: workspace.pendingThumbnailPurges) else {
            throw VaultWorkspaceError.invalidData
        }
    }
}
