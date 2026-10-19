import CryptoKit
import Foundation
import PhotoMaidCore

/// PMVB2: bounded key envelope, typed opaque records, HMAC-SHA256 over the complete archive.
/// Payloads (including the index) remain encrypted. No plaintext vault key, title, note or filename
/// is ever put in the archive header. Restore is an additive, re-keyed import, never a replacement.
enum VaultBackup {
    private static let magic = Data("PMVB2".utf8)
    private static let maxIndexBytes = 64 << 20
    private static let maxRecords = 1_000_000

    struct Imported: Sendable {
        var snapshot: VaultSnapshot
        let newObjects: [URL]
        let newThumbnails: [URL]
        func removeUncommittedFiles() {
            for url in newObjects + newThumbnails { try? FileManager.default.removeItem(at: url) }
        }
    }

    static func export(_ snapshot: VaultSnapshot, password: String, lease: VaultSessionLease,
                       objects: URL, thumbnails: URL) throws -> URL {
        guard password.count >= 12 else { throw VaultWorkspaceError.invalidData }
        try snapshot.validate(); try lease.check()
        var saved = snapshot
        saved.workspace.pendingObjectPurges = []; saved.workspace.pendingThumbnailPurges = []
        let plainIndex = try JSONEncoder().encode(saved)
        guard plainIndex.count <= maxIndexBytes else { throw VaultWorkspaceError.invalidData }
        let encryptedIndex = try VaultCrypto.seal(plainIndex, key: VaultCrypto.subkey(lease.key, salt: [], info: "pm-vault-index"))
        let wrapped = try VaultCrypto.wrap(lease.key, secret: password, rounds: VaultCrypto.codeRounds)
        let envelope = try JSONEncoder().encode(wrapped)
        let media = saved.allMedia
        let objectNames = Set(media.flatMap(\.resources).map(\.file) + saved.workspace.files.map(\.objectName)).sorted()
        let thumbnailNames = Set(media.compactMap(\.thumbnail)).sorted()
        let count = 1 + objectNames.count + thumbnailNames.count
        guard count <= maxRecords else { throw VaultWorkspaceError.invalidData }
        let folder = try lease.makeDirectory()
        let target = folder.appendingPathComponent("PhotoMaid-\(Int(Date().timeIntervalSince1970)).pmvault")
        guard FileManager.default.createFile(atPath: target.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]) else { throw VaultCryptoError.io }
        let out = try FileHandle(forWritingTo: target)
        var mac = HMAC<SHA256>(key: VaultCrypto.subkey(lease.key, salt: [], info: "pm-vault-backup-v2"))
        func write(_ data: Data) throws { try lease.check(); mac.update(data: data); try out.write(contentsOf: data) }
        func header(kind: UInt8, name: String, count: UInt64) throws {
            let bytes = Data(name.utf8)
            try write(Data([kind])); try write(integer(UInt64(bytes.count), bytes: 2)); try write(bytes)
            try write(integer(count, bytes: 8))
        }
        func copy(kind: UInt8, name: String, from url: URL) throws {
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            let length = try input.seekToEnd(); try input.seek(toOffset: 0)
            try header(kind: kind, name: name, count: length)
            var copied: UInt64 = 0
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { try write(chunk); copied += UInt64(chunk.count) }
            guard copied == length else { throw VaultCryptoError.io }
        }
        do {
            try write(magic); try write(integer(UInt64(envelope.count), bytes: 4)); try write(envelope)
            try write(integer(UInt64(count), bytes: 4))
            try header(kind: 0, name: "index.bin", count: UInt64(encryptedIndex.count)); try write(encryptedIndex)
            for name in objectNames { try copy(kind: 1, name: name, from: objects.appendingPathComponent(name)) }
            for name in thumbnailNames { try copy(kind: 2, name: name, from: thumbnails.appendingPathComponent(name)) }
            try lease.check(); try out.write(contentsOf: Data(mac.finalize())); try out.synchronize(); try out.close()
            try lease.check(); return target
        } catch { try? out.close(); try? FileManager.default.removeItem(at: folder); throw error }
    }

    static func importArchive(_ url: URL, password: String, lease: VaultSessionLease,
                              objects: URL, thumbnails: URL, remainingMedia: Int?) throws -> Imported {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Imported, any Error> = .failure(VaultCryptoError.io)
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result { try readAndRekey(coordinated, password: password, lease: lease,
                objects: objects, thumbnails: thumbnails, remainingMedia: remainingMedia) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func readAndRekey(_ url: URL, password: String, lease: VaultSessionLease,
                                    objects: URL, thumbnails: URL, remainingMedia: Int?) throws -> Imported {
        try lease.check()
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let length = try input.seekToEnd(); try input.seek(toOffset: 0)
        guard length >= 5 + 4 + 4 + 32 else { throw VaultCryptoError.format }
        var consumed: UInt64 = 0
        var prefix = Data()
        var mac: HMAC<SHA256>?
        func read(_ count: Int, authenticate: Bool = true) throws -> Data {
            try lease.check()
            guard count >= 0, UInt64(count) <= length - consumed,
                  let data = try input.read(upToCount: count), data.count == count else { throw VaultCryptoError.format }
            consumed += UInt64(count)
            if authenticate {
                if mac != nil { mac?.update(data: data) } else { prefix.append(data) }
            }
            return data
        }
        func number(_ bytes: Int) throws -> UInt64 { try read(bytes).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } }
        guard try read(5) == magic else { throw VaultCryptoError.format }
        let envelopeLength = try number(4)
        guard envelopeLength > 0, envelopeLength <= 8192 else { throw VaultCryptoError.format }
        let wrapped = try JSONDecoder().decode(VaultWrappedKey.self, from: read(Int(envelopeLength)))
        guard wrapped.rounds == VaultCrypto.codeRounds, wrapped.salt.count == 16, wrapped.box.count == 60 else { throw VaultCryptoError.format }
        let sourceKey = try VaultCrypto.unwrap(wrapped, secret: password)
        mac = HMAC<SHA256>(key: VaultCrypto.subkey(sourceKey, salt: [], info: "pm-vault-backup-v2")); mac?.update(data: prefix); prefix = Data()
        let count = try number(4)
        guard count > 0, count <= UInt64(maxRecords) else { throw VaultCryptoError.format }
        let stage = try lease.makeDirectory()
        defer { try? FileManager.default.removeItem(at: stage) }
        let stagedObjects = stage.appendingPathComponent("o", isDirectory: true)
        let stagedThumbs = stage.appendingPathComponent("t", isDirectory: true)
        try lease.withPermit {
            for folder in [stagedObjects, stagedThumbs] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete])
            }
        }
        var records: Set<String> = []
        var stagedIndex: URL?
        for _ in 0..<count {
            let kind = try number(1); let nameLength = try number(2)
            guard nameLength > 0, nameLength <= 64, let name = String(data: try read(Int(nameLength)), encoding: .utf8) else { throw VaultCryptoError.format }
            let size = try number(8)
            guard consumed <= length - 32, size <= length - 32 - consumed else { throw VaultCryptoError.format }
            let destination: URL
            switch kind {
            case 0:
                guard name == "index.bin", stagedIndex == nil, size <= UInt64(maxIndexBytes + 28) else { throw VaultCryptoError.format }
                destination = stage.appendingPathComponent("index.bin"); stagedIndex = destination
            case 1, 2:
                guard VaultWorkspace.isOpaqueName(name), name == UUID(uuidString: name)?.uuidString else { throw VaultCryptoError.format }
                destination = (kind == 1 ? stagedObjects : stagedThumbs).appendingPathComponent(name)
                if kind == 2 && size > UInt64(20 << 20) { throw VaultCryptoError.format }
            default: throw VaultCryptoError.format
            }
            guard records.insert("\(kind):\(name)").inserted else { throw VaultCryptoError.format }
            let out: FileHandle = try lease.withPermit {
                guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                    attributes: [.protectionKey: FileProtectionType.complete]) else { throw VaultCryptoError.io }
                return try FileHandle(forWritingTo: destination)
            }
            do {
                var left = size
                while left > 0 { let amount = Int(min(left, 1 << 20)); try out.write(contentsOf: read(amount)); left -= UInt64(amount) }
                try out.close()
            } catch { try? out.close(); throw error }
        }
        guard consumed == length - 32, let calculated = mac?.finalize() else { throw VaultCryptoError.format }
        let supplied = try read(32, authenticate: false)
        let different = zip(Array(calculated), Array(supplied)).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard different == 0, let stagedIndex else { throw VaultCryptoError.authentication }
        let sealed = try Data(contentsOf: stagedIndex)
        let plain = try VaultCrypto.open(sealed, key: VaultCrypto.subkey(sourceKey, salt: [], info: "pm-vault-index"))
        let snapshot = try VaultSnapshot.decode(plain); try snapshot.validate()
        if let remainingMedia, snapshot.allMedia.count > remainingMedia { throw VaultWorkspaceError.invalidData }
        let expectedObjects = Set(snapshot.allMedia.flatMap(\.resources).map(\.file) + snapshot.workspace.files.map(\.objectName))
        let expectedThumbs = Set(snapshot.allMedia.compactMap(\.thumbnail))
        let expectedRecords = Set(["0:index.bin"] + expectedObjects.map { "1:" + $0 } + expectedThumbs.map { "2:" + $0 })
        guard records == expectedRecords else { throw VaultCryptoError.format }
        var objectMap: [String: String] = [:]; var thumbnailMap: [String: String] = [:]
        var writtenObjects: [URL] = []; var writtenThumbnails: [URL] = []
        do {
            for name in expectedObjects {
                try lease.check()
                let next = UUID().uuidString; let target = objects.appendingPathComponent(next)
                writtenObjects.append(target)
                let actual = try rekey(stagedObjects.appendingPathComponent(name), sourceKey: sourceKey,
                    target: target, lease: lease)
                let mediaRefs = snapshot.allMedia.flatMap(\.resources).filter { $0.file == name }
                let fileRefs = snapshot.workspace.files.filter { $0.objectName == name }
                guard mediaRefs.allSatisfy({ $0.size == actual.size && $0.sha256 == actual.sha256 }),
                      fileRefs.allSatisfy({ $0.byteCount == actual.size && $0.sha256 == actual.sha256 }) else { throw VaultCryptoError.authentication }
                objectMap[name] = next
            }
            for name in expectedThumbs {
                try lease.check()
                let old = try Data(contentsOf: stagedThumbs.appendingPathComponent(name))
                let data = try VaultCrypto.open(old, key: VaultCrypto.subkey(sourceKey, salt: [], info: "pm-vault-thumb"))
                let fresh = try VaultCrypto.seal(data, key: VaultCrypto.subkey(lease.key, salt: [], info: "pm-vault-thumb"))
                let next = UUID().uuidString; let target = thumbnails.appendingPathComponent(next)
                writtenThumbnails.append(target)
                try lease.withPermit { try fresh.write(to: target, options: [.atomic, .completeFileProtection]) }
                thumbnailMap[name] = next
            }
            let remapped = try remap(snapshot, objectMap: objectMap, thumbnailMap: thumbnailMap)
            try remapped.validate(); try lease.check()
            return Imported(snapshot: remapped, newObjects: writtenObjects, newThumbnails: writtenThumbnails)
        } catch {
            for file in writtenObjects + writtenThumbnails { try? FileManager.default.removeItem(at: file) }
            throw error
        }
    }

    /// Re-key authenticated chunks directly: no plaintext document is staged during backup restore.
    private static func rekey(_ source: URL, sourceKey: VaultKey, target: URL, lease: VaultSessionLease) throws -> (size: Int64, sha256: String) {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let length = try input.seekToEnd(); try input.seek(toOffset: 0)
        guard length <= UInt64(Int64.max), let head = try input.read(upToCount: VaultChunkLayout.headerLength),
              let header = VaultChunkLayout.parseHeader(Array(head)),
              let chunks = VaultChunkLayout.chunks(fileLength: Int64(length), chunkSize: header.chunkSize) else { throw VaultCryptoError.format }
        let key = VaultCrypto.subkey(sourceKey, salt: header.salt, info: "pm-vault-file")
        let writer = try lease.withPermit { try VaultFileWriter(url: target, master: lease.key) }
        do {
            for chunk in chunks {
                try lease.check(); try input.seek(toOffset: UInt64(chunk.offset))
                guard let sealed = try input.read(upToCount: chunk.length), sealed.count == chunk.length else { throw VaultCryptoError.format }
                let aad = Data(VaultChunkLayout.aad(index: chunk.index, isLast: chunk.isLast))
                let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad)
                writer.receive(plain)
            }
            let written = try writer.finish(); let verified = try VaultFileReader.digest(target, master: lease.key)
            guard written.size == verified.size, written.sha256 == verified.sha256 else { throw VaultCryptoError.authentication }
            return written
        } catch { writer.abort(); throw error }
    }

    private static func remap(_ original: VaultSnapshot, objectMap: [String: String], thumbnailMap: [String: String]) throws -> VaultSnapshot {
        let mediaFolderMap = Dictionary(uniqueKeysWithValues: original.media.folders.map { ($0.id, UUID().uuidString) })
        let folderMap = Dictionary(uniqueKeysWithValues: original.workspace.folders.map { ($0.id, UUID().uuidString) })
        let fileMap = Dictionary(uniqueKeysWithValues: original.workspace.files.map { ($0.id, UUID().uuidString) })
        func media(_ old: VaultItem) throws -> VaultItem {
            let resources = try old.resources.map { value -> VaultResource in
                guard let file = objectMap[value.file] else { throw VaultCryptoError.format }
                return VaultResource(role: value.role, file: file, uti: value.uti, originalFilename: value.originalFilename, size: value.size, sha256: value.sha256)
            }
            return VaultItem(id: UUID().uuidString, kind: old.kind, folderID: old.folderID.flatMap { mediaFolderMap[$0] }, resources: resources,
                creationMs: old.creationMs, addedMs: old.addedMs, latitude: old.latitude, longitude: old.longitude,
                isFavorite: old.isFavorite, duration: old.duration, pixelWidth: old.pixelWidth, pixelHeight: old.pixelHeight,
                thumbnail: old.thumbnail.flatMap { thumbnailMap[$0] }, sourceID: old.sourceID,
                originalID: old.originalID)
        }
        var result = VaultSnapshot()
        result.media.folders = original.media.folders.map { VaultFolder(id: mediaFolderMap[$0.id]!, name: $0.name, createdMs: $0.createdMs) }
        result.media.items = try original.media.items.map(media)
        result.workspace.folders = original.workspace.folders.map { VaultWorkspaceFolder(id: folderMap[$0.id]!, name: $0.name, scope: $0.scope, createdMs: $0.createdMs) }
        for old in original.workspace.files {
            guard let object = objectMap[old.objectName], let id = fileMap[old.id] else { throw VaultCryptoError.format }
            var file = VaultDocument(id: id, name: old.name, objectName: object, typeIdentifier: old.typeIdentifier,
                byteCount: old.byteCount, sha256: old.sha256, nowMs: old.createdMs, origin: .restoredFromBackup)
            file.folderID = old.folderID.flatMap { folderMap[$0] }; file.modifiedMs = old.modifiedMs; file.trashedMs = old.trashedMs
            // Bookmarks are device-specific capabilities; never reuse a backup's external-file deletion authority.
            file.sourceBookmark = nil; result.workspace.files.append(file)
        }
        for old in original.workspace.notes {
            var note = VaultNote(id: UUID().uuidString, title: old.title, nowMs: old.createdMs)
            note.blocks = old.blocks; note.attachmentIDs = try old.attachmentIDs.map { guard let id = fileMap[$0] else { throw VaultCryptoError.format }; return id }
            note.folderID = old.folderID.flatMap { folderMap[$0] }; note.pinned = old.pinned; note.modifiedMs = old.modifiedMs
            note.revision = 1; note.trashedMs = old.trashedMs; result.workspace.notes.append(note)
        }
        for archived in original.workspace.mediaTrash {
            let item = try media(JSONDecoder().decode(VaultItem.self, from: archived.encodedItem))
            result.workspace.mediaTrash.append(VaultTrashedMedia(id: item.id, deletedMs: archived.deletedMs, encodedItem: try JSONEncoder().encode(item)))
        }
        return result
    }

    private static func integer(_ value: UInt64, bytes: Int) -> Data {
        Data((0..<bytes).map { UInt8((value >> UInt64((bytes - 1 - $0) * 8)) & 0xff) })
    }
}

