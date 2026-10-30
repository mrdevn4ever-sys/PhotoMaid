import SwiftUI
import UIKit

/// Seitentitel der Startseite: der Produktname (`AppConfig.brandName`, „GaleriQ“), sein großes „Q“ ist ein
/// Zahlenschloss-Rad (`CombinationDial`) mit Q-Schweif (Nutzerwunsch 30.10.2026) – zugleich der versteckte Eingang zum
/// Tresor (E16, Nutzerwunsch 21.10.2026 statt „Heute“; vorher im „o“ von „PhotoMaid“/„Arrumo“). 2 Sekunden halten öffnet
/// einen eingerichteten Tresor; dabei dreht sich das Rad links, rechts, links und klickt wie ein Zahlenschloss.
/// Ohne Tresor bleibt es ein ruhiges „Q“ und nichts passiert.
/// Der Markenname bleibt in jeder Sprache und Schreibrichtung gleich (links nach rechts).
/// Experiment-Design: Bricolage 800, 40 pt; als „Q“ hat das Rad Versalhöhe (29/40), als „o“ x-Höhe (23/40).
struct VaultDialWordmark: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn: Double = 0
    @State private var turning: Task<Void, Never>?

    /// Schriftgröße wie `AppTypography.largeTitle` (40 pt bei Standardgröße, mit Dynamic Type skaliert).
    private var pointSize: CGFloat {
        UIFontMetrics(forTextStyle: .largeTitle)
            .scaledValue(for: 40, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize)))
    }

    var body: some View {
        let size = pointSize
        let parts = Self.parts
        let dial = size * (parts.capital ? 29 : 23) / 40
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: parts.before)
            CombinationDial(rotation: turn)
                .frame(width: dial, height: dial)
                .overlay {
                    if parts.capital {
                        // Schweif des „Q“: schräg über den Rand nach rechts unten, mit Fuge in Hintergrundfarbe.
                        ZStack {
                            QTail().stroke(AppColors.background, style: StrokeStyle(lineWidth: size * 0.21, lineCap: .round))
                            QTail().stroke(AppColors.textPrimary, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round))
                        }
                    }
                }
                .padding(.leading, size / 40)
                .padding(.trailing, parts.capital ? dial * 0.2 : size / 40)
                // Wie ein gesetzter runder Buchstabe reicht das Rad minimal unter die Grundlinie.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - size / 40 }
            if !parts.after.isEmpty { Text(verbatim: parts.after) }
        }
        .font(AppTypography.largeTitle)
        .tracking(-0.02 * size)
        .foregroundStyle(AppColors.textPrimary)
        .lineLimit(1)
        .fixedSize()
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L("app_name")))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.title")
        .onLongPressGesture(minimumDuration: 2) {
            if VaultStore.shared.openFromHiddenEntry() { Haptics.commit() }
        } onPressingChanged: { down in
            pressing(down)
        }
    }

    /// Name vor und nach dem Buchstaben, an dessen Stelle das Rad steht: das große „Q“, sonst das erste „o“, sonst am Ende.
    private static var parts: (before: String, after: String, capital: Bool) {
        let name = AppConfig.brandName
        if let q = name.range(of: "Q") {
            return (String(name[..<q.lowerBound]), String(name[q.upperBound...]), true)
        }
        guard let o = name.range(of: "o") else { return (name, "", false) }
        return (String(name[..<o.lowerBound]), String(name[o.upperBound...]), false)
    }

    private func pressing(_ down: Bool) {
        turning?.cancel()
        turning = nil
        guard down, VaultStore.shared.isSetUp else {
            if turn != 0 { withAnimation(.spring(duration: 0.45, bounce: 0.35)) { turn = 0 } }
            return
        }
        turning = Task {
            // Wie ein Zahlenschloss: links über eine volle Umdrehung, rechts, links – zusammen unter den 2 Sekunden bis
            // zum Öffnen. Unterwegs klickt es etwa alle 30°, an jedem Richtungswechsel rastet es spürbar ein.
            var current = 0.0
            for (angle, seconds) in [(-400.0, 0.65), (-130.0, 0.55), (-290.0, 0.45)] {
                if !reduceMotion { withAnimation(.easeInOut(duration: seconds)) { turn = angle } }
                let clicks = max(1, Int(abs(angle - current) / 30))
                for _ in 0..<clicks {
                    try? await Task.sleep(for: .seconds(seconds / Double(clicks)))
                    guard !Task.isCancelled else { return }
                    Haptics.tick()
                }
                current = angle
                Haptics.threshold()
            }
        }
    }
}

/// Schweif des „Q“ im Rahmen des Rads: kurz und kräftig, setzt am Rand unten rechts an und läuft flach nach außen –
/// wie in der Schrift, nicht wie der Stiel einer Lupe (erste Fassung vom Rad-Inneren aus wirkte so).
private struct QTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 1.08, y: rect.minY + rect.height * 1.00))
        return path
    }
}
