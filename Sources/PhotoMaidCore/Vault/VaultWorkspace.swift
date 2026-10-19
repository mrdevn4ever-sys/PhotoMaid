import Foundation

/// These values may only be persisted inside the authenticated, encrypted vault index.
/// They intentionally have no public-library, Spotlight, analytics or cloud adapters.
public enum VaultWorkspaceError: Error, Equatable, Sendable {
    case invalidName, duplicateName, missingItem, invalidFolder, conflict
    case invalidData, unsupportedVersion, attachmentInUse, notInTrash
}

public enum VaultFolderScope: String, Codable, CaseIterable, Sendable { case notes, files }
public enum VaultNoteStyle: String, Codable, CaseIterable, Sendable { case paragraph, heading, bullet, checklist }

public struct VaultNoteBlock: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var style: VaultNoteStyle
    public var text: String
    public var bold: Bool
    public var checked: Bool

    public init(id: String = UUID().uuidString, style: VaultNoteStyle = .paragraph,
                text: String = "", bold: Bool = false, checked: Bool = false) {
        self.id = id; self.style = style; self.text = text; self.bold = bold; self.checked = checked
    }
}

public struct VaultNote: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var blocks: [VaultNoteBlock]
    public var attachmentIDs: [String]
    public var folderID: String?
    public var pinned: Bool
    public let createdMs: Int64
    public var modifiedMs: Int64
    public var revision: UInt64
    public var trashedMs: Int64?

    public init(id: String = UUID().uuidString, title: String = "", nowMs: Int64) {
        self.id = id; self.title = title; blocks = [VaultNoteBlock()]; attachmentIDs = []
        folderID = nil; pinned = false; createdMs = nowMs; modifiedMs = nowMs; revision = 0; trashedMs = nil
    }

    public var plainText: String {
        blocks.map { block in
            switch block.style {
            case .heading: "# " + block.text
            case .bullet: "• " + block.text
            case .checklist: (block.checked ? "☑ " : "☐ ") + block.text
            case .paragraph: block.text
            }
        }.joined(separator: "\n")
    }
}

public enum VaultFileOrigin: String, Codable, Sendable {
    /// Importing a file is a verified copy, never evidence that its source was deleted.
    case copied, sourceRemoved, createdInsideVault, restoredFromBackup
}

public struct VaultDocument: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var folderID: String?
    public var objectName: String
    public var typeIdentifier: String
    public var byteCount: Int64
    public var sha256: String
    public let createdMs: Int64
    public var modifiedMs: Int64
    public var trashedMs: Int64?
    public var origin: VaultFileOrigin
    /// Optional security-scoped source bookmark. This is sensitive and stays encrypted with the index.
    public var sourceBookmark: Data?
    /// System-Datei-ID der Quelle (nur im verschlüsselten Index), damit PhotoMaid das Original in verbundenen Ordnern
    /// nicht mehr zeigt, solange die Datei im Tresor liegt.
    public var sourceKey: String?

    public init(id: String = UUID().uuidString, name: String, objectName: String, typeIdentifier: String,
                byteCount: Int64, sha256: String, nowMs: Int64,
                origin: VaultFileOrigin = .copied, sourceBookmark: Data? = nil, sourceKey: String? = nil) {
        self.id = id; self.name = name; self.objectName = objectName; self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount; self.sha256 = sha256; createdMs = nowMs; modifiedMs = nowMs
        self.origin = origin; self.sourceBookmark = sourceBookmark; self.sourceKey = sourceKey
        folderID = nil; trashedMs = nil
    }
}

public struct VaultWorkspaceFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public let scope: VaultFolderScope
    public let createdMs: Int64
    public init(id: String = UUID().uuidString, name: String, scope: VaultFolderScope, createdMs: Int64) {
        self.id = id; self.name = name; self.scope = scope; self.createdMs = createdMs
    }
}

/// The app encodes the existing VaultItem here. Keeping the bytes in the same encrypted transaction
/// allows media to leave the live grid without deleting any resource file.
public struct VaultTrashedMedia: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let deletedMs: Int64
    public let encodedItem: Data
    public init(id: String, deletedMs: Int64, encodedItem: Data) {
        self.id = id; self.deletedMs = deletedMs; self.encodedItem = encodedItem
    }
}

