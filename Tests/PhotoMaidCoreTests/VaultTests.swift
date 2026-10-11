import Testing
import Foundation
@testable import PhotoMaidCore

/// Privater Tresor (E16): Index, Ordner, Sortierung, Free-Grenze, Code, Fehlversuche, Notfallschlüssel, Dateiformat.
@Suite struct VaultTests {
    func res(_ role: VaultResourceRole, _ name: String = "IMG_1.HEIC", size: Int64 = 100) -> VaultResource {
        VaultResource(role: role, file: UUID().uuidString, uti: "public.heic", originalFilename: name, size: size, sha256: "x")
    }

    func item(_ id: String, name: String = "IMG_1.HEIC", created: Int64? = 1_000, added: Int64 = 1_000, size: Int64 = 100,
              folder: String? = nil) -> VaultItem {
        VaultItem(id: id, kind: .photo, folderID: folder, resources: [res(.photo, name, size: size)], creationMs: created,
                  addedMs: added)
    }

    @Test func ordnerAnlegenUmbenennenLoeschen() {
        var index = VaultIndex()
        let created = index.createFolder(name: "  Urlaub ", id: "F1", nowMs: 1)
        #expect(created != nil)
        #expect(index.folders.first?.name == "Urlaub")
        let duplicate = index.createFolder(name: "urlaub", id: "F2", nowMs: 2) // doppelt (ohne Groß/Klein)
        #expect(duplicate == nil)
        let empty = index.createFolder(name: "   ", id: "F3", nowMs: 3)
        #expect(empty == nil)
        index.add(item("A"))
        index.add(item("B"))
        index.move(ids: ["A"], to: "F1")
        #expect(index.count(inFolder: "F1") == 1)
        index.move(ids: ["B"], to: "unbekannt")
        #expect(index.items.first { $0.id == "B" }?.folderID == nil)
        let renamed = index.renameFolder("F1", to: "Familie")
        #expect(renamed)
        index.deleteFolder("F1")
        #expect(index.folders.isEmpty)
        #expect(index.items.count == 2) // Medien bleiben im Tresor
        #expect(index.items.allSatisfy { $0.folderID == nil })
    }

    @Test func entfernenLiefertEintraegeFuerDateien() {
        var index = VaultIndex(items: [item("A"), item("B"), item("C")])
        let removed = index.remove(ids: ["A", "C"])
        #expect(Set(removed.map(\.id)) == ["A", "C"])
        #expect(index.items.map(\.id) == ["B"])
    }

    @Test func sortierungUnbekanntesDatumAmEnde() {
        let items = [item("A", name: "IMG_10.JPG", created: nil, added: 5, size: 300),
                     item("B", name: "IMG_2.JPG", created: 2_000, added: 9, size: 100),
                     item("C", name: "img_1.jpg", created: 3_000, added: 1, size: 200)]
        #expect(VaultSort.captured.sorted(items).map(\.id) == ["C", "B", "A"])
        #expect(VaultSort.added.sorted(items).map(\.id) == ["B", "A", "C"])
        #expect(VaultSort.name.sorted(items).map(\.id) == ["C", "B", "A"]) // 1 < 2 < 10, ohne Groß/Klein
        #expect(VaultSort.size.sorted(items).map(\.id) == ["A", "C", "B"])
    }

    @Test func freeGrenze50ProUnbegrenzt() {
        #expect(VaultPolicy.allowed(requested: 10, existing: 45, unlimited: false) == 5)
        #expect(VaultPolicy.allowed(requested: 10, existing: 50, unlimited: false) == 0)
        #expect(VaultPolicy.allowed(requested: 10, existing: 60, unlimited: false) == 0)
        #expect(VaultPolicy.allowed(requested: 500, existing: 60, unlimited: true) == 500)
        #expect(VaultPolicy.remaining(existing: 12, unlimited: false) == 38)
        #expect(VaultPolicy.remaining(existing: 12, unlimited: true) == nil)
    }

