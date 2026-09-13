import Foundation
import UserNotifications

@MainActor
enum KairosNotificationScheduler {
    private static let bedtimeIdentifier = "kairos.bedtime-reminder"

    static func scheduleBedtimeReminder(hour: Int = 21, minute: Int = 0) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [bedtimeIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Kairos"
        content.body = "A good time to check your study plan and wrap up the day."
        content.sound = .default

        var components = DateComponents()
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: bedtimeIdentifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    static func cancelBedtimeReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [bedtimeIdentifier])
    }
}
