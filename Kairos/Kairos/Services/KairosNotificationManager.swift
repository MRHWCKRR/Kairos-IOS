import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class KairosNotificationManager {
    enum AuthorizationState: Equatable { case notDetermined, denied, authorized, provisional, ephemeral }
    private(set) var authorizationState: AuthorizationState = .notDetermined

    init() { refreshAuthorizationState() }

    func refreshAuthorizationState() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in self?.authorizationState = Self.map(settings.authorizationStatus) }
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            authorizationState = granted ? .authorized : .denied
            refreshAuthorizationState()
            return granted
        } catch {
            authorizationState = .denied
            refreshAuthorizationState()
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func postBoardCompletion(boardTitle: String) async {
        guard authorizationState == .authorized || authorizationState == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Board complete"
        content.body = "You finished \(boardTitle). Nice work."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "board-complete-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Schedules a local reminder for a task's due date/time. The identifier is
    /// stable so editing a task replaces its previous due reminder.
    func scheduleTaskDue(taskID: String, title: String, date: Date) async {
        guard authorizationState == .authorized || authorizationState == .provisional else { return }
        guard date > Date.now else { return }
        let center = UNUserNotificationCenter.current()
        await center.removePendingNotificationRequests(withIdentifiers: ["task-due-\(taskID)"])
        let content = UNMutableNotificationContent()
        content.title = "Kairos task due"
        content.body = title
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "task-due-\(taskID)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelTaskDue(taskID: String) async {
        await UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["task-due-\(taskID)"])
    }

    private static func map(_ status: UNAuthorizationStatus) -> AuthorizationState {
        switch status { case .notDetermined: return .notDetermined; case .denied: return .denied; case .authorized: return .authorized; case .provisional: return .provisional; case .ephemeral: return .ephemeral; @unknown default: return .notDetermined }
    }
}