    @Test func codeRegeln() {
        #expect(VaultCodeRules.validate("123456", kind: .pin, confirmation: "123456") == nil)
        #expect(VaultCodeRules.validate("12345", kind: .pin, confirmation: "12345") == .tooShort)
        #expect(VaultCodeRules.validate("12a456", kind: .pin, confirmation: "12a456") == .notDigits)
        #expect(VaultCodeRules.validate("١٢٣٤٥٦", kind: .pin, confirmation: "١٢٣٤٥٦") == .notDigits) // nur 0–9
        #expect(VaultCodeRules.validate("123456", kind: .pin, confirmation: "123457") == .mismatch)
        #expect(VaultCodeRules.validate("geheim", kind: .password, confirmation: "geheim") == nil)
        #expect(VaultCodeRules.validate("kurz", kind: .password, confirmation: "kurz") == .tooShort)
    }

    @Test func fehlversucheNurWartezeit() {
        var l = VaultLockout()
        for _ in 0..<4 { l.registerFailure(nowMs: 0) }
        #expect(l.remainingSeconds(nowMs: 0) == 0)
        l.registerFailure(nowMs: 10_000) // 5.
        #expect(l.remainingSeconds(nowMs: 10_000) == 60)
        #expect(l.remainingSeconds(nowMs: 69_500) == 1)
        #expect(l.remainingSeconds(nowMs: 70_000) == 0)
        l.registerFailure(nowMs: 70_000) // 6.
        #expect(l.remainingSeconds(nowMs: 70_000) == 300)
        l.registerFailure(nowMs: 0)
        l.registerFailure(nowMs: 0)
        l.registerFailure(nowMs: 0)
        #expect(VaultLockout.penaltySeconds(failures: 20) == 3600) // nie Löschen, höchstens eine Stunde
        l.registerSuccess()
        #expect(l == VaultLockout())
    }

    @Test func notfallschluesselFormatUndEingabe() {
        let bytes: [UInt8] = Array(0..<16)
        let key = VaultRecoveryKey.format(bytes)
        #expect(key.count == 26 + 6) // 7 Gruppen, 6 Striche
        #expect(key.split(separator: "-").count == 7)
        let plain = key.replacingOccurrences(of: "-", with: "")
        #expect(VaultRecoveryKey.normalize(key.lowercased()) == plain)
        #expect(VaultRecoveryKey.normalize(key.replacingOccurrences(of: "-", with: " ")) == plain)
        #expect(VaultRecoveryKey.normalize("O" + plain.dropFirst()) == "0" + plain.dropFirst())
        #expect(VaultRecoveryKey.normalize("ABC") == nil)
        #expect(VaultRecoveryKey.normalize(plain.dropLast() + "U") == nil) // U gibt es nicht
        // Verschiedene Bytes ergeben verschiedene Schlüssel.
        #expect(VaultRecoveryKey.format(Array(repeating: 0xFF, count: 16)) != key)
        #expect(VaultRecoveryKey.format(Array(repeating: 0, count: 16)) == "0000-0000-0000-0000-0000-0000-00")
    }

