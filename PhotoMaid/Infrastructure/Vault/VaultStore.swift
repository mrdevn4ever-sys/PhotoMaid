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

/// Privater Tresor (E16). Eine Wahrheit: das verschlüsselte Inhaltsverzeichnis im App-Container. Was hier liegt,
/// zeigt PhotoMaid nirgends sonst (`VaultConcealment` an allen PhotoKit-Zugängen) – auch wenn iOS das Löschen in der
/// Fotos-App nicht bestätigt. Schlüssel und Inhaltsverzeichnis liegen nur im Speicher, solange der Tresor offen ist;
/// jede Sperre widerruft die Sitzung (`VaultSessionFence`), verspätete Aufgaben öffnen, zeigen oder schreiben danach
/// nichts mehr. Änderungen am Inhaltsverzeichnis gelten erst, wenn sie gespeichert sind (`VaultTransaction`).
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
    private(set) var thumbnails: [String: UIImage] = [:]
    private(set) var progress: VaultProgress?
    /// Nach dem Öffnen mit dem Notfallschlüssel muss ein neuer Code gesetzt werden.
    private(set) var needsNewCode = false
    @ObservationIgnored private var key: VaultKey?
    @ObservationIgnored private var loadingThumbs: Set<String> = []
    @ObservationIgnored private let fence = VaultSessionFence()
    @ObservationIgnored private var lease: VaultSessionFence.Lease?
    /// Zählt Sperren: Ein Entsperren, das erst nach einer Sperre fertig wird, öffnet nicht.
    @ObservationIgnored private var lockCount = 0

    var isSetUp: Bool { phase != .notSetUp }
    /// Eingang in den Einstellungen ausgeblendet; geöffnet wird dann nur über „Heute“ 2 Sekunden halten.
    var hidesEntry: Bool { isSetUp && settings?.hideEntry == true }
    var biometryName: String? { VaultKeychain.biometryName }

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
    private var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

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

    // MARK: Öffnen, Sperren

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

    /// Schließen = sperren: Sitzung widerrufen, Schlüssel, Inhaltsverzeichnis, Vorschaubilder und entschlüsselte
    /// Temp-Dateien weg.
    func lock() {
        fence.revoke()
        lease = nil
        lockCount += 1
        key = nil
        index = VaultIndex()
        thumbnails = [:]
        loadingThumbs = []
        progress = nil
        needsNewCode = false
        if phase == .unlocked { phase = .locked }
        isPresented = false
        cleanTemp()
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
        guard attempt == lockCount else { return .cancelled }
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
        guard settings?.biometrics == true else { return false }
        let attempt = lockCount
        guard let key = await VaultKeychain.readBiometric(reason: L("vault_biometric_reason")), attempt == lockCount
        else { return false }
        return open(with: key)
    }

    /// Notfallschlüssel: öffnet und verlangt danach einen neuen Code (auch bei Fehlversuchssperre erlaubt).
    func unlock(recoveryKey: String) async -> UnlockResult {
        guard var s = settings, let wrapped = s.recovery,
              let normalized = VaultRecoveryKey.normalize(recoveryKey) else { return .wrong }
        let attempt = lockCount
        let key = await Task.detached(priority: .userInitiated) { try? VaultCrypto.unwrap(wrapped, secret: normalized) }.value
        guard attempt == lockCount else { return .cancelled }
        guard let key, open(with: key) else { return .wrong }
        s.lockout.registerSuccess()
        store(s)
        needsNewCode = true
        return .opened
    }

    private func open(with key: VaultKey) -> Bool {
        do {
            let sealed = try Data(contentsOf: Self.indexURL)
            let plain = try VaultCrypto.open(sealed, key: Self.indexKey(key))
            var opened = try JSONDecoder().decode(VaultIndex.self, from: plain)
            // Einträge älterer Fassungen: ursprüngliche Kennung übernehmen, solange bekannt (nie raten).
            if opened.migrateOriginalIDs() { try? Self.persist(opened, key: key) }
            index = opened
            self.key = key
            lease = fence.activate()
            phase = .unlocked
            return true
        } catch {
            return false
        }
    }

    /// Verbergen-Liste mit dem Inhaltsverzeichnis abgleichen (z. B. Einträge aus Build 3/4, beschädigte Liste) und die
    /// übrige App aufräumen, falls sich etwas geändert hat.
    func syncConcealment(app: AppModel) async {
        guard phase == .unlocked else { return }
        let ids = index.originalIDs
        guard !ids.isEmpty, (try? VaultConcealment.shared.conceal(ids)) == true else { return }
        await app.applyVaultConcealment(ids)
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
            try Self.persist(VaultIndex(), key: key)
            // Zugangsdaten zuletzt: erst wenn Index und Einstellungen sicher liegen.
            try VaultKeychain.set(JSONEncoder().encode(wrapped), account: VaultKeychain.codeAccount)
            var final = s
            if biometrics, (try? VaultKeychain.setBiometric(key.data)) != nil {
                final.biometrics = true
                try? write(final)
            }
            self.key = key
            index = VaultIndex()
            settings = final
            lease = fence.activate()
            phase = .unlocked
            needsNewCode = false
            return true
        } catch {
            // Nur entfernen, was dieser Versuch selbst angelegt hat (nie einen früheren Tresor).
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

    /// Ganzen Tresor unwiderruflich löschen (nur offen, mit Bestätigung in der Ansicht). Originale, die noch in der
    /// Fotos-App liegen, erscheinen danach wieder in PhotoMaid.
    func deleteVault(app: AppModel) {
        guard phase == .unlocked else { return }
        try? FileManager.default.removeItem(at: Self.root)
        VaultKeychain.deleteAll()
        VaultConcealment.shared.forgetAll()
        lock()
        settings = nil
        phase = .notSetUp
        app.reloadLibraryIfNeeded(force: true)
        Task { await app.publishRead() }
    }

    // MARK: Ordner (erst gespeichert, dann sichtbar)

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

    // MARK: Medien

    /// Endgültig aus dem Tresor löschen (es gibt dafür kein „Zuletzt gelöscht“). Dateien erst nach gespeichertem
    /// Inhaltsverzeichnis. Originale, die noch in der Fotos-App liegen, erscheinen wieder in PhotoMaid.
    @discardableResult
    func delete(_ ids: Set<String>, app: AppModel) -> Bool {
        var removed: [VaultItem] = []
        guard (try? commit { removed = $0.remove(ids: ids) }) != nil else { return false }
        for item in removed { Self.removeFiles(of: item) }
        for id in ids { thumbnails[id] = nil }
        // Nur zeigen, was kein anderer Eintrag im Tresor mehr verbirgt.
        let stillHidden = index.originalIDs
        reveal(removed.compactMap(\.originalID).filter { !stillHidden.contains($0) }, app: app)
        return true
    }

    private func reveal(_ originalIDs: [String], app: AppModel) {
        guard !originalIDs.isEmpty, (try? VaultConcealment.shared.reveal(originalIDs)) == true else { return }
        app.reloadLibraryIfNeeded(force: true)
        Task { await app.publishRead() }
    }

    func thumbnail(_ item: VaultItem) async {
        guard thumbnails[item.id] == nil, !loadingThumbs.contains(item.id), let key, let lease,
              let name = item.thumbnail else { return }
        loadingThumbs.insert(item.id)
        defer { loadingThumbs.remove(item.id) }
        let url = Self.thumbs.appendingPathComponent(name)
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard lease.isValid, let sealed = try? Data(contentsOf: url),
                  let data = try? VaultCrypto.open(sealed, key: VaultCrypto.subkey(key, salt: [], info: "pm-vault-thumb"))
            else { return nil }
            return UIImage(data: data)
        }.value
        guard lease.isValid, let image else { return }
        thumbnails[item.id] = image
    }

    /// Foto für die Ansicht (verkleinert auf `maxPixel`, nie verzerrt). Nach einer Sperre: nichts.
    func photo(_ item: VaultItem, maxPixel: CGFloat) async -> UIImage? {
        guard let key, let lease, let resource = item.current else { return nil }
        let url = Self.objects.appendingPathComponent(resource.file)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard lease.isValid, let data = try? VaultFileReader.data(at: url, master: key) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }.value
        return lease.isValid ? image : nil
    }

    /// Video in eine geschützte Temp-Datei entschlüsseln (wird beim Sperren gelöscht; nach einer Sperre: nichts).
    func videoFile(_ item: VaultItem) async -> URL? {
        guard let key, let lease, let resource = item.current else { return nil }
        return await Task.detached(priority: .userInitiated) {
            try? Self.decryptToTemp(resource, key: key, lease: lease)
        }.value
    }

    /// Dateien zum Teilen (aktuelle Fassung unter ihrem Originalnamen, sofern der ein sicherer Dateiname ist).
    func shareFiles(_ ids: Set<String>) async -> [URL] {
        guard let key, let lease else { return [] }
        let resources = index.items.filter { ids.contains($0.id) }.compactMap(\.current)
        let urls = await Task.detached(priority: .userInitiated) {
            resources.compactMap { try? Self.decryptToTemp($0, key: key, lease: lease) }
        }.value
        guard lease.isValid else {
            removeTempFiles(urls)
            return []
        }
        return urls
    }

    func removeTempFiles(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
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
    /// iOS, ob sie aus der Fotos-App gelöscht werden dürfen. Free: höchstens 50 Medien im Tresor.
    func importAssets(_ ids: [String], app: AppModel) async -> VaultImportReport {
        var report = VaultImportReport()
        guard let key, let lease, phase == .unlocked else { return report }
        let allowed = VaultPolicy.allowed(requested: ids.count, existing: index.items.count,
                                          unlimited: app.capabilities.hasProToolsAccess)
        report.skippedByLimit = ids.count - allowed
        let list = Array(ids.prefix(allowed))
        guard !list.isEmpty else { return report }
        progress = VaultProgress(done: 0, total: list.count)
        var copied: [String] = []
        for (i, id) in list.enumerated() {
            guard lease.isValid, !Task.isCancelled else { break }
            do {
                let item = try await VaultImporter.importAsset(id: id, key: key, objects: Self.objects, thumbs: Self.thumbs,
                                                               nowMs: nowMs)
                guard lease.isValid else { Self.removeFiles(of: item); break }
                do {
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
        _ = try? VaultConcealment.shared.conceal(copied)
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
    /// zurückgeholt) und soll das Medium den Tresor verlassen, wird es nur wieder sichtbar gemacht (keine doppelte Kopie). Sonst entsteht ein neues Medium mit
    /// Datum, Ort und Favorit wie vorher. `removeFromVault`: danach aus dem Tresor löschen – nur, was vollständig
    /// zurückgelegt wurde; bei einem vereinfachten Ergebnis bleibt das vollständige Original im Tresor.
    func restore(_ ids: Set<String>, removeFromVault: Bool, app: AppModel) async -> VaultRestoreReport {
        var report = VaultRestoreReport()
        guard let key, let lease, phase == .unlocked else { return report }
        let items = index.items.filter { ids.contains($0.id) }
        progress = VaultProgress(done: 0, total: items.count)
        var leaveVault: Set<String> = []
        for (i, item) in items.enumerated() {
            guard lease.isValid else { break }
            if removeFromVault, let original = item.originalID ?? item.sourceID,
               PhotoLibraryService.phAssetIncludingConcealed(original) != nil {
                leaveVault.insert(item.id)
                report.restored += 1
            } else {
                switch await VaultRestorer.restore(item, key: key, objects: Self.objects, temp: Self.temp, lease: lease) {
                case .complete:
                    report.restored += 1
                    leaveVault.insert(item.id)
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
        if removeFromVault && lease.isValid && !leaveVault.isEmpty { delete(leaveVault, app: app) }
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

    /// Änderung am Inhaltsverzeichnis: erst verschlüsselt gespeichert, dann im Speicher übernommen.
    private func commit(_ change: (inout VaultIndex) throws -> Void) throws {
        guard let key, lease?.isValid == true else { throw VaultCryptoError.authentication }
        try VaultTransaction.update(&index, mutate: change, persist: { try Self.persist($0, key: key) })
    }

    private static func persist(_ index: VaultIndex, key: VaultKey) throws {
        let sealed = try VaultCrypto.seal(JSONEncoder().encode(index), key: indexKey(key))
        try sealed.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    private static func indexKey(_ key: VaultKey) -> SymmetricKey {
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

    /// Entschlüsselt in einen eigenen Temp-Ordner. Der Originalname wird nur verwendet, wenn er ein sicherer
    /// Dateiname ist. Wurde inzwischen gesperrt, bleibt kein Klartext liegen.
    nonisolated static func decryptToTemp(_ resource: VaultResource, key: VaultKey,
                                          lease: VaultSessionFence.Lease) throws -> URL {
        try lease.requireValid()
        guard VaultPathRules.isComponent(resource.file) else { throw VaultCryptoError.format }
        let folder = temp.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
            try VaultFileReader.decrypt(objects.appendingPathComponent(resource.file), to: url, master: key)
            try lease.requireValid()
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

    static func restore(_ item: VaultItem, key: VaultKey, objects: URL, temp: URL,
                        lease: VaultSessionFence.Lease) async -> Outcome {
        let folder = temp.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try lease.requireValid()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let full = VaultRestorePlan.full(item.resources)
            let simple = VaultRestorePlan.simple(item.resources)
            let needed = Set((full + simple).map(\.file))
            var urls: [String: URL] = [:]
            for r in item.resources where needed.contains(r.file) {
                guard VaultPathRules.isComponent(r.file) else { return .failed }
                let ext = (r.originalFilename as NSString).pathExtension
                let url = folder.appendingPathComponent(VaultPathRules.temporaryName(
                    fileExtension: ext.isEmpty ? (UTType(r.uti)?.preferredFilenameExtension ?? "dat") : ext))
                try VaultFileReader.decrypt(objects.appendingPathComponent(r.file), to: url, master: key)
                try lease.requireValid()
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
