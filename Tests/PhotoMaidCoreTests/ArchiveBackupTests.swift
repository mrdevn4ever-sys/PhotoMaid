import Testing
import Foundation
@testable import PhotoMaidCore

/// Port von `ArchiveTest.kt` – mit iOS-Zieleinordnung über Volume-Eigenschaften und Android-kompatibler Sicherung.
@Suite struct ArchiveTests {
    let utc = TimeZone(identifier: "UTC")!
    let october7: Int64 = 1_791_374_400_000 // 2026-10-07T12:00:00Z

    @Test func targetKindSeparatesDeviceRemovableAndOtherApps() {
        #expect(ArchiveTargets.classify(VolumeFacts(isUbiquitous: false, volumeIsInternal: true, volumeIsRemovable: false)) == .sameDevice)
        #expect(ArchiveTargets.classify(VolumeFacts(isUbiquitous: false, volumeIsInternal: false, volumeIsRemovable: true,
                                                    volumeIsEjectable: true)) == .removable)
        #expect(ArchiveTargets.classify(VolumeFacts(volumeIsInternal: false)) == .removable)
        // iCloud Drive / nicht lokal ausgewiesen: nie automatisch „lokal“.
        #expect(ArchiveTargets.classify(VolumeFacts(isUbiquitous: true, volumeIsInternal: true)) == .provider)
        #expect(ArchiveTargets.classify(VolumeFacts(volumeIsInternal: true, volumeIsLocal: false)) == .provider)
        #expect(ArchiveTargets.classify(VolumeFacts()) == .provider)
        #expect(TargetKind.removable.allowsCleanupOffer)
        #expect(!TargetKind.sameDevice.allowsCleanupOffer && !TargetKind.provider.allowsCleanupOffer)
    }

    @Test func foldersByMonthAndNeverAnInventedDate() {
        let s = ArchiveSource(id: "a", name: "IMG_1.jpg", uti: "public.jpeg", size: 10, takenMillis: october7)
        #expect(ArchivePlan.folder(for: s, options: ArchiveOptions(), undatedLabel: "Ohne Datum", timeZone: utc) == ["2026", "10"])
        #expect(ArchivePlan.folder(for: s, options: ArchiveOptions(byMonth: false), undatedLabel: "Ohne Datum", timeZone: utc).isEmpty)
        let undated = ArchiveSource(id: "a", name: "IMG_1.jpg", uti: "public.jpeg", size: 10, takenMillis: nil)
        #expect(ArchivePlan.folder(for: undated, options: ArchiveOptions(), undatedLabel: "Ohne Datum", timeZone: utc) == ["Ohne Datum"])
    }

    @Test func storedKeysAreAlwaysAsciiDigits() {
        #expect(ArchivePlan.fallbackName(index: 0, uti: "public.jpeg") == "PhotoMaid_0001.jpg")
        #expect([UInt8(10), 255].hexString == "0aff")
        #expect(LocalDay(year: 2026, month: 10, day: 8).description == "2026-10-08")
        #expect(MonthKey(year: 2026, month: 9).description == "2026-09")
    }

    @Test func namesAreSafeForMemoryCardsAndUnique() {
        #expect(ArchivePlan.safeName("Urlaub: Strand?.jpg", fallback: "x") == "Urlaub_ Strand_.jpg")
        #expect(ArchivePlan.safeName("  ..  ", fallback: "x") == "x")
        #expect(ArchivePlan.safeName(nil, fallback: "x") == "x")
        let cut = ArchivePlan.safeName(String(repeating: "a", count: 300) + ".jpeg", fallback: "x")
        #expect(cut.count == 120 && cut.hasSuffix(".jpeg"))
        #expect(ArchivePlan.uniqueName(taken: ["other.jpg"], wanted: "IMG.jpg") == "IMG.jpg")
        #expect(ArchivePlan.uniqueName(taken: ["img.JPG"], wanted: "IMG.jpg") == "IMG (2).jpg")
        #expect(ArchivePlan.uniqueName(taken: ["IMG.jpg", "IMG (2).jpg"], wanted: "IMG.jpg") == "IMG (3).jpg")
        #expect(ArchivePlan.uniqueName(taken: ["README"], wanted: "README") == "README (2)")
        #expect(ArchivePlan.fallbackName(index: 6, uti: "public.mpeg-4") == "PhotoMaid_0007.mp4")
    }

    @Test func spaceIsOnlyEnoughWhenEverythingIsKnown() {
        #expect(ArchiveSpace.check(sizes: [10, 20], availableBytes: 30) == .enough)
        #expect(ArchiveSpace.check(sizes: [10, 21], availableBytes: 30) == .notEnough)
        #expect(ArchiveSpace.check(sizes: [10, nil], availableBytes: 30) == .unknown)
        #expect(ArchiveSpace.check(sizes: [40, nil], availableBytes: 30) == .notEnough)
        #expect(ArchiveSpace.check(sizes: [10], availableBytes: nil) == .unknown)
    }

    @Test func onlyVerifiedCopiesCountAfterAnInterruption() throws {
        func e(_ id: String, _ st: EntryState, bytes: Int64? = nil, target: String? = nil, reason: EntryReason? = nil) -> JournalEntry {
            var x = JournalEntry(sourceId: id, name: "\(id).jpg")
            x.state = st; x.bytes = bytes; x.targetUri = target; x.reason = reason
            return x
        }
        let j = ArchiveJournal(id: "j", targetLabel: "USB", targetKind: .removable, startedAt: 1, entries: [
            e("a", .verified, bytes: 100), e("b", .alreadyThere, bytes: 50), e("c", .copying, target: "2026/10/c.jpg"),
            e("d", .pending), e("e", .failed, reason: .mismatch),
        ])
        let (closed, remove) = ArchiveJournalRules.close(j, reason: .interrupted, now: 9)
        #expect(remove == ["2026/10/c.jpg"])
        #expect(closed.finishedAt == 9)
        #expect(closed.entries[2].state == .notDone && closed.entries[2].targetUri == nil)
        #expect(closed.entries[3].reason == .interrupted)
        #expect(closed.verified.map(\.sourceId) == ["a", "b"])
        let s = closed.summary
        #expect(s.total == 5 && s.verified == 1 && s.alreadyThere == 1 && s.failed == 1 && s.notDone == 2 && s.verifiedBytes == 150)
        #expect(try JSONDecoder().decode(ArchiveJournal.self, from: JSONEncoder().encode(closed)) == closed)
    }

    @Test func listIsValidCsvAndNeverAFormula() {
        let csv = ArchiveList.render(header: ["Ordner", "Name"], rows: [ArchiveList.Row(
            folder: "2026/10", name: "a,b.jpg", taken: "2026-10-07", bytes: "12", sha256: "ab", albums: "Ferien",
            tags: "=HYPERLINK(\"x\")", note: "Zeile 1\nZeile 2")])
        #expect(csv.hasPrefix("\u{FEFF}Ordner,Name\r\n"))
        #expect(csv.contains("\"a,b.jpg\""))
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(csv.contains("\"Zeile 1\nZeile 2\""))
        #expect(ArchiveList.cell("-1") == "'-1" && ArchiveList.cell("x") == "x")
    }
}