    @Test func dateiformatBloecke() {
        let size = 1024
        let header = VaultChunkLayout.header(chunkSize: size, salt: Array(repeating: 7, count: 16))
        #expect(header.count == VaultChunkLayout.headerLength)
        let parsed = VaultChunkLayout.parseHeader(header)
        #expect(parsed?.chunkSize == size)
        #expect(parsed?.salt == Array(repeating: 7, count: 16))
        #expect(VaultChunkLayout.parseHeader(Array(header.dropLast())) == nil)

        for plain: Int64 in [0, 1, 1023, 1024, 1025, 4096, 5000] {
            let length = VaultChunkLayout.fileLength(plaintext: plain, chunkSize: size)
            let chunks = VaultChunkLayout.chunks(fileLength: length, chunkSize: size)
            #expect(chunks != nil)
            #expect(VaultChunkLayout.plaintextLength(fileLength: length, chunkSize: size) == plain)
            #expect(chunks?.last?.isLast == true)
            #expect(chunks?.filter(\.isLast).count == 1)
            #expect(chunks?.map(\.index) == (0..<UInt64(chunks?.count ?? 0)).map { $0 })
        }
        // Abgeschnitten oder ohne Inhalt: beschädigt.
        #expect(VaultChunkLayout.chunks(fileLength: Int64(VaultChunkLayout.headerLength + 10), chunkSize: size) == nil)
        let twoFull = VaultChunkLayout.fileLength(plaintext: 2048, chunkSize: size)
        #expect(VaultChunkLayout.chunks(fileLength: twoFull + 28, chunkSize: size) == nil) // leerer Zusatzblock
        #expect(VaultChunkLayout.aad(index: 1, isLast: true) == [0, 0, 0, 0, 0, 0, 0, 1, 1])
        #expect(VaultChunkLayout.aad(index: 258, isLast: false) == [0, 0, 0, 0, 0, 0, 1, 2, 0])
    }

