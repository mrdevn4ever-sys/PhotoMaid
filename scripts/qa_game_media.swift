// Bounded synthetic PhotoKit fixtures for game/layout tests. No personal media and no videos to encode.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width = 1280, height = 1600
let space = CGColorSpaceCreateDeviceRGB()
for index in 1...18 {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("QA context") }
    let angle = Double(index) * 2.399963229728653
    let red = 0.3 + 0.3 * (sin(angle) + 1)
    let green = 0.25 + 0.3 * (sin(angle + 2.1) + 1)
    let blue = 0.25 + 0.3 * (sin(angle + 4.2) + 1)
    let colors = [CGColor(red: red, green: green, blue: blue, alpha: 1),
                  CGColor(red: red * 0.3, green: green * 0.45, blue: blue * 0.55, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])
    context.setFillColor(CGColor(gray: 1, alpha: 0.55))
    let sunX = 180 + (index * 113) % 820
    context.fillEllipse(in: CGRect(x: CGFloat(sunX), y: CGFloat(800 + (index * 47) % 280), width: 180, height: 180))
    context.setFillColor(CGColor(red: red * 0.2, green: green * 0.2, blue: blue * 0.2, alpha: 0.8))
    context.move(to: .zero)
    context.addLine(to: CGPoint(x: 0, y: 530))
    context.addLine(to: CGPoint(x: CGFloat(370 + index * 11), y: 740))
    context.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(300 + index * 9)))
    context.addLine(to: CGPoint(x: CGFloat(width), y: 0)); context.closePath(); context.fillPath()
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 100, nil)
    let text = NSAttributedString(string: String(format: "QA %02d", index), attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.9)])
    context.textPosition = CGPoint(x: 90, y: 650)
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
    let url = output.appendingPathComponent(String(format: "QA_GAME_%02d.jpg", index))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [
        kCGImageDestinationLossyCompressionQuality: 0.85,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: String(format: "2026:09:%02d 10:00:00", index)]
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("QA image") }
}
print("Created 18 labelled synthetic QA photographs")
