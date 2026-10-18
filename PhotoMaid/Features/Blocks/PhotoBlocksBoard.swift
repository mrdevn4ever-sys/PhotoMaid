import PhotoMaidCore
import SwiftUI
import UIKit

enum PhotoBlocksPalette {
    static let ink = Color(red: 0.035, green: 0.06, blue: 0.085)
    static let accent = Color(red: 0.48, green: 0.88, blue: 0.78)
    static func color(_ shape: PhotoBlocksShape) -> Color {
        switch shape {
        case .pebble: Color(red: 0.35, green: 0.76, blue: 0.76)
        case .shoot: Color(red: 0.75, green: 0.64, blue: 0.91)
        case .arch: Color(red: 0.94, green: 0.65, blue: 0.48)
        case .petal: Color(red: 0.68, green: 0.81, blue: 0.48)
        case .bough: Color(red: 0.43, green: 0.66, blue: 0.91)
        case .fern: Color(red: 0.91, green: 0.53, blue: 0.66)
        }
    }
}

struct PhotoBlocksBoard: View {
    let game: PhotoBlocksGame
    let image: UIImage?
    let onActions: ([PhotoBlocksInput.Action]) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(game.width)
            ZStack(alignment: .top) {
                PhotoBlocksPalette.ink
                photo(size: geo.size)
                    // This mask is in photo coordinates, entirely independent of the block grid.
                    .mask(alignment: .top) {
                        Rectangle().frame(height: geo.size.height * PhotoBlocksPhotos.revealedHeight(strips: game.revealedStrips))
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: game.revealedStrips)
                    .id(game.level) // New photos start at their carried progress; never animate backwards from 100%.
                if game.phase != .discovered {
                    Canvas { context, size in
                        let visible = !game.isPaused && game.phase != .gameOver
                        if visible {
                            var grid = Path()
                            for x in 1..<game.width {
                                grid.move(to: CGPoint(x: CGFloat(x) * cell, y: 0))
                                grid.addLine(to: CGPoint(x: CGFloat(x) * cell, y: size.height))
                            }
                            for y in 1..<game.height {
                                grid.move(to: CGPoint(x: 0, y: CGFloat(y) * cell))
                                grid.addLine(to: CGPoint(x: size.width, y: CGFloat(y) * cell))
                            }
                            context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
                            if let ghost = game.ghost {
                                for position in ghost.cells { draw(position, shape: ghost.shape, ghost: true, cell: cell, context: context) }
                            }
                        }
                        for y in 0..<game.height {
                            for x in 0..<game.width {
                                if let shape = game.board[y][x] {
                                    var layer = context
                                    if game.clearedRows.contains(y) { layer.opacity = 1 - game.clearFraction }
                                    draw(.init(x, y), shape: shape, cell: cell, context: layer)
                                }
                            }
                        }
                        if let active = game.active {
                            for position in active.cells { draw(position, shape: active.shape, cell: cell, context: context) }
                        }
                        for y in game.clearedRows {
                            let band = CGRect(x: 0, y: CGFloat(y) * cell, width: size.width, height: cell)
                            context.fill(Path(band), with: .color(PhotoBlocksPalette.accent.opacity((1 - game.clearFraction) * 0.35)))
                        }
                    }
                }
                PhotoBlocksTouchView(cellSize: cell, enabled: game.acceptsInput, onActions: onActions)
                    .accessibilityIdentifier("blocks.board")
                    .accessibilityLabel(L("blocks_gestures"))
            }
            .clipShape(.rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.2), lineWidth: 1) }
        }
        .aspectRatio(CGFloat(game.width) / CGFloat(game.height), contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight) // Physical left/right are never mirrored in RTL.
    }

    @ViewBuilder private func photo(size: CGSize) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: game.phase == .discovered ? .fit : .fill)
                    .frame(width: size.width, height: size.height).clipped()
            } else {
                LinearGradient(colors: [Color(red: 0.12, green: 0.29, blue: 0.31), PhotoBlocksPalette.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.white.opacity(0.3))
            }
        }
        .overlay(.black.opacity(game.phase == .discovered ? 0 : 0.55)) // Even pure white stays behind bright block outlines.
        .accessibilityHidden(true)
    }

    private func draw(_ position: PhotoBlocksCell, shape: PhotoBlocksShape, ghost: Bool = false,
                      cell: CGFloat, context: GraphicsContext) {
        let rect = CGRect(x: CGFloat(position.x) * cell + 1.5, y: CGFloat(position.y) * cell + 1.5,
                          width: cell - 3, height: cell - 3)
        let path = Path(roundedRect: rect, cornerRadius: max(3, cell * 0.19))
        let color = PhotoBlocksPalette.color(shape)
        if ghost {
            context.fill(path, with: .color(color.opacity(0.10)))
            context.stroke(path, with: .color(.white.opacity(0.4)), style: .init(lineWidth: 1, dash: [3, 3]))
        } else {
            context.fill(path, with: .linearGradient(.init(colors: [color, color.opacity(0.76)]), startPoint: rect.origin,
                                                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 0.9)
            let glint = CGRect(x: rect.minX + 4, y: rect.minY + 3, width: max(2, rect.width - 8), height: 1.5)
            context.fill(Path(roundedRect: glint, cornerRadius: 0.75), with: .color(.white.opacity(0.32)))
            // A tiny form-specific notch adds a second cue beyond color.
            for dot in 0...shape.rawValue % 3 {
                let mark = CGRect(x: rect.midX - 3 + CGFloat(dot) * 3, y: rect.maxY - 5, width: 1.5, height: 1.5)
                context.fill(Path(ellipseIn: mark), with: .color(.black.opacity(0.4)))
            }
        }
    }
}

struct PhotoBlocksNext: View {
    let shape: PhotoBlocksShape
    var body: some View {
        Canvas { context, size in
            let cells = shape.cells()
            let w = CGFloat((cells.map(\.x).max() ?? 0) + 1), h = CGFloat((cells.map(\.y).max() ?? 0) + 1)
            let unit = min(size.width / w, size.height / h, 12)
            for position in cells {
                let rect = CGRect(x: (size.width - unit * w) / 2 + CGFloat(position.x) * unit + 1,
                                  y: (size.height - unit * h) / 2 + CGFloat(position.y) * unit + 1,
                                  width: unit - 2, height: unit - 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(PhotoBlocksPalette.color(shape)))
            }
        }.frame(width: 44, height: 44).accessibilityHidden(true)
    }
}
