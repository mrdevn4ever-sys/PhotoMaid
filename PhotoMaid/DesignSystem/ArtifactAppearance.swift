import UIKit

/// Experiment-Design: UIKit-Bestandteile (Navigationsleisten, Segmente, Schalter) im Look des Artefakts, damit auch
/// Ansichten ohne eigenes Layout (Formulare, Unterseiten) dieselbe Schrift und Farbe tragen.
@MainActor
enum ArtifactAppearance {
    static func apply() {
        // Dunkel wie im Artefakt, hell im selben warmen Stil (gleiche Werte wie `AppColors`).
        let text = UIColor.dynamic(dark: 0xF4EFE8, light: 0x1C1916)
        let accent = UIColor.dynamic(dark: 0xF2B24C, light: 0x9A600E)
        let ground = UIColor.dynamic(dark: 0x0F0E0D, light: 0xF6F2EC)

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
        segments.backgroundColor = UIColor.dynamic(dark: 0x1B1917, light: 0xFFFFFF)
        segments.selectedSegmentTintColor = UIColor.dynamic(dark: 0x2F2B28, light: 0xEFE8DF)
        segments.setTitleTextAttributes([.foregroundColor: UIColor.dynamic(dark: 0xA89F94, light: 0x6F665C),
                                         .font: PMFont.uiText(.semibold, 14)],
                                        for: .normal)
        segments.setTitleTextAttributes([.foregroundColor: text, .font: PMFont.uiText(.semibold, 14)], for: .selected)

        UISwitch.appearance().onTintColor = UIColor.dynamic(dark: 0x8FD9A8, light: 0x34A065)
    }
}
