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
            let cellWidth = geo.size.width / CGFloat(game.width)
            let cellHeight = geo.size.height / CGFloat(game.height)
            ZStack(alignment: .topLeading) {
                AppColors.warm.opacity(0.45)
                Canvas { context, _ in
                    var lines = Path()
                    for x in 0...game.width {
                        lines.move(to: CGPoint(x: CGFloat(x) * cellWidth, y: 0))
                        lines.addLine(to: CGPoint(x: CGFloat(x) * cellWidth, y: CGFloat(game.height) * cellHeight))
                    }
                    for y in 0...game.height {
                        lines.move(to: CGPoint(x: 0, y: CGFloat(y) * cellHeight))
                        lines.addLine(to: CGPoint(x: CGFloat(game.width) * cellWidth, y: CGFloat(y) * cellHeight))
                    }
                    context.stroke(lines, with: .color(AppColors.surfaceStroke), lineWidth: 0.5)
                }
                ForEach(Array(game.body.enumerated()), id: \.offset) { index, point in
                    tile(index == 0 || strip.isEmpty ? nil : strip[(index - 1) % strip.count], head: index == 0)
                        .frame(width: max(1, cellWidth - 2), height: max(1, cellHeight - 2))
                        .position(x: (CGFloat(point.x) + 0.5) * cellWidth, y: (CGFloat(point.y) + 0.5) * cellHeight)
                }
                if let food = game.food {
                    tile(foodPicture, head: false)
                        .overlay { RoundedRectangle(cornerRadius: 3).stroke(AppColors.accent, lineWidth: 2) }
                        .frame(width: max(1, cellWidth - 2), height: max(1, cellHeight - 2))
                        .position(x: (CGFloat(food.x) + 0.5) * cellWidth, y: (CGFloat(food.y) + 0.5) * cellHeight)
                }
            }
            .frame(width: CGFloat(game.width) * cellWidth, height: CGFloat(game.height) * cellHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(key: "snake_board"))
        .accessibilityValue(Text(verbatim: boardDescription))
    }

    private var boardDescription: String {
        guard let head = game.body.first, let food = game.food else { return L("snake_won") }
        let direction = game.nextDirection
        let title: String
        switch direction {
        case .up: title = L("snake_up")
        case .right: title = L("snake_right")
        case .down: title = L("snake_down")
        case .left: title = L("snake_left")
        }
        var x = head.x, y = head.y
        switch direction { case .up: y -= 1; case .right: x += 1; case .down: y += 1; case .left: x -= 1 }
        let wall = game.mode == .classic && (x < 0 || x >= game.width || y < 0 || y >= game.height)
        let next = PhotoSnakeGame.Cell((x + game.width) % game.width, (y + game.height) % game.height)
        let body = next == food ? game.body[...] : game.body.dropLast()
        let blocked = wall || body.contains(next)
        return L("snake_board_position", head.x + 1, head.y + 1, food.x + 1, food.y + 1) + ". " +
            title + ". " + L(blocked ? "snake_obstacle" : "snake_clear_path")
    }

    private func tile(_ id: String?, head: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                (head ? AppColors.accentFill : AppColors.warm)
                if head {
                    Image(systemName: "camera.fill").resizable().scaledToFit().foregroundStyle(.white)
                        .rotationEffect(.degrees(headAngle)).padding(min(4, geo.size.width * 0.15))
                } else if let id, let image = images[id] {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                } else if let id {
                    Image(systemName: PhotoMemoryModel.motifs.contains(id) ? id : "photo")
                        .resizable().scaledToFit().foregroundStyle(AppColors.accent).padding(min(4, geo.size.width * 0.15))
                }
            }
            .clipShape(.rect(cornerRadius: 3))
        }
    }

    private var headAngle: Double {
        switch game.direction { case .right: 0; case .down: 90; case .left: 180; case .up: -90 }
    }
}
