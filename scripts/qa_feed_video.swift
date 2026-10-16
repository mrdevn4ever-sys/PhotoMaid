// Two tiny labelled videos for disposable PhotoKit recovery tests; no personal media.
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for number in 1...2 {
    let output = directory.appendingPathComponent(String(format: "QA_FEED_%02d.mp4", number))
    let source = directory.appendingPathComponent(String(format: "QA_GAME_%02d.jpg", number))
    let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 400
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 400,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ])
    writer.add(input)
    guard writer.startWriting() else { fatalError("QA writer start") }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<48 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess,
              let buffer else { fatalError("QA pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 400,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 400))
        context.setFillColor(CGColor(gray: 1, alpha: 0.7))
        context.fill(CGRect(x: CGFloat(frame * 5), y: 30, width: 20, height: 8))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else {
            fatalError("QA frame append")
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { fatalError("QA writer finish") }
}
print("Created two labelled 2-second QA videos")