@Suite struct BackupTests {
    @Test func backupChecksFormatAndVersion() {
        #expect(BackupRules.check(nil as PhotoMaidBackup?) == .notABackup)
        var other = PhotoMaidBackup(createdAt: 1, appVersion: "1"); other.format = "x"
        #expect(BackupRules.check(other) == .notABackup)
        var newer = PhotoMaidBackup(createdAt: 1, appVersion: "1"); newer.version = 9
        #expect(BackupRules.check(newer) == .tooNew(9))
        guard case .ok = BackupRules.check(PhotoMaidBackup(createdAt: 1, appVersion: "1")) else { Issue.record("ok erwartet"); return }
        #expect(BackupRules.state(.kept) == .kept)
        #expect(BackupRules.state(.undecided) == nil && BackupRules.state(.removed) == nil)
        #expect(BackupRules.check(data: Data("kein json".utf8)) == .notABackup)
    }

    @Test func restoreFindsMediaOnANewPhoneAndNeverOverwrites() {
        var t = BackupRefTable()
        let kept = t.add(MediaRef(id: "old/1", name: "IMG_1.jpg", size: 100, takenMillis: 1000))
        let later = t.add(MediaRef(id: "old/2", name: "IMG_2.jpg", size: 200, takenMillis: 2000))
        let decidedHere = t.add(MediaRef(id: "old/3", name: "IMG_3.jpg", size: 300, takenMillis: 3000))
        let gone = t.add(MediaRef(id: "old/4", name: "IMG_4.jpg", size: 400, takenMillis: 4000))
        let twin = t.add(MediaRef(id: "old/5", name: "IMG_5.jpg", size: 500, takenMillis: 5000))
        #expect(t.add(MediaRef(id: "old/1", name: "IMG_1.jpg", size: 100, takenMillis: 1000)) == kept)
        var b = PhotoMaidBackup(createdAt: 1, appVersion: "1")
        b.refs = t.refs
        b.decisions = [BackupDecision(ref: kept, state: .kept),
                       BackupDecision(ref: later, state: .later, due: LocalDay(year: 2026, month: 10, day: 20)),
                       BackupDecision(ref: decidedHere, state: .marked), BackupDecision(ref: gone, state: .kept),
                       BackupDecision(ref: twin, state: .kept)]
        b.albums = [BackupAlbum(name: "Ferien", createdAt: 1, items: [kept, gone]), BackupAlbum(name: "Neu", createdAt: 1, items: [later])]
        b.tags = [kept: ["#Strand", "strand"]]
        b.notes = [kept: "Notiz", later: "Andere"]
        b.basket = [later]
        b.hiddenMedia = [gone]
        let current = [MediaRef(id: "new/1", name: "IMG_1.jpg", size: 100, takenMillis: 1000),
                       MediaRef(id: "new/2", name: "img_2.JPG", size: 200, takenMillis: 2000),
                       MediaRef(id: "new/3", name: "IMG_3.jpg", size: 300, takenMillis: 3000),
                       MediaRef(id: "new/5a", name: "IMG_5.jpg", size: 500, takenMillis: 5000),
                       MediaRef(id: "new/5b", name: "IMG_5.jpg", size: 500, takenMillis: 5000)]
        let p = BackupRestore.plan(b, current: current, ref: { $0 }, dispositions: ["new/3": .kept], albumNames: ["ferien"],
                                   notesPresent: ["new/2"])
        #expect(Set(p.decisions.keys) == ["new/1", "new/2"])
        #expect(p.decisions["new/2"]?.due == LocalDay(year: 2026, month: 10, day: 20))
        #expect(p.decisionsKeptLocal == 1)
        #expect(p.albums == [RestorePlan.AlbumPlan(name: "Ferien", items: ["new/1"]), RestorePlan.AlbumPlan(name: "Neu", items: ["new/2"])])
        #expect(p.newAlbums == 1)
        #expect(p.tags == ["new/1": ["Strand"]])
        #expect(p.notes == ["new/1": "Notiz"])
        #expect(p.basket == ["new/2"])
        #expect(p.hidden.isEmpty)
        #expect(Set(p.missing.map(\.id)) == ["old/4", "old/5"])
        #expect(!p.isEmpty)
        let same = BackupRestore.plan(b, current: [MediaRef(id: "old/4", name: "IMG_4.jpg", size: 400, takenMillis: 4000)], ref: { $0 },
                                      dispositions: [:], albumNames: [], notesPresent: [])
        #expect(same.hidden == ["old/4"])
        #expect(Set(same.decisions.keys) == ["old/4"])
    }

