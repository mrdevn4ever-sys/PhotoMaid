import SwiftUI
import UIKit

/// Seitentitel der Startseite: „PhotoMaid“, das erste „o“ ist ein kleines Zahlenschloss-Rad (`CombinationDial`) –
/// zugleich der versteckte Eingang zum Tresor (E16, Nutzerwunsch 21.10.2026 statt „Heute“). 2 Sekunden halten öffnet
/// einen eingerichteten Tresor; dabei dreht sich das Rad links, rechts, links und klickt wie ein Zahlenschloss.
/// Ohne Tresor bleibt es ein ruhiges „o“ und nichts passiert.
/// Der Markenname bleibt in jeder Sprache und Schreibrichtung gleich (links nach rechts).
/// Experiment-Design: Maße wie im Artefakt (Bricolage 800, 40 pt; Rad 23/40 der Schriftgröße).
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
        let dial = size * 23 / 40
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "Ph")
            CombinationDial(rotation: turn)
                .frame(width: dial, height: dial)
                .padding(.horizontal, size / 40)
                // Wie ein gesetztes „o“ reicht das Rad minimal unter die Grundlinie.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - size / 40 }
            Text(verbatim: "toMaid")
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