    @Test func zuruecklegenAktuelleFassungUndAlleTeile() {
        let live = [res(.photo), res(.pairedVideo), res(.fullSizePhoto), res(.fullSizePairedVideo), res(.adjustmentData),
                    res(.alternatePhoto)]
        #expect(VaultRestorePlan.current(live)?.role == .fullSizePhoto)
        #expect(VaultRestorePlan.simple(live).map(\.role) == [.fullSizePhoto, .fullSizePairedVideo, .alternatePhoto])
        #expect(VaultRestorePlan.full(live).map(\.role) == [.photo, .pairedVideo, .alternatePhoto, .adjustmentData,
                                                            .fullSizePhoto, .fullSizePairedVideo])
        // Ohne Anpassungsdaten keine Bearbeitung zum Wiederherstellen: einfacher Plan.
        let noAdjust = [res(.photo), res(.fullSizePhoto)]
        #expect(VaultRestorePlan.full(noAdjust).map(\.role) == [.fullSizePhoto])
        #expect(VaultRestorePlan.simpleRole(.fullSizePairedVideo) == .pairedVideo)
        let video = [res(.video, "IMG_2.MOV")]
        #expect(VaultRestorePlan.current(video)?.role == .video)
    }

    @Test func nochInDerFotosApp() {
        var index = VaultIndex(items: [item("A"), item("B")])
        index.items[0].sourceID = "P1"
        index.items[1].sourceID = "P2"
        index.markRemovedFromLibrary(sourceIDs: ["P1"])
        #expect(index.stillInLibrary == ["P2"])
    }

    @Test func einstellungenUndIndexSindKodierbar() throws {
        var settings = VaultSettings(codeKind: .pin, hideEntry: true, biometrics: false,
                                     recovery: VaultWrappedKey(salt: Data([1, 2]), rounds: 10, box: Data([3])), createdMs: 5)
        settings.lockout.registerFailure(nowMs: 0)
        let s2 = try JSONDecoder().decode(VaultSettings.self, from: JSONEncoder().encode(settings))
        #expect(s2 == settings)
        let index = VaultIndex(folders: [VaultFolder(id: "F", name: "A", createdMs: 1)], items: [item("A", folder: "F")])
        let i2 = try JSONDecoder().decode(VaultIndex.self, from: JSONEncoder().encode(index))
        #expect(i2 == index)
    }

    // MARK: Isolation (nur im Tresor, nirgendwo sonst)

    /// Einfache Ersatz-Prüfsumme für Linux-Tests (die App nutzt SHA-256).
    func fakeDigest(_ salt: Data, _ id: String) -> String { salt.map { String($0) }.joined() + "|" + id }

    @Test func verbergenListeEnthaeltNurPruefsummen() throws {
        var set = VaultConcealmentSet(salt: Data([7, 8]))
        #expect(set.isEmpty)
        #expect(!set.contains("A", digest: fakeDigest))
        let added = set.insert(["A", "B", ""], digest: fakeDigest)
        #expect(added)
        let again = set.insert(["A"], digest: fakeDigest) // schon enthalten
        #expect(!again)
        #expect(set.contains("A", digest: fakeDigest))
        #expect(!set.contains("C", digest: fakeDigest))
        #expect(!set.digests.contains("A")) // keine Klartext-Kennung
        #expect(set.digests.count == 2) // leere Kennung wird ignoriert
        let removed = set.remove(["A"], digest: fakeDigest)
        #expect(removed)
        #expect(!set.contains("A", digest: fakeDigest))
        let decoded = try JSONDecoder().decode(VaultConcealmentSet.self, from: JSONEncoder().encode(set))
        #expect(decoded == set)
    }

    @Test func originalKennungBleibtNachLoeschbestaetigung() {
        var index = VaultIndex(items: [VaultItem(id: "V1", kind: .photo, resources: [res(.photo)], creationMs: 1, addedMs: 1,
                                                 sourceID: "P1")])
        #expect(index.items[0].originalID == "P1")
        index.markRemovedFromLibrary(sourceIDs: ["P1"])
        #expect(index.items[0].sourceID == nil)
        #expect(index.originalIDs == ["P1"]) // bleibt für die Verbergen-Liste
    }

    @Test func alteEintraegeWerdenOhneRatenUebernommen() throws {
        // Build 3/4: kein originalID-Feld. Mit sourceID → übernommen; ohne → bleibt unbekannt (nie geraten).
        let old = """
        {"version":1,"folders":[],"items":[
         {"id":"V1","kind":"photo","resources":[],"addedMs":1,"isFavorite":false,"duration":0,"pixelWidth":0,
          "pixelHeight":0,"sourceID":"P1"},
         {"id":"V2","kind":"photo","resources":[],"addedMs":1,"isFavorite":false,"duration":0,"pixelWidth":0,
          "pixelHeight":0}]}
        """
        var index = try JSONDecoder().decode(VaultIndex.self, from: Data(old.utf8))
        #expect(index.items.allSatisfy { $0.originalID == nil })
        let migrated = index.migrateOriginalIDs()
        #expect(migrated)
        #expect(index.items[0].originalID == "P1")
        #expect(index.items[1].originalID == nil)
        let migratedAgain = index.migrateOriginalIDs()
        #expect(!migratedAgain)
        #expect(index.originalIDs == ["P1"])
    }

    @Test func abgeleiteteKopienUeberMehrereStufen() {
        let records = [
            EditRecord(newId: "E1", sourceId: "P1", mode: .copy, video: false, atMs: 1),                     // Bearbeitung
            EditRecord(newId: "C1", sourceId: "", mode: .copy, video: false, atMs: 2, kind: .collage, count: 2,
                       sources: ["E1", "P9"]),                                                                 // Collage
            EditRecord(newId: "M1", sourceId: "", mode: .copy, video: true, atMs: 3, kind: .merge, count: 1,
                       sources: ["C1"]),                                                                       // Film
            EditRecord(newId: "X1", sourceId: "P2", mode: .copy, video: false, atMs: 4),                     // fremd
            EditRecord(newId: "OLD", sourceId: "", mode: .copy, video: false, atMs: 5, kind: .collage, count: 3), // alt
        ]
        #expect(VaultDerivation.copies(of: ["P1"], records: records) == ["E1", "C1", "M1"])
        #expect(VaultDerivation.copies(of: ["P9"], records: records) == ["C1", "M1"])
        #expect(VaultDerivation.copies(of: ["P3"], records: records).isEmpty)
    }

    @Test func gespeichertOhneQuellenBleibtLesbar() throws {
        let old = """
        {"newId":"N","sourceId":"S","mode":"COPY","video":false,"atMs":1,"kind":"EDIT","count":1}
        """
        let r = try JSONDecoder().decode(EditRecord.self, from: Data(old.utf8))
        #expect(r.sources == nil)
        #expect(VaultDerivation.parents(of: r) == ["S"])
    }
}

