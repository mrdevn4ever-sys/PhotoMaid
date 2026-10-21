import Foundation
import Testing
@testable import PhotoMaidCore

@Suite("Bearbeiten im Tresor")
struct VaultEditTests {
    private func resource(_ role: VaultResourceRole = .photo) -> VaultResource {
        VaultResource(role: role, file: UUID().uuidString, uti: "public.jpeg", originalFilename: "IMG_1.jpg", size: 10,
                      sha256: String(repeating: "b", count: 64))
    }

    private func original() -> VaultItem {
        VaultItem(id: "orig", kind: .photo, folderID: "f1", resources: [resource(.fullSizePhoto), resource()],
                  creationMs: 1_000, addedMs: 5, latitude: 47.4, longitude: 8.5, isFavorite: true, pixelWidth: 4032,
                  pixelHeight: 3024, sourceID: "PH-1", originalID: "PH-1")
    }

    @Test func editedCopyStaysInVaultWithoutPhotosIdentity() {
        let copy = VaultEdit.item(from: original(), id: "new", kind: .photo, resource: resource(), addedMs: 9,
                                  removeLocation: false, replace: false, duration: 0, pixelWidth: 2000,
                                  pixelHeight: 1500, thumbnail: "t")
        #expect(copy.sourceID == nil && copy.originalID == nil)
        #expect(copy.folderID == "f1")
        #expect(copy.creationMs == 1_000)
        #expect(copy.latitude == 47.4 && copy.longitude == 8.5)
        #expect(copy.isFavorite == false)
        #expect(copy.current?.role == .photo)
    }

    @Test func removeLocationAndFrameOffset() {
        let frame = VaultEdit.item(from: original(), id: "frame", kind: .photo, resource: resource(), addedMs: 9,
                                   creationOffsetMs: 2_500, removeLocation: true, replace: false, duration: 0,
                                   pixelWidth: 1, pixelHeight: 1, thumbnail: nil)
        #expect(frame.creationMs == 3_500)
        #expect(frame.latitude == nil && frame.longitude == nil)
    }

    @Test func copyKeepsOriginal() throws {
        var snapshot = VaultSnapshot(media: VaultIndex(items: [original()]))
        let copy = VaultEdit.item(from: original(), id: "new", kind: .photo, resource: resource(), addedMs: 9,
                                  removeLocation: false, replace: false, duration: 0, pixelWidth: 1, pixelHeight: 1,
                                  thumbnail: nil)
        try snapshot.addEdited(copy, replacing: nil, nowMs: 9)
        #expect(snapshot.media.items.map(\.id) == ["orig", "new"])
        #expect(snapshot.workspace.mediaTrash.isEmpty)
    }

    @Test func replaceMovesOriginalToVaultTrashInOneStep() throws {
        var snapshot = VaultSnapshot(media: VaultIndex(items: [original()]))
        let copy = VaultEdit.item(from: original(), id: "new", kind: .photo, resource: resource(), addedMs: 9,
                                  removeLocation: false, replace: true, duration: 0, pixelWidth: 1, pixelHeight: 1,
                                  thumbnail: nil)
        try snapshot.addEdited(copy, replacing: "orig", nowMs: 42)
        #expect(snapshot.media.items.map(\.id) == ["new"])
        #expect(snapshot.media.items[0].isFavorite)
        #expect(snapshot.workspace.mediaTrash.map(\.id) == ["orig"])
        #expect(snapshot.workspace.mediaTrash[0].deletedMs == 42)
        // Das Original bleibt vollständig erhalten (zurückholbar) und weiter in PhotoMaid verborgen.
        #expect(snapshot.allMedia.contains { $0.id == "orig" && $0.originalID == "PH-1" })
        #expect(snapshot.originalIDs == ["PH-1"])
        #expect(snapshot.mediaSlotsUsed == 2)
    }

    @Test func editedCopyKeepsPhotosOriginalHiddenAfterTrashIsEmptied() throws {
        var snapshot = VaultSnapshot(media: VaultIndex(items: [original()]))
        let copy = VaultEdit.item(from: original(), id: "new", kind: .photo, resource: resource(), addedMs: 9,
                                  removeLocation: false, replace: true, duration: 0, pixelWidth: 1, pixelHeight: 1,
                                  thumbnail: nil)
        #expect(copy.concealsOriginalID == "PH-1" && copy.concealmentIDs == ["PH-1"])
        try snapshot.addEdited(copy, replacing: "orig", nowMs: 42)
        snapshot.workspace.mediaTrash.removeAll() // Tresor-Papierkorb endgültig geleert
        #expect(snapshot.originalIDs == ["PH-1"], "Das Fotos-Original bleibt verborgen, solange die Fassung im Tresor liegt")
        // Eine Bearbeitung der Bearbeitung trägt den Schlüssel weiter.
        let second = VaultEdit.item(from: copy, id: "new2", kind: .photo, resource: resource(), addedMs: 10,
                                    removeLocation: false, replace: false, duration: 0, pixelWidth: 1, pixelHeight: 1,
                                    thumbnail: nil)
        #expect(second.concealsOriginalID == "PH-1")
        // Ältere Einträge ohne das Feld lassen sich weiter lesen.
        let legacy = try JSONDecoder().decode(VaultItem.self, from: JSONEncoder().encode(original()))
        #expect(legacy.concealsOriginalID == nil)
        #expect(legacy.concealmentIDs == ["PH-1"])
    }
}
