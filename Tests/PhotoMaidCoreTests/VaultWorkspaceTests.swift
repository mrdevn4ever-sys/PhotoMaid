import Foundation
import Testing
@testable import PhotoMaidCore

@Suite("Vault workspace domain")
struct VaultWorkspaceTests {
    private func file(name: String = "private.pdf", size: Int64 = 7) -> VaultDocument {
        VaultDocument(name: name, objectName: UUID().uuidString, typeIdentifier: "com.adobe.pdf", byteCount: size,
                      sha256: String(repeating: "a", count: 64), nowMs: 10)
    }

    @Test func emptySnapshotRoundTrip() throws {
        let workspace = VaultWorkspace()
        let decoded = try JSONDecoder().decode(VaultWorkspace.self, from: JSONEncoder().encode(workspace))
        try decoded.validate()
        #expect(decoded == workspace)
    }

    @Test func noteSaveRequiresCorrectRevision() throws {
        var workspace = VaultWorkspace()
        var note = VaultNote(title: "Insurance", nowMs: 1)
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 1)
        #expect(workspace.notes[0].revision == 1)
        note = workspace.notes[0]; note.title = "Updated"
        try workspace.saveNote(note, expectedRevision: 1, nowMs: 2)
        let snapshot = workspace
        #expect(throws: VaultWorkspaceError.conflict) { try workspace.saveNote(note, expectedRevision: 1, nowMs: 3) }
        #expect(workspace == snapshot)
    }

    @Test func deletedNoteCannotBeResurrectedByAutosave() throws {
        var workspace = VaultWorkspace()
        let draft = VaultNote(title: "Private", nowMs: 1)
        try workspace.saveNote(draft, expectedRevision: nil, nowMs: 1)
        let stale = workspace.notes[0]
        try workspace.trash([draft.id], scope: .notes, nowMs: 2)
        #expect(throws: VaultWorkspaceError.conflict) { try workspace.saveNote(stale, expectedRevision: stale.revision, nowMs: 3) }
        #expect(workspace.visibleNotes().isEmpty)
        #expect(workspace.trashCount == 1)
    }

    @Test func trashRestorePreservesRichNote() throws {
        var workspace = VaultWorkspace()
        var note = VaultNote(title: "Secret", nowMs: 1)
        note.blocks = [.init(style: .heading, text: "Heading"), .init(style: .checklist, text: "Done", checked: true),
                       .init(style: .bullet, text: "Bold", bold: true)]
        note.pinned = true
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 1)
        try workspace.trash([note.id], scope: .notes, nowMs: 2)
        try workspace.restore([note.id], scope: .notes)
        #expect(workspace.visibleNotes()[0].blocks == note.blocks)
        #expect(workspace.visibleNotes()[0].pinned)
        #expect(workspace.trashCount == 0)
    }

    @Test func attachmentCannotBeTrashedOrPurgedWhileReferenced() throws {
        var workspace = VaultWorkspace()
        let attachment = file()
        try workspace.addFile(attachment)
        var note = VaultNote(nowMs: 1); note.attachmentIDs = [attachment.id]
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 1)
        #expect(throws: VaultWorkspaceError.attachmentInUse) { try workspace.trash([attachment.id], scope: .files, nowMs: 2) }
        try workspace.trash([note.id], scope: .notes, nowMs: 3)
        #expect(throws: VaultWorkspaceError.attachmentInUse) { try workspace.trash([attachment.id], scope: .files, nowMs: 4) }
        try workspace.permanentlyRemove([note.id], scope: .notes)
        try workspace.trash([attachment.id], scope: .files, nowMs: 5)
        try workspace.permanentlyRemove([attachment.id], scope: .files)
        #expect(workspace.files.isEmpty)
        #expect(workspace.pendingObjectPurges == [attachment.objectName])
    }

    @Test func missingAttachmentsAreRejected() throws {
        var workspace = VaultWorkspace()
        var note = VaultNote(nowMs: 1); note.attachmentIDs = [UUID().uuidString]
        #expect(throws: VaultWorkspaceError.missingItem) { try workspace.saveNote(note, expectedRevision: nil, nowMs: 1) }
        #expect(workspace.notes.isEmpty)
    }

    @Test func folderScopesAndCaseInsensitiveNames() throws {
        var workspace = VaultWorkspace()
        let notes = try workspace.createFolder(name: "  Personal  ", scope: .notes, nowMs: 1)
        let files = try workspace.createFolder(name: "Personal", scope: .files, nowMs: 1)
        #expect(notes.name == "Personal")
        #expect(throws: VaultWorkspaceError.duplicateName) { try workspace.createFolder(name: "PERSONAL", scope: .notes, nowMs: 2) }
        var note = VaultNote(nowMs: 1); note.folderID = files.id
        #expect(throws: VaultWorkspaceError.invalidFolder) { try workspace.saveNote(note, expectedRevision: nil, nowMs: 1) }
        note.folderID = notes.id
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 1)
    }

    @Test func deletingFolderNeverDeletesContent() throws {
        var workspace = VaultWorkspace()
        let folder = try workspace.createFolder(name: "Archive", scope: .files, nowMs: 1)
        let document = file()
        try workspace.addFile(document, folderID: folder.id)
        try workspace.trash([document.id], scope: .files, nowMs: 2)
        workspace.removeFolder(folder.id)
        #expect(workspace.files.count == 1)
        #expect(workspace.files[0].folderID == nil)
        #expect(workspace.files[0].trashedMs == 2)
    }

    @Test func movingNoteInvalidatesOldEditorRevision() throws {
        var workspace = VaultWorkspace()
        let note = VaultNote(nowMs: 1)
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 1)
        let old = workspace.notes[0]
        let folder = try workspace.createFolder(name: "Private", scope: .notes, nowMs: 1)
        try workspace.move([note.id], scope: .notes, folderID: folder.id, nowMs: 2)
        #expect(throws: VaultWorkspaceError.conflict) { try workspace.saveNote(old, expectedRevision: 1, nowMs: 3) }
    }

    @Test func searchIsPrivateAndExcludesTrash() throws {
        var workspace = VaultWorkspace()
        var note = VaultNote(title: "Reise", nowMs: 1); note.blocks[0].text = "Zürich"
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 1)
        #expect(workspace.visibleNotes(query: "ZURICH").count == 1)
        try workspace.trash([note.id], scope: .notes, nowMs: 2)
        #expect(workspace.visibleNotes(query: "ZURICH").isEmpty)
    }

    @Test func pinningAndStableSorting() throws {
        var workspace = VaultWorkspace()
        var older = VaultNote(title: "Older", nowMs: 1); older.pinned = true
        let newer = VaultNote(title: "Newer", nowMs: 2)
        try workspace.saveNote(older, expectedRevision: nil, nowMs: 1)
        try workspace.saveNote(newer, expectedRevision: nil, nowMs: 2)
        #expect(workspace.visibleNotes().map(\.id) == [older.id, newer.id])
        try workspace.addFile(file(name: "File10.pdf", size: 10))
        try workspace.addFile(file(name: "File2.pdf", size: 20))
        #expect(workspace.visibleFiles(sort: .name).map(\.name) == ["File2.pdf", "File10.pdf"])
        #expect(workspace.visibleFiles(sort: .size).first?.byteCount == 20)
    }

    @Test func permanentDeletionRequiresTrash() throws {
        var workspace = VaultWorkspace()
        let document = file(); try workspace.addFile(document)
        #expect(throws: VaultWorkspaceError.notInTrash) { try workspace.permanentlyRemove([document.id], scope: .files) }
        #expect(workspace.files.count == 1)
    }

    @Test(arguments: ["../escape", "/etc/passwd", "a/b", "a\\b", "..", ".", "", "\n", "nul\u{0}.pdf"])
    func unsafeDisplayNamesRejected(name: String) {
        #expect(throws: VaultWorkspaceError.invalidName) { try VaultWorkspace.cleanName(name) }
    }

    @Test(arguments: ["../outside", "/tmp/item", "prefix-00000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-00000000000G"])
    func arbitraryObjectPathsRejected(name: String) {
        #expect(!VaultWorkspace.isOpaqueName(name))
    }

    @Test func corruptedMetadataRejected() throws {
        var workspace = VaultWorkspace()
        var document = file(); document.byteCount = -1
        #expect(throws: VaultWorkspaceError.invalidData) { try workspace.addFile(document) }
        document = file(); document.objectName = "../../outside"
        #expect(throws: VaultWorkspaceError.invalidData) { try workspace.addFile(document) }
        workspace.version = 99
        #expect(throws: VaultWorkspaceError.unsupportedVersion) { try workspace.validate() }
    }

    @Test func duplicateObjectsRejected() throws {
        var workspace = VaultWorkspace()
        let first = file(); try workspace.addFile(first)
        var second = file(); second.objectName = first.objectName
        #expect(throws: VaultWorkspaceError.conflict) { try workspace.addFile(second) }
    }

    @Test func partialSelectionDoesNotPartlyMutate() throws {
        var workspace = VaultWorkspace()
        let document = file(); try workspace.addFile(document)
        let baseline = workspace
        #expect(throws: VaultWorkspaceError.missingItem) { try workspace.trash([document.id, UUID().uuidString], scope: .files, nowMs: 3) }
        #expect(workspace == baseline)
    }

    @Test func futureSavedTimeDoesNotRegress() throws {
        var workspace = VaultWorkspace()
        let note = VaultNote(nowMs: 1)
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 100)
        try workspace.saveNote(workspace.notes[0], expectedRevision: 1, nowMs: 20)
        #expect(workspace.notes[0].modifiedMs == 100)
    }

    @Test func originalIsNeverClaimedRemovedByImport() throws {
        var workspace = VaultWorkspace()
        try workspace.addFile(file())
        #expect(workspace.files[0].origin == .copied)
    }

    @Test func fullWorkspaceRoundTripIncludesTrashAndAttachments() throws {
        var workspace = VaultWorkspace()
        let document = file(); try workspace.addFile(document)
        var note = VaultNote(nowMs: 1); note.attachmentIDs = [document.id]
        try workspace.saveNote(note, expectedRevision: nil, nowMs: 1)
        try workspace.trash([note.id], scope: .notes, nowMs: 2)
        workspace.mediaTrash = [.init(id: UUID().uuidString, deletedMs: 3, encodedItem: Data("private media metadata".utf8))]
        let decoded = try JSONDecoder().decode(VaultWorkspace.self, from: JSONEncoder().encode(workspace))
        try decoded.validate()
        #expect(decoded == workspace)
        #expect(decoded.trashCount == 2)
    }
}

