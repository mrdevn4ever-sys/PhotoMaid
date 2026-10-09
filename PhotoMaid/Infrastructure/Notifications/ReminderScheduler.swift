import Foundation
import Observation
import PhotoMaidCore
import UserNotifications

/// Opt-in-Erinnerungen (Einstellung „Mitteilungen“, Standard aus). Nur „Später ist wieder dran“ – keine Dateinamen,
/// keine Zahlen auf dem Sperrbildschirm. Höchstens `maxPending` geplante Erinnerungen.
@MainActor
@Observable
final class ReminderScheduler {
    enum Access: Equatable { case notDetermined, allowed, denied }
    private(set) var access: Access = .notDetermined
    static let maxPending = 8

    func refresh() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: access = .allowed
        case .denied: access = .denied
        case .notDetermined: access = .notDetermined
        @unknown default: access = .denied
        }
    }

    /// Nur nach ausdrücklicher Nutzeraktion.
    func requestAccess() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    /// Erinnerung an fällige Wiedervorlagen am Termintag (09:00 lokal). Idempotent je Tag.
    func scheduleDueReminder(for day: LocalDay, optedIn: Bool) async {
        guard optedIn, access == .allowed else { return }
        let id = "later.\(day)"
        var comps = DateComponents()
        comps.year = day.year; comps.month = day.month; comps.day = day.day; comps.hour = 9
        let content = UNMutableNotificationContent()
        content.title = L("app_name")
        content.body = L("notif_due_body")
        await add(id: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    /// Alle Später-Erinnerungen entfernen (Mitteilungen ausgeschaltet).
    func removeDueReminders() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("later.") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func add(id: String, content: UNMutableNotificationContent, trigger: UNNotificationTrigger) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard pending.count < Self.maxPending || pending.contains(where: { $0.identifier == id }) else { return }
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
