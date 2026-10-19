import Foundation
import Observation
import PhotoMaidCore
import UniformTypeIdentifiers

/// Vom Nutzer ausdrücklich freigegebener Ordner (security-scoped Bookmark).
struct ConnectedSource: Codable, Hashable, Identifiable, Sendable {
    let id: ConnectedSourceID
    var displayName: String
    var bookmark: Data
    let addedAt: Date
    /// Zuletzt festgestellte Schreibfähigkeit.
    var isWritable: Bool
    /// Vom Nutzer als Downloads-Quelle bezeichnet (nur dann heißt der Screen „Downloads“).
    var isDownloads: Bool
}

enum SourceProblem: Error, Equatable, Sendable {
    case accessDenied
    case unavailable
    /// iCloud Drive o. ä.: Offline-Verhalten nicht belegt → nicht als lokale Quelle aktivieren.
    case cloudProviderNotSupported
    case notADirectory
}

/// Verwaltung verbundener Quellen. Ordnerzugriff entfernen ist keine Dateilöschung.
@MainActor
@Observable
final class ConnectedSourceStore {
    private(set) var sources: [ConnectedSource] = []
    private(set) var problems: [ConnectedSourceID: SourceProblem] = [:]
    @ObservationIgnored private let kv: KeyValueStore?

    init(kv: KeyValueStore?) {
        self.kv = kv
        sources = kv?.get(StoreKeys.sources) ?? []
    }

    private func save(_ list: [ConnectedSource]) throws {
        try kv?.set(StoreKeys.sources, list)
    }

    var downloadsSource: ConnectedSource? { sources.first { $0.isDownloads } }

    /// URL stammt aus dem Dokumentauswahldialog (security-scoped).
    func add(folderURL url: URL, asDownloads: Bool) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey, .isWritableKey, .localizedNameKey])
        guard values.isDirectory == true else { throw SourceProblem.notADirectory }
        if values.isUbiquitousItem == true { throw SourceProblem.cloudProviderNotSupported }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var list = sources
        if asDownloads { for i in list.indices { list[i].isDownloads = false } }
        list.append(ConnectedSource(id: ConnectedSourceID(), displayName: values.localizedName ?? url.lastPathComponent,
                                    bookmark: bookmark, addedAt: Date(), isWritable: values.isWritable ?? false,
                                    isDownloads: asDownloads))
        try save(list)
        sources = list
    }

    /// Entfernt nur die Verbindung. Keine Datei wird gelöscht.
    func remove(_ id: ConnectedSourceID) throws {
        let list = sources.filter { $0.id != id }
        try save(list)
        sources = list
        problems[id] = nil
    }

    /// Für lange, asynchrone Arbeiten (Scan, Hashing): Zugriff öffnen. Jeder erfolgreiche Aufruf
    /// MUSS mit `endAccess` ausgeglichen werden.
    func beginAccess(_ id: ConnectedSourceID) -> URL? {
        guard let source = sources.first(where: { $0.id == id }) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: source.bookmark, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            problems[id] = .unavailable
            return nil
        }
        // App-eigene Ordner (Container) brauchen keinen security-scoped Zugriff.
        guard url.startAccessingSecurityScopedResource() || Self.isInsideAppContainer(url) else {
            problems[id] = .accessDenied
            return nil
        }
        problems[id] = nil
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
           let idx = sources.firstIndex(where: { $0.id == id }) {
            var list = sources
            list[idx].bookmark = fresh
            try? save(list)
            sources = list
        }
        return url
    }

    func endAccess(_ url: URL) {
        if !Self.isInsideAppContainer(url) { url.stopAccessingSecurityScopedResource() }
    }

    static func isInsideAppContainer(_ url: URL) -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.resolvingSymlinksInPath().path
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(home + "/")
    }

    /// Führt `body` mit ausgeglichenem start/stop-Zugriff aus. Stale Bookmarks werden erneuert.
    func withAccess<T>(_ id: ConnectedSourceID, _ body: (URL) throws -> T) throws -> T {
        guard let idx = sources.firstIndex(where: { $0.id == id }) else { throw SourceProblem.unavailable }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: sources[idx].bookmark, options: [], relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        } catch {
            problems[id] = .unavailable
            throw SourceProblem.unavailable
        }
        let scoped = url.startAccessingSecurityScopedResource()
        guard scoped || Self.isInsideAppContainer(url) else {
            problems[id] = .accessDenied
            throw SourceProblem.accessDenied
        }
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var list = sources
            list[idx].bookmark = fresh
            try? save(list)
            sources = list
        }
        let writable = (try? url.resourceValues(forKeys: [.isWritableKey]).isWritable) ?? false
        if sources[idx].isWritable != writable {
            var list = sources
            list[idx].isWritable = writable
            try? save(list)
            sources = list
        }
        problems[id] = nil
        return try body(url)
    }
}