@Suite("Vault session boundaries")
struct VaultAccessSessionTests {
    @Test func lockedSessionRejectsResults() {
        let session = VaultAccessSession()
        #expect(!session.accepts(UUID(), now: 1))
    }

    @Test func unlockLockUnlockCannotAcceptOldResult() {
        var session = VaultAccessSession()
        let old = session.begin(now: 10, timeout: 120)
        session.revoke()
        let current = session.begin(now: 12, timeout: 120)
        #expect(!session.accepts(old, now: 13))
        #expect(session.accepts(current, now: 13))
    }

    @Test func timeoutBoundaryCannotBeExtendedAfterExpiry() {
        var session = VaultAccessSession()
        let token = session.begin(now: 0, timeout: 30)
        #expect(session.accepts(token, now: 29.999))
        #expect(!session.accepts(token, now: 30))
        let touched = session.touch(now: 30)
        #expect(!touched)
        #expect(session.requiresLock(now: 30))
    }

    @Test func interactionRenewsOnlyCurrentSession() {
        var session = VaultAccessSession()
        let token = session.begin(now: 0, timeout: 30)
        let touched = session.touch(now: 20)
        #expect(touched)
        #expect(session.accepts(token, now: 49.9))
        #expect(!session.accepts(token, now: 50))
    }