public enum VaultWorkspaceSort: String, Codable, CaseIterable, Sendable { case modified, name, size }

public struct VaultWorkspace: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version = currentVersion
    public var notes: [VaultNote] = []
    public var files: [VaultDocument] = []
    public var folders: [VaultWorkspaceFolder] = []
    public var mediaTrash: [VaultTrashedMedia] = []
    /// Resource names waiting for physical deletion after their index references were durably removed.
    /// These are opaque names, never caller-supplied paths.
    public var pendingObjectPurges: Set<String> = []
    public var pendingThumbnailPurges: Set<String> = []
    public var inactivitySeconds = 120

    public init() {}

    public var trashCount: Int { notes.filter { $0.trashedMs != nil }.count + files.filter { $0.trashedMs != nil }.count + mediaTrash.count }

    public func visibleNotes(query: String = "", folderID: String? = nil) -> [VaultNote] {
        let needle = Self.searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return notes.filter {
            $0.trashedMs == nil && (folderID == nil || $0.folderID == folderID) &&
            (needle.isEmpty || Self.searchKey($0.title + "\n" + $0.plainText).contains(needle))
        }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.modifiedMs != $1.modifiedMs { return $0.modifiedMs > $1.modifiedMs }
            return $0.id < $1.id
        }
    }

    public func visibleFiles(query: String = "", folderID: String? = nil, sort: VaultWorkspaceSort = .modified) -> [VaultDocument] {
        let needle = Self.searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return files.filter {
            $0.trashedMs == nil && (folderID == nil || $0.folderID == folderID) &&
            (needle.isEmpty || Self.searchKey($0.name).contains(needle))
        }.sorted {
            switch sort {
            case .modified: if $0.modifiedMs != $1.modifiedMs { return $0.modifiedMs > $1.modifiedMs }
            case .size: if $0.byteCount != $1.byteCount { return $0.byteCount > $1.byteCount }
            case .name:
                let cmp = $0.name.compare($1.name, options: [.caseInsensitive, .numeric])
                if cmp != .orderedSame { return cmp == .orderedAscending }
            }
            return $0.id < $1.id
        }
    }

    /// A caller must persist a candidate copy before publishing it to UI state.
    /// Revision checks prevent a stale editor from overwriting a newer note or resurrecting trash.
    public mutating func saveNote(_ draft: VaultNote, expectedRevision: UInt64?, nowMs: Int64) throws {
        guard draft.trashedMs == nil, draft.title.utf8.count <= 4096, draft.blocks.count <= 4096,
              draft.blocks.reduce(0, { $0 + $1.text.utf8.count }) <= 2 * 1024 * 1024,
              Set(draft.blocks.map(\.id)).count == draft.blocks.count,
              Set(draft.attachmentIDs).count == draft.attachmentIDs.count else { throw VaultWorkspaceError.invalidData }
        try requireFolder(draft.folderID, scope: .notes)
        guard draft.attachmentIDs.allSatisfy({ id in files.contains { $0.id == id && $0.trashedMs == nil } })
        else { throw VaultWorkspaceError.missingItem }
        var saved = draft
        if let i = notes.firstIndex(where: { $0.id == draft.id }) {
            guard notes[i].trashedMs == nil, expectedRevision == notes[i].revision,
                  draft.createdMs == notes[i].createdMs, notes[i].revision < UInt64.max else { throw VaultWorkspaceError.conflict }
            saved.revision = notes[i].revision + 1
            saved.modifiedMs = max(nowMs, notes[i].modifiedMs)
            notes[i] = saved
        } else {
            guard expectedRevision == nil, VaultWorkspace.isOpaqueName(draft.id) else { throw VaultWorkspaceError.conflict }
            saved.revision = 1; saved.modifiedMs = nowMs; notes.append(saved)
        }
    }

    public mutating func addFile(_ file: VaultDocument, folderID: String? = nil) throws {
        try requireFolder(folderID, scope: .files)
        guard !files.contains(where: { $0.id == file.id || $0.objectName == file.objectName }) else { throw VaultWorkspaceError.conflict }
        try Self.validateFile(file)
        var value = file; value.folderID = folderID
        files.append(value)
    }

    public mutating func renameFile(_ id: String, name: String, nowMs: Int64) throws {
        guard let i = files.firstIndex(where: { $0.id == id && $0.trashedMs == nil }) else { throw VaultWorkspaceError.missingItem }
        files[i].name = try Self.cleanName(name)
        files[i].modifiedMs = max(files[i].modifiedMs, nowMs)
    }

    @discardableResult
    public mutating func createFolder(name: String, scope: VaultFolderScope, nowMs: Int64) throws -> VaultWorkspaceFolder {
        let clean = try Self.cleanName(name)
        guard !folders.contains(where: { $0.scope == scope && Self.searchKey($0.name) == Self.searchKey(clean) })
        else { throw VaultWorkspaceError.duplicateName }
        let folder = VaultWorkspaceFolder(name: clean, scope: scope, createdMs: nowMs)
        folders.append(folder)
        return folder
    }

    public mutating func renameFolder(_ id: String, name: String) throws {
        let clean = try Self.cleanName(name)
        guard let i = folders.firstIndex(where: { $0.id == id }) else { throw VaultWorkspaceError.invalidFolder }
        let scope = folders[i].scope
        guard !folders.contains(where: { $0.id != id && $0.scope == scope && Self.searchKey($0.name) == Self.searchKey(clean) })
        else { throw VaultWorkspaceError.duplicateName }
        folders[i].name = clean
    }

    /// Removing a folder never removes its contents, including trashed entries.
    public mutating func removeFolder(_ id: String) {
        folders.removeAll { $0.id == id }
        for i in notes.indices where notes[i].folderID == id { notes[i].folderID = nil }
        for i in files.indices where files[i].folderID == id { files[i].folderID = nil }
    }

    public mutating func move(_ ids: Set<String>, scope: VaultFolderScope, folderID: String?, nowMs: Int64) throws {
        try requireFolder(folderID, scope: scope)
        switch scope {
        case .notes:
            let indices = notes.indices.filter { ids.contains(notes[$0].id) && notes[$0].trashedMs == nil }
            guard indices.count == ids.count, indices.allSatisfy({ notes[$0].revision < UInt64.max }) else { throw VaultWorkspaceError.conflict }
            for i in indices { notes[i].folderID = folderID; notes[i].revision += 1; notes[i].modifiedMs = max(notes[i].modifiedMs, nowMs) }
        case .files:
            let indices = files.indices.filter { ids.contains(files[$0].id) && files[$0].trashedMs == nil }
            guard indices.count == ids.count else { throw VaultWorkspaceError.missingItem }
            for i in indices { files[i].folderID = folderID; files[i].modifiedMs = max(files[i].modifiedMs, nowMs) }
        }
    }

    public mutating func trash(_ ids: Set<String>, scope: VaultFolderScope, nowMs: Int64) throws {
        switch scope {
        case .notes:
            let indices = notes.indices.filter { ids.contains(notes[$0].id) && notes[$0].trashedMs == nil }
            guard indices.count == ids.count, indices.allSatisfy({ notes[$0].revision < UInt64.max }) else { throw VaultWorkspaceError.conflict }
            for i in indices { notes[i].trashedMs = nowMs; notes[i].revision += 1 }
        case .files:
            guard !notes.contains(where: { $0.attachmentIDs.contains(where: ids.contains) }) else { throw VaultWorkspaceError.attachmentInUse }
            let indices = files.indices.filter { ids.contains(files[$0].id) && files[$0].trashedMs == nil }
            guard indices.count == ids.count else { throw VaultWorkspaceError.missingItem }
            for i in indices { files[i].trashedMs = nowMs }
        }
    }

    public mutating func restore(_ ids: Set<String>, scope: VaultFolderScope) throws {
        switch scope {
        case .notes:
            let indices = notes.indices.filter { ids.contains(notes[$0].id) && notes[$0].trashedMs != nil }
            guard indices.count == ids.count, indices.allSatisfy({ notes[$0].revision < UInt64.max }) else { throw VaultWorkspaceError.notInTrash }
            for i in indices { notes[i].trashedMs = nil; notes[i].revision += 1 }
        case .files:
            let indices = files.indices.filter { ids.contains(files[$0].id) && files[$0].trashedMs != nil }
            guard indices.count == ids.count else { throw VaultWorkspaceError.notInTrash }
            for i in indices { files[i].trashedMs = nil }
        }
    }

    public mutating func permanentlyRemove(_ ids: Set<String>, scope: VaultFolderScope) throws {
        switch scope {
        case .notes:
            guard notes.filter({ ids.contains($0.id) && $0.trashedMs != nil }).count == ids.count else { throw VaultWorkspaceError.notInTrash }
            notes.removeAll { ids.contains($0.id) }
        case .files:
            guard !notes.contains(where: { $0.attachmentIDs.contains(where: ids.contains) }) else { throw VaultWorkspaceError.attachmentInUse }
            let removed = files.filter { ids.contains($0.id) && $0.trashedMs != nil }
            guard removed.count == ids.count else { throw VaultWorkspaceError.notInTrash }
            pendingObjectPurges.formUnion(removed.map(\.objectName))
            files.removeAll { ids.contains($0.id) }
        }
    }

    public func validate() throws {
        guard version == Self.currentVersion else { throw VaultWorkspaceError.unsupportedVersion }
        guard [30, 60, 120, 300, 600].contains(inactivitySeconds),
              Set(notes.map(\.id)).count == notes.count, Set(files.map(\.id)).count == files.count,
              Set(files.map(\.objectName)).count == files.count, Set(folders.map(\.id)).count == folders.count,
              Set(mediaTrash.map(\.id)).count == mediaTrash.count,
              pendingObjectPurges.allSatisfy(Self.isOpaqueName), pendingThumbnailPurges.allSatisfy(Self.isOpaqueName),
              pendingObjectPurges.isDisjoint(with: Set(files.map(\.objectName))) else { throw VaultWorkspaceError.invalidData }
        for file in files { try Self.validateFile(file); try requireFolder(file.folderID, scope: .files) }
        for folder in folders { guard Self.isOpaqueName(folder.id) else { throw VaultWorkspaceError.invalidData }; _ = try Self.cleanName(folder.name) }
        for note in notes {
            guard Self.isOpaqueName(note.id), note.title.utf8.count <= 4096, note.blocks.count <= 4096,
                  note.blocks.reduce(0, { $0 + $1.text.utf8.count }) <= 2 * 1024 * 1024,
                  Set(note.blocks.map(\.id)).count == note.blocks.count,
                  Set(note.attachmentIDs).count == note.attachmentIDs.count,
                  note.attachmentIDs.allSatisfy({ id in files.contains { $0.id == id && $0.trashedMs == nil } })
            else { throw VaultWorkspaceError.invalidData }
            try requireFolder(note.folderID, scope: .notes)
        }
        for media in mediaTrash {
            guard Self.isOpaqueName(media.id), !media.encodedItem.isEmpty, media.encodedItem.count <= 1 << 20 else { throw VaultWorkspaceError.invalidData }
        }
    }

    public static func isOpaqueName(_ name: String) -> Bool {
        name.count == 36 && UUID(uuidString: name) != nil
    }

    public static func cleanName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 255, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw VaultWorkspaceError.invalidName }
        return name
    }

    private func requireFolder(_ id: String?, scope: VaultFolderScope) throws {
        if let id, !folders.contains(where: { $0.id == id && $0.scope == scope }) { throw VaultWorkspaceError.invalidFolder }
    }

    private static func validateFile(_ file: VaultDocument) throws {
        guard isOpaqueName(file.id), isOpaqueName(file.objectName), file.byteCount >= 0,
              file.sha256.count == 64, file.sha256.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              !file.typeIdentifier.isEmpty, file.typeIdentifier.utf8.count <= 256,
              (file.sourceKey?.utf8.count ?? 0) <= 1024 else { throw VaultWorkspaceError.invalidData }
        _ = try cleanName(file.name)
    }

    private static func searchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
