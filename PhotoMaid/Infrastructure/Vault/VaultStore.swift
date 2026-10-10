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

/// Privater Tresor (E16). Eine Wahrheit: das verschlüsselte Inhaltsverzeichnis im App-Container; die Medien gibt es
/// danach weder in der Fotos-App noch irgendwo sonst in PhotoMaid (kein Prüfstand, keine Statistik, kein Protokoll).
/// Schlüssel und Inhaltsverzeichnis liegen nur im Speicher, solange der Tresor offen ist; Sperren beim Verlassen der App.
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
        cleanTemp()
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

    /// Schließen = sperren: Schlüssel, Inhaltsverzeichnis, Vorschaubilder und entschlüsselte Temp-Dateien weg.
    func lock() {
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
        let key = await Task.detached(priority: .userInitiated) { try? VaultCrypto.unwrap(wrapped, secret: code) }.value
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
        guard settings?.biometrics == true,
              let key = await VaultKeychain.readBiometric(reason: L("vault_biometric_reason")) else { return false }
        return open(with: key)
    }

    /// Notfallschlüssel: öffnet und verlangt danach einen neuen Code (auch bei Fehlversuchssperre erlaubt).
    func unlock(recoveryKey: String) async -> UnlockResult {
        guard var s = settings, let wrapped = s.recovery,
              let normalized = VaultRecoveryKey.normalize(recoveryKey) else { return .wrong }
        let key = await Task.detached(priority: .userInitiated) { try? VaultCrypto.unwrap(wrapped, secret: normalized) }.value
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
            index = try JSONDecoder().decode(VaultIndex.self, from: plain)
            self.key = key
            phase = .unlocked
            return true
        } catch {
            return false
        }
    }

    // MARK: Einrichten und Einstellungen

    /// Neuer Notfallschlüssel zum Aufschreiben (16 Zufallsbytes).
    nonisolated static func makeRecoveryKey() -> String? {
        guard let bytes = try? VaultCrypto.randomBytes(VaultRecoveryKey.byteCount) else { return nil }
        return VaultRecoveryKey.format(bytes)
    }

    /// Richtet den Tresor neu ein. Reste eines früheren Tresors (z. B. Schlüsselbund nach Neuinstallation) werden entfernt.
    func setUp(code: String, kind: VaultCodeKind, recoveryKey: String?, biometrics: Bool, hideEntry: Bool) async -> Bool {
        let fm = FileManager.default
        do {
            try? fm.removeItem(at: Self.root)
            VaultKeychain.deleteAll()
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
            try VaultKeychain.set(JSONEncoder().encode(wrapped), account: VaultKeychain.codeAccount)
            let bio = biometrics && (try? VaultKeychain.setBiometric(key.data)) != nil
            for dir in [Self.root, Self.objects, Self.thumbs] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
            let s = VaultSettings(codeKind: kind, hideEntry: hideEntry, biometrics: bio, recovery: recovery, createdMs: nowMs)
            try write(s)
            self.key = key
            index = VaultIndex()
            try saveIndex()
            settings = s
            phase = .unlocked
            needsNewCode = false
            return true
        } catch {
            try? fm.removeItem(at: Self.root)
            VaultKeychain.deleteAll()
            key = nil
            settings = nil
            phase = .notSetUp
            return false
        }
    }

    func changeCode(_ code: String, kind: VaultCodeKind) async -> Bool {
        guard let key, var s = settings else { return false }
        guard let wrapped = try? await Task.detached(priority: .userInitiated, operation: {
            try VaultCrypto.wrap(key, secret: code, rounds: VaultCrypto.codeRounds)
        }).value, let data = try? JSONEncoder().encode(wrapped), (try? VaultKeychain.set(data, account: VaultKeychain.codeAccount)) != nil
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
        }).value else { return nil }
        s.recovery = wrapped
        store(s)
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

    /// Ganzen Tresor unwiderruflich löschen (nur offen, mit Bestätigung in der Ansicht).
    func deleteVault() {
        guard phase == .unlocked else { return }
        try? FileManager.default.removeItem(at: Self.root)
        VaultKeychain.deleteAll()
        lock()
        settings = nil
        phase = .notSetUp
    }

    // MARK: Ordner

    @discardableResult
    func createFolder(_ name: String) -> VaultFolder? {
        let folder = index.createFolder(name: name, id: UUID().uuidString, nowMs: nowMs)
        if folder != nil { try? saveIndex() }
        return folder
    }

    @discardableResult
    func renameFolder(_ id: String, to name: String) -> Bool {
        let ok = index.renameFolder(id, to: name)
        if ok { try? saveIndex() }
        return ok
    }

    func deleteFolder(_ id: String) {
        index.deleteFolder(id)
        try? saveIndex()
    }

    func move(_ ids: Set<String>, to folderID: String?) {
        index.move(ids: ids, to: folderID)
        try? saveIndex()
    }

    // MARK: Medien

    /// Endgültig aus dem Tresor löschen (es gibt dafür kein „Zuletzt gelöscht“).
    func delete(_ ids: Set<String>) {
        let removed = index.remove(ids: ids)
        try? saveIndex()
        for item in removed { Self.removeFiles(of: item) }
        for id in ids { thumbnails[id] = nil }
    }

    func thumbnail(_ item: VaultItem) async {
        guard thumbnails[item.id] == nil, !loadingThumbs.contains(item.id), let key, let name = item.thumbnail else { return }
        loadingThumbs.insert(item.id)
        defer { loadingThumbs.remove(item.id) }
        let url = Self.thumbs.appendingPathComponent(name)
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let sealed = try? Data(contentsOf: url),
                  let data = try? VaultCrypto.open(sealed, key: VaultCrypto.subkey(key, salt: [], info: "pm-vault-thumb"))
            else { return nil }
            return UIImage(data: data)
        }.value
        guard phase == .unlocked, let image else { return }
        thumbnails[item.id] = image
    }

    /// Foto für die Ansicht (verkleinert auf `maxPixel`, nie verzerrt).
    func photo(_ item: VaultItem, maxPixel: CGFloat) async -> UIImage? {
        guard let key, let resource = item.current else { return nil }
        let url = Self.objects.appendingPathComponent(resource.file)
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? VaultFileReader.data(at: url, master: key) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }.value
    }

    /// Video in eine geschützte Temp-Datei entschlüsseln (wird beim Sperren gelöscht).
    func videoFile(_ item: VaultItem) async -> URL? {
        guard let key, let resource = item.current else { return nil }
        return await Task.detached(priority: .userInitiated) {
            try? Self.decryptToTemp(resource, key: key)
        }.value
    }

    /// Dateien zum Teilen (aktuelle Fassung unter ihrem Originalnamen).
    func shareFiles(_ ids: Set<String>) async -> [URL] {
        guard let key else { return [] }
        let resources = index.items.filter { ids.contains($0.id) }.compactMap(\.current)
        return await Task.detached(priority: .userInitiated) {
            resources.compactMap { try? Self.decryptToTemp($0, key: key) }
        }.value
    }

    func removeTempFiles(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    // MARK: Ablegen (Fotos-App → Tresor)

    /// Kopiert die Medien vollständig und geprüft in den Tresor; erst danach fragt iOS, ob sie aus der Fotos-App
    /// gelöscht werden dürfen. Free: höchstens 50 Medien im Tresor.
    func importAssets(_ ids: [String], app: AppModel) async -> VaultImportReport {
        var report = VaultImportReport()
        guard let key, phase == .unlocked else { return report }
        let allowed = VaultPolicy.allowed(requested: ids.count, existing: index.items.count,
                                          unlimited: app.capabilities.hasProToolsAccess)
        report.skippedByLimit = ids.count - allowed
        let list = Array(ids.prefix(allowed))
        guard !list.isEmpty else { return report }
        progress = VaultProgress(done: 0, total: list.count)
        var copied: [String] = []
        for (i, id) in list.enumerated() {
            guard phase == .unlocked, !Task.isCancelled else { break }
            do {
                let item = try await VaultImporter.importAsset(id: id, key: key, objects: Self.objects, thumbs: Self.thumbs,
                                                               nowMs: nowMs)
                guard phase == .unlocked else { Self.removeFiles(of: item); break }
                index.add(item)
                try saveIndex()
                copied.append(id)
                report.imported += 1
            } catch {
                report.failed += 1
            }
            progress = VaultProgress(done: i + 1, total: list.count)
        }
        progress = nil
        guard !copied.isEmpty, phase == .unlocked else { return report }
        report.removedFromLibrary = await removeFromLibrary(copied, app: app)
        return report
    }

    /// iOS-Löschabfrage für Medien, die schon sicher im Tresor liegen. Danach verschwinden sie aus PhotoMaid
    /// (Papierkorb- und Später-Einträge werden aufgehoben).
    private func removeFromLibrary(_ sourceIDs: [String], app: AppModel) async -> Int {
        let outcome = await app.library.delete(ids: sourceIDs)
        let removed: Set<String>
        switch outcome {
        case .succeeded: removed = Set(sourceIDs)
        case .partial(let refs): removed = Set(refs.map(\.localIdentifier))
        case .cancelled, .failed: removed = []
        }
        guard !removed.isEmpty else { return 0 }
        if phase == .unlocked {
            index.markRemovedFromLibrary(sourceIDs: removed)
            try? saveIndex()
        }
        for id in removed {
            let ref = ItemReference.photo(id)
            switch app.record(ref).disposition {
            case .markedForCleanup: await app.decide(ref, .unmark)
            case .later: await app.decide(ref, .removeDeferral)
            default: break
            }
        }
        app.reloadLibraryIfNeeded(force: true)
        return removed.count
    }

    /// Medien, die noch zusätzlich in der Fotos-App liegen (iOS-Abfrage abgelehnt), erneut zum Löschen anbieten.
    func retryLibraryRemoval(app: AppModel) async -> Int {
        let pending = index.stillInLibrary
        let existing = pending.filter { PhotoLibraryService.phAsset($0) != nil }
        let gone = Set(pending).subtracting(existing)
        if !gone.isEmpty {
            index.markRemovedFromLibrary(sourceIDs: gone)
            try? saveIndex()
        }
        guard !existing.isEmpty else { return 0 }
        return await removeFromLibrary(existing, app: app)
    }

    /// Noch in der Fotos-App vorhandene Originale (für den Hinweis im Tresor).
    var stillInLibraryCount: Int { index.stillInLibrary.filter { PhotoLibraryService.phAsset($0) != nil }.count }

    // MARK: Zurücklegen (Tresor → Fotos-App)

    /// Legt Medien als neue Medien in der Fotos-App an (Datum, Ort, Favorit wie vorher). `removeFromVault`: danach
    /// aus dem Tresor löschen – nur, was erfolgreich angelegt wurde.
    func restore(_ ids: Set<String>, removeFromVault: Bool, app: AppModel) async -> (restored: Int, failed: Int) {
        guard let key, phase == .unlocked else { return (0, 0) }
        let items = index.items.filter { ids.contains($0.id) }
        progress = VaultProgress(done: 0, total: items.count)
        var done: Set<String> = []
        var failed = 0
        for (i, item) in items.enumerated() {
            guard phase == .unlocked else { break }
            if await VaultRestorer.restore(item, key: key, objects: Self.objects, temp: Self.temp) {
                done.insert(item.id)
            } else {
                failed += 1
            }
            progress = VaultProgress(done: i + 1, total: items.count)
        }
        progress = nil
        if removeFromVault && phase == .unlocked && !done.isEmpty { delete(done) }
        app.reloadLibraryIfNeeded(force: true)
        return (done.count, failed)
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

    private func saveIndex() throws {
        guard let key else { throw VaultCryptoError.authentication }
        let sealed = try VaultCrypto.seal(JSONEncoder().encode(index), key: Self.indexKey(key))
        try sealed.write(to: Self.indexURL, options: [.atomic, .completeFileProtection])
    }

    private static func indexKey(_ key: VaultKey) -> SymmetricKey {
        VaultCrypto.subkey(key, salt: [], info: "pm-vault-index")
    }

    nonisolated static func removeFiles(of item: VaultItem) {
        let fm = FileManager.default
        for r in item.resources { try? fm.removeItem(at: objects.appendingPathComponent(r.file)) }
        if let t = item.thumbnail { try? fm.removeItem(at: thumbs.appendingPathComponent(t)) }
    }

    private func cleanTemp() {
        try? FileManager.default.removeItem(at: Self.temp)
    }

    nonisolated static func decryptToTemp(_ resource: VaultResource, key: VaultKey) throws -> URL {
        let folder = temp.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = resource.originalFilename.isEmpty ? resource.file : resource.originalFilename
        if (name as NSString).pathExtension.isEmpty, let ext = UTType(resource.uti)?.preferredFilenameExtension {
            name += "." + ext
        }
        let url = folder.appendingPathComponent(name)
        try VaultFileReader.decrypt(objects.appendingPathComponent(resource.file), to: url, master: key)
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
        guard let asset = PhotoLibraryService.phAsset(id) else { throw VaultCryptoError.io }
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
    static func restore(_ item: VaultItem, key: VaultKey, objects: URL, temp: URL) async -> Bool {
        let folder = temp.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let full = VaultRestorePlan.full(item.resources)
            let simple = VaultRestorePlan.simple(item.resources)
            let needed = Set((full + simple).map(\.file))
            var urls: [String: URL] = [:]
            for r in item.resources where needed.contains(r.file) {
                var ext = (r.originalFilename as NSString).pathExtension
                if ext.isEmpty { ext = UTType(r.uti)?.preferredFilenameExtension ?? "dat" }
                let url = folder.appendingPathComponent(r.file).appendingPathExtension(ext)
                try VaultFileReader.decrypt(objects.appendingPathComponent(r.file), to: url, master: key)
                urls[r.file] = url
            }
            if full.map(\.role) != simple.map(\.role), supports(full.map(\.role)),
               await create(item, plan: full, urls: urls, simplify: false) {
                return true
            }
            return await create(item, plan: simple, urls: urls, simplify: true)
        } catch {
            return false
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
