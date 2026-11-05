import Foundation
import UserNotifications
import FirebaseAuth

extension Notification.Name { static let kairosReminderPermissionChanged = Notification.Name("kairosReminderPermissionChanged") }

@MainActor enum KairosTaskReminderScheduler {
    private static var generation = UUID()
    private static var activeScope: UUID?
    static func enableFromUserAction(notificationsEnabled: Bool) async -> String? {
        guard notificationsEnabled else { return "Reminder saved. Turn on Notifications in Kairos Settings for alerts." }
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        NotificationCenter.default.post(name: .kairosReminderPermissionChanged, object: nil)
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) ? nil : "Reminder saved. Allow notifications in iOS Settings for alerts."
    }
    static func cancel(scopeID: UUID) async {
        guard activeScope == scopeID else { return }
        generation = UUID()
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        guard activeScope == scopeID else { return }
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("kairos.task.") })
    }
    static func refresh(planRepo: StudyPlanRepository, ownerID: String, timezone: String, enabled: Bool, scopeID: UUID) async {
        activeScope = scopeID
        let token = UUID(); generation = token
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        guard token == generation, Auth.auth().currentUser?.uid == ownerID else { return }
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("kairos.task.") })
        guard enabled else { return }
        let permission = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(permission.authorizationStatus) else { return }
        do {
            let candidates = try await planRepo.taskReminderCandidates(timezone: timezone)
            guard token == generation, !Task.isCancelled, Auth.auth().currentUser?.uid == ownerID else { return }
            for reminder in KairosTaskReminders.plan(candidates, ownerID: ownerID, timezone: timezone, now: Date()) {
                guard token == generation, !Task.isCancelled, Auth.auth().currentUser?.uid == ownerID else { return }
                let content = UNMutableNotificationContent(); content.title = "Kairos"; content.body = reminder.title; content.sound = .default
                let delay = max(1, reminder.dueAt.timeIntervalSinceNow)
                let id = reminder.id + "." + token.uuidString
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
                if token != generation || Auth.auth().currentUser?.uid != ownerID { center.removePendingNotificationRequests(withIdentifiers: [id]); return }
            }
        } catch { /* Keep the successful pending requests; the next refresh retries. */ }
    }
}
