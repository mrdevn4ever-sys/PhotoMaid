import SwiftUI

/// Zahlenschloss-Rad wie an einem Tresor (Nutzerwunsch 21.10.2026): Chromrand, schwarze Skala mit 100 Teilstrichen
/// (klein 50) und Zahlen (erst ab 60 pt lesbar), Chromring und gewölbter Chromknopf, oben eine feste Bernstein-Marke.
/// `rotation` dreht nur die Skala – Licht und Knopf bleiben, wie bei einem echten Rad. Ein physisches Objekt: gleiche
/// Farben in hell und dunkel, mit dunkler Kante für hellen Grund. Nur Zeichnung, keine eigene Bedienung.
struct CombinationDial: View {
    var rotation: Double = 0

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = d / 2
            let detailed = d >= 60
            ZStack {
                // Chromrand (fest; Lichtreflexe wandern nicht mit).
                Circle().fill(AngularGradient(colors: Self.chrome, center: .center, angle: .degrees(-20)))
                Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: max(0.5, r * 0.02))
                // Schwarze Skala mit Teilstrichen und Zahlen – dreht sich.
                Canvas { context, size in
                    Self.drawFace(in: &context, size: size, detailed: detailed)
                }
                .frame(width: d * 0.86, height: d * 0.86)
                .rotationEffect(.degrees(rotation))
                // Innerer Chromring (hohl: Licht von unten rechts) und dunkle Fuge.
                Circle()
                    .fill(LinearGradient(colors: [Self.c(0x4A4A48), Self.c(0xBDBDBB), Self.c(0xF7F7F5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: d * (detailed ? 0.48 : 0.54), height: d * (detailed ? 0.48 : 0.54))
                Circle().fill(Self.c(0x0B0B0B))
                    .frame(width: d * (detailed ? 0.36 : 0.42), height: d * (detailed ? 0.36 : 0.42))
                // Gewölbter Knopf (Licht von oben links).
                Circle()
                    .fill(RadialGradient(colors: [.white, Self.c(0xDCDCDA), Self.c(0x8E8E8C), Self.c(0x4C4C4A)],
                                         center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: d * 0.24))
                    .frame(width: d * (detailed ? 0.31 : 0.36), height: d * (detailed ? 0.31 : 0.36))
                    .shadow(color: .black.opacity(0.5), radius: d * 0.02, y: d * 0.012)
                // Feste Marke oben.
                Path { p in
                    let w = d * (detailed ? 0.07 : 0.12), h = d * (detailed ? 0.06 : 0.09)
                    p.move(to: CGPoint(x: r - w / 2, y: 0))
                    p.addLine(to: CGPoint(x: r + w / 2, y: 0))
                    p.addLine(to: CGPoint(x: r, y: h))
                    p.closeSubpath()
                }
                .fill(AppColors.accentFill)
            }
            .frame(width: d, height: d)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private static let chrome: [Color] = [0xF4F4F2, 0x9C9C9A, 0xE6E6E4, 0x6F6F6D, 0xD8D8D6, 0x8A8A88, 0xF4F4F2].map(c)

    nonisolated private static func c(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Skala: 0 oben, im Uhrzeigersinn bis 99. Groß 100 Striche (lang je 10, mittel je 5) und Zahlen je 10;
    /// klein 50 Striche (lang je 10 Einheiten), ohne Zahlen.
    private static func drawFace(in context: inout GraphicsContext, size: CGSize, detailed: Bool) {
        let r = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [c(0x1E1E1E), c(0x050505)]), center: center,
                                           startRadius: 0, endRadius: r))
        let step = detailed ? 1 : 2
        let tickColor = Color.white.opacity(0.92)
        for unit in stride(from: 0, to: 100, by: step) {
            let major = unit % 10 == 0, mid = unit % 5 == 0
            let length = r * (detailed ? (major ? 0.2 : mid ? 0.14 : 0.09) : (major ? 0.3 : 0.17))
            let width = r * (detailed ? (major ? 0.022 : 0.014) : (major ? 0.06 : 0.035))
            let angle = Double(unit) / 100 * 2 * .pi
            let outer = r * 0.95
            let dir = CGPoint(x: sin(angle), y: -cos(angle))
            var tick = Path()
            tick.move(to: CGPoint(x: center.x + dir.x * outer, y: center.y + dir.y * outer))
            tick.addLine(to: CGPoint(x: center.x + dir.x * (outer - length), y: center.y + dir.y * (outer - length)))
            context.stroke(tick, with: .color(tickColor), lineWidth: max(0.35, width))
        }
        guard detailed else { return }
        for unit in stride(from: 0, to: 100, by: 10) {
            let angle = Double(unit) / 100 * 2 * .pi
            let radius = r * 0.665
            var label = context
            label.translateBy(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
            label.rotate(by: .radians(angle))
            label.draw(Text(verbatim: String(unit)).font(.system(size: r * 0.14, weight: .semibold, design: .rounded))
                .foregroundStyle(tickColor), at: .zero, anchor: .center)
        }
    }
}
