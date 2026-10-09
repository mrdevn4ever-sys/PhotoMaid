import Accelerate
import CoreImage
import ImageIO
import Photos
import PhotoMaidCore
import Vision

struct LocalAnalysisResult: Sendable {
    let cache: [String: AnalysisCacheEntry]
    let similarGroups: [[String]]
}

enum LocalPhotoAnalyzer {
    static func analyze(_ assets: [MediaAsset]) async -> LocalAnalysisResult {
        var cache: [String: AnalysisCacheEntry] = [:]
        var prints: [String: UncheckedBox<VNFeaturePrintObservation>] = [:]
        for asset in assets where !asset.isVideo {
            if Task.isCancelled { break }
            guard let data = try? await BatchProcessor.imageData(asset.id),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let request = VNClassifyImageRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .fast
            let feature = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            try? handler.perform([request, text, feature])
            let observations = (request.results ?? []).map { (identifier: $0.identifier, confidence: $0.confidence) }
            let category = PhotoCategory.best(observations)
            let recognized = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let sharpness = laplacian(image)
            cache[asset.id] = AnalysisCacheEntry(modified: asset.modificationDate, sharpness: sharpness,
                                                 category: category, text: recognized.isEmpty ? nil : recognized)
            if let value = feature.results?.first { prints[asset.id] = UncheckedBox(value) }
        }
        let photos = assets.map { AnalyzedPhoto(id: $0.id, takenAt: $0.creationDate, sharpness: cache[$0.id]?.sharpness) }
        let groups = SimilarPhotos.groups(photos) { first, second in
            guard let a = prints[first.id], let b = prints[second.id] else { return nil }
            var distance: Float = 0
            try? a.value.computeDistance(&distance, to: b.value)
            return distance
        }.map { $0.map(\.id) }
        return LocalAnalysisResult(cache: cache, similarGroups: groups)
    }

    private static func laplacian(_ image: CGImage) -> Double {
        let width = 128, height = 128
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let luma = pixels.map { Float($0) / 255 }
        return BlurryPhotos.laplacianVariance(luma, w: width, h: height)
    }
}
