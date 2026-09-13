import Foundation
import UserNotifications

/// Keeps Kairos' bedtime preference useful on iOS without requiring a server push.
/// The scheduled notification is intentionally local and can be refreshed whenever
/// the user changes notification preferences.
@MainActor
enum KairosBedtimeReminderScheduler {
    static let identifier = "kairos.bedtime-reminder"

    static func refresh(enabled: Bool, notificationsEnabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard enabled, notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Wind down with Kairos"
        content.body = "A small study plan today makes tomorrow easier."
        content.sound = .default

        var components = DateComponents()
        components.hour = 21
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
