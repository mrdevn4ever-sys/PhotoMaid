import CoreLocation
import CryptoKit
import Foundation
import ImageIO
import Observation
import Photos
import PhotoMaidCore
import UIKit
import UniformTypeIdentifiers

/// Fortschritt beim Ablegen oder Zurücklegen (gezählt, nie geschätzt).
struct VaultProgress: Equatable {
    var done: Int
    let total: Int
}

struct VaultImportReport: Equatable {
    var imported = 0
    var failed = 0
    var skippedByLimit = 0
    /// Von iOS aus der Fotos-App entfernt (nach der Systemabfrage).
    var removedFromLibrary = 0
}

/// Ergebnis von „Zurück in Fotos“.
struct VaultRestoreReport: Equatable {
    var restored = 0
    var failed = 0
    /// Nur vereinfacht zurückgelegt (z. B. ohne rücksetzbare Bearbeitung): das vollständige Original bleibt im Tresor.
    var keptComplete = 0
}

/// Privater Tresor (E16): Medien, Notizen, Dateien und ein eigener Tresor-Papierkorb. Eine Wahrheit: ein
/// verschlüsselter Schnappschuss (`VaultSnapshot`) im App-Container; Notiz-Eingaben zusätzlich als verschlüsseltes
/// Journal, bis der nächste Schnappschuss sie enthält. Was hier liegt, zeigt PhotoMaid nirgends sonst
/// (`VaultConcealment` an allen PhotoKit-Zugängen) – auch wenn iOS das Löschen in der Fotos-App nicht bestätigt.
/// Schlüssel und Inhalte liegen nur im Speicher, solange der Tresor offen ist; jede Sperre widerruft die Sitzung
/// (`VaultSessionLease`), verspätete Aufgaben öffnen, zeigen oder schreiben danach nichts mehr. Änderungen gelten
/// erst, wenn sie gespeichert sind (`VaultTransaction`). Nichts wird automatisch gelöscht.
@MainActor
@Observable
final class VaultStore {
    static let shared = VaultStore()

    enum Phase: Equatable { case notSetUp, locked, unlocked }

    enum UnlockResult: Equatable {
        case opened
        case wrong
        case lockedOut(seconds: Int64)
        /// Der Code-Eintrag fehlt auf diesem Gerät (z. B. unverschlüsseltes Backup): nur der Notfallschlüssel hilft.
        case unavailable
        /// Während der Prüfung wurde gesperrt (App verlassen, Schließen): nicht öffnen, kein Fehlversuch.
        case cancelled
    }

    private(set) var phase: Phase = .notSetUp
    var isPresented = false
    private(set) var settings: VaultSettings?
    private(set) var index = VaultIndex()
    /// Notizen, Dateien, Ordner und Tresor-Papierkorb.
    private(set) var workspace = VaultWorkspace()
    private(set) var thumbnails: [String: UIImage] = [:]
    private(set) var progress: VaultProgress?
    /// Nach dem Öffnen mit dem Notfallschlüssel muss ein neuer Code gesetzt werden.
    private(set) var needsNewCode = false
    /// Eine Aktion ließ sich nicht speichern (Hinweis in der Ansicht; nichts wurde still verworfen).
    var operationFailed = false
    @ObservationIgnored private var key: VaultKey?
    @ObservationIgnored private var loadingThumbs: Set<String> = []
    @ObservationIgnored private var lease: VaultSessionLease?
    /// Inaktivitätssperre (Systemlaufzeit, nicht Uhrzeit).
    @ObservationIgnored private var session = VaultAccessSession()
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var noteJournals: [String: VaultNoteJournal] = [:]
    @ObservationIgnored private var closing = false
    /// Zählt Sperren: Ein Entsperren, das erst nach einer Sperre fertig wird, öffnet nicht.
    @ObservationIgnored private var lockCount = 0

    var isSetUp: Bool { phase != .notSetUp }
    /// Eingang in den Einstellungen ausgeblendet; geöffnet wird dann nur über „Heute“ 2 Sekunden halten.
    var hidesEntry: Bool { isSetUp && settings?.hideEntry == true }
    var biometryName: String? { VaultKeychain.biometryName }
    var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var snapshot: VaultSnapshot { VaultSnapshot(sequence: sequence, media: index, workspace: workspace) }
    /// Belegte Plätze für das Free-Limit (Tresor-Papierkorb zählt mit).
    var mediaSlotsUsed: Int { index.items.count + workspace.mediaTrash.count }

    private init() { reloadState() }

    // MARK: Ablage (neutral benannt, im iPhone-Backup enthalten, Dateien mit Dateischutz „vollständig“)

