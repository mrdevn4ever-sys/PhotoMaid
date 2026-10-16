import PhotoMaidCore
import SwiftUI
import UIKit

/// Only the discrete game tick redraws the strip; no display-link, network or image work happens here.
struct PhotoSnakeBoard: View {
    let game: PhotoSnakeGame
    let strip: [String]
    let foodPicture: String
    let images: [String: UIImage]

    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(game.width), geo.size.height / CGFloat(game.height))
            ZStack(alignment: .topLeading) {
                AppColors.surface
                Canvas { context, _ in
                    var lines = Path()
                    for x in 0...game.width {
                        lines.move(to: CGPoint(x: CGFloat(x) * cell, y: 0))
                        lines.addLine(to: CGPoint(x: CGFloat(x) * cell, y: CGFloat(game.height) * cell))
                    }
                    for y in 0...game.height {
                        lines.move(to: CGPoint(x: 0, y: CGFloat(y) * cell))
                        lines.addLine(to: CGPoint(x: CGFloat(game.width) * cell, y: CGFloat(y) * cell))
                    }
                    context.stroke(lines, with: .color(AppColors.surfaceStroke), lineWidth: 0.5)
                }
                ForEach(Array(game.body.enumerated()), id: \.offset) { index, point in
                    tile(index == 0 || strip.isEmpty ? nil : strip[(index - 1) % strip.count], head: index == 0)
                        .frame(width: max(1, cell - 2), height: max(1, cell - 2))
                        .position(x: (CGFloat(point.x) + 0.5) * cell, y: (CGFloat(point.y) + 0.5) * cell)
                }
                if let food = game.food {
                    tile(foodPicture, head: false)
                        .overlay { RoundedRectangle(cornerRadius: 3).stroke(AppColors.accent, lineWidth: 2) }
                        .frame(width: max(1, cell - 2), height: max(1, cell - 2))
                        .position(x: (CGFloat(food.x) + 0.5) * cell, y: (CGFloat(food.y) + 0.5) * cell)
                }
            }
            .frame(width: CGFloat(game.width) * cell, height: CGFloat(game.height) * cell)
            .clipShape(.rect(cornerRadius: AppRadii.small))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(key: "snake_board"))
        .accessibilityValue(Text(verbatim: boardDescription))
    }

    private var boardDescription: String {
        guard let head = game.body.first, let food = game.food else { return L("snake_won") }
        return L("snake_board_position", head.x + 1, head.y + 1, food.x + 1, food.y + 1)
    }

    private func tile(_ id: String?, head: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                (head ? AppColors.accentFill : AppColors.warm)
                if head {
                    Image(systemName: "camera.fill").resizable().scaledToFit().foregroundStyle(.white).padding(4)
                } else if let id, let image = images[id] {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                } else if let id {
                    Image(systemName: PhotoMemoryModel.motifs.contains(id) ? id : "photo")
                        .resizable().scaledToFit().foregroundStyle(AppColors.accent).padding(4)
                }
            }
            .clipShape(.rect(cornerRadius: 3))
        }
    }
}
