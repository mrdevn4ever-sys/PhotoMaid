import Foundation

/// A note-only write-ahead record. A full snapshot advances the sequence, making all previous
/// journals obsolete, including journals of notes that were deliberately trashed or deleted.
public struct VaultNoteJournal: Codable, Equatable, Sendable {
    public var version = 1
    public let snapshotSequence: UInt64
    public let baseRevision: UInt64?
    public let note: VaultNote
    public init(snapshotSequence: UInt64, baseRevision: UInt64?, note: VaultNote) {
        self.snapshotSequence = snapshotSequence; self.baseRevision = baseRevision; self.note = note
    }
    @discardableResult
    public func apply(to workspace: inout VaultWorkspace, snapshotSequence current: UInt64) throws -> Bool {
        guard version == 1, snapshotSequence <= current else { throw VaultWorkspaceError.invalidData }
        guard snapshotSequence == current else { return false }
        guard note.trashedMs == nil, note.revision > 0 else { throw VaultWorkspaceError.invalidData }
        if let index = workspace.notes.firstIndex(where: { $0.id == note.id }) {
            let existing = workspace.notes[index]
            if existing == note { return false }
            guard baseRevision == existing.revision, existing.trashedMs == nil,
                  note.revision > existing.revision, note.createdMs == existing.createdMs else { throw VaultWorkspaceError.conflict }
            var candidate = workspace; candidate.notes[index] = note; try candidate.validate(); workspace = candidate
        } else {
            guard baseRevision == nil else { throw VaultWorkspaceError.conflict }
            var candidate = workspace; candidate.notes.append(note); try candidate.validate(); workspace = candidate
        }
        return true
    }
}
