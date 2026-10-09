import UIKit

/// Haptik nur bei echten Ereignissen (Entscheidung gespeichert, Schwelle erreicht, Fehler). Abschaltbar in den
/// Einstellungen; Systemeinstellung „Haptik“ gilt ohnehin.
@MainActor
enum Haptics {
    static var enabled = true

    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    /// Geste hat die Commit-Schwelle erreicht (einmal je Überschreiten).
    static func threshold() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.7)
    }

    /// Entscheidung gespeichert.
    static func commit() {
        guard enabled else { return }
        medium.impactOccurred(intensity: 0.8)
    }

    static func tick() {
        guard enabled else { return }
        selection.selectionChanged()
    }

    static func success() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        notification.notificationOccurred(.warning)
    }

    static func error() {
        guard enabled else { return }
        notification.notificationOccurred(.error)
    }

    /// Anschlag am Anfang des Feeds („runter“ ohne vorheriges Medium).
    static func boundary() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.4)
    }
}
