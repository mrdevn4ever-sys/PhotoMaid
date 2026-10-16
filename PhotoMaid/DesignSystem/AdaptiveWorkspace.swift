import SwiftUI

/// Window measurements include SwiftUI's per-edge safe areas; never infer a viewport from a device model.
enum AppWorkspace {
    static func isWide(_ size: CGSize, accessibility: Bool = false) -> Bool {
        size.width >= 580 && size.height >= 400 && !accessibility
    }
}

/// Two content groups stay in the same view hierarchy when the window grows or folds.
struct WorkspaceColumns: Layout {
    var accessibility = false
    var spacing: CGFloat = AppSpacing.xl

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let wide = width >= 548 && !accessibility && subviews.count == 2
        let column = wide ? (width - spacing) / 2 : width
        let sizes = subviews.map { $0.sizeThatFits(.init(width: column, height: nil)) }
        return CGSize(width: width, height: wide ? sizes.map(\.height).max() ?? 0 : sizes.reduce(0) { $0 + $1.height } + CGFloat(max(0, sizes.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let wide = bounds.width >= 548 && !accessibility && subviews.count == 2
        let width = wide ? (bounds.width - spacing) / 2 : bounds.width
        var y = bounds.minY
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + (wide ? CGFloat(index) * (width + spacing) : 0), y: wide ? bounds.minY : y),
                       anchor: .topLeading, proposal: .init(width: width, height: nil))
            if !wide { y += view.sizeThatFits(.init(width: width, height: nil)).height + spacing }
        }
    }
}

/// Maintains the same child identity while controls move beside a preview on an expanded display.
struct AdaptiveWorkspace<Primary: View, Controls: View>: View {
    var controlsWidth: CGFloat = 280
    @ViewBuilder var primary: Primary
    @ViewBuilder var controls: Controls
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        GeometryReader { geo in
            let wide = AppWorkspace.isWide(geo.size, accessibility: dynamicType.isAccessibilitySize)
            let layout = wide ? AnyLayout(HStackLayout(spacing: AppSpacing.l)) : AnyLayout(VStackLayout(spacing: AppSpacing.s))
            layout {
                primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                controls.frame(width: wide ? min(controlsWidth, geo.size.width * 0.38) : nil)
            }
        }
    }
}

private struct ReadableContent: ViewModifier {
    let maximum: CGFloat
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(AppSpacing.l, (width - maximum) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    /// Keeps forms and history readable while media canvases use the entire window.
    func readableContent(maximum: CGFloat = 760) -> some View { modifier(ReadableContent(maximum: maximum)) }
}
