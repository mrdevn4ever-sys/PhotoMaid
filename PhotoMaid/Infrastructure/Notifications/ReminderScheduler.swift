import Foundation
import Observation
import PhotoMaidCore
import UserNotifications

/// Opt-in-Erinnerungen. Begrenzte Anzahl, keine privaten Dateinamen auf dem Sperrbildschirm,
/// keine Fundzahlen ohne tatsächlichen Scan.
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
    func scheduleDueReminder(for day: LocalDay) async {
        guard access == .allowed else { return }
        let id = "later.\(day)"
        var comps = DateComponents()
        comps.year = day.year; comps.month = day.month; comps.day = day.day; comps.hour = 9
        let content = UNMutableNotificationContent()
        content.title = String(localized: "PhotoMaid")
        content.body = String(localized: "Heute sind zurückgestellte Elemente wieder fällig.")
        await add(id: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    /// Wöchentliche Erinnerung einer Regel. Enthält nur den Hinweis, keine Fundzahl.
    func scheduleRuleReminder(ruleID: ReviewRuleID, weekday: Int) async {
        guard access == .allowed else { return }
        var comps = DateComponents()
        comps.weekday = weekday; comps.hour = 10
        let content = UNMutableNotificationContent()
        content.title = String(localized: "PhotoMaid")
        content.body = String(localized: "Zeit für deine geplante Prüfung.")
        await add(id: "rule.\(ruleID.rawValue.uuidString)", content: content,
                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
    }

    func removeRuleReminder(ruleID: ReviewRuleID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rule.\(ruleID.rawValue.uuidString)"])
    }

    private func add(id: String, content: UNMutableNotificationContent, trigger: UNNotificationTrigger) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard pending.count < Self.maxPending || pending.contains(where: { $0.identifier == id }) else { return }
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
