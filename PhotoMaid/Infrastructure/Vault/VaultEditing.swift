import AVFoundation
import Foundation
import ImageIO
import PhotoMaidCore
import UIKit
import UniformTypeIdentifiers

/// Ergebnis einer Bearbeitung im Tresor: neues Medium, beim Ersetzen liegt das Original im Tresor-Papierkorb.
struct VaultEditResult: Equatable, Sendable {
    let newID: String
    let originalID: String
    let replaced: Bool
    let frame: Bool
}

enum VaultEditError: Error { case missing, limit }

/// Bearbeitete Fassung als Daten (Foto, Standbild) oder als Datei in der geschützten Temp-Ablage der Sitzung (Video).
enum VaultMediaPayload: Sendable {
    case data(Data)
    case file(URL)
}

/// Bild- und Videobearbeitung im Tresor (Nutzerwunsch 21.10.2026): Quellen kommen nur aus dem Tresor, Ergebnisse gehen
/// nur in den Tresor – verschlüsselt, geprüft, mit verschlüsseltem Vorschaubild. Keine Fotos-App, kein Verlauf, keine
/// Liste „Bearbeitet“, keine Caches auf der Platte; Klartext nur in der Temp-Ablage der Sitzung (beim Sperren gelöscht).
extension VaultStore {
    /// Sitzung, an die eine Bearbeitung gebunden ist (beim Öffnen des Editors festgehalten). Ergebnisse gehen nur in
    /// genau diese Sitzung – nach einer Sperre und erneutem Öffnen nie in die neue.
    func editSession() -> VaultSessionLease? { try? requireLease() }

    /// Laufende Bearbeitungs-Arbeit (zählt als Bedienung). Das Sperren setzt den Zähler zurück.
    func beginEditWork() { editWork += 1 }
    func endEditWork() { editWork = max(0, editWork - 1) }

    /// Original eines Fotos vollständig entschlüsselt in den Speicher (für den Foto-Editor) samt Dateinamen.
    func editPhotoSource(_ id: String, lease activeLease: VaultSessionLease) async -> (data: Data, name: String)? {
        guard accepts(activeLease), let item = index.items.first(where: { $0.id == id }),
              let resource = item.current, VaultPathRules.isComponent(resource.file) else { return nil }
        let url = Self.objects.appendingPathComponent(resource.file)
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard activeLease.isValid else { return nil }
            return try? VaultFileReader.data(at: url, master: activeLease.key)
        }.value
        guard accepts(activeLease), let data, Int64(data.count) == resource.size else { return nil }
        return (data, resource.originalFilename)
    }

    /// Video in die Temp-Ablage der Sitzung entschlüsseln (für den Video-Editor) samt Dateinamen.
    func editVideoSource(_ id: String, lease activeLease: VaultSessionLease) async -> (url: URL, name: String)? {
        guard accepts(activeLease), let item = index.items.first(where: { $0.id == id }), item.isVideo,
              let resource = item.current, let url = await videoFile(item) else { return nil }
        guard accepts(activeLease) else {
            removeTempFiles([url])
            return nil
        }
        return (url, resource.originalFilename)
    }

    /// Geschützter Ordner der Sitzung für einen Export (beim Sperren gelöscht; danach nie neu angelegt).
    func editTempFolder(lease activeLease: VaultSessionLease) throws -> URL {
        guard accepts(activeLease) else { throw VaultCryptoError.authentication }
        return try activeLease.makeDirectory()
    }

    /// Bearbeitete Fassung neben dem Original ablegen: verschlüsselt schreiben, gegen den Klartext prüfen, Vorschaubild
    /// erzeugen, dann in einem Schreibvorgang übernehmen (beim Ersetzen samt Original in den Tresor-Papierkorb).
    func addEditedMedia(_ payload: VaultMediaPayload, video: Bool, uti: String, filename: String, basedOn originalID: String,
                        creationOffsetMs: Int64 = 0, frame: Bool = false, removeLocation: Bool, replace: Bool,
                        unlimited: Bool, lease activeLease: VaultSessionLease) async throws -> VaultEditResult {
        guard accepts(activeLease), !needsNewCode else { throw VaultCryptoError.authentication }
        try activeLease.check()
        guard let original = index.items.first(where: { $0.id == originalID }) else { throw VaultEditError.missing }
        guard VaultPolicy.allowed(requested: 1, existing: mediaSlotsUsed, unlimited: unlimited) == 1 else {
            throw VaultEditError.limit
        }
        beginEditWork()
        defer { endEditWork() }
        let objects = Self.objects, thumbs = Self.thumbs
        let written = try await Task.detached(priority: .userInitiated) {
            try await VaultEditWriter.write(payload, video: video, lease: activeLease, objects: objects, thumbs: thumbs)
        }.value
        let resource = VaultResource(role: video ? .video : .photo, file: written.file, uti: uti,
                                     originalFilename: filename, size: written.size, sha256: written.sha256)
        let item = VaultEdit.item(from: original, id: UUID().uuidString, kind: video ? .video : .photo, resource: resource,
                                  addedMs: nowMs, creationOffsetMs: creationOffsetMs, removeLocation: removeLocation,
                                  replace: replace, duration: written.duration, pixelWidth: written.width,
                                  pixelHeight: written.height, thumbnail: written.thumbnail)
        do {
            guard accepts(activeLease) else { throw CancellationError() }
            let now = nowMs
            try commitSnapshot { try $0.addEdited(item, replacing: replace ? originalID : nil, nowMs: now) }
        } catch {
            Self.removeFiles(of: item)
            throw error
        }
        return VaultEditResult(newID: item.id, originalID: originalID, replaced: replace, frame: frame)
    }
}

