import Foundation

public struct PhotoSnakeGallery: Codable, Equatable, Sendable {
    public static let maximumPhotos = 100
    public struct Photo: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sourceAssetID: String?
        public init(id: UUID = UUID(), sourceAssetID: String? = nil) { self.id = id; self.sourceAssetID = sourceAssetID }
    }
    public private(set) var photos: [Photo] = []
    public init() {}
    @discardableResult public mutating func append(_ photo: Photo) -> Bool {
        guard photos.count < Self.maximumPhotos, !photos.contains(where: { $0.id == photo.id }) else { return false }
        photos.append(photo); return true
    }
    public mutating func remove(_ id: UUID) { photos.removeAll { $0.id == id } }
    public mutating func move(from offsets: IndexSet, to destination: Int) {
        guard (0...photos.count).contains(destination), offsets.allSatisfy({ photos.indices.contains($0) }) else { return }
        let moved = offsets.sorted().map { photos[$0] }
        let rest = photos.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let target = destination - offsets.filter { $0 < destination }.count
        photos = Array(rest.prefix(target)) + moved + Array(rest.dropFirst(target))
    }
    public func order(shuffled: Bool, seed: UInt64) -> [UUID] {
        var ids = photos.map(\.id)
        guard shuffled, ids.count > 1 else { return ids }
        var state = seed
        for i in stride(from: ids.count - 1, through: 1, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            ids.swapAt(i, Int(state % UInt64(i + 1)))
        }
        return ids
    }
    public func photo(at segment: Int, order: [UUID]? = nil) -> UUID? {
        let ids = order ?? photos.map(\.id)
        guard !ids.isEmpty, segment >= 0 else { return nil }
        return ids[segment % ids.count]
    }
    private enum CodingKeys: String, CodingKey { case photos }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        for photo in try c.decode([Photo].self, forKey: .photos) { _ = append(photo) }
    }
}

/// Application Support thumbnail archive, not originals. UUID-only filenames prevent path injection.
/// One actor serializes atomic index changes and file cleanup, including crash-orphaned thumbnails.
public actor PhotoSnakePhotoArchive {
    public enum Failure: Error { case oversizedImage, duplicate, symlink }
    public let directory: URL
    private let manager = FileManager.default
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> PhotoSnakeGallery {
        try prepare()
        let file = directory.appendingPathComponent("selection.json")
        guard manager.fileExists(atPath: file.path) else { try cleanOrphans(keeping: []); return .init() }
        try rejectSymlink(file)
        let gallery = try JSONDecoder().decode(PhotoSnakeGallery.self, from: Data(contentsOf: file))
        try cleanOrphans(keeping: Set(gallery.photos.map { $0.id.uuidString + ".jpg" }))
        return gallery
    }
    public func image(_ id: UUID) throws -> Data? {
        let file = photoURL(id)
        guard manager.fileExists(atPath: file.path) else { return nil }
        try rejectSymlink(file)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 262_144 else { throw Failure.oversizedImage }
        return try Data(contentsOf: file)
    }
    public func insert(_ data: Data, photo: PhotoSnakeGallery.Photo) throws -> PhotoSnakeGallery {
        guard !data.isEmpty, data.count <= 262_144 else { throw Failure.oversizedImage }
        var gallery = try load()
        guard gallery.append(photo) else { throw Failure.duplicate }
        let file = photoURL(photo.id)
        try write(data, to: file)
        do { try save(gallery) } catch { try? manager.removeItem(at: file); throw error }
        return gallery
    }
    public func remove(_ id: UUID) throws -> PhotoSnakeGallery {
        var gallery = try load()
        let file = photoURL(id)
        if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
        gallery.remove(id)
        try save(gallery)
        return gallery
    }
    public func move(from offsets: IndexSet, to destination: Int) throws -> PhotoSnakeGallery {
        var gallery = try load(); gallery.move(from: offsets, to: destination)
        try save(gallery); return gallery
    }
    private func save(_ gallery: PhotoSnakeGallery) throws {
        try write(JSONEncoder().encode(gallery), to: directory.appendingPathComponent("selection.json"))
    }
    private func photoURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".jpg") }
    private func write(_ data: Data, to file: URL) throws {
        #if os(iOS) || os(tvOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
    private func prepare() throws {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try rejectSymlink(directory)
        #if os(iOS) || os(tvOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #endif
    }
    private func rejectSymlink(_ file: URL) throws {
        if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw Failure.symlink }
    }
    private func cleanOrphans(keeping: Set<String>) throws {
        for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "jpg" && !keeping.contains(url.lastPathComponent) {
            try manager.removeItem(at: url)
        }
    }
}
