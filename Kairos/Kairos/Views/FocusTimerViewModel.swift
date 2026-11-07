import Foundation
import Observation

/// Dashboard-facing adapter for the shared focus timer.
/// The coordinator preserves background timing and recovers paused after relaunch.
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

    /// Retains the session until its idempotent log is confirmed.
    func stopAndLog() {
        coordinator.log()
    }

    static func formatHMS(_ totalSeconds: Int64) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
