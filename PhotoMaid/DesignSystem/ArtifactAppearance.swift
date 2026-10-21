import UIKit

/// Experiment-Design: UIKit-Bestandteile (Navigationsleisten, Segmente, Schalter) im Look des Artefakts, damit auch
/// Ansichten ohne eigenes Layout (Formulare, Unterseiten) dieselbe Schrift und Farbe tragen.
@MainActor
enum ArtifactAppearance {
    static func apply() {
        let text = UIColor(hex: 0xF4EFE8)
        let accent = UIColor(hex: 0xF2B24C)
        let ground = UIColor(hex: 0x0F0E0D)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = ground
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: text, .font: PMFont.uiText(.semibold, 17)]
        nav.largeTitleTextAttributes = [.foregroundColor: text, .font: PMFont.uiDisplay(40), .kern: -0.8]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.foregroundColor: accent, .font: PMFont.uiText(.semibold, 16)]
        nav.buttonAppearance = button
        nav.backButtonAppearance = button
        nav.doneButtonAppearance = button
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = nav
        bar.scrollEdgeAppearance = nav
        bar.compactAppearance = nav
        bar.tintColor = accent

        let segments = UISegmentedControl.appearance()
        segments.backgroundColor = UIColor(hex: 0x1B1917)
        segments.selectedSegmentTintColor = UIColor(hex: 0x2F2B28)
        segments.setTitleTextAttributes([.foregroundColor: UIColor(hex: 0xA89F94), .font: PMFont.uiText(.semibold, 14)],
                                        for: .normal)
        segments.setTitleTextAttributes([.foregroundColor: text, .font: PMFont.uiText(.semibold, 14)], for: .selected)

        UISwitch.appearance().onTintColor = UIColor(hex: 0x8FD9A8)
    }
}
