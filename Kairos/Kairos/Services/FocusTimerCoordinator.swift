import Foundation
import Observation

@Observable
@MainActor
final class FocusTimerCoordinator {
    static let shared = FocusTimerCoordinator()

    private(set) var isRunning = false
    private(set) var elapsedSeconds: Int64 = 0
    private var startedAt: Date?
    private var tickTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !isRunning else { return }
        startedAt = Date().addingTimeInterval(-Double(elapsedSeconds))
        isRunning = true
        refreshElapsed()
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while let self, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.isRunning else { return }
                self.refreshElapsed()
            }
        }
    }

    func pause() {
        refreshElapsed()
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        startedAt = nil
    }

    func stopAndReset() -> Int64 {
        refreshElapsed()
        let seconds = elapsedSeconds
        pause()
        elapsedSeconds = 0
        return seconds
    }

    private func refreshElapsed() {
        guard let startedAt else { return }
        elapsedSeconds = max(0, Int64(Date().timeIntervalSince(startedAt)))
    }
}
