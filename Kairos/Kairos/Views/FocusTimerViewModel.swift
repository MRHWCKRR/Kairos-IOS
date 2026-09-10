import Foundation
import Observation

/// Mirrors Android's MainViewModel focus timer (startFocusTimer/pauseFocusTimer/
/// stopAndLogFocus): a simple running counter, not a wall-clock reconstruction.
/// Neither Android nor this currently survive the app being backgrounded/killed
/// mid-session — that's an accepted gap on both platforms for now, not a regression.
@Observable
@MainActor
final class FocusTimerViewModel {
    var isRunning = false
    var elapsedSeconds: Int64 = 0

    private var tickTask: Task<Void, Never>?
    private let profileRepo: UserProfileRepository

    init(profileRepo: UserProfileRepository) {
        self.profileRepo = profileRepo
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        tickTask = Task { [weak self] in
            while let self, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.isRunning else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    func pause() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
    }

    /// Mirrors Android's stopAndLogFocus(): logs the session if it's at
    /// least 1 second, then resets the display to zero.
    func stopAndLog() {
        let seconds = elapsedSeconds
        pause()
        elapsedSeconds = 0
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