/// Schreiben und Messen außerhalb des Hauptthreads.
enum VaultEditWriter {
    struct Written: Sendable {
        let file: String
        let size: Int64
        let sha256: String
        let thumbnail: String?
        let width: Int
        let height: Int
        let duration: Double
    }

    static func write(_ payload: VaultMediaPayload, video: Bool, lease: VaultSessionLease, objects: URL,
                      thumbs: URL) async throws -> Written {
        try lease.check()
        let name = UUID().uuidString
        let url = objects.appendingPathComponent(name)
        let writer = try VaultFileWriter(url: url, master: lease.key)
        let result: (size: Int64, sha256: String)
        do {
            switch payload {
            case .data(let data):
                writer.receive(data)
            case .file(let file):
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                    try lease.check()
                    writer.receive(chunk)
                }
            }
            result = try writer.finish()
            let check = try VaultFileReader.digest(url, master: lease.key)
            guard check.size == result.size, check.sha256 == result.sha256 else { throw VaultCryptoError.authentication }
            try lease.check()
        } catch {
            writer.abort()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        let measured: (preview: UIImage?, width: Int, height: Int, duration: Double)
        switch payload {
        case .data(let data):
            measured = photoMeasure(data)
        case .file(let file):
            if video { measured = await videoMeasure(file) } else { measured = (nil, 0, 0, 0) }
        }
        let thumb = measured.preview.flatMap { sealThumbnail($0, key: lease.key, thumbs: thumbs) }
        return Written(file: name, size: result.size, sha256: result.sha256, thumbnail: thumb, width: measured.width,
                       height: measured.height, duration: measured.duration)
    }

    /// Pixelmaße (mit Ausrichtung) und verkleinertes Vorschaubild eines Fotos.
    private static func photoMeasure(_ data: Data) -> (UIImage?, Int, Int, Double) {
        var width = 0, height = 0
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            if let orientation = props[kCGImagePropertyOrientation] as? UInt32, (5...8).contains(orientation) {
                swap(&width, &height)
            }
        }
        return (VaultStore.downsample(data, maxPixel: 400), width, height, 0)
    }

    /// Maße, Dauer und erstes Bild eines Videos (aus der Temp-Ablage der Sitzung).
    private static func videoMeasure(_ url: URL) async -> (UIImage?, Int, Int, Double) {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        var width = 0, height = 0
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let loaded = try? await track.load(.naturalSize, .preferredTransform) {
            let shown = loaded.0.applying(loaded.1)
            width = Int(abs(shown.width).rounded())
            height = Int(abs(shown.height).rounded())
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        let time = CMTime(seconds: min(0.1, max(0, duration / 2)), preferredTimescale: 600)
        let image = (try? await generator.image(at: time)).map { UIImage(cgImage: $0.image) }
        return (image, width, height, duration.isFinite ? duration : 0)
    }

    /// Vorschaubild verschlüsselt wie beim Ablegen (eigener Unterschlüssel, Zufallsname, Dateischutz „vollständig“).
    private static func sealThumbnail(_ image: UIImage, key: VaultKey, thumbs: URL) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8),
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

/// UTI einer exportierten Videodatei (MOV oder MP4).
extension UTType {
    static func videoIdentifier(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.quickTimeMovie.identifier
    }
}