@MainActor
extension VaultStore {
    func encryptedBackup(password: String) async throws -> URL {
        let activeLease = try requireLease(); let value = snapshot
        let url = try await Task.detached(priority: .userInitiated) {
            try VaultBackup.export(value, password: password, lease: activeLease, objects: Self.objects, thumbnails: Self.thumbs)
        }.value
        guard accepts(activeLease) else { removeTempFiles([url]); throw CancellationError() }
        return url
    }

    /// Fügt ein geprüftes Backup zusätzlich hinzu (nie ersetzen). Medien daraus sind sofort in PhotoMaid verborgen.
    func restoreEncryptedBackup(_ url: URL, password: String, unlimited: Bool, app: AppModel) async throws {
        let activeLease = try requireLease()
        let remaining = VaultPolicy.remaining(existing: mediaSlotsUsed, unlimited: unlimited)
        let imported = try await Task.detached(priority: .userInitiated) {
            try VaultBackup.importArchive(url, password: password, lease: activeLease, objects: Self.objects,
                thumbnails: Self.thumbs, remainingMedia: remaining)
        }.value
        do {
            guard accepts(activeLease) else { throw CancellationError() }
            let additional = imported.snapshot.allMedia.count
            guard VaultPolicy.allowed(requested: additional, existing: mediaSlotsUsed, unlimited: unlimited) == additional
            else { throw VaultWorkspaceError.invalidData }
            let roots = imported.snapshot.originalIDs
            let records = app.kv?.get(StoreKeys.edits) ?? []
            let identities = roots.union(VaultDerivation.copies(of: roots, records: records))
                .union(imported.snapshot.fileConcealmentKeys)
            try VaultConcealment.shared.conceal(identities)
            try commitSnapshot { candidate in
                for folder in imported.snapshot.media.folders {
                    var value = folder; var suffix = 2
                    while candidate.media.folders.contains(where: { $0.name.caseInsensitiveCompare(value.name) == .orderedSame }) {
                        value.name = String(folder.name.prefix(48)) + " (\(suffix))"; suffix += 1
                    }
                    candidate.media.folders.append(value)
                }
                for folder in imported.snapshot.workspace.folders {
                    var value = folder; var suffix = 2
                    while candidate.workspace.folders.contains(where: {
                        $0.scope == value.scope && $0.name.caseInsensitiveCompare(value.name) == .orderedSame
                    }) {
                        value.name = String(folder.name.prefix(240)) + " (\(suffix))"; suffix += 1
                    }
                    candidate.workspace.folders.append(value)
                }
                candidate.media.items += imported.snapshot.media.items
                candidate.workspace.notes += imported.snapshot.workspace.notes
                candidate.workspace.files += imported.snapshot.workspace.files
                candidate.workspace.mediaTrash += imported.snapshot.workspace.mediaTrash
            }
        } catch {
            imported.removeUncommittedFiles()
            throw error
        }
        await syncConcealment(app: app)
    }
}
