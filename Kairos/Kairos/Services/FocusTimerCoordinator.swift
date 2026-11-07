import ActivityKit
import Foundation
import Observation
import FirebaseAuth

@Observable @MainActor
final class FocusTimerCoordinator {
    static let shared = FocusTimerCoordinator()
    private(set) var session: KairosFocusSession?
    private(set) var elapsedSeconds: Int64 = 0
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var notice: String?
    private(set) var expiredRequest = false
    private var owner: String?
    private var binding: UUID?
    private weak var planRepo: StudyPlanRepository?
    private weak var profileRepo: UserProfileRepository?
    private var tickTask: Task<Void, Never>?
    private var liveActivity: Activity<FocusTimerAttributes>?
    private var recoveryBlocked = false
    private var requestedStartOwner: String?
    private var foreground = false
    private let store: KairosFocusRecoveryStore
    var isRunning: Bool { session?.startedAt != nil }
    var hasPendingLog: Bool { session?.pending != nil }
    var canStart: Bool { foreground && !recoveryBlocked && planRepo?.focusIdentity?.owner == owner && owner != nil }
    private var now: Double { Date().timeIntervalSince1970 * 1000 }
    func belongs(to uid: String?) -> Bool { uid != nil && uid == owner && Auth.auth().currentUser?.uid == uid }
    func clearFeedback() { notice = nil; if session == nil && !recoveryBlocked { errorMessage = nil } }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        store = .init(directory: base.appendingPathComponent("KairosFocusRecovery", isDirectory: true))
    }
    func bind(planRepo: StudyPlanRepository, profileRepo: UserProfileRepository, owner: String, binding: UUID, active: Bool) {
        if self.owner != owner {
            pause()
            self.owner = owner; session = nil; elapsedSeconds = 0; errorMessage = nil; notice = nil
            expiredRequest = false; recoveryBlocked = false; isSaving = false
            endActivity()
            endStaleActivities()
            do {
                if let saved = try store.read(owner: owner) {
                    let restored = try saved.recovered(now: now)
                    try store.write(restored); session = restored; elapsedSeconds = restored.accumulatedMs / 1000
                    notice = restored.pending == nil ? "Recovered paused at your last saved checkpoint." : "An unconfirmed log is retained. Retry uses the same request."
                }
            } catch { recoveryBlocked = true; errorMessage = "Focus recovery could not be read safely. Your saved record is retained. Restart Kairos to retry." }
        }
        self.binding = binding; self.planRepo = planRepo; self.profileRepo = profileRepo; foreground = active
        if let session, let identity = planRepo.focusIdentity, session.planId != identity.plan { pause(); errorMessage = "Open this session’s original planner before resuming or logging." }
        if requestedStartOwner == owner, canStart { requestedStartOwner = nil; start() }
    }
    func sceneChanged(active: Bool, binding: UUID) {
        guard self.binding == binding else { return }
        foreground = active
        if let session, isRunning { _ = persist(session.checkpoint(now: now, running: true)); Task { await updateActivity() } }
        else if requestedStartOwner == owner, canStart { requestedStartOwner = nil; start() }
    }
    func requestGeneralStart() {
        KairosFirebase.configure()
        guard let user = Auth.auth().currentUser, user.isEmailVerified else { return }
        requestedStartOwner = user.uid
        if canStart { requestedStartOwner = nil; start() }
    }
    func requestPause() { requestedStartOwner = nil; pause() }
    func accountChanged(to uid: String?) {
        guard owner != uid else { return }
        pause(); endActivity(); endStaleActivities()
        if let requestedStartOwner, requestedStartOwner != uid { self.requestedStartOwner = nil }
        owner = nil; binding = nil; session = nil; elapsedSeconds = 0; foreground = false
        planRepo = nil; profileRepo = nil; isSaving = false; notice = nil; errorMessage = nil
    }
    func detach(binding: UUID) {
        guard self.binding == binding else { return }
        pause(); endActivity(); endStaleActivities(); session = nil; elapsedSeconds = 0; owner = nil
        self.binding = nil; planRepo = nil; profileRepo = nil; errorMessage = nil; notice = nil; foreground = false
    }
    @discardableResult private func persist(_ value: KairosFocusSession) -> Bool {
        do { try store.write(value); session = value; elapsedSeconds = value.accumulatedMs / 1000; return true }
        catch {
            session = value.checkpoint(now: now, running: false); elapsedSeconds = session!.accumulatedMs / 1000
            tickTask?.cancel(); tickTask = nil
            errorMessage = "Recovery storage could not be saved. The timer is paused. Retry before leaving Kairos."
            return false
        }
    }
    func start(target: KairosFocusTarget? = nil, expectedScope: String? = nil) {
        guard canStart, !isSaving, let owner, let repo = planRepo, let identity = repo.focusIdentity,
              identity.owner == owner, Auth.auth().currentUser?.uid == owner else { errorMessage = "Open your verified planner before starting focus."; return }
        if let expectedScope, expectedScope != repo.searchScope { errorMessage = "This task changed. Reopen its focus controls."; return }
        if let target {
            guard (try? repo.focusTarget(taskID: target.taskId, occurrenceDate: target.occurrenceDate).0) == target else { errorMessage = "This task or occurrence is no longer available."; return }
        }
        if let current = session {
            guard current.pending == nil else { errorMessage = "Retry the pending log before starting another session."; return }
            guard current.planId == identity.plan, target == nil || current.target == target else { errorMessage = "Log or discard the current session before starting a different task."; return }
            guard !isRunning else { return }
            var copy = current; copy.startedAt = now; copy.lastSeenAt = now
            guard copy.accumulatedMs < 86_400_000 else { errorMessage = "The 24-hour session limit is reached. Log this session before starting another."; return }
            guard persist(copy) else { return }
        } else {
            let time = now
            let value = KairosFocusSession(id: "focus-\(UUID().uuidString)", ownerId: owner, planId: identity.plan, createdAt: time, startedAt: time, lastSeenAt: time, target: target)
            guard persist(value) else { return }
        }
        errorMessage = nil; notice = nil; expiredRequest = false
        startActivity(); tickTask?.cancel()
        tickTask = Task { [weak self] in
            while let self, self.isRunning {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.isRunning, let value = self.session else { return }
                guard self.persist(value.checkpoint(now: self.now, running: true)) else { await self.updateActivity(); return }
                await self.updateActivity()
            }
        }
    }
    func pause() {
        guard let value = session, value.startedAt != nil else { return }
        _ = persist(value.checkpoint(now: now, running: false))
        tickTask?.cancel(); tickTask = nil
        Task { await updateActivity() }
    }
    func log() {
        guard !isSaving, let current = session, let repo = planRepo, owner == current.ownerId else { return }
        pause()
        do {
            let prepared = try (session ?? current).preparedLog(now: now)
            guard persist(prepared), let entry = prepared.pending else { return }
            isSaving = true; errorMessage = nil
            let capturedBinding = binding
            Task {
                defer { if binding == capturedBinding, owner == entry.ownerId { isSaving = false } }
                do {
                    let result = try await repo.logFocus(entry)
                    guard binding == capturedBinding, owner == entry.ownerId, session?.pending == entry else { return }
                    try store.remove(owner: entry.ownerId, expectedID: entry.id)
                    session = nil; elapsedSeconds = 0; expiredRequest = false; endActivity()
                    notice = entry.target != nil && !result.attributed ? "Time saved to overall focus. The original task changed, so its ledger was left unchanged." : "Focus time saved."
                    await profileRepo?.checkAchievements()
                } catch {
                    guard binding == capturedBinding, owner == entry.ownerId else { return }
                    expiredRequest = (error as NSError).userInfo["focusCode"] as? String == "focus-log-expired"
                    errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func discardReviewedSession() {
        guard !isSaving, let current = session, current.pending == nil || expiredRequest else { return }
        pause()
        do {
            try store.remove(owner: current.ownerId, expectedID: current.id)
            session = nil; elapsedSeconds = 0; errorMessage = nil; notice = nil; expiredRequest = false; endActivity()
        } catch { errorMessage = "The recovery record could not be cleared. Your session is still retained." }
    }
    private func state() -> FocusTimerAttributes.ContentState { .init(isRunning: isRunning, elapsedSeconds: Int(elapsedSeconds)) }
    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, liveActivity == nil else { return }
        liveActivity = try? Activity.request(attributes: FocusTimerAttributes(startedAt: Date().addingTimeInterval(-Double(elapsedSeconds))), content: ActivityContent(state: state(), staleDate: nil), pushType: nil)
    }
    private func updateActivity() async {
        guard let activity = liveActivity else { return }
        await activity.update(ActivityContent(state: state(), staleDate: nil))
    }
    private func endActivity() {
        let activity = liveActivity; liveActivity = nil
        if let activity { let final = state(); Task { await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate) } }
    }
    private func endStaleActivities() {
        let stale = Activity<FocusTimerAttributes>.activities
        let paused = FocusTimerAttributes.ContentState(isRunning: false, elapsedSeconds: Int(elapsedSeconds))
        Task { for activity in stale { await activity.end(ActivityContent(state: paused, staleDate: nil), dismissalPolicy: .immediate) } }
    }
}

