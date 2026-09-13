import Foundation
import UserNotifications

@MainActor
@Observable
final class KairosNotificationManager {
    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral
    }

    private(set) var authorizationState: AuthorizationState = .notDetermined

    init() {
        refreshAuthorizationState()
    }

    func refreshAuthorizationState() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationState = Self.map(settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            refreshAuthorizationState()
            return granted
        } catch {
            refreshAuthorizationState()
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "app-settings:") else { return }
        UIApplication.shared.open(url)
    }

    func postBoardCompletion(boardTitle: String) async {
        guard authorizationState == .authorized || authorizationState == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Board complete"
        content.body = "You finished \(boardTitle). Nice work."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "board-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func map(_ status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .notDetermined
        }
    }
}
