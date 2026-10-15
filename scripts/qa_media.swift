// Erzeugt deterministische, synthetische QA-Medien für den Simulator (macOS, `swift scripts/qa_media.swift <out>`).
// Keine persönlichen Fotos, keine Downloads. Jeder Lauf erzeugt identische Bytes.
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "qa-media", isDirectory: true)
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

struct Palette { let top: (CGFloat, CGFloat, CGFloat); let bottom: (CGFloat, CGFloat, CGFloat) }
let palettes: [Palette] = [
    .init(top: (0.97, 0.84, 0.66), bottom: (0.17, 0.37, 0.56)),   // Sonnenuntergang über Meer
    .init(top: (0.75, 0.89, 0.97), bottom: (0.21, 0.37, 0.49)),   // Himmel / Berge
    .init(top: (1.00, 0.89, 0.70), bottom: (0.56, 0.44, 0.66)),   // Abendlicht
    .init(top: (0.84, 0.94, 0.85), bottom: (0.24, 0.48, 0.35)),   // Wald
    .init(top: (0.98, 0.91, 0.78), bottom: (0.62, 0.42, 0.24)),   // Wüste
    .init(top: (0.91, 0.93, 0.97), bottom: (0.68, 0.75, 0.84)),   // Nebel
]

func draw(_ ctx: CGContext, w: Int, h: Int, palette p: Palette, label: String, phase: CGFloat = 0) {
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [CGColor(red: p.top.0, green: p.top.1, blue: p.top.2, alpha: 1),
                  CGColor(red: p.bottom.0, green: p.bottom.1, blue: p.bottom.2, alpha: 1)] as CFArray
    let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: 0), options: [])
    // Hügel-Silhouetten
    for (i, alpha) in [0.35, 0.55].enumerated() {
        ctx.setFillColor(CGColor(red: p.bottom.0 * 0.6, green: p.bottom.1 * 0.6, blue: p.bottom.2 * 0.6, alpha: alpha))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: 0))
        let base = CGFloat(h) * (0.28 - 0.1 * CGFloat(i))
        for x in stride(from: 0, through: w, by: 8) {
            let y = base + CGFloat(h) * 0.06 * sin(CGFloat(x) / CGFloat(w) * .pi * CGFloat(2 + i) + phase)
            ctx.addLine(to: CGPoint(x: CGFloat(x), y: y))
        }
        ctx.addLine(to: CGPoint(x: w, y: 0)); ctx.closePath(); ctx.fillPath()
    }
    // Sonne
    ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.88, alpha: 0.9))
    let r = CGFloat(min(w, h)) * 0.09
    ctx.fillEllipse(in: CGRect(x: CGFloat(w) * 0.68 - r, y: CGFloat(h) * 0.62 + phase * 20 - r, width: 2 * r, height: 2 * r))
    // Beschriftung (klein, unten links)
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(min(w, h)) * 0.035, nil)
    let attr = NSAttributedString(string: label, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 0.85)])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.textPosition = CGPoint(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.05)
    CTLineDraw(line, ctx)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
}

func writeJPEG(_ image: CGImage, to url: URL, date: String) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: date, kCGImagePropertyExifDateTimeDigitized: date]
    let props: [CFString: Any] = [kCGImagePropertyExifDictionary: exif,
                                  kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: date],
                                  kCGImageDestinationLossyCompressionQuality: 0.9]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}

// Fotos: hoch, quer, Panorama, quadratisch – feste EXIF-Daten (neueste zuerst im Feed).
let sizes = [(1179, 2556, "hoch"), (4032, 3024, "quer"), (1179, 2556, "hoch"), (6000, 1500, "panorama"),
             (3024, 3024, "quadrat"), (4032, 3024, "quer"), (1179, 2556, "hoch"), (3024, 4032, "hoch"),
             (4032, 3024, "quer"), (1179, 2556, "hoch"), (3024, 4032, "hoch"), (4032, 3024, "quer")]
for (i, s) in sizes.enumerated() {
    let ctx = makeContext(s.0, s.1)
    draw(ctx, w: s.0, h: s.1, palette: palettes[i % palettes.count], label: String(format: "QA %02d · %@", i + 1, s.2))
    let url = out.appendingPathComponent(String(format: "QA_%02d_%@.jpg", i + 1, s.2))
    writeJPEG(ctx.makeImage()!, to: url, date: String(format: "2026:09:%02d 10:%02d:00", 27 - i / 2, 10 + i))
}
// Exakte Duplikate: dieselben Bytes zweimal.
let dupSource = out.appendingPathComponent("QA_01_hoch.jpg")
try FileManager.default.copyItem(at: dupSource, to: out.appendingPathComponent("QA_DUP_01_hoch.jpg"))

// Videos (H.264, ohne Ton): hoch und quer.
func writeVideo(_ url: URL, w: Int, h: Int, seconds: Int, palette: Palette, label: String) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: w,
        kCVPixelBufferHeightKey as String: h])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let fps = 30
    for f in 0..<(seconds * fps) {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        draw(ctx, w: w, h: h, palette: palette, label: label, phase: CGFloat(f) / CGFloat(fps))
        CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
}
try writeVideo(out.appendingPathComponent("QA_VIDEO_01_hoch.mov"), w: 720, h: 1280, seconds: 14, palette: palettes[2], label: "QA Video 01")
try writeVideo(out.appendingPathComponent("QA_VIDEO_02_quer.mov"), w: 1280, h: 720, seconds: 12, palette: palettes[0], label: "QA Video 02")
print("QA-Medien erzeugt in \(out.path)")