    @Test func nonFiniteAndBackwardTimesFailClosed() {
        var session = VaultAccessSession()
        let token = session.begin(now: 100, timeout: 120)
        #expect(!session.accepts(token, now: .nan))
        #expect(!session.accepts(token, now: .infinity))
        #expect(!session.accepts(token, now: 99))
    }
}

@Suite struct VaultAudioFormatTests {
    @Test func headerIsStreamingMonoCAF() throws {
        let bytes = Array(try VaultAudioFormat.header(sampleRate: 48000))
        #expect(bytes.count == 68)
        #expect(String(bytes: bytes[0..<4], encoding: .utf8) == "caff")
        #expect(Array(bytes[4..<8]) == [0, 1, 0, 0])
        #expect(String(bytes: bytes[8..<12], encoding: .utf8) == "desc")
        #expect(String(bytes: bytes[28..<32], encoding: .utf8) == "lpcm")
        #expect(Array(bytes[32..<36]) == [0, 0, 0, 2])
        #expect(Array(bytes[44..<48]) == [0, 0, 0, 1])
        #expect(String(bytes: bytes[52..<56], encoding: .utf8) == "data")
        #expect(Array(bytes[56..<64]) == Array(repeating: 255, count: 8))
    }
    @Test(arguments: [Double.nan, Double.infinity, -1, 0, 7999, 192001])
    func invalidSampleRatesAreRejected(_ rate: Double) {
        #expect(throws: VaultWorkspaceError.invalidData) { try VaultAudioFormat.header(sampleRate: rate) }
    }
}