/// Eine Datei innerhalb einer verbundenen Quelle.
struct FileEntry: Hashable, Identifiable, Sendable {
    var id: ItemReference { reference }
    let reference: ItemReference
    let sourceID: ConnectedSourceID
    /// Relativer Pfad innerhalb der Quelle (nur lokal verwendet, nie extern übertragen).
    let relativePath: String
    let name: String
    let size: KnownSize
    let modified: Date?
    let created: Date?
    let contentType: UTType?
    /// Datei-Ressourcen-ID des Systems für Aliaserkennung (falls verfügbar).
    let aliasKey: String?

    var kind: FileKindFilter { FileKindFilter.classify(contentType) }
}

enum FileKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all, pdf, archive, image, video, document, other
    var id: String { rawValue }

    static func classify(_ t: UTType?) -> FileKindFilter {
        guard let t else { return .other }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .archive) || t.conforms(to: .zip) { return .archive }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
        if t.conforms(to: .text) || t.conforms(to: .presentation) || t.conforms(to: .spreadsheet)
            || t.conforms(to: .content) { return .document }
        return .other
    }
}

/// Inventarisiert eine Quelle koordiniert, ohne Symlinks zu folgen und ohne Pakete zu öffnen.
enum FileScanner {
    static let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                                         .contentModificationDateKey, .creationDateKey, .contentTypeKey,
                                         .fileResourceIdentifierKey, .nameKey]

    static func scan(root: URL, sourceID: ConnectedSourceID, limit: Int = 20_000) throws -> [FileEntry] {
        var result: [FileEntry] = []
        var coordError: NSError?
        var innerError: Error?
        NSFileCoordinator().coordinate(readingItemAt: root, options: [.immediatelyAvailableMetadataOnly], error: &coordError) { dir in
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                         errorHandler: { _, _ in true }) else { return }
            let rootPath = dir.standardizedFileURL.path
            for case let url as URL in e {
                if result.count >= limit { break }
                if Task.isCancelled { innerError = CancellationError(); break }
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isSymbolicLink == true { continue }       // keinen Symlinks folgen
                guard v.isRegularFile == true else { continue }
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(rootPath + "/") else { continue }
                let rel = String(path.dropFirst(rootPath.count + 1))
                let size: KnownSize = v.fileSize.map { .known(Int64($0)) } ?? .unknown
                let alias = v.fileResourceIdentifier.map { String(describing: $0) }
                result.append(FileEntry(
                    reference: ItemReference(provider: .connectedSource(sourceID), localIdentifier: rel),
                    sourceID: sourceID, relativePath: rel, name: v.name ?? url.lastPathComponent,
                    size: size, modified: v.contentModificationDate, created: v.creationDate,
                    contentType: v.contentType, aliasKey: alias))
            }
        }
        if let coordError { throw coordError }
        if let innerError { throw innerError }
        return result
    }

    /// Nur Pfadprüfung (ohne Existenz): kein `..`, nicht absolut, Ziel liegt innerhalb der Quelle.
    static func containedURL(root: URL, relativePath: String) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else { return nil }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard parent == rootPath || parent.hasPrefix(rootPath + "/") else { return nil }
        return url
    }

    /// Löst einen relativen Pfad sicher innerhalb der Quelle auf. Manipulierte Pfade
    /// (`..`, Symlinks, Ziele außerhalb der Quelle) werden abgelehnt.
    static func safeURL(root: URL, relativePath: String) -> URL? {
        guard let url = containedURL(root: root, relativePath: relativePath) else { return nil }
        guard let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
              v.isSymbolicLink != true, v.isRegularFile == true, isPublic(url) else { return nil }
        return url
    }

    /// Shared boundary for public Quick Look, Open In, byte streams and cleanup. Unknown identity
    /// is not proof of visibility once private originals exist. Vault operations use their own scoped IO.
    static func isPublic(_ url: URL) -> Bool {
        let boundary = VaultConcealment.shared
        if boundary.isEmpty { return true }
        guard boundary.analysisReady else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let identity = values.fileResourceIdentifier else { return false }
        return !boundary.isConcealed(VaultSnapshot.fileConcealmentKey(String(describing: identity)))
    }
}

