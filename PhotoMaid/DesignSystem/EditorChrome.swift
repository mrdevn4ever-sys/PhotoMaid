import SwiftUI
import UIKit

/// Editor-Oberfläche wie die Fotos-App: immer dunkel, ✕/✓-Kapseln, große Bühne, schmale Werkzeugzone.

/// Skalenregler (Strichskala, Mitte = 0). Haptik bei 0. Werte ganzzahlig. VoiceOver: anpassbar.
struct EditorRuler: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    @State private var startValue: Float?

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(verbatim: title).font(AppTypography.footnote.weight(.semibold))
                Spacer()
                Text(verbatim: "\(Int(value.rounded()))").font(AppTypography.footnote.monospacedDigit())
            }
            .foregroundStyle(.white)
            GeometryReader { geo in
                let w = geo.size.width
                let span = range.upperBound - range.lowerBound
                ZStack {
                    Canvas { ctx, size in
                        let steps = 40
                        for i in 0...steps {
                            let x = CGFloat(i) / CGFloat(steps) * size.width
                            let major = i % 5 == 0
                            var p = Path()
                            p.move(to: CGPoint(x: x, y: size.height / 2 - (major ? 9 : 5)))
                            p.addLine(to: CGPoint(x: x, y: size.height / 2 + (major ? 9 : 5)))
                            ctx.stroke(p, with: .color(.white.opacity(major ? 0.7 : 0.35)), lineWidth: 1)
                        }
                    }
                    let x = CGFloat((value - range.lowerBound) / span) * w
                    Capsule().fill(Color.yellow).frame(width: 3, height: 28).position(x: x, y: geo.size.height / 2)
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if startValue == nil { startValue = value; onBegin() }
                        let delta = Float(g.translation.width / w) * span
                        let v = min(range.upperBound, max(range.lowerBound, (startValue ?? 0) + delta))
                        if (value < 0 && v >= 0) || (value > 0 && v <= 0) { Haptics.tick() }
                        value = v.rounded()
                    }
                    .onEnded { _ in startValue = nil; onEnd() })
                .onTapGesture(count: 2) { onBegin(); value = 0; onEnd() }
            }
            .frame(height: 36)
            .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: "\(Int(value.rounded()))"))
        .accessibilityAdjustableAction { dir in
            onBegin()
            switch dir {
            case .increment: value = min(range.upperBound, value + 5)
            case .decrement: value = max(range.lowerBound, value - 5)
            @unknown default: break
            }
            onEnd()
        }
    }
}

/// Runder Werkzeugknopf mit Beschriftung (aktiv = hervorgehoben, geändert = Punkt).
struct RoundToolButton: View {
    let symbol: String
    let title: String
    var active = false
    var changed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(active ? Color.white : Color.white.opacity(0.12)).frame(width: 46, height: 46)
                    Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(active ? .black : .white)
                }
                .overlay(alignment: .topTrailing) {
                    if changed { Circle().fill(Color.yellow).frame(width: 8, height: 8) }
                }
                Text(verbatim: title).font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
            .frame(minWidth: 60)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityValue(Text(verbatim: changed ? L("edit_changed") : ""))
    }
}

/// Kapsel-Kopf: ✕ links, Mitte frei, ✓ rechts.
struct EditorHeader<Center: View>: View {
    let cancel: () -> Void
    let confirm: () -> Void
    var confirmEnabled = true
    @ViewBuilder var center: Center

    var body: some View {
        GlassEffectContainer(spacing: AppSpacing.s) {
            HStack {
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.body.weight(.bold)).frame(width: AppSpacing.touch, height: AppSpacing.touch)
                }
                .buttonStyle(.pmBordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text(key: "cancel"))
                Spacer()
                center
                Spacer()
                Button(action: confirm) {
                    Image(systemName: "checkmark").font(.body.weight(.bold)).frame(width: AppSpacing.touch, height: AppSpacing.touch)
                }
                .buttonStyle(.pmProminent)
                .buttonBorderShape(.circle)
                .tint(.yellow)
                .disabled(!confirmEnabled)
                .accessibilityLabel(Text(key: "save"))
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }
}

/// Zwei Finger verändern nur die Ansicht. Ein Finger bleibt für die Werkzeuge frei,
/// auch bei Zoom. Werkzeug-Gesten gehören IN den Inhalt, vor dessen Transformation:
/// SwiftUI liefert ihnen dadurch bildlokale Punkte und Verschiebungen.
struct ZoomableStage<Content: View>: View {
    @Binding var zoom: CGFloat
    @ViewBuilder var content: Content
    @State private var base: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero

    var body: some View {
        content
            .scaleEffect(zoom)
            .offset(pan)
            .simultaneousGesture(MagnifyGesture()
                .onChanged { v in zoom = min(8, max(1, base * v.magnification)) }
                .onEnded { _ in base = zoom; if zoom <= 1.01 { reset() } })
            .gesture(TwoFingerStagePan(changed: { translation in
                guard zoom > 1.01 else { return }
                pan = CGSize(width: panBase.width + translation.width, height: panBase.height + translation.height)
            }, ended: { panBase = pan }))
            .clipped()
            .contentShape(.rect)
    }

    private func reset() {
        zoom = 1; base = 1; pan = .zero; panBase = .zero
    }
}

/// SwiftUI's DragGesture also recognizes a single finger; it would compete with
/// drawing and crop handles. Limit viewport panning to exactly two touches.
struct TwoFingerStagePan: UIGestureRecognizerRepresentable {
    var changed: (CGSize) -> Void
    var ended: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            guard let translation = context.converter.translation(in: .local) else { return }
            changed(CGSize(width: translation.x, height: translation.y))
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true // Two-finger panning and pinching may update the viewport together.
        }
    }
}
