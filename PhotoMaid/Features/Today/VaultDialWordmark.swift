import SwiftUI
import UIKit

/// Seitentitel der Startseite: „PhotoMaid“, das erste „o“ ist ein kleines Tresor-Drehrad – zugleich der versteckte
/// Eingang zum Tresor (E16, Nutzerwunsch 21.10.2026 statt „Heute“). 2 Sekunden halten öffnet einen eingerichteten
/// Tresor; dabei dreht sich das Rad wie ein Zahlenschloss. Ohne Tresor bleibt es ein ruhiges „o“ und nichts passiert.
/// Der Markenname bleibt in jeder Sprache und Schreibrichtung gleich (links nach rechts).
struct VaultDialWordmark: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn: Double = 0
    @State private var turning: Task<Void, Never>?

    /// Schrift wie `AppTypography.largeTitle`; daraus Größe und Strichstärke des „o“.
    private var titleFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .largeTitle,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize)))
        return .systemFont(ofSize: base.pointSize, weight: .bold)
    }

    var body: some View {
        let font = titleFont
        let dial = font.xHeight * 1.04
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "Ph")
            VaultDial(turn: turn, stroke: font.pointSize * 0.1)
                .frame(width: dial, height: dial)
                .padding(.horizontal, font.pointSize * 0.035)
                // Wie ein gesetztes „o“ reicht das Rad minimal unter die Grundlinie.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - dial * 0.02 }
            Text(verbatim: "toMaid")
        }
        .font(AppTypography.largeTitle)
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
            if turn != 0 { withAnimation(.spring(duration: 0.4)) { turn = 0 } }
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

/// Das „o“ als Drehrad: Ring in Buchstabenstärke, kurzer Zeiger und Nabe. Nur Zeichnung, keine eigene Bedienung.
private struct VaultDial: View {
    var turn: Double
    var stroke: CGFloat

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let inner = d / 2 - stroke
            ZStack {
                Circle().inset(by: stroke / 2).stroke(lineWidth: stroke)
                Capsule()
                    .frame(width: stroke * 0.45, height: inner * 0.55)
                    .offset(y: -inner * (1 - 0.55 / 2))
                    .rotationEffect(.degrees(turn))
                Circle().frame(width: stroke * 0.6, height: stroke * 0.6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
