import CryptoKit
import Photos
import PhotoMaidCore

enum ArchiveService {
    static func copy(app: AppModel, ids: [String], target: URL, options: ArchiveOptions) async -> ArchiveJournal {
        let values = try? target.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsInternalKey, .volumeIsRemovableKey,
                                                          .volumeIsEjectableKey, .volumeIsLocalKey])
        let facts = VolumeFacts(isUbiquitous: values?.isUbiquitousItem, volumeIsInternal: values?.volumeIsInternal,
                                volumeIsRemovable: values?.volumeIsRemovable, volumeIsEjectable: values?.volumeIsEjectable,
                                volumeIsLocal: values?.volumeIsLocal)
        var journal = ArchiveJournal(id: UUID().uuidString, targetLabel: target.lastPathComponent,
                                     targetKind: ArchiveTargets.classify(facts),
                                     startedAt: Int64(Date().timeIntervalSince1970 * 1000), options: options)
        for (index, id) in ids.enumerated() {
            guard let asset = app.asset(id), let ph = PhotoLibraryService.phAsset(id),
                  let resource = PHAssetResource.assetResources(for: ph).first else { continue }
            let measured = await app.sizer.size(of: asset)
            let size: Int64?
            if case .known(let bytes) = measured { size = bytes } else { size = nil }
            let source = ArchiveSource(id: id, name: resource.originalFilename, uti: resource.uniformTypeIdentifier,
                                       size: size, takenMillis: asset.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) })
            let folderParts = ArchivePlan.folder(for: source, options: options, undatedLabel: L("archive_undated"),
                                                 timeZone: .autoupdatingCurrent)
            let fallback = ArchivePlan.fallbackName(index: index, uti: source.uti)
            let name = ArchivePlan.safeName(source.name, fallback: fallback)
            var entry = JournalEntry(sourceId: id, name: name, folder: folderParts, size: size)
            entry.state = .copying
            journal.entries.append(entry)
            do {
                let folder = folderParts.reduce(target) { $0.appendingPathComponent($1, isDirectory: true) }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                let unique = ArchivePlan.uniqueName(taken: existing, wanted: name)
                let output = folder.appendingPathComponent(unique)
                let request = PHAssetResourceRequestOptions()
                request.isNetworkAccessAllowed = true
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: output, options: request)
                let sourceHash = try await sourceDigest(provider: app.bytes, reference: asset.reference)
                let copied = try Data(contentsOf: output, options: .mappedIfSafe)
                let targetHash = SHA256.hash(data: copied).hexString
                if sourceHash == targetHash {
                    journal.entries[index].state = .verified
                    journal.entries[index].bytes = Int64(copied.count)
                    journal.entries[index].sha256 = targetHash
                    journal.entries[index].targetUri = (folderParts + [unique]).joined(separator: "/")
                } else {
                    try? FileManager.default.removeItem(at: output)
                    journal.entries[index].state = .failed
                    journal.entries[index].reason = .mismatch
                }
            } catch {
                journal.entries[index].state = .failed
                journal.entries[index].reason = .writeFailed
            }
        }
        journal.finishedAt = Int64(Date().timeIntervalSince1970 * 1000)
        return journal
    }

    private static func sourceDigest(provider: PhotoResourceByteProvider, reference: ItemReference) async throws -> String {
        try await Task.detached {
            guard let stream = try provider.openStream(for: reference) else { throw CocoaError(.fileReadUnknown) }
            defer { stream.close() }
            var hash = SHA256()
            while true {
                let data = try stream.read(maxLength: 1_048_576)
                if data.isEmpty { break }
                hash.update(data: data)
            }
            return hash.finalize().hexString
        }.value
    }
}
