import ActivityKit
import Foundation
import Observation

/// Shared data contract used by the app and the eventual WidgetKit extension.
/// Keep the fields stable so an extension can render an already-running session.
struct FocusTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRunning: Bool
        var elapsedSeconds: Int
    }

    var startedAt: Date
}

@Observable
@MainActor
final class FocusTimerCoordinator {
    static let shared = FocusTimerCoordinator()

    private(set) var isRunning = false
    private(set) var elapsedSeconds: Int64 = 0
    private var startedAt: Date?
    private var tickTask: Task<Void, Never>?
    private var liveActivity: Activity<FocusTimerAttributes>?

    private init() {}

    func start() {
        guard !isRunning else { return }
        startedAt = Date().addingTimeInterval(-Double(elapsedSeconds))
        isRunning = true
        refreshElapsed()
        startLiveActivityIfPossible()
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while let self, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.isRunning else { return }
                self.refreshElapsed()
                await self.updateLiveActivity()
            }
        }
    }

    func pause() {
        refreshElapsed()
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        startedAt = nil
        Task { await updateLiveActivity() }
    }

    func stopAndReset() -> Int64 {
        refreshElapsed()
        let seconds = elapsedSeconds
        pause()
        Task { await endLiveActivity() }
        elapsedSeconds = 0
        return seconds
    }

    private func refreshElapsed() {
        guard let startedAt else { return }
        elapsedSeconds = max(0, Int64(Date().timeIntervalSince(startedAt)))
    }

    private func currentActivityState() -> FocusTimerAttributes.ContentState {
        FocusTimerAttributes.ContentState(
            isRunning: isRunning,
            elapsedSeconds: Int(min(Int64(Int.max), elapsedSeconds))
        )
    }

    private func startLiveActivityIfPossible() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard liveActivity == nil else {
            Task { await updateLiveActivity() }
            return
        }

        let attributes = FocusTimerAttributes(startedAt: startedAt ?? Date())
        let content = ActivityContent(state: currentActivityState(), staleDate: nil)
        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Live Activities are an enhancement; the in-app timer remains authoritative.
            liveActivity = nil
        }
    }

    private func updateLiveActivity() async {
        guard let liveActivity else { return }
        let content = ActivityContent(state: currentActivityState(), staleDate: nil)
        await liveActivity.update(content)
    }

    private func endLiveActivity() async {
        guard let liveActivity else { return }
        let finalState = FocusTimerAttributes.ContentState(
            isRunning: false,
            elapsedSeconds: Int(min(Int64(Int.max), elapsedSeconds))
        )
        await liveActivity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.liveActivity = nil
    }
}