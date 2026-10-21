import AVFoundation
import CoreMedia
import Foundation

/// Schreibt eine Komposition neu: Bild über den eigenen Compositor (H.264, Bitrate aus Profil oder Zielgröße), Ton als
/// AAC mit gleicher Tonhöhe bei Tempo. Fortschritt nach Zeitstempel. Abbrechen über Task-Abbruch – die halbe Datei
/// wird gelöscht. Größen werden danach gemessen, nicht geschätzt.
enum VideoWriter {
    struct Options: Sendable {
        var videoBitrate: Int
        var audioOnly = false
        var fileType: AVFileType = .mp4
        /// Aus im Tresor: kein zusätzlicher Schreibdurchgang außerhalb des vorgegebenen Ordners.
        var optimizeForNetwork = true
    }

    static func write(_ built: BuiltComposition, to url: URL, options: Options,
                      progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let asset = built.composition
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: url, fileType: options.fileType)
        writer.shouldOptimizeForNetworkUse = options.optimizeForNetwork
        var pairs: [Pump.Pair] = []

        if !options.audioOnly {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let out = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            out.videoComposition = built.videoComposition
            out.alwaysCopiesSampleData = false
            guard reader.canAdd(out) else { throw VideoError.read }
            reader.add(out)
            let size = built.plan.size
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: options.videoBitrate,
                    AVVideoExpectedSourceFrameRateKey: Int(built.fps),
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ] as [String: Any],
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw VideoError.write }
            writer.add(input)
            pairs.append(Pump.Pair(output: out, input: input, gain: 1, isVideo: true))
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
            ])
            out.audioMix = built.audioMix
            out.audioTimePitchAlgorithm = .spectral
            guard reader.canAdd(out) else { throw VideoError.read }
            reader.add(out)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw VideoError.write }
            writer.add(input)
            pairs.append(Pump.Pair(output: out, input: input, gain: built.audioBoost, isVideo: false))
        } else if options.audioOnly {
            throw VideoError.noAudio
        }

        guard reader.startReading() else { throw reader.error ?? VideoError.read }
        guard writer.startWriting() else { throw writer.error ?? VideoError.write }
        writer.startSession(atSourceTime: .zero)
        let pump = Pump(reader: reader, writer: writer, pairs: pairs, durationMs: built.durationMs, progress: progress)
        do {
            try await withTaskCancellationHandler {
                try await pump.run()
            } onCancel: {
                pump.cancel()
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        progress(1)
    }

    /// Nur Anfang/Ende gekürzt: ohne Neuberechnung (gleiche Qualität, HDR bleibt). Schlägt das fehl, rechnet der Aufrufer neu.
    static func passthroughTrim(_ asset: AVAsset, startMs: Int64, endMs: Int64, to url: URL, optimizeForNetwork: Bool = true,
                                progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoError.write
        }
        session.timeRange = CMTimeRange(start: .ms(startMs), end: .ms(endMs))
        session.shouldOptimizeForNetworkUse = optimizeForNetwork
        let box = UncheckedBox(session)
        let watcher = Task {
            for await state in box.value.states(updateInterval: 0.2) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await box.value.export(to: url, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        progress(1)
    }
}

/// Führt Lesen und Schreiben aller Spuren zusammen (je Spur eine Warteschlange). `@unchecked Sendable`: alle Zustände
/// hinter einem Lock, AVFoundation-Objekte werden nur in ihren Warteschlangen benutzt.
private final class Pump: @unchecked Sendable {
    struct Pair: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
        /// Zusätzliche Tonverstärkung (> 1 nur, wenn Lautstärke über 100 %).
        let gain: Float
        let isVideo: Bool
    }

    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let pairs: [Pair]
    private let durationMs: Int64
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var remaining: Int
    private var cancelled = false
    private var failed = false
    private var continuation: CheckedContinuation<Void, any Error>?
    private var lastReport: Double = -1

    init(reader: AVAssetReader, writer: AVAssetWriter, pairs: [Pair], durationMs: Int64,
         progress: @escaping @Sendable (Double) -> Void) {
        self.reader = reader
        self.writer = writer
        self.pairs = pairs
        self.durationMs = max(1, durationMs)
        self.progress = progress
        remaining = pairs.count
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            lock.withLock { continuation = cont }
            if pairs.isEmpty { finishAll(); return }
            for (i, pair) in pairs.enumerated() {
                let queue = DispatchQueue(label: "app.photomaid.writer.\(i)")
                pair.input.requestMediaDataWhenReady(on: queue) { [self] in drain(pair) }
            }
        }
    }

    func cancel() {
        lock.withLock { cancelled = true }
        reader.cancelReading()
    }

    private func drain(_ pair: Pair) {
        while pair.input.isReadyForMoreMediaData {
            if lock.withLock({ cancelled || failed }) { pair.input.markAsFinished(); trackDone(); return }
            guard let sample = pair.output.copyNextSampleBuffer() else {
                pair.input.markAsFinished()
                trackDone()
                return
            }
            if !pair.isVideo && pair.gain > 1.001 { Self.amplify(sample, by: pair.gain) }
            if pair.isVideo || pairs.count == 1 { report(CMSampleBufferGetPresentationTimeStamp(sample)) }
            if !pair.input.append(sample) {
                lock.withLock { failed = true }
                reader.cancelReading()
                pair.input.markAsFinished()
                trackDone()
                return
            }
        }
    }

    private func report(_ t: CMTime) {
        let p = min(0.99, max(0, Double(t.milliseconds) / Double(durationMs)))
        let send = lock.withLock { () -> Bool in
            guard p - lastReport >= 0.01 else { return false }
            lastReport = p
            return true
        }
        if send { progress(p) }
    }

    private func trackDone() {
        let last = lock.withLock { () -> Bool in
            remaining -= 1
            return remaining == 0
        }
        if last { finishAll() }
    }

    private func finishAll() {
        let (isCancelled, isFailed) = lock.withLock { (cancelled, failed) }
        if isCancelled || isFailed || reader.status == .failed {
            writer.cancelWriting()
            let error: any Error = isCancelled ? CancellationError() : (reader.error ?? writer.error ?? VideoError.write)
            resume(.failure(error))
            return
        }
        let w = UncheckedBox(writer)
        writer.finishWriting { [self] in
            if w.value.status == .completed { resume(.success(())) } else { resume(.failure(w.value.error ?? VideoError.write)) }
        }
    }

    private func resume(_ result: Result<Void, any Error>) {
        let cont = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        cont?.resume(with: result)
    }

    /// Lautstärke über 100 %: Gleitkomma-Proben (interleaved) mit dem Faktor multiplizieren und auf ±1 begrenzen.
    private static func amplify(_ sample: CMSampleBuffer, by gain: Float) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let total = CMBlockBufferGetDataLength(block)
        var offset = 0
        while offset < total {
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: offset, lengthAtOffsetOut: &length, totalLengthOut: nil,
                                              dataPointerOut: &pointer) == kCMBlockBufferNoErr,
                  let pointer, length > 0 else { return }
            let count = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: count) { f in
                for i in 0..<count { f[i] = min(1, max(-1, f[i] * gain)) }
            }
            offset += length
        }
    }
}
