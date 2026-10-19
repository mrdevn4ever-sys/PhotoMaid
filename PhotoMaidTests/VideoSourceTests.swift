import AVFoundation
import CoreVideo
import Testing
import UIKit
@testable import PhotoMaid

@MainActor struct VideoSourceTests {
    @Test func mainActorPreviewDecodesFramesFromAReadOnlyVideo() async throws {
        let url = try await Self.makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let source = UncheckedBox<AVAsset>(asset)
        let frame = try #require(await VideoSource.frame(source, sourceMs: 250, maxEdge: 32))
        #expect(frame.value.width > 0 && frame.value.width <= 32)
        let thumbnails = await VideoSource.thumbnails(source, durationMs: 1000, count: 3, height: 16)
        #expect(thumbnails.count == 3)
        #expect(thumbnails.allSatisfy { $0.size.width > 0 && $0.size.width <= 32 })
        #expect(Set(thumbnails.compactMap { $0.pngData() }).count > 1)
        #expect(asset.url == url)
    }

    /// Tiny synthetic video in the test's temporary directory; never accesses the photo library.
    nonisolated private static func makeVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64, AVVideoHeightKey: 48
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48
            ])
            guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
            let deadline = Date().addingTimeInterval(10)
            for index in 0..<4 {
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else {
                        throw writer.error ?? CocoaError(.fileWriteUnknown)
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                var pixelBuffer: CVPixelBuffer?
                guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32ARGB,
                                           nil, &pixelBuffer) == kCVReturnSuccess,
                      let pixelBuffer else { throw CocoaError(.fileWriteUnknown) }
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                    let pixels = base.assumingMemoryBound(to: UInt8.self)
                    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
                    for y in 0..<48 { for x in 0..<64 {
                        let offset = y * stride + x * 4
                        pixels[offset] = 255
                        pixels[offset + 1] = index.isMultiple(of: 2) ? 255 : 0
                        pixels[offset + 2] = 0
                        pixels[offset + 3] = index.isMultiple(of: 2) ? 0 : 255
                    } }
                }
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 4)) else {
                    throw writer.error ?? CocoaError(.fileWriteUnknown)
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
