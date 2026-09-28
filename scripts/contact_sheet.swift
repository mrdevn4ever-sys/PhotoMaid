// Erstellt aus allen PNGs eines Verzeichnisses (rekursiv) ein Kontaktblatt und prüft
// jede Aufnahme automatisch auf leere/einfarbige Bilder.
// Aufruf: swift scripts/contact_sheet.swift <screenshots-dir> <out.png>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
    .filter { $0.pathExtension == "png" && $0.lastPathComponent != outURL.lastPathComponent }
    .sorted { $0.path < $1.path }
guard !files.isEmpty else { print("Keine Screenshots gefunden"); exit(1) }

var images: [(String, CGImage)] = []
var problems: [String] = []
for f in files {
    guard let src = CGImageSourceCreateWithURL(f as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        problems.append("\(f.lastPathComponent): nicht lesbar"); continue
    }
    // Einfache Leer-Erkennung: Streuung der Helligkeit auf einem 32×32-Raster.
    let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    let px = UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: 1024)
    let mean = px.reduce(0.0) { $0 + Double($1) } / 1024
    let variance = px.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / 1024
    if variance < 20 { problems.append("\(f.lastPathComponent): nahezu einfarbig (möglicher leerer Screen)") }
    let rel = f.path.replacingOccurrences(of: dir.path + "/", with: "")
    images.append((rel, img))
}

let cols = 6
let thumbW = 330, thumbH = 716, labelH = 44, pad = 24
let rows = (images.count + cols - 1) / cols
let W = cols * (thumbW + pad) + pad, H = rows * (thumbH + labelH + pad) + pad + 60
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
ctx.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 0.99, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

func text(_ s: String, x: Int, y: Int, size: CGFloat) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.06, green: 0.15, blue: 0.28, alpha: 1)])
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
}
text("PhotoMaid – echte Simulator-Screenshots (\(images.count))", x: pad, y: H - 44, size: 28)
for (i, (name, img)) in images.enumerated() {
    let c = i % cols, r = i / cols
    let x = pad + c * (thumbW + pad)
    let top = H - 60 - pad - r * (thumbH + labelH + pad)
    let scale = min(Double(thumbW) / Double(img.width), Double(thumbH) / Double(img.height))
    let w = Int(Double(img.width) * scale), h = Int(Double(img.height) * scale)
    ctx.draw(img, in: CGRect(x: x + (thumbW - w) / 2, y: top - thumbH + (thumbH - h), width: w, height: h))
    text(name, x: x, y: top - thumbH - 30, size: 16)
}
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("Kontaktblatt: \(outURL.path) (\(images.count) Screenshots)")
if problems.isEmpty { print("Automatische Prüfung: keine leeren Screens") } else { problems.forEach { print("::warning::\($0)") } }