@Suite struct VaultNoteJournalTests {
    @Test func recoversNewNoteWithoutRewritingTheMediaSnapshot() throws {
        var edited = VaultWorkspace(); let draft = VaultNote(title: "Private", nowMs: 1)
        try edited.saveNote(draft, expectedRevision: nil, nowMs: 1)
        let note = try #require(edited.notes.first)
        let journal = VaultNoteJournal(snapshotSequence: 3, baseRevision: nil, note: note)
        var stored = VaultWorkspace()
        let applied = try journal.apply(to: &stored, snapshotSequence: 3)
        #expect(applied); #expect(stored.notes == [note])
        let again = try journal.apply(to: &stored, snapshotSequence: 3)
        #expect(!again)
    }
    @Test func coalescedEditsRecoverFromTheirOriginalBaseRevision() throws {
        var stored = VaultWorkspace(); let draft = VaultNote(title: "One", nowMs: 1)
        try stored.saveNote(draft, expectedRevision: nil, nowMs: 1)
        var edited = stored
        for time in 2...10 {
            var note = try #require(edited.notes.first); note.title = "Edit \(time)"
            try edited.saveNote(note, expectedRevision: note.revision, nowMs: Int64(time))
        }
        let latest = try #require(edited.notes.first)
        let journal = VaultNoteJournal(snapshotSequence: 5, baseRevision: 1, note: latest)
        let applied = try journal.apply(to: &stored, snapshotSequence: 5)
        #expect(applied); #expect(stored.notes.first?.revision == 10)
    }
    @Test func obsoleteJournalCannotResurrectDeletedNote() throws {
        var edited = VaultWorkspace(); let draft = VaultNote(nowMs: 1)
        try edited.saveNote(draft, expectedRevision: nil, nowMs: 1)
        let journal = VaultNoteJournal(snapshotSequence: 3, baseRevision: nil, note: try #require(edited.notes.first))
        var afterPermanentDeletion = VaultWorkspace()
        let applied = try journal.apply(to: &afterPermanentDeletion, snapshotSequence: 4)
        #expect(!applied); #expect(afterPermanentDeletion.notes.isEmpty)
    }
    @Test func futureJournalIsRejected() throws {
        var edited = VaultWorkspace(); let draft = VaultNote(nowMs: 1)
        try edited.saveNote(draft, expectedRevision: nil, nowMs: 1)
        let journal = VaultNoteJournal(snapshotSequence: 8, baseRevision: nil, note: try #require(edited.notes.first))
        var stored = VaultWorkspace()
        #expect(throws: VaultWorkspaceError.invalidData) { try journal.apply(to: &stored, snapshotSequence: 7) }
    }
    @Test func mismatchedBaseDoesNotOverwriteNewerContent() throws {
        var stored = VaultWorkspace(); let draft = VaultNote(nowMs: 1)
        try stored.saveNote(draft, expectedRevision: nil, nowMs: 1)
        var changed = try #require(stored.notes.first); changed.revision = 10; changed.title = "Wrong base"
        let journal = VaultNoteJournal(snapshotSequence: 3, baseRevision: 8, note: changed)
        let before = stored
        #expect(throws: VaultWorkspaceError.conflict) { try journal.apply(to: &stored, snapshotSequence: 3) }
        #expect(stored == before)
    }
}
