import CoreGraphics
import Foundation
import PhotoMaidCore
import Vision

struct AnalysisOutput: Sendable {
    var item: AnalysisItem
    var feature: Data?
    var interrupted = false
}
private struct AnalysisVisionRequest: @unchecked Sendable { let value: VNRequest }

enum LocalPhotoAnalyzer {
    /// Explicit signatures invalidate old results after changes to scale, OCR or Vision revision.
    static func algorithm(_ kind: AnalysisKind) -> String {
        switch kind {
        case .blurry: "blur-aspect512-v2"
        case .documents: "ocr1600-accurate-v2-\(VNRecognizeTextRequest.defaultRevision)"
        case .categories: "classify1024-v2-\(VNClassifyImageRequest.defaultRevision)"
        case .similar: "feature1024-v2-\(VNGenerateImageFeaturePrintRequest.defaultRevision)"
        }
    }
    static func analyze(_ source: AnalysisItem, cloud: Bool,
                        progress: @escaping @Sendable (Double) -> Void) async -> AnalysisOutput {
        var item = source
        let outcome = await AnalysisImageLoader.load(id: item.id, kind: item.kind, allowCloud: cloud, progress: progress)
        if Task.isCancelled { return AnalysisOutput(item: item, interrupted: true) }
        switch outcome {
        case .cloud: item.state = .waitingForCloud
        case .quality: item.state = .insufficientQuality
        case .network, .cancelled, .privateItem: return AnalysisOutput(item: item, interrupted: true)
        case .failed, .timedOut: item.fail(now: Date())
        case .image(let image):
            do {
                let (updated, feature) = try autoreleasepool { try evaluate(item, image: image) }
                return AnalysisOutput(item: updated, feature: feature)
            } catch is CancellationError { return AnalysisOutput(item: item, interrupted: true) }
            catch { item.fail(now: Date()) }
        }
        return AnalysisOutput(item: item)
    }
    private static func evaluate(_ original: AnalysisItem, image: AnalysisImage) throws -> (AnalysisItem, Data?) {
        try Task.checkCancellation()
        var item = original
        item.sampleWidth = image.image.width; item.sampleHeight = image.image.height
        let handler = VNImageRequestHandler(cgImage: image.image, orientation: image.orientation, options: [:])
        var feature: Data?
        switch item.kind {
        case .blurry:
            guard let score = laplacian(image.image), score.isFinite, score >= 0 else { throw AnalysisDatabaseError.read }
            item.sharpness = score
        case .documents:
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            try perform(request, handler: handler)
            guard let results = request.results else { throw AnalysisDatabaseError.read }
            item.text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        case .categories:
            let request = VNClassifyImageRequest()
            try perform(request, handler: handler)
            guard let results = request.results else { throw AnalysisDatabaseError.read }
            item.category = PhotoCategory.best(results.map { (identifier: $0.identifier, confidence: $0.confidence) })?.rawValue
        case .similar:
            let request = VNGenerateImageFeaturePrintRequest()
            try perform(request, handler: handler)
            guard let result = request.results?.first else { throw AnalysisDatabaseError.read }
            feature = try NSKeyedArchiver.archivedData(withRootObject: result, requiringSecureCoding: true)
        }
        try Task.checkCancellation()
        item.failures = 0; item.retryAfter = nil
        item.state = item.kind == .similar ? .featuresReady : .complete
        return (item, feature)
    }
    /// Vision runs on a utility worker. Cancel unusually long requests rather than leaving them unchecked.
    private static func perform(_ request: VNRequest, handler: VNImageRequestHandler) throws {
        let box = AnalysisVisionRequest(value: request)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 15)
        timer.setEventHandler { box.value.cancel() }
        timer.resume()
        defer { timer.cancel() }
        try Task.checkCancellation()
        try handler.perform([request])
        try Task.checkCancellation()
    }
    static func distance(_ a: Data, _ b: Data) throws -> Float {
        try autoreleasepool {
            guard let first = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: a),
                  let second = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: b) else {
                throw AnalysisDatabaseError.corrupt
            }
            var distance: Float = .nan
            try first.computeDistance(&distance, to: second)
            guard distance.isFinite, distance >= 0 else { throw AnalysisDatabaseError.corrupt }
            return distance
        }
    }
    private static func laplacian(_ image: CGImage) -> Double? {
        let scale = min(1, 512.0 / Double(max(image.width, image.height)))
        let width = Int(Double(image.width) * scale), height = Int(Double(image.height) * scale)
        guard width >= 3, height >= 3 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return max(0, BlurryPhotos.laplacianVariance(pixels.map { Float($0) / 255 }, w: width, h: height))
    }
}