    nonisolated static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".pmv", isDirectory: true)
    }
    nonisolated static var objects: URL { root.appendingPathComponent("o", isDirectory: true) }
    nonisolated static var thumbs: URL { root.appendingPathComponent("t", isDirectory: true) }
    nonisolated static var temp: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pmv-tmp", isDirectory: true)
    }
    private static var settingsURL: URL { root.appendingPathComponent("state.json") }
    private static var indexURL: URL { root.appendingPathComponent("index.bin") }

    /// Zustand von der Platte lesen. Eingerichtet = verschlüsseltes Inhaltsverzeichnis vorhanden.
    func reloadState() {
        if phase != .unlocked { cleanTemp() }
        guard FileManager.default.fileExists(atPath: Self.indexURL.path) else {
            settings = nil
            phase = .notSetUp
            return
        }
        if let data = try? Data(contentsOf: Self.settingsURL), let s = try? JSONDecoder().decode(VaultSettings.self, from: data) {
            settings = s
        }
        if phase != .unlocked { phase = .locked }
    }

    // MARK: Öffnen, Sperren, Sitzung

    /// Geheimer Eingang („Heute“ 2 Sekunden halten). Ohne eingerichteten Tresor passiert nichts.
    @discardableResult
    func openFromHiddenEntry() -> Bool {
        reloadState()
        guard isSetUp else { return false }
        isPresented = true
        return true
    }

    /// Sichtbarer Eintrag in den Einstellungen (Einrichten oder Öffnen).
    func present() {
        reloadState()
        isPresented = true
    }

    /// Schließen = sperren: laufende Aufnahmen zuerst sicher abschließen, dann Sitzung widerrufen; Schlüssel, Inhalte,
    /// Vorschaubilder und entschlüsselte Temp-Dateien weg.
    func lock() {
        guard !closing else { return }
        closing = true
        defer { closing = false }
        NotificationCenter.default.post(name: .vaultWillLock, object: nil)
        VaultDisclosure.cancel()
        lease?.revoke()
        lease = nil
        session.revoke()
        lockCount += 1
        key = nil
        index = VaultIndex()
        workspace = VaultWorkspace()
        sequence = 0
        noteJournals = [:]
        thumbnails = [:]
        loadingThumbs = []
        progress = nil
        needsNewCode = false
        if phase == .unlocked { phase = .locked }
        isPresented = false
        cleanTemp()
    }

    /// Bedienung verlängert die Sitzung (Inaktivitätssperre).
    func touch() {
        guard phase == .unlocked, !closing else { return }
        if !session.touch(now: uptime) { lock() }
    }

    /// Regelmäßig aus der Ansicht: nach der eingestellten Zeit ohne Bedienung sperren. Läuft gerade eine gezählte
    /// Aktion (Ablegen, Zurücklegen, Import), gilt das als Bedienung.
    func checkInactivity() {
        guard phase == .unlocked else { return }
        // A running vault operation counts as activity.
        if progress != nil { _ = session.touch(now: uptime); return }
        if session.requiresLock(now: uptime) { lock() }
    }

    /// Gültige Sitzung für eine Aktion aus der Ansicht (nicht bei Pflicht zum neuen Code).
    func requireLease() throws -> VaultSessionLease {
        guard phase == .unlocked, !needsNewCode, let lease, accepts(lease) else { throw VaultCryptoError.authentication }
        try lease.check()
        return lease
    }

    /// Ergebnis darf nur in die Sitzung, die es angefordert hat (nicht nach Sperre oder Inaktivität).
    func accepts(_ candidate: VaultSessionLease) -> Bool {
        guard lease === candidate, candidate.isValid, phase == .unlocked, let token = session.token else { return false }
        return closing || session.accepts(token, now: uptime)
    }

    func unlock(code: String) async -> UnlockResult {
        guard var s = settings else { return .unavailable }
        let now = nowMs
        let wait = s.lockout.remainingSeconds(nowMs: now)
        if wait > 0 { return .lockedOut(seconds: wait) }
        guard let data = VaultKeychain.get(VaultKeychain.codeAccount),
              let wrapped = try? JSONDecoder().decode(VaultWrappedKey.self, from: data) else { return .unavailable }
        let attempt = lockCount
        let key = await Task.detached(priority: .userInitiated) { try? VaultCrypto.unwrap(wrapped, secret: code) }.value
        guard attempt == lockCount, isPresented else { return .cancelled }
        guard let key else {
            s.lockout.registerFailure(nowMs: now)
            store(s)
            let w = s.lockout.remainingSeconds(nowMs: now)
            return w > 0 ? .lockedOut(seconds: w) : .wrong
        }
        s.lockout.registerSuccess()
        store(s)
        return open(with: key) ? .opened : .unavailable
    }

    func unlockWithBiometrics() async -> Bool {
        // Nur bei sichtbar geöffnetem Tresor: nie im Hintergrund oder während des Schließens entsperren.
        guard settings?.biometrics == true, isPresented else { return false }
        let attempt = lockCount
        guard let key = await VaultKeychain.readBiometric(reason: L("vault_biometric_reason")), attempt == lockCount,
              isPresented
        else { return false }
        return open(with: key)
    }

    /// Notfallschlüssel: öffnet und verlangt danach einen neuen Code (auch bei Fehlversuchssperre erlaubt).
    func unlock(recoveryKey: String) async -> UnlockResult {
        guard var s = settings, let wrapped = s.recovery,
              let normalized = VaultRecoveryKey.normalize(recoveryKey) else { return .wrong }
        let attempt = lockCount
        let key = await Task.detached(priority: .userInitiated) { try? VaultCrypto.unwrap(wrapped, secret: normalized) }.value
        guard attempt == lockCount, isPresented else { return .cancelled }
        guard let key, open(with: key) else { return .wrong }
        s.lockout.registerSuccess()
        store(s)
        needsNewCode = true
        return .opened
    }

    /// Öffnet erst, wenn Schnappschuss und Notiz-Journale geprüft sind. Ein beschädigtes Journal ist ein Fehler, keine
    /// Erlaubnis, einen älteren Stand als gespeichert zu zeigen.
    private func open(with key: VaultKey) -> Bool {
        do {
            let sealed = try Data(contentsOf: Self.indexURL)
            let plain = try VaultCrypto.open(sealed, key: Self.indexKey(key))
            // Version 1 (nur Medien) wird hier übernommen und beim nächsten Speichern als Version 2 geschrieben.
            var value = try VaultSnapshot.decode(plain)
            var changed = try VaultNoteJournalIO.replay(into: &value, root: Self.root, key: key)
            // Einträge älterer Fassungen: ursprüngliche Kennung übernehmen, solange bekannt (nie raten).
            if value.media.migrateOriginalIDs() { changed = true }
            try value.validate()
            // A damaged public projection stays closed until syncConcealment can also rebuild
            // the transitive derived-output identities from AppModel's persisted provenance.
            if changed {
                guard value.sequence < UInt64.max else { throw VaultWorkspaceError.invalidData }
                value.sequence += 1
                try Self.persist(value, key: key)
            }
            VaultNoteJournalIO.removeReplayed(root: Self.root)
            cleanTemp()
            index = value.media
            workspace = value.workspace
            sequence = value.sequence
            noteJournals = [:]
            thumbnails = [:]
            loadingThumbs = []
            self.key = key
            lease = VaultSessionLease(key: key, parent: Self.temp)
            session.begin(now: uptime, timeout: Double(value.workspace.inactivitySeconds))
            phase = .unlocked
            finishPendingPurges()
            VaultCaptureRecovery.recoverSealed(store: self)
            return true
        } catch {
            Diagnostics.error(.persistence, "vault-open-failed", error)
            return false
        }
    }

    /// Verbergen-Liste mit dem Inhaltsverzeichnis abgleichen (z. B. Einträge aus Build 3/4, beschädigte Liste,
    /// wiederhergestelltes Backup) und die übrige App aufräumen, falls sich etwas geändert hat.
    func syncConcealment(app: AppModel) async {
        guard phase == .unlocked else { return }
        let roots = snapshot.originalIDs
        let records = app.kv?.get(StoreKeys.edits) ?? []
        let ids = roots.union(VaultDerivation.copies(of: roots, records: records))
        do {
            // phase == unlocked proves the snapshot was decrypted, replayed and validated in open().
            // Repair only once ALL known roots/files/descendants are available, never a partial list.
            let boundary = VaultConcealment.shared
            let identities = snapshot.fileConcealmentKeys.union(ids)
            if boundary.analysisReady {
                try boundary.conceal(identities)
            } else {
                try boundary.repair(authenticatedIDs: identities)
            }
            await app.applyVaultConcealment(ids)
        } catch {
            operationFailed = true
            lock()
            await app.applyVaultConcealment(ids)
        }
    }

    // MARK: Einrichten und Einstellungen

    /// Neuer Notfallschlüssel zum Aufschreiben (16 Zufallsbytes).
    nonisolated static func makeRecoveryKey() -> String? {
        guard let bytes = try? VaultCrypto.randomBytes(VaultRecoveryKey.byteCount) else { return nil }
        return VaultRecoveryKey.format(bytes)
    }

    /// Richtet den Tresor neu ein. Reste eines früheren Tresors werden nie gelöscht, sondern beiseitegelegt (z. B. ein
    /// beschädigtes Inhaltsverzeichnis); die Verbergen-Liste bleibt erhalten.
    func setUp(code: String, kind: VaultCodeKind, recoveryKey: String?, biometrics: Bool, hideEntry: Bool) async -> Bool {
        let fm = FileManager.default
        var createdRoot = false
        do {
            try Self.setAsideLeftovers()
            let key = try VaultKey.random()
            let wrapped = try await Task.detached(priority: .userInitiated) {
                try VaultCrypto.wrap(key, secret: code, rounds: VaultCrypto.codeRounds)
            }.value
            var recovery: VaultWrappedKey?
            if let normalized = recoveryKey.flatMap(VaultRecoveryKey.normalize) {
                recovery = try await Task.detached(priority: .userInitiated) {
                    try VaultCrypto.wrap(key, secret: normalized, rounds: VaultCrypto.recoveryRounds)
                }.value
            }
            for dir in [Self.root, Self.objects, Self.thumbs] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
            createdRoot = true
            let s = VaultSettings(codeKind: kind, hideEntry: hideEntry, biometrics: false, recovery: recovery, createdMs: nowMs)
            try write(s)
            try VaultConcealment.shared.conceal([String]())
            try Self.persist(VaultSnapshot(), key: key)
            // Zugangsdaten zuletzt: erst wenn Index und Einstellungen sicher liegen.
            try VaultKeychain.set(JSONEncoder().encode(wrapped), account: VaultKeychain.codeAccount)
            var configured = s
            if biometrics, (try? VaultKeychain.setBiometric(key.data)) != nil {
                configured.biometrics = true
                try? write(configured)
            }
            settings = configured
            needsNewCode = false
            return open(with: key)
        } catch {
            // Nur entfernen, was dieser Versuch selbst angelegt hat (nie einen früheren Tresor).
            Diagnostics.error(.persistence, "vault-setup-failed", error)
            if createdRoot {
                for url in [Self.indexURL, Self.settingsURL] { try? fm.removeItem(at: url) }
            }
            key = nil
            settings = nil
            phase = .notSetUp
            return false
        }
    }

    /// Vorhandene Tresor-Dateien ohne gültiges Inhaltsverzeichnis: nicht löschen, sondern daneben aufbewahren.
    private static func setAsideLeftovers() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        let objects = (try? fm.contentsOfDirectory(atPath: Self.objects.path)) ?? []
        let hasData = !objects.isEmpty || fm.fileExists(atPath: indexURL.path) || fm.fileExists(atPath: settingsURL.path)
        guard hasData else { return }
        let aside = root.deletingLastPathComponent()
            .appendingPathComponent(".pmv-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try fm.moveItem(at: root, to: aside)
        // Die Verbergen-Liste gilt weiter (Originale bleiben in PhotoMaid verborgen).
        let concealment = aside.appendingPathComponent(VaultConcealment.url.lastPathComponent)
        if fm.fileExists(atPath: concealment.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try fm.copyItem(at: concealment, to: VaultConcealment.url)
        }
    }

    func changeCode(_ code: String, kind: VaultCodeKind) async -> Bool {
        guard let key, var s = settings else { return false }
        guard let wrapped = try? await Task.detached(priority: .userInitiated, operation: {
            try VaultCrypto.wrap(key, secret: code, rounds: VaultCrypto.codeRounds)
        }).value, lease?.isValid == true, let data = try? JSONEncoder().encode(wrapped),
              (try? VaultKeychain.set(data, account: VaultKeychain.codeAccount)) != nil
        else { return false }
        s.codeKind = kind
        store(s)
        needsNewCode = false
        return true
    }

    /// Neuer Notfallschlüssel (ersetzt den alten). Ergebnis zum Aufschreiben.
    func renewRecoveryKey() async -> String? {
        guard let key, var s = settings, let formatted = Self.makeRecoveryKey(),
              let normalized = VaultRecoveryKey.normalize(formatted) else { return nil }
        guard let wrapped = try? await Task.detached(priority: .userInitiated, operation: {
            try VaultCrypto.wrap(key, secret: normalized, rounds: VaultCrypto.recoveryRounds)
        }).value, lease?.isValid == true else { return nil }
        s.recovery = wrapped
        guard (try? write(s)) != nil else { return nil }
        settings = s
        return formatted
    }

    func removeRecoveryKey() {
        guard var s = settings else { return }
        s.recovery = nil
        store(s)
    }

    func setBiometrics(_ on: Bool) -> Bool {
        guard let key, var s = settings else { return false }
        if on {
            guard (try? VaultKeychain.setBiometric(key.data)) != nil else { return false }
        } else {
            VaultKeychain.delete(VaultKeychain.biometricAccount)
        }
        s.biometrics = on
        store(s)
        return true
    }

    func setHideEntry(_ on: Bool) {
        guard var s = settings else { return }
        s.hideEntry = on
        store(s)
    }

    func setSort(_ sort: VaultSort) {
        guard var s = settings, s.sort != sort else { return }
        s.sort = sort
        store(s)
    }

    /// Inaktivitätssperre in Sekunden (30, 60, 120, 300, 600).
    func setInactivity(_ seconds: Int) throws {
        try workspaceTransaction { $0.inactivitySeconds = seconds }
        session.begin(now: uptime, timeout: Double(seconds))
    }

    /// Ganzen Tresor unwiderruflich löschen (nur offen, mit Bestätigung in der Ansicht). Originale, die noch in der
    /// Fotos-App liegen, erscheinen danach wieder in PhotoMaid.
    func deleteVault(app: AppModel) {
        guard phase == .unlocked else { return }
        NotificationCenter.default.post(name: .vaultWillLock, object: nil) // laufende Aufnahme vorher beenden
        do {
            try FileManager.default.removeItem(at: Self.root)
            try VaultConcealment.shared.forgetAll()
        } catch {
            operationFailed = true
            return
        }
        VaultKeychain.deleteAll()
        lock()
        settings = nil
        phase = .notSetUp
        app.reloadLibraryIfNeeded(force: true)
        Task { await app.publishRead() }
    }

    // MARK: Speichern (erst gespeichert, dann sichtbar)

    /// Änderung an Notizen, Dateien, Ordnern oder Einstellungen des Tresors aus der Ansicht.
    func workspaceTransaction(_ mutate: (inout VaultWorkspace) throws -> Void) throws {
        _ = try requireLease()
        try commitSnapshot { try mutate(&$0.workspace) }
    }

    /// Medien-Inhaltsverzeichnis ändern.
    private func commit(_ change: (inout VaultIndex) throws -> Void) throws {
        try commitSnapshot { try change(&$0.media) }
    }

    /// Ein Schreibvorgang für alles: geprüft und verschlüsselt gespeichert, erst danach im Speicher übernommen.
    /// Ältere Notiz-Journale sind damit überholt.
    func commitSnapshot(_ change: (inout VaultSnapshot) throws -> Void) throws {
        guard let lease, lease.isValid, sequence < UInt64.max else { throw VaultCryptoError.authentication }
        var value = snapshot
        let filesBefore = value.fileConcealmentKeys
        try VaultTransaction.update(&value, mutate: { candidate in
            try change(&candidate)
            candidate.sequence += 1
            try candidate.validate()
        }, persist: { candidate in
            // Isolation must be durable BEFORE a newly imported object enters the encrypted index.
            try VaultConcealment.shared.conceal(candidate.originalIDs.union(candidate.fileConcealmentKeys))
            try Self.persist(candidate, key: lease.key)
        })
        index = value.media
        workspace = value.workspace
        sequence = value.sequence
        let acknowledged = Set(noteJournals.keys)
        noteJournals = [:]
        VaultNoteJournalIO.removeAcknowledged(root: Self.root, ids: acknowledged)
        // Originale von Dateien aus verbundenen Ordnern: verbergen, solange die Datei im Tresor liegt (abgeglichen im
        // Bereich „Dateien“ beim Schließen des Tresors).
        let filesAfter = value.fileConcealmentKeys
        if filesAfter != filesBefore {
            do { try VaultConcealment.shared.reveal(filesBefore.subtracting(filesAfter)) }
            catch {
                // Index is committed: never throw and let an import caller remove its ciphertext.
                // A failed reveal leaves extra concealment, not exposure, and is surfaced to the user.
                operationFailed = true
            }
        }
        touch()
    }

    /// Notiz speichern: nur dieser Eintrag als verschlüsseltes Journal (Tastenanschläge schreiben nie das ganze
    /// Inhaltsverzeichnis). Die Revision verhindert, dass ein veralteter Editor Neueres überschreibt.
    func saveNote(_ draft: VaultNote, expectedRevision: UInt64?) throws {
        let activeLease = try requireLease()
        var candidate = workspace
        try candidate.saveNote(draft, expectedRevision: expectedRevision, nowMs: nowMs)
        guard let saved = candidate.notes.first(where: { $0.id == draft.id }) else { throw VaultWorkspaceError.missingItem }
        // Basis bleibt die des ersten Journals seit dem letzten Schnappschuss – auch `nil` für eine neue Notiz (sonst
        // passt das Journal beim nächsten Öffnen nicht mehr zum gespeicherten Stand).
        let baseRevision: UInt64?
        if let pending = noteJournals[draft.id] {
            baseRevision = pending.baseRevision
        } else {
            baseRevision = workspace.notes.first(where: { $0.id == draft.id })?.revision
        }
        let journal = VaultNoteJournal(snapshotSequence: sequence, baseRevision: baseRevision, note: saved)
        try VaultNoteJournalIO.save(journal, root: Self.root, lease: activeLease)
        workspace = candidate
        noteJournals[draft.id] = journal
        touch()
    }

    // MARK: Ordner

    @discardableResult
    func createFolder(_ name: String) -> VaultFolder? {
        var folder: VaultFolder?
        let id = UUID().uuidString, now = nowMs
        guard (try? commit { folder = $0.createFolder(name: name, id: id, nowMs: now) }) != nil else { return nil }
        return folder
    }

    @discardableResult
    func renameFolder(_ id: String, to name: String) -> Bool {
        var ok = false
        guard (try? commit { ok = $0.renameFolder(id, to: name) }) != nil else { return false }
        return ok
    }

    @discardableResult
    func deleteFolder(_ id: String) -> Bool {
        (try? commit { $0.deleteFolder(id) }) != nil
    }

    @discardableResult
    func move(_ ids: Set<String>, to folderID: String?) -> Bool {
        (try? commit { $0.move(ids: ids, to: folderID) }) != nil
    }

    // MARK: Medien und Tresor-Papierkorb

    /// In den Tresor-Papierkorb (umkehrbar, bleibt verschlüsselt und in PhotoMaid verborgen). Gelöscht wird nur
    /// ausdrücklich im Tresor-Papierkorb.
    /// `forgetOriginals`: das Medium liegt wieder in der Fotos-App (Zurücklegen) – die Kopie im Papierkorb verbirgt
    /// das Original dort nicht mehr.
    @discardableResult
    func moveToTrash(_ ids: Set<String>, forgetOriginals: Bool = false) -> Bool {
        let now = nowMs
        do {
            try commitSnapshot { s in
                for var item in s.media.remove(ids: ids) {
                    if forgetOriginals {
                        item.originalID = nil
                        item.sourceID = nil
                    }
                    s.workspace.mediaTrash.append(VaultTrashedMedia(id: item.id, deletedMs: now,
                                                                    encodedItem: try JSONEncoder().encode(item)))
                }
            }
        } catch {
            return false
        }
        for id in ids { thumbnails[id] = nil }
        return true
    }

    /// Aus dem Tresor-Papierkorb zurück zu den Medien. Das Original bleibt bzw. wird wieder in PhotoMaid verborgen.
    func restoreMediaFromTrash(_ ids: Set<String>, app: AppModel) async throws {
        var restored: [VaultItem] = []
        try commitSnapshot { s in
            let selected = s.workspace.mediaTrash.filter { ids.contains($0.id) }
            guard selected.count == ids.count else { throw VaultWorkspaceError.notInTrash }
            for archived in selected {
                var item = try JSONDecoder().decode(VaultItem.self, from: archived.encodedItem)
                if let folder = item.folderID, !s.media.folders.contains(where: { $0.id == folder }) { item.folderID = nil }
                s.media.add(item)
                restored.append(item)
            }
            s.workspace.mediaTrash.removeAll { ids.contains($0.id) }
        }
        let originals = Set(restored.compactMap { $0.originalID ?? $0.sourceID })
        // commitSnapshot already required durable isolation; refresh even if hashes did not change.
        await app.applyVaultConcealment(originals)
    }

    /// Endgültig aus dem Tresor löschen (nur aus dem Tresor-Papierkorb). Dateien erst nach gespeichertem
    /// Inhaltsverzeichnis. Originale, die noch in der Fotos-App liegen, erscheinen wieder in PhotoMaid.
    func purgeMediaFromTrash(_ ids: Set<String>, app: AppModel) throws {
        var purged: [VaultItem] = []
        try commitSnapshot { s in
            let selected = s.workspace.mediaTrash.filter { ids.contains($0.id) }
            guard selected.count == ids.count else { throw VaultWorkspaceError.notInTrash }
            for archived in selected {
                let item = try JSONDecoder().decode(VaultItem.self, from: archived.encodedItem)
                s.workspace.pendingObjectPurges.formUnion(item.resources.map(\.file).filter(VaultWorkspace.isOpaqueName))
                if let thumb = item.thumbnail, VaultWorkspace.isOpaqueName(thumb) { s.workspace.pendingThumbnailPurges.insert(thumb) }
                purged.append(item)
            }
            s.workspace.mediaTrash.removeAll { ids.contains($0.id) }
        }
        finishPendingPurges()
        let stillHidden = snapshot.originalIDs
        reveal(purged.compactMap { $0.originalID ?? $0.sourceID }.filter { !stillHidden.contains($0) }, app: app)
    }

    /// Dateien, deren Verweise schon sicher entfernt sind, physisch löschen (auch nach einem Abbruch beim nächsten
    /// Öffnen). Nur undurchsichtige Namen, nie übergebene Pfade.
    func finishPendingPurges() {
        guard lease?.isValid == true, !workspace.pendingObjectPurges.isEmpty || !workspace.pendingThumbnailPurges.isEmpty
        else { return }
        let fm = FileManager.default
        var doneObjects: Set<String> = [], doneThumbs: Set<String> = []
        for name in workspace.pendingObjectPurges where VaultWorkspace.isOpaqueName(name) {
            let url = Self.objects.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) || (try? fm.removeItem(at: url)) != nil { doneObjects.insert(name) }
        }
        for name in workspace.pendingThumbnailPurges where VaultWorkspace.isOpaqueName(name) {
            let url = Self.thumbs.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) || (try? fm.removeItem(at: url)) != nil { doneThumbs.insert(name) }
        }
        guard !doneObjects.isEmpty || !doneThumbs.isEmpty else { return }
        do {
            try commitSnapshot { s in
                s.workspace.pendingObjectPurges.subtract(doneObjects)
                s.workspace.pendingThumbnailPurges.subtract(doneThumbs)
            }
        } catch {
            operationFailed = true
        }
    }

    private func reveal(_ originalIDs: [String], app: AppModel) {
        guard !originalIDs.isEmpty else { return }
        let records = app.kv?.get(StoreKeys.edits) ?? []
        let roots = Set(originalIDs)
        let candidates = roots.union(VaultDerivation.copies(of: roots, records: records))
        let remaining = snapshot.originalIDs
        let stillPrivate = remaining.union(VaultDerivation.copies(of: remaining, records: records))
        // A mixed collage/movie stays concealed if another source still belongs to the vault.
        do { try VaultConcealment.shared.reveal(candidates.subtracting(stillPrivate)) }
        catch { operationFailed = true; return }
        app.reloadLibraryIfNeeded(force: true)
        Task { await app.publishRead() }
    }

    func thumbnail(_ item: VaultItem) async {
        guard thumbnails[item.id] == nil, !loadingThumbs.contains(item.id), let lease, lease.isValid,
              let name = item.thumbnail, VaultPathRules.isComponent(name) else { return }
        loadingThumbs.insert(item.id)
        defer { loadingThumbs.remove(item.id) }
        let url = Self.thumbs.appendingPathComponent(name)
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard lease.isValid, let sealed = try? Data(contentsOf: url),
                  let data = try? VaultCrypto.open(sealed, key: VaultCrypto.subkey(lease.key, salt: [], info: "pm-vault-thumb"))
            else { return nil }
            return UIImage(data: data)
        }.value
        guard lease.isValid, let image else { return }
        thumbnails[item.id] = image
    }

    /// Foto für die Ansicht (verkleinert auf `maxPixel`, nie verzerrt). Nach einer Sperre: nichts.
    func photo(_ item: VaultItem, maxPixel: CGFloat) async -> UIImage? {
        guard let lease, lease.isValid, let resource = item.current, VaultPathRules.isComponent(resource.file) else { return nil }
        let url = Self.objects.appendingPathComponent(resource.file)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard lease.isValid, let data = try? VaultFileReader.data(at: url, master: lease.key) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }.value
        return lease.isValid ? image : nil
    }

    /// Video in eine geschützte Temp-Datei entschlüsseln (wird beim Sperren gelöscht; nach einer Sperre: nichts).
    func videoFile(_ item: VaultItem) async -> URL? {
        guard let lease, lease.isValid, let resource = item.current else { return nil }
        let url = await Task.detached(priority: .userInitiated) { try? Self.decryptToTemp(resource, lease: lease) }.value
        guard lease.isValid else {
            if let url { removeTempFiles([url]) }
            return nil
        }
        return url
    }

    /// Dateien zum Teilen (aktuelle Fassung unter ihrem Originalnamen, sofern der ein sicherer Dateiname ist). Vorher
    /// der Hinweis, dass die Kopie den Tresorschutz verlässt. `nil` = abgebrochen (keine Fehlermeldung).
    func shareFiles(_ ids: Set<String>) async -> [URL]? {
        guard let activeLease = try? requireLease() else { return [] }
        guard await VaultDisclosure.confirm(), accepts(activeLease) else { return nil }
        let resources = index.items.filter { ids.contains($0.id) }.compactMap(\.current)
        let urls = await Task.detached(priority: .userInitiated) {
            resources.compactMap { try? Self.decryptToTemp($0, lease: activeLease) }
        }.value
        guard accepts(activeLease), urls.count == resources.count else {
            removeTempFiles(urls)
            return []
        }
        return urls
    }

    func removeTempFiles(_ urls: [URL]) {
        let base = Self.temp.standardizedFileURL.path + "/"
        for url in urls where url.standardizedFileURL.path.hasPrefix(base) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    // MARK: Dateien

    /// Dateien verschlüsselt und geprüft in den Tresor kopieren. Ein Import ist nie ein Beleg, dass die Quelle
    /// gelöscht wurde („Original entfernen“ ist ein eigener, bestätigter Schritt).
    func importDocuments(_ urls: [URL], folderID: String? = nil) async -> VaultFileImportResult {
        var report = VaultFileImportResult()
        guard progress == nil, let activeLease = try? requireLease() else {
            report.failed = urls.count
            return report
        }
        progress = VaultProgress(done: 0, total: urls.count)
        defer { if accepts(activeLease) { progress = nil } }
        for (offset, source) in urls.enumerated() {
            do {
                guard activeLease.isValid else { throw CancellationError() }
                let now = nowMs
                let file = try await Task.detached(priority: .userInitiated) {
                    try VaultWorkspaceIO.importFile(source, lease: activeLease, objects: Self.objects, nowMs: now)
                }.value
                do {
                    guard activeLease.isValid else { throw CancellationError() }
                    try commitSnapshot { try $0.workspace.addFile(file, folderID: folderID) }
                    report.imported.append(file.id)
                } catch {
                    try? FileManager.default.removeItem(at: Self.objects.appendingPathComponent(file.objectName))
                    throw error
                }
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.failed += 1
            }
            if activeLease.isValid { progress = VaultProgress(done: offset + 1, total: urls.count) }
        }
        return report
    }

    /// Im Tresor erzeugte Daten (z. B. Scan als PDF) direkt verschlüsselt ablegen – ohne Klartext-Zwischendatei.
    @discardableResult
    func importData(_ data: Data, name: String, type: UTType, folderID: String? = nil) async throws -> String {
        let activeLease = try requireLease()
        let now = nowMs
        let file = try await Task.detached(priority: .userInitiated) {
            try VaultWorkspaceIO.importData(data, name: name, type: type, lease: activeLease, objects: Self.objects, nowMs: now)
        }.value
        do {
            guard accepts(activeLease) else { throw CancellationError() }
            try commitSnapshot { try $0.workspace.addFile(file, folderID: folderID) }
            return file.id
        } catch {
            try? FileManager.default.removeItem(at: Self.objects.appendingPathComponent(file.objectName))
            throw error
        }
    }

    /// Private Vorschau einer Datei (geschützte Temp-Datei der Sitzung, beim Sperren gelöscht).
    func documentPreview(_ id: String) async throws -> URL {
        let activeLease = try requireLease()
        guard let document = workspace.files.first(where: { $0.id == id && $0.trashedMs == nil }) else {
            throw VaultWorkspaceError.missingItem
        }
        let url = try await Task.detached(priority: .userInitiated) {
            try VaultWorkspaceIO.preview(document, lease: activeLease, objects: Self.objects)
        }.value
        guard accepts(activeLease) else {
            removeTempFiles([url])
            throw CancellationError()
        }
        return url
    }

    func shareDocuments(_ ids: Set<String>) async throws -> [URL] {
        let activeLease = try requireLease()
        guard await VaultDisclosure.confirm(), accepts(activeLease) else { throw CancellationError() }
        var urls: [URL] = []
        do {
            for id in ids { urls.append(try await documentPreview(id)) }
            guard accepts(activeLease) else { throw CancellationError() }
            return urls
        } catch {
            removeTempFiles(urls)
            throw error
        }
    }

    /// Original einer importierten Datei am Quellort entfernen: nur nach ausdrücklicher Bestätigung und erneuter
    /// Prüfung der Tresorkopie und der unveränderten Quelle.
    func removeFileOriginal(_ id: String) async throws {
        let activeLease = try requireLease()
        guard let file = workspace.files.first(where: { $0.id == id && $0.trashedMs == nil }),
              await VaultDisclosure.confirm(messageKey: "vault2_remove_original_warning"), accepts(activeLease)
        else { throw CancellationError() }
        try await Task.detached(priority: .userInitiated) {
            let verified = try VaultFileReader.digest(Self.objects.appendingPathComponent(file.objectName), master: activeLease.key)
            guard verified.size == file.byteCount, verified.sha256 == file.sha256 else { throw VaultCryptoError.authentication }
            try VaultWorkspaceIO.removeOriginal(file, lease: activeLease)
        }.value
        guard activeLease.isValid else { return }
        try commitSnapshot { s in
            guard let i = s.workspace.files.firstIndex(where: { $0.id == id }) else { throw VaultWorkspaceError.missingItem }
            s.workspace.files[i].origin = .sourceRemoved
            s.workspace.files[i].sourceBookmark = nil
        }
    }

    // MARK: Ablegen (Fotos-App → Tresor)

    /// Von PhotoMaid erstellte Kopien der Auswahl (Bearbeitungen, Collagen, Filme, GIFs), die noch sichtbar sind –
    /// zum Mit-Ablegen anbieten. Ältere Collagen/Filme ohne gespeicherte Quellen lassen sich nicht zuordnen.
    func derivedCopies(of ids: [String], app: AppModel) -> [String] {
        let records = app.kv?.get(StoreKeys.edits) ?? []
        let selected = Set(ids)
        return VaultDerivation.copies(of: selected, records: records)
            .filter { !selected.contains($0) && app.asset($0) != nil }
            .sorted()
    }

    /// Kopiert die Medien vollständig und geprüft in den Tresor, verbirgt sie sofort in PhotoMaid und fragt erst dann
    /// iOS, ob sie aus der Fotos-App gelöscht werden dürfen. Free: höchstens 50 Medien im Tresor (inkl. Papierkorb).
    func importAssets(_ ids: [String], app: AppModel) async -> VaultImportReport {
        var report = VaultImportReport()
        guard progress == nil, let lease, lease.isValid, phase == .unlocked else { return report }
        let allowed = VaultPolicy.allowed(requested: ids.count, existing: mediaSlotsUsed,
                                          unlimited: app.capabilities.hasProToolsAccess)
        report.skippedByLimit = ids.count - allowed
        let list = Array(ids.prefix(allowed))
        guard !list.isEmpty else { return report }
        progress = VaultProgress(done: 0, total: list.count)
        var copied: [String] = []
        for (i, id) in list.enumerated() {
            guard lease.isValid, !Task.isCancelled else { break }
            do {
                let item = try await VaultImporter.importAsset(id: id, key: lease.key, objects: Self.objects, thumbs: Self.thumbs,
                                                               nowMs: nowMs)
                guard lease.isValid else { Self.removeFiles(of: item); break }
                do {
                    let roots: Set<String> = [id]
                    let records = app.kv?.get(StoreKeys.edits) ?? []
                    try VaultConcealment.shared.conceal(roots.union(VaultDerivation.copies(of: roots, records: records)))
                    try commit { $0.add(item) }
                } catch {
                    Self.removeFiles(of: item)
                    throw error
                }
                copied.append(id)
                report.imported += 1
            } catch {
                report.failed += 1
            }
            progress = VaultProgress(done: i + 1, total: list.count)
        }
        progress = nil
        guard !copied.isEmpty else { return report }
        // Sofort verbergen – unabhängig davon, ob iOS das Löschen gleich bestätigt.
        await app.applyVaultConcealment(Set(copied))
        guard lease.isValid else { return report }
        report.removedFromLibrary = await removeFromLibrary(copied, app: app)
        return report
    }

    /// iOS-Löschabfrage für Medien, die schon sicher im Tresor liegen und in PhotoMaid verborgen sind.
    private func removeFromLibrary(_ sourceIDs: [String], app: AppModel) async -> Int {
        let outcome = await app.library.delete(ids: sourceIDs)
        let removed: Set<String>
        switch outcome {
        case .succeeded: removed = Set(sourceIDs)
        case .partial(let refs): removed = Set(refs.map(\.localIdentifier))
        case .cancelled, .failed: removed = []
        }
        guard !removed.isEmpty else { return 0 }
        if lease?.isValid == true { _ = try? commit { $0.markRemovedFromLibrary(sourceIDs: removed) } }
        app.reloadLibraryIfNeeded(force: true)
        return removed.count
    }

    /// Medien, die noch zusätzlich in der Fotos-App liegen (iOS-Abfrage abgelehnt), erneut zum Löschen anbieten.
    func retryLibraryRemoval(app: AppModel) async -> Int {
        let pending = index.stillInLibrary
        let existing = pending.filter { PhotoLibraryService.phAssetIncludingConcealed($0) != nil }
        let gone = Set(pending).subtracting(existing)
        if !gone.isEmpty { _ = try? commit { $0.markRemovedFromLibrary(sourceIDs: gone) } }
        guard !existing.isEmpty else { return 0 }
        return await removeFromLibrary(existing, app: app)
    }

    /// Noch in der Fotos-App vorhandene Originale (für den Hinweis im Tresor; in PhotoMaid sind sie verborgen).
    var stillInLibraryCount: Int {
        index.stillInLibrary.filter { PhotoLibraryService.phAssetIncludingConcealed($0) != nil }.count
    }

    // MARK: Zurücklegen (Tresor → Fotos-App)

    /// Zurück in die Fotos-App. Liegt das Original dort noch (iOS-Löschabfrage abgelehnt oder aus „Zuletzt gelöscht“
    /// zurückgeholt) und soll das Medium den Tresor verlassen, wird es nur wieder sichtbar gemacht (keine doppelte Kopie).
    /// Sonst entsteht ein neues Medium mit Datum, Ort und Favorit wie vorher. `removeFromVault`: danach in den
    /// Tresor-Papierkorb (umkehrbar) – nur, was vollständig zurückgelegt wurde; bei einem vereinfachten Ergebnis bleibt
    /// das vollständige Original bei den Medien im Tresor.
    func restore(_ ids: Set<String>, removeFromVault: Bool, app: AppModel) async -> VaultRestoreReport {
        var report = VaultRestoreReport()
        guard progress == nil, let lease, lease.isValid, phase == .unlocked else { return report }
        let items = index.items.filter { ids.contains($0.id) }
        progress = VaultProgress(done: 0, total: items.count)
        var leaveVault: [VaultItem] = []
        for (i, item) in items.enumerated() {
            guard lease.isValid else { break }
            if removeFromVault, let original = item.originalID ?? item.sourceID,
               PhotoLibraryService.phAssetIncludingConcealed(original) != nil {
                leaveVault.append(item)
                report.restored += 1
            } else {
                switch await VaultRestorer.restore(item, objects: Self.objects, lease: lease) {
                case .complete:
                    report.restored += 1
                    leaveVault.append(item)
                case .simplified:
                    report.restored += 1
                    report.keptComplete += removeFromVault ? 1 : 0
                case .failed:
                    report.failed += 1
                }
            }
            progress = VaultProgress(done: i + 1, total: items.count)
        }
        progress = nil
        if removeFromVault && lease.isValid && !leaveVault.isEmpty,
           moveToTrash(Set(leaveVault.map(\.id)), forgetOriginals: true) {
            // Das Medium ist wieder in der Fotos-App: dort auch in PhotoMaid zeigen.
            let stillHidden = snapshot.originalIDs
            reveal(leaveVault.compactMap { $0.originalID ?? $0.sourceID }.filter { !stillHidden.contains($0) }, app: app)
        }
        app.reloadLibraryIfNeeded(force: true)
        return report
    }

    // MARK: Hilfen

    private func store(_ s: VaultSettings) {
        settings = s
        try? write(s)
    }

    private func write(_ s: VaultSettings) throws {
        try JSONEncoder().encode(s).write(to: Self.settingsURL,
                                          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func persist(_ snapshot: VaultSnapshot, key: VaultKey) throws {
        let sealed = try VaultCrypto.seal(JSONEncoder().encode(snapshot), key: indexKey(key))
        try sealed.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    static func indexKey(_ key: VaultKey) -> SymmetricKey {
        VaultCrypto.subkey(key, salt: [], info: "pm-vault-index")
    }

    nonisolated static func removeFiles(of item: VaultItem) {
        let fm = FileManager.default
        for r in item.resources where VaultPathRules.isComponent(r.file) {
            try? fm.removeItem(at: objects.appendingPathComponent(r.file))
        }
        if let t = item.thumbnail, VaultPathRules.isComponent(t) { try? fm.removeItem(at: thumbs.appendingPathComponent(t)) }
    }

    private func cleanTemp() {
        try? FileManager.default.removeItem(at: Self.temp)
    }

    /// Entschlüsselt in einen Temp-Ordner der Sitzung und prüft Größe und Prüfsumme. Der Originalname wird nur
    /// verwendet, wenn er ein sicherer Dateiname ist. Wurde inzwischen gesperrt, bleibt kein Klartext liegen.
    nonisolated static func decryptToTemp(_ resource: VaultResource, lease: VaultSessionLease) throws -> URL {
        try lease.check()
        guard VaultPathRules.isComponent(resource.file) else { throw VaultCryptoError.format }
        let folder = try lease.makeDirectory()
        var name = resource.originalFilename
        let ext = (name as NSString).pathExtension.isEmpty ? UTType(resource.uti)?.preferredFilenameExtension
            : (name as NSString).pathExtension
        if !VaultPathRules.isComponent(name) || name.hasPrefix(".") {
            name = VaultPathRules.temporaryName(fileExtension: ext)
        } else if (name as NSString).pathExtension.isEmpty, let ext {
            name += "." + ext
        }
        let url = folder.appendingPathComponent(name)
        do {
            let result = try VaultFileReader.decrypt(objects.appendingPathComponent(resource.file), to: url, master: lease.key)
            guard result.size == resource.size, result.sha256 == resource.sha256 else { throw VaultCryptoError.authentication }
            try lease.check()
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return url
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

extension Notification.Name {
    /// Vor dem Sperren: laufende Aufnahmen sicher abschließen, solange der Schlüssel noch da ist.
    static let vaultWillLock = Notification.Name("PhotoMaid.vaultWillLock")
}

/// Ablegen eines Mediums: alle Teile laden (auch aus iCloud), verschlüsselt schreiben, gegen die Quelle prüfen.
enum VaultImporter {
    static func importAsset(id: String, key: VaultKey, objects: URL, thumbs: URL, nowMs: Int64) async throws -> VaultItem {
        guard let asset = PhotoLibraryService.phAssetIncludingConcealed(id) else { throw VaultCryptoError.io }
        var written: [VaultResource] = []
        var files: [URL] = []
        do {
            for resource in PHAssetResource.assetResources(for: asset) {
                guard let role = role(resource.type) else { continue }
                try Task.checkCancellation()
                let name = UUID().uuidString
                let url = objects.appendingPathComponent(name)
                files.append(url)
                let writer = try VaultFileWriter(url: url, master: key)
                do {
                    try await fetch(resource, into: writer)
                } catch {
                    writer.abort()
                    throw error
                }
                let result = try writer.finish()
                let check = try VaultFileReader.digest(url, master: key)
                guard check.size == result.size, check.sha256 == result.sha256 else { throw VaultCryptoError.authentication }
                written.append(VaultResource(role: role, file: name, uti: resource.uniformTypeIdentifier,
                                             originalFilename: resource.originalFilename, size: result.size,
                                             sha256: result.sha256))
            }
            guard VaultRestorePlan.current(written) != nil else { throw VaultCryptoError.io }
            let thumb = await thumbnail(asset, key: key, thumbs: thumbs)
            let kind: VaultMediaKind = asset.mediaType == .video ? .video
                : (asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo)
            return VaultItem(id: UUID().uuidString, kind: kind, resources: written,
                             creationMs: asset.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) }, addedMs: nowMs,
                             latitude: asset.location?.coordinate.latitude, longitude: asset.location?.coordinate.longitude,
                             isFavorite: asset.isFavorite, duration: asset.duration, pixelWidth: asset.pixelWidth,
                             pixelHeight: asset.pixelHeight, thumbnail: thumb, sourceID: id)
        } catch {
            for f in files { try? FileManager.default.removeItem(at: f) }
            throw error
        }
    }

    static func role(_ type: PHAssetResourceType) -> VaultResourceRole? {
        switch type {
        case .photo: .photo
        case .video: .video
        case .pairedVideo: .pairedVideo
        case .fullSizePhoto: .fullSizePhoto
        case .fullSizeVideo: .fullSizeVideo
        case .fullSizePairedVideo: .fullSizePairedVideo
        case .alternatePhoto: .alternatePhoto
        case .adjustmentData: .adjustmentData
        default: nil
        }
    }

    private static func fetch(_ resource: PHAssetResource, into writer: VaultFileWriter) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let box = UncheckedBox(resource)
        let request = DataRequestBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                let id = PHAssetResourceManager.default().requestData(for: box.value, options: options, dataReceivedHandler: { data in
                    writer.receive(data)
                }, completionHandler: { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                })
                request.set(id)
            }
        } onCancel: {
            if let id = request.id { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
    }

    private static func thumbnail(_ asset: PHAsset, key: VaultKey, thumbs: URL) async -> String? {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .highQualityFormat // genau ein Callback
        o.resizeMode = .fast
        o.version = .current
        let box = UncheckedBox(asset)
        let image: UIImage? = await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: box.value, targetSize: CGSize(width: 400, height: 400),
                                                  contentMode: .aspectFill, options: o) { @Sendable img, _ in
                cont.resume(returning: img)
            }
        }
        guard let data = image?.jpegData(compressionQuality: 0.8),
              let sealed = try? VaultCrypto.seal(data, key: VaultCrypto.subkey(key, salt: [], info: "pm-vault-thumb"))
        else { return nil }
        let name = UUID().uuidString
        do {
            try sealed.write(to: thumbs.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        } catch {
            return nil
        }
        return name
    }
}

/// Zurücklegen in die Fotos-App: zuerst mit allen Teilen (Bearbeitung bleibt rücksetzbar), sonst die aktuelle Fassung.
enum VaultRestorer {
    enum Outcome: Equatable {
        /// Alle gesicherten Teile liegen wieder in der Fotos-App.
        case complete
        /// Nur die aktuelle Fassung (mit Live-Photo-Video und RAW); Original/Bearbeitungsdaten fehlen dort.
        case simplified
        case failed
    }

    static func restore(_ item: VaultItem, objects: URL, lease: VaultSessionLease) async -> Outcome {
        guard let folder = try? lease.makeDirectory() else { return .failed }
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try lease.check()
            let full = VaultRestorePlan.full(item.resources)
            let simple = VaultRestorePlan.simple(item.resources)
            let needed = Set((full + simple).map(\.file))
            var urls: [String: URL] = [:]
            for r in item.resources where needed.contains(r.file) {
                guard VaultPathRules.isComponent(r.file) else { return .failed }
                let ext = (r.originalFilename as NSString).pathExtension
                let url = folder.appendingPathComponent(VaultPathRules.temporaryName(
                    fileExtension: ext.isEmpty ? (UTType(r.uti)?.preferredFilenameExtension ?? "dat") : ext))
                let result = try VaultFileReader.decrypt(objects.appendingPathComponent(r.file), to: url, master: lease.key)
                guard result.size == r.size, result.sha256 == r.sha256 else { return .failed }
                try lease.check()
                urls[r.file] = url
            }
            // Bringt der vereinfachte Plan alle Teile mit, ist er vollständig.
            let simpleIsComplete = Set(simple.map(\.file)) == Set(item.resources.map(\.file))
            if full.map(\.role) != simple.map(\.role), supports(full.map(\.role)),
               await create(item, plan: full, urls: urls, simplify: false) {
                return .complete
            }
            guard await create(item, plan: simple, urls: urls, simplify: true) else { return .failed }
            return simpleIsComplete ? .complete : .simplified
        } catch {
            return .failed
        }
    }

    private static func type(_ role: VaultResourceRole) -> PHAssetResourceType {
        switch role {
        case .photo: .photo
        case .video: .video
        case .pairedVideo: .pairedVideo
        case .fullSizePhoto: .fullSizePhoto
        case .fullSizeVideo: .fullSizeVideo
        case .fullSizePairedVideo: .fullSizePairedVideo
        case .alternatePhoto: .alternatePhoto
        case .adjustmentData: .adjustmentData
        }
    }

    private static func supports(_ roles: [VaultResourceRole]) -> Bool {
        PHAssetCreationRequest.supportsAssetResourceTypes(roles.map { NSNumber(value: type($0).rawValue) })
    }

    private static func create(_ item: VaultItem, plan: [VaultResource], urls: [String: URL], simplify: Bool) async -> Bool {
        let entries: [(PHAssetResourceType, URL, String)] = plan.compactMap { r in
            guard let url = urls[r.file] else { return nil }
            return (type(simplify ? VaultRestorePlan.simpleRole(r.role) : r.role), url, r.originalFilename)
        }
        guard !entries.isEmpty else { return false }
        let creation = item.creationMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        let latitude = item.latitude, longitude = item.longitude, favorite = item.isFavorite
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                for (type, url, name) in entries {
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = name
                    options.shouldMoveFile = false
                    request.addResource(with: type, fileURL: url, options: options)
                }
                request.creationDate = creation
                if let latitude, let longitude { request.location = CLLocation(latitude: latitude, longitude: longitude) }
                request.isFavorite = favorite
            }
            return true
        } catch {
            return false
        }
    }
}

/// Kennung eines laufenden Datei-Requests, damit ein Abbruch ihn beenden kann.
private final class DataRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: PHAssetResourceDataRequestID?
    var id: PHAssetResourceDataRequestID? { lock.withLock { _id } }
    func set(_ id: PHAssetResourceDataRequestID) { lock.withLock { _id = id } }
}
