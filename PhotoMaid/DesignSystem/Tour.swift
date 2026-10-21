import SwiftUI
import UIKit

/// Ziel eines Rundgangschritts: ein markiertes Element oder ein Tab der unteren Leiste.
enum TourTarget: Equatable {
    case anchor(String)
    /// Index in der Tableiste, Titel-Kennung und Symbol (wie in `RootView`).
    case tab(Int, titleKey: String, symbol: String)
    case none
}

struct TourStep: Equatable {
    let titleKey: String
    let textKey: String
    let target: TourTarget
}

/// Rahmen der markierten Elemente (Kennung → Anker).
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Markiert ein Element als Ziel eines Rundgangschritts.
    func tourTarget(_ id: String) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Zeigt den aktiven Schritt: Element hervorgehoben, Karte mit Pfeil direkt daneben. Abdunkelung blockiert die
    /// Bedienung nicht. Ohne auffindbares Ziel steht die Karte unten.
    @MainActor
    func tourOverlay(step: TourStep?, isLast: Bool, next: @escaping () -> Void, skip: @escaping () -> Void) -> some View {
        overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if let step {
                GeometryReader { proxy in
                    TourSpotlight(target: Self.frame(of: step.target, anchors: anchors, in: proxy), step: step,
                                  isLast: isLast, size: proxy.size, next: next, skip: skip)
                }
                .ignoresSafeArea()
            }
        }
    }

    @MainActor
    private static func frame(of target: TourTarget, anchors: [String: Anchor<CGRect>], in proxy: GeometryProxy) -> CGRect? {
        switch target {
        case .anchor(let id):
            guard let anchor = anchors[id] else { return nil }
            let rect = proxy[anchor]
            return rect.isEmpty ? nil : rect
        case .tab(let index, _, _):
            guard let window = TabBarGeometry.itemFrame(index: index) else { return nil }
            let origin = proxy.frame(in: .global).origin
            return window.offsetBy(dx: -origin.x, dy: -origin.y)
        case .none:
            return nil
        }
    }
}

private struct TourSpotlight: View {
    let target: CGRect?
    let step: TourStep
    let isLast: Bool
    let size: CGSize
    let next: () -> Void
    let skip: () -> Void

    private let gap: CGFloat = 14

    var body: some View {
        let spot = target?.insetBy(dx: -8, dy: -8)
        let below = spot.map { $0.midY < size.height * 0.5 } ?? false
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                if let spot { p.addRoundedRect(in: spot, cornerSize: CGSize(width: 14, height: 14)) }
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if let spot {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppColors.accent, lineWidth: 2)
                    .frame(width: spot.width, height: spot.height)
                    .offset(x: spot.minX, y: spot.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                TourArrow(pointsUp: below)
                    .fill(AppColors.surface)
                    .frame(width: 22, height: 11)
                    .offset(x: min(max(spot.midX - 11, 24), size.width - 46),
                            y: below ? spot.maxY + gap - 11 : spot.minY - gap)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            card
                .padding(.top, spot.map { below ? $0.maxY + gap : 0 } ?? 0)
                .padding(.bottom, spot.map { below ? 0 : size.height - $0.minY + gap } ?? 120)
                .frame(width: size.width, height: size.height,
                       alignment: spot == nil ? .bottom : (below ? .top : .bottom))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            if case .tab(_, let titleKey, let symbol) = step.target {
                Label { Text(key: titleKey) } icon: { Image(systemName: symbol) }
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
            }
            Text(key: step.titleKey).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
            Text(key: step.textKey).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if !isLast {
                    Button(action: skip) { Text(key: "tour_skip") }.frame(minHeight: AppSpacing.minTouch)
                }
                Spacer()
                Button(action: next) { Text(key: isLast ? "done" : "tour_next") }
                    .buttonStyle(.pmProminent)
            }
        }
        .padding(AppSpacing.m)
        .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .padding(.horizontal, AppSpacing.pageMargin)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Kleines Dreieck zwischen Karte und Ziel.
private struct TourArrow: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointsUp {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// Lage der Tab-Schaltflächen in Fensterkoordinaten (öffentliche UIKit-API: Rahmen der `UITabBar`, Einträge
/// gleichmäßig verteilt). Ohne Tableiste `nil` – die Karte steht dann unten.
@MainActor
enum TabBarGeometry {
    static func itemFrame(index: Int) -> CGRect? {
        // Experiment-Design: eigene schwebende Tableiste.
        if let own = PMTabBarFrames.frames[index], own.width > 0 { return own }
        guard let bar = tabBar(), !bar.isHidden, bar.alpha > 0.01,
              let count = bar.items?.count, count > 0, (0..<count).contains(index) else { return nil }
        let frame = bar.convert(bar.bounds, to: nil)
        guard frame.width > 0, frame.height > 0 else { return nil }
        let width = frame.width / CGFloat(count)
        return CGRect(x: frame.minX + CGFloat(index) * width, y: frame.minY, width: width, height: frame.height)
    }

    private static func tabBar() -> UITabBar? {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows where window.isKeyWindow {
                if let controller = tabBarController(in: window.rootViewController) { return controller.tabBar }
            }
        }
        return nil
    }

    private static func tabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let found = tabBarController(in: child) { return found }
        }
        return nil
    }
}
