import CoreImage
import ImageIO
import PhotoMaidCore
import UIKit
import UniformTypeIdentifiers

/// Zeichnet eine Collage – mit derselben Geometrie (`CollageGeometry`) wie die Vorschau. Fotos werden nur gleichmäßig
/// skaliert und beschnitten (nie verzerrt, nie gestreckt). Text und Sticker zeichnet derselbe `LayerRenderer` wie im
/// Foto-Editor. Die Originale bleiben unberührt; das Ergebnis ist immer eine neue Datei.
final class CollageRenderer: @unchecked Sendable {
    enum Failure: Error { case missingImage, renderFailed, encodeFailed }

    static let shared = CollageRenderer()

    private let context = CIContext()

    /// Unschärfe des Foto-Hintergrunds relativ zur kürzeren Kante (Vorschau nutzt denselben Wert).
    static let blurFraction: CGFloat = 0.03

    /// `images`: aufrechte Fotos je Medien-ID (ohne Vierteldrehung/Spiegeln). `scene` und `size` stammen aus
    /// `CollageGeometry` – dieselben Werte wie in der Vorschau.
    func render(project: CollageProject, scene: CollageScene, size: PxSize, images: [String: CGImage]) throws -> CGImage {
        guard !project.items.isEmpty, size.width > 0, size.height > 0 else { throw Failure.missingImage }
        var oriented: [Int: CGImage] = [:]
        for (i, item) in project.items.enumerated() {
            guard let src = images[item.mediaId] else { continue }
            oriented[i] = Self.oriented(src, quarterTurns: item.quarterTurns, flipH: item.flipH)
        }
        let w = CGFloat(size.width), h = CGFloat(size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let base = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { drawing in
            let c = drawing.cgContext
            drawBackground(project, oriented: oriented, in: c, width: w, height: h)
            for placement in scene.placements {
                guard let image = oriented[placement.index] else { continue }
                Self.draw(image, placement: placement, in: c, width: w, height: h)
            }
        }
        guard let cg = base.cgImage else { throw Failure.renderFailed }
        let decor = project.layers.filter { if case .redact = $0 { false } else { true } }
        guard !decor.isEmpty else { return cg }
        let composed = LayerRenderer.draw(decor, over: CIImage(cgImage: cg), size: size)
        guard let out = context.createCGImage(composed, from: CGRect(x: 0, y: 0, width: w, height: h)) else {
            throw Failure.renderFailed
        }
        return out
    }

    /// JPEG (Standard, kleiner) oder PNG (verlustfrei).
    func encode(_ image: CGImage, format: EditFormat) throws -> Data {
        let data = NSMutableData()
        let type = format == .png ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil) else {
            throw Failure.encodeFailed
        }
        let props: [CFString: Any] = format == .png ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodeFailed }
        return data as Data
    }

    /// Text und Sticker als durchsichtiges Bild für die Vorschau (derselbe `LayerRenderer` wie im Export).
    func layerOverlay(_ layers: [PhotoMaidCore.Layer], size: PxSize) -> CGImage? {
        let decor = layers.filter { if case .redact = $0 { false } else { true } }
        guard !decor.isEmpty, size.width >= 2, size.height >= 2 else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let out = LayerRenderer.draw(decor, over: CIImage(color: .clear).cropped(to: rect), size: size)
        return context.createCGImage(out, from: rect)
    }

    // MARK: Zeichnen

    /// Ein Foto: gleichmäßiger Maßstab aus `source` → `photo`, beschnitten auf die (abgerundete) Fotofläche.
    static func draw(_ image: CGImage, placement pl: CollagePlacement, in c: CGContext, width w: CGFloat, height h: CGFloat) {
        let short = min(w, h)
        let frame = rect(pl.frame, w, h), photo = rect(pl.photo, w, h)
        c.saveGState()
        if abs(pl.rotation) > 0.001 {
            c.translateBy(x: frame.midX, y: frame.midY)
            c.rotate(by: CGFloat(pl.rotation) * .pi / 180)
            c.translateBy(x: -frame.midX, y: -frame.midY)
        }
        if pl.polaroid {
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: short * 0.006), blur: short * 0.024,
                        color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: CGFloat(pl.frameCorner) * short).fill()
            c.restoreGState()
        }
        c.addPath(UIBezierPath(roundedRect: photo, cornerRadius: CGFloat(pl.photoCorner) * short).cgPath)
        c.clip()
        c.interpolationQuality = .high
        UIImage(cgImage: image).draw(in: drawRect(image, source: pl.source, photo: photo))
        c.restoreGState()
    }

    /// Lage des ganzen Fotos, sodass `source` genau die Fotofläche füllt – Breite und Höhe mit demselben Faktor.
    static func drawRect(_ image: CGImage, source: NormRect, photo: CGRect) -> CGRect {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let k = photo.width / max(CGFloat(source.width) * iw, 0.0001)
        return CGRect(x: photo.minX - CGFloat(source.left) * iw * k, y: photo.minY - CGFloat(source.top) * ih * k,
                      width: iw * k, height: ih * k)
    }

    static func rect(_ r: NormRect, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: CGFloat(r.left) * w, y: CGFloat(r.top) * h, width: CGFloat(r.width) * w, height: CGFloat(r.height) * h)
    }

    private func drawBackground(_ project: CollageProject, oriented: [Int: CGImage], in c: CGContext, width w: CGFloat,
                                height h: CGFloat) {
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        Self.uiColor(project.background.color).setFill()
        c.fill(full)
        guard project.background.kind == .blur, !project.items.isEmpty else { return }
        let index = min(max(project.background.blurIndex, 0), project.items.count - 1)
        guard let src = oriented[index], let blurred = blurredFill(src, width: w, height: h) else { return }
        UIImage(cgImage: blurred).draw(in: full)
    }

    /// Foto füllend (beschnitten, nie gestreckt) und weichgezeichnet.
    private func blurredFill(_ image: CGImage, width w: CGFloat, height h: CGFloat) -> CGImage? {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0 else { return nil }
        let s = max(w / iw, h / ih)
        let tx = (w - iw * s) / 2, ty = (h - ih * s) / 2
        let scaled = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: s, y: s).concatenating(
            CGAffineTransform(translationX: tx, y: ty)))
        let radius = Double(min(w, h) * Self.blurFraction)
        let blurred = scaled.clampedToExtent().applyingGaussianBlur(sigma: radius)
        return context.createCGImage(blurred, from: CGRect(x: 0, y: 0, width: w, height: h))
    }

    // MARK: Quellen

    /// Aufrechte Fassung (Ausrichtung des `UIImage` eingerechnet).
    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard size.width >= 1, size.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// Vierteldrehungen im Uhrzeigersinn, danach waagerecht spiegeln – für Vorschau und Export dieselbe Funktion.
    static func oriented(_ image: CGImage, quarterTurns: Int, flipH: Bool) -> CGImage {
        let q = ((quarterTurns % 4) + 4) % 4
        guard q != 0 || flipH else { return image }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let out = q % 2 == 0 ? CGSize(width: w, height: h) : CGSize(width: h, height: w)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: out, format: format).image { drawing in
            let c = drawing.cgContext
            c.translateBy(x: out.width / 2, y: out.height / 2)
            if flipH { c.scaleBy(x: -1, y: 1) }
            c.rotate(by: CGFloat(q) * .pi / 2)
            UIImage(cgImage: image).draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
        return rendered.cgImage ?? image
    }

    static func uiColor(_ argb: ARGB) -> UIColor {
        let c = ARGBColor.components(argb)
        return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
    }
}
