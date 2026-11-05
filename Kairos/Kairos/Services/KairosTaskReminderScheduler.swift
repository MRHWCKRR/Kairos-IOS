import Foundation
import UserNotifications
import FirebaseAuth

extension Notification.Name { static let kairosReminderPermissionChanged = Notification.Name("kairosReminderPermissionChanged") }

@MainActor enum KairosTaskReminderScheduler {
    private static var generation = UUID()
    private static var activeScope: UUID?
    private static var activeLedgerKey: String?
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
        clearScheduledEntries(requests, key: activeLedgerKey)
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("kairos.task.") })
    }
    private static func clearScheduledEntries(_ requests: [UNNotificationRequest], key: String?) {
        guard let key else { return }
        var ledger = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        for request in requests { if let id = request.content.userInfo["kairosTaskReminderID"] as? String { ledger[id] = nil } }
        UserDefaults.standard.set(ledger, forKey: key)
    }
    static func refresh(planRepo: StudyPlanRepository, ownerID: String, timezone: String, enabled: Bool, scopeID: UUID) async {
        guard !Task.isCancelled, Auth.auth().currentUser?.uid == ownerID else { return }
        activeScope = scopeID
        let ledgerKey = "kairos.task.scheduled." + ((try? KairosAIProposalEngine.digest([ownerID])) ?? ownerID)
        activeLedgerKey = ledgerKey
        let token = UUID(); generation = token
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        guard token == generation, Auth.auth().currentUser?.uid == ownerID else { return }
        let permission = await center.notificationSettings()
        guard token == generation, !Task.isCancelled, Auth.auth().currentUser?.uid == ownerID else { return }
        guard enabled, [.authorized, .provisional, .ephemeral].contains(permission.authorizationStatus) else {
            clearScheduledEntries(existing, key: ledgerKey)
            center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("kairos.task.") }); return
        }
        do {
            let revision = planRepo.plannerRevision
            let candidates = try await planRepo.taskReminderCandidates(timezone: timezone)
            guard token == generation, !Task.isCancelled, Auth.auth().currentUser?.uid == ownerID, revision == planRepo.plannerRevision else { return }
            let now = Date()
            var ledger = (UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: Double] ?? [:]).filter { $0.value > now.timeIntervalSince1970 - 8 * 86400 }
            let pendingIDs = Set(existing.compactMap { $0.content.userInfo["kairosTaskReminderID"] as? String })
            let planned = KairosTaskReminders.plan(candidates, ownerID: ownerID, timezone: timezone, now: now)
            let ready = KairosTaskReminders.excludingDelivered(planned, scheduled: ledger, pendingIDs: pendingIDs, now: now)
            center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("kairos.task.") })
            for reminder in ready {
                guard token == generation, !Task.isCancelled, Auth.auth().currentUser?.uid == ownerID else { return }
                let content = UNMutableNotificationContent(); content.title = "Kairos"; content.body = reminder.title; content.sound = .default
                content.userInfo["kairosTaskReminderID"] = reminder.id
                let delay = max(1, reminder.dueAt.timeIntervalSinceNow)
                let id = reminder.id + "." + token.uuidString
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
                if token != generation || Task.isCancelled || Auth.auth().currentUser?.uid != ownerID { center.removePendingNotificationRequests(withIdentifiers: [id]); return }
                ledger[reminder.id] = reminder.dueAt.timeIntervalSince1970
                UserDefaults.standard.set(ledger, forKey: ledgerKey)
            }
        } catch { /* Keep the successful pending requests; the next refresh retries. */ }
    }
}
