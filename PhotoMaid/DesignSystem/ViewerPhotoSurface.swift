import SwiftUI

/// Gemeinsame Fotobühne für Fotos und Tresor. Die Quelle bleibt beim jeweiligen
/// Betrachter: Tresor-Inhalte werden nie über PhotoKit oder den Feed geladen.
struct ViewerPhotoSurface: View {
    let image: UIImage
    let size: CGSize
    let isCurrent: Bool
    @Binding var zoomed: Bool
    let toggleChrome: () -> Void
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(zoom)
            .offset(pan)
            .frame(width: size.width, height: size.height)
            .contentShape(.rect)
            .gesture(MagnifyGesture()
                .onChanged { value in
                    zoom = min(6, max(1, zoomBase * value.magnification))
                    zoomed = zoom > 1.01
                }
                .onEnded { _ in zoomBase = zoom; if zoom <= 1.01 { reset() } })
            .simultaneousGesture(DragGesture()
                .onChanged { value in
                    pan = CGSize(width: panBase.width + value.translation.width, height: panBase.height + value.translation.height)
                }
                .onEnded { _ in panBase = pan }, including: zoom > 1.01 ? .all : .none)
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    if zoom > 1.01 { reset() }
                    else { zoom = 2.5; zoomBase = 2.5; zoomed = true }
                }
            }
            .onTapGesture { toggleChrome() }
            .clipped()
            .accessibilityHint(Text(key: "viewer_controls_hint"))
            .accessibilityValue(Text(verbatim: Double(zoom).formatted(.percent.precision(.fractionLength(0)))))
            .accessibilityAction(named: Text(key: "viewer_toggle_controls"), toggleChrome)
            .onChange(of: isCurrent) { _, current in if !current { reset() } }
            .onChange(of: size) { _, _ in reset() }
    }

    private func reset() {
        zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero; zoomed = false
    }
}