/// Dateioperationen je Quelle. iOS hat keinen universellen Dateipapierkorb:
/// PhotoMaid bietet für Dateien ausschließlich „Endgültig löschen“ mit eigener Bestätigung an.
@MainActor
enum FileOperations {
    private static func split(_ items: [ItemReference]) -> [ConnectedSourceID: [ItemReference]] {
        var out: [ConnectedSourceID: [ItemReference]] = [:]
        for i in items { if case .connectedSource(let s) = i.provider { out[s, default: []].append(i) } }
        return out
    }

    /// Löscht einzelne reguläre Dateien endgültig. Kein rekursives Ordnerlöschen, keine Symlinks,
    /// keine Ziele außerhalb der Quelle. Ergebnis belegt pro Datei, was tatsächlich entfernt wurde.
    static func deletePermanently(_ items: [ItemReference], sources: ConnectedSourceStore) -> OperationOutcome {
        var removed: Set<ItemReference> = []
        for (sourceID, files) in split(items) {
            _ = try? sources.withAccess(sourceID) { root in
                guard (try? root.resourceValues(forKeys: [.isWritableKey]).isWritable) == true else { return }
                for f in files {
                    guard let url = FileScanner.safeURL(root: root, relativePath: f.localIdentifier) else { continue }
                    var err: NSError?
                    NSFileCoordinator().coordinate(writingItemAt: url, options: [.forDeleting], error: &err) { target in
                        if (try? FileManager.default.removeItem(at: target)) != nil { removed.insert(f) }
                    }
                }
            }
        }
        if removed.isEmpty { return .failed(reason: "nothing-removed") }
        return removed.count == items.count ? .succeeded : .partial(removed: removed)
    }

    /// Existenzprüfung für den Abgleich. Ohne Quellzugriff: unbekannt (kein Löschbeweis).
    static func probe(_ items: [ItemReference], sources: ConnectedSourceStore) -> [ItemReference: ExistenceProbe] {
        var out: [ItemReference: ExistenceProbe] = [:]
        for i in items { out[i] = .unknown }
        for (sourceID, files) in split(items) {
            _ = try? sources.withAccess(sourceID) { root in
                for f in files {
                    // Manipulierte Pfade sind kein Löschbeweis.
                    guard let url = FileScanner.containedURL(root: root, relativePath: f.localIdentifier) else { continue }
                    out[f] = FileManager.default.fileExists(atPath: url.path) ? .exists : .missingWithFullAccess
                }
            }
        }
        return out
    }
}

/// Pull-basierter Byte-Strom für Dateien einer Quelle (für `DuplicateFinder`).
/// Hält den security-scoped Zugriff während des Streams offen und gibt ihn danach frei.
final class ConnectedSourceByteProvider: ByteSourceProvider, @unchecked Sendable {
    private let roots: [ConnectedSourceID: URL]
    private let entries: [ItemReference: FileEntry]

    init(roots: [ConnectedSourceID: URL], entries: [FileEntry]) {
        self.roots = roots
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.reference, $0) })
    }

    func openStream(for item: ItemReference) throws -> (any ByteStream)? {
        guard let e = entries[item], let root = roots[e.sourceID],
              let url = FileScanner.safeURL(root: root, relativePath: e.relativePath) else { return nil }
        return try FileHandleByteStream(url: url)
    }
}
