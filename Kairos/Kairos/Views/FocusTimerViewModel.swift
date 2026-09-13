import Foundation
import Observation

/// Dashboard-facing adapter for the shared focus timer.
/// The coordinator keeps the timer accurate while the app is backgrounded or suspended.
@Observable
@MainActor
final class FocusTimerViewModel {
    private let profileRepo: UserProfileRepository
    private let coordinator = FocusTimerCoordinator.shared

    var isRunning: Bool { coordinator.isRunning }
    var elapsedSeconds: Int64 { coordinator.elapsedSeconds }

    init(profileRepo: UserProfileRepository) {
        self.profileRepo = profileRepo
    }

    func start() {
        coordinator.start()
    }

    func pause() {
        coordinator.pause()
    }

    /// Logs the session if it is at least 1 second, then resets the display.
    func stopAndLog() {
        let seconds = coordinator.stopAndReset()
        guard seconds >= 1 else { return }
        Task { await profileRepo.logFocusSession(seconds: seconds) }
    }

    static func formatHMS(_ totalSeconds: Int64) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
