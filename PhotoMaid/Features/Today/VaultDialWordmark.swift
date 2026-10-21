import SwiftUI
import UIKit

/// Seitentitel der Startseite: „PhotoMaid“, das erste „o“ ist ein kleines Tresor-Drehrad – zugleich der versteckte
/// Eingang zum Tresor (E16, Nutzerwunsch 21.10.2026 statt „Heute“). 2 Sekunden halten öffnet einen eingerichteten
/// Tresor; dabei dreht sich das Rad wie ein Zahlenschloss. Ohne Tresor bleibt es ein ruhiges „o“ und nichts passiert.
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
            VaultDial(turn: turn)
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
            // Wie ein Zahlenschloss: rechts, links, rechts – zusammen knapp unter den 2 Sekunden bis zum Öffnen.
            for (angle, seconds) in [(300.0, 0.7), (120.0, 0.6), (210.0, 0.5)] {
                if !reduceMotion { withAnimation(.easeInOut(duration: seconds)) { turn = angle } }
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                Haptics.tick()
            }
        }
    }
}

/// Das „o“ als Drehrad, Geometrie 1:1 aus dem Artefakt (Ansichtsfeld 24: Ring r 9,3 / Strich 5,4, Zeiger 2 × 3,4,
/// Nabe r 1,4). Nur Zeichnung, keine eigene Bedienung.
struct VaultDial: View {
    var turn: Double

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 24
            ZStack {
                Circle().stroke(lineWidth: 5.4 * s).frame(width: 18.6 * s, height: 18.6 * s)
                RoundedRectangle(cornerRadius: s)
                    .frame(width: 2 * s, height: 3.4 * s)
                    .offset(y: -4.7 * s)
                    .rotationEffect(.degrees(turn))
                Circle().frame(width: 2.8 * s, height: 2.8 * s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
