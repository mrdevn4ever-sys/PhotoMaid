import CoreImage
import ImageIO
import PhotoMaidCore
import UIKit
import UniformTypeIdentifiers

final class CollageRenderer: @unchecked Sendable {
    enum Failure: Error { case missingImage, renderFailed, encodeFailed }

    private let context = CIContext()

    func render(project: CollageProject, images: [String: CGImage], longEdge: Int) throws -> CGImage {
        guard !project.items.isEmpty else { throw Failure.missingImage }
        let size = CollageExport.size(aspect: project.aspect, longEdge: CollageExport.clampLong(longEdge))
        let color = UIColor(argb: project.background.color)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width, height: size.height), format: format)
        let output = renderer.image { drawing in
            color.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            let rects = project.cellRects()
            for index in project.items.indices {
                guard let source = images[project.items[index].mediaId] else { continue }
                let normalized = rects[index]
                let cell = CGRect(x: CGFloat(normalized.left) * CGFloat(size.width),
                                  y: CGFloat(normalized.top) * CGFloat(size.height),
                                  width: CGFloat(normalized.width) * CGFloat(size.width),
                                  height: CGFloat(normalized.height) * CGFloat(size.height))
                draw(source, item: project.items[index], in: cell, context: drawing.cgContext)
            }
        }
        guard let result = output.cgImage else { throw Failure.renderFailed }
        return result
    }

    func jpeg(_ image: CGImage, quality: CGFloat = 0.92) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodeFailed }
        return data as Data
    }

    private func draw(_ image: CGImage, item: CollageItem, in cell: CGRect, context: CGContext) {
        let imageAspect = Float(image.width) / Float(max(1, image.height))
        let cellAspect = Float(cell.width / max(1, cell.height))
        let source = CellFit.source(imgAspect: imageAspect, cellAspect: cellAspect, zoom: item.zoom,
                                    panX: item.panX, panY: item.panY, fit: item.fit)
        let crop = CGRect(x: CGFloat(source.left) * CGFloat(image.width),
                          y: CGFloat(source.top) * CGFloat(image.height),
                          width: CGFloat(source.width) * CGFloat(image.width),
                          height: CGFloat(source.height) * CGFloat(image.height)).integral
        guard let cropped = image.cropping(to: crop) else { return }
        context.saveGState()
        context.clip(to: cell)
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: cell.midY * 2)
        context.scaleBy(x: 1, y: -1)
        context.draw(cropped, in: cell)
        context.restoreGState()
    }
}

private extension UIColor {
    convenience init(argb: ARGB) {
        let value = UInt32(truncatingIfNeeded: argb)
        self.init(red: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255,
                  alpha: CGFloat((value >> 24) & 255) / 255)
    }
}
