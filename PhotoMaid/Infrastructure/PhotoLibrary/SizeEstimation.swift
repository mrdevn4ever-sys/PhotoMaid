import Foundation
import PhotoMaidCore
import UniformTypeIdentifiers

extension MediaAsset {
    /// Was die Größenschätzung über ein Medium weiß (Art, Pixel, Dauer – keine Bilddaten).
    var estimateInput: EstimateInput {
        let kind: EstimateKind = isVideo ? .video : (self.kind == .screenshot ? .screenshot : (isLivePhoto ? .livePhoto : .photo))
        return EstimateInput(kind: kind, pixels: pixelWidth * pixelHeight, duration: duration)
    }
}

extension FileEntry {
    var estimateInput: EstimateInput { EstimateInput(kind: .file, fileType: contentType?.identifier) }
}

extension SizeEstimator {
    /// Aus den gemessenen Medien und Dateien dieser Mediathek kalibrieren (Medianwerte; wenige Messungen → Richtwerte).
    static func calibrated(media: [MediaAsset], records: [String: SizeRecord], files: [FileEntry]) -> SizeEstimator {
        var samples: [SizeSample] = []
        samples.reserveCapacity(min(media.count, records.count) + files.count)
        for a in media {
            guard let r = records[a.id], r.state == .known, let b = r.bytes, r.isCurrent(modified: a.modificationDate) else { continue }
            samples.append(SizeSample(a.estimateInput, bytes: b))
        }
        for f in files {
            if case .known(let b) = f.size { samples.append(SizeSample(f.estimateInput, bytes: b)) }
        }
        return SizeEstimator(samples: samples)
    }
}