    @Test func backupSurvivesJsonAndReadsAndroidFiles() throws {
        var b = PhotoMaidBackup(createdAt: 5, appVersion: "0.2.0")
        b.refs = [BackupRef(id: "a", name: "x.jpg", size: 1, taken: 2)]
        b.decisions = [BackupDecision(ref: 0, state: .later, bookmarked: true)]
        b.tags = [0: ["t"]]
        b.extras = ["settings": .object(["laterDays": .number(2)])]
        #expect(try JSONDecoder().decode(PhotoMaidBackup.self, from: JSONEncoder().encode(b)) == b)
        // Form einer Android-Datei (kotlinx.serialization, Zahl-Schlüssel als Text, LocalDay als Objekt).
        let android = #"""
        {"format":"photomaid-backup","version":1,"createdAt":1791460000000,"appVersion":"0.9.0",
         "refs":[{"id":"content://media/external/images/media/12","name":"IMG_0001.jpg","size":2048,"taken":1791400000000}],
         "decisions":[{"ref":0,"state":"LATER","due":{"year":2026,"month":10,"day":20}}],
         "albums":[{"name":"Ferien","createdAt":1,"items":[0]}],"tags":{"0":["Strand"]},"notes":{"0":"Notiz"},
         "basket":[0],"hiddenMedia":[],"extras":{"quickAccess":[{"kind":"PHOTOS"}]}}
        """#
        guard case .ok(let a) = BackupRules.check(data: Data(android.utf8)) else { Issue.record("Android-Sicherung lesbar"); return }
        #expect(a.decisions[0].due == LocalDay(year: 2026, month: 10, day: 20) && !a.decisions[0].bookmarked)
        #expect(a.tags[0] == ["Strand"] && a.notes[0] == "Notiz" && a.basket == [0])
        let plan = BackupRestore.plan(a, current: [MediaRef(id: "ios-A/L0/001", name: "IMG_0001.jpg", size: 2048, takenMillis: 1_791_400_000_000)],
                                      ref: { $0 }, dispositions: [:], albumNames: [], notesPresent: [])
        #expect(plan.decisions["ios-A/L0/001"]?.state == .later)
        #expect(plan.missing.isEmpty)
    }
}

@Suite struct PluralAndAnalysisTests {
    @Test func pluralCategoriesForAllSixteenLanguages() {
        #expect(PluralRules.category(1, language: "de") == .one && PluralRules.category(0, language: "de") == .other)
        #expect(PluralRules.category(2, language: "en") == .other)
        #expect(PluralRules.category(0, language: "fr") == .one && PluralRules.category(2, language: "fr") == .other)
        #expect(PluralRules.category(1_000_000, language: "fr") == .many)
        #expect(PluralRules.category(1, language: "pt-PT") == .one && PluralRules.category(0, language: "pt-PT") == .other)
        #expect(PluralRules.category(5, language: "ja") == .other && PluralRules.category(1, language: "zh-Hans") == .other)
        #expect(PluralRules.category(1, language: "ko") == .other)
        // Russisch/Ukrainisch
        for (n, c) in [(1, PluralCategory.one), (21, .one), (11, .many), (2, .few), (4, .few), (12, .many), (5, .many), (0, .many), (101, .one)] {
            #expect(PluralRules.category(n, language: "ru") == c, "ru \(n)")
            #expect(PluralRules.category(n, language: "uk") == c, "uk \(n)")
        }
        // Polnisch
        for (n, c) in [(1, PluralCategory.one), (2, .few), (22, .few), (12, .many), (5, .many), (21, .many)] {
            #expect(PluralRules.category(n, language: "pl") == c, "pl \(n)")
        }
        // Rumänisch
        for (n, c) in [(1, PluralCategory.one), (0, .few), (2, .few), (19, .few), (20, .other), (101, .few), (120, .other)] {
            #expect(PluralRules.category(n, language: "ro") == c, "ro \(n)")
        }
        // Arabisch
        for (n, c) in [(0, PluralCategory.zero), (1, .one), (2, .two), (3, .few), (10, .few), (11, .many), (99, .many), (100, .other), (103, .few)] {
            #expect(PluralRules.category(n, language: "ar") == c, "ar \(n)")
        }
        #expect(PluralRules.category(1, language: "tr") == .one && PluralRules.category(1, language: "nl") == .one)
        #expect(PluralRules.lookupOrder(3, language: "ar") == [.few, .other])
        #expect(PluralRules.lookupOrder(7, language: "de") == [.other])
    }

    @Test func similarPhotosGroupOnlyWithinWindowAndThreshold() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let photos = [AnalyzedPhoto(id: "a", takenAt: t0), AnalyzedPhoto(id: "b", takenAt: t0.addingTimeInterval(5)),
                      AnalyzedPhoto(id: "c", takenAt: t0.addingTimeInterval(8)), AnalyzedPhoto(id: "d", takenAt: t0.addingTimeInterval(3600)),
                      AnalyzedPhoto(id: "e", takenAt: nil)]
        let near: Set<String> = ["a|b", "b|c", "c|d"]
        var calls = 0
        let groups = SimilarPhotos.groups(photos) { x, y in
            calls += 1
            return near.contains("\(x.id)|\(y.id)") || near.contains("\(y.id)|\(x.id)") ? 0.2 : 0.9
        }
        #expect(groups.map { $0.map(\.id) } == [["a", "b", "c"]]) // d außerhalb des Zeitfensters, e ohne Datum
        #expect(calls == 3) // nur Paare im Zeitfenster
    }

    @Test func sharpestSuggestionNeedsMeasurementsAndClearLead() {
        let g = [AnalyzedPhoto(id: "a", takenAt: nil, sharpness: 0.002), AnalyzedPhoto(id: "b", takenAt: nil, sharpness: 0.004)]
        #expect(SimilarPhotos.sharpest(g) == "b")
        let close = [AnalyzedPhoto(id: "a", takenAt: nil, sharpness: 0.0040), AnalyzedPhoto(id: "b", takenAt: nil, sharpness: 0.0042)]
        #expect(SimilarPhotos.sharpest(close) == nil)
        let unmeasured = [AnalyzedPhoto(id: "a", takenAt: nil, sharpness: 0.004), AnalyzedPhoto(id: "b", takenAt: nil)]
        #expect(SimilarPhotos.sharpest(unmeasured) == nil)
    }

    @Test func blurVerdictAndLaplacian() {
        #expect(BlurryPhotos.verdict(nil) == .unknown)
        #expect(BlurryPhotos.verdict(0.0001) == .possiblyBlurry)
        #expect(BlurryPhotos.verdict(0.01) == .sharp)
        let w = 32, h = 32
        let flat = [Float](repeating: 0.5, count: w * h)
        #expect(BlurryPhotos.laplacianVariance(flat, w: w, h: h) == 0)
        let checker = (0..<(w * h)).map { i -> Float in ((i % w) + (i / w)) % 2 == 0 ? 0 : 1 }
        #expect(BlurryPhotos.laplacianVariance(checker, w: w, h: h) > BlurryPhotos.defaultThreshold)
    }

    @Test func categoriesNeedConfidence() {
        #expect(PhotoCategory.of(identifier: "receipt") == .documents)
        #expect(PhotoCategory.of(identifier: "dog") == .animals)
        #expect(PhotoCategory.of(identifier: "spaceship") == nil)
        #expect(PhotoCategory.best([(identifier: "food", confidence: 0.4), (identifier: "dog", confidence: 0.8)]) == .animals)
        #expect(PhotoCategory.best([(identifier: "food", confidence: 0.4)]) == nil)
    }
}
