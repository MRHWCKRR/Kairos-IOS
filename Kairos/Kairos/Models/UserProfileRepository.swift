import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

@Observable
@MainActor
final class UserProfileRepository {
    var profile: KairosUserProfile?
    var focusData: KairosFocusData?
    var achievementsData: KairosAchievementsData?
    var aiChatHistory: [ChatMessage] = []
    var isLoading = false
    var errorMessage: String?

    let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(userID: String) {
        stopListening()
        isLoading = true

        listener = db.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = try? snapshot?.data(as: KairosUserDocument.self) else {
                    self.profile = nil
                    self.focusData = nil
                    self.achievementsData = nil
                    self.aiChatHistory = []
                    return
                }

                self.profile = data.settings?.profile
                self.focusData = data.focusData
                self.achievementsData = data.achievements
                self.aiChatHistory = data.aiChatHistory ?? []
                self.errorMessage = nil
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Settings

    func saveSettings(_ settings: KairosUserSettings) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            try await db.collection("users").document(uid).setData(["settings": encoded], merge: true)
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    // MARK: - AI chat history

    func saveAiChatHistory(_ messages: [ChatMessage]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let encoded = try messages.map { try Firestore.Encoder().encode($0) }
            try await db.collection("users").document(uid).setData(["aiChatHistory": encoded], merge: true)
        } catch {
            errorMessage = "Failed to save chat history: \(error.localizedDescription)"
        }
    }

    // MARK: - Achievements

    func setGoal(index: Int, achievementID: String?) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var goals = achievementsData?.goals ?? [nil, nil, nil]
        while goals.count <= index { goals.append(nil) }
        goals[index] = achievementID
        do {
            try await db.collection("users").document(uid).setData(["achievements.goals": goals], merge: true)
        } catch {
            errorMessage = "Failed to set goal: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func unlockAchievement(id: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        if achievementsData?.unlocked?[id] != nil { return false }
        var unlocked = achievementsData?.unlocked ?? [:]
        unlocked[id] = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            try await db.collection("users").document(uid).setData(["achievements.unlocked": unlocked], merge: true)
            return true
        } catch {
            errorMessage = "Failed to unlock achievement: \(error.localizedDescription)"
            return false
        }
    }

    func checkAchievements() async {
        guard let focus = focusData, let ach = achievementsData else { return }
        for def in KAIROS_ACHIEVEMENTS {
            guard ach.unlocked?[def.id] == nil else { continue }
            let isUnlocked: Bool
            switch def.type {
            case "focus_seconds": isUnlocked = focus.totalSeconds >= def.threshold
            case "tasks_completed": isUnlocked = Int64(ach.lifetimeTasksCompleted) >= def.threshold
            default: isUnlocked = false
            }
            if isUnlocked { await unlockAchievement(id: def.id) }
        }
    }

    // MARK: - Task completion accounting
    // Mirrors Android's MainViewModel.toggleTask side-effect: increments
    // lifetimeTasksCompleted and logs today's dailyTasksLog entry, but only
    // the FIRST time a given taskID is completed (countedTaskIds guards
    // against re-counting if a task is unchecked then rechecked).
    //
    // Simplification vs Android: no "stability lock" debounce against the
    // snapshot listener overwriting this optimistic update — acceptable for
    // now since writes are small and infrequent, but worth revisiting if
    // rapid double-taps ever cause a visible flicker/undercount.
    func recordTaskCompletion(taskID: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var ach = achievementsData ?? defaultAchievementsData()
        var counted = ach.countedTaskIds ?? []
        guard !counted.contains(taskID) else { return }

        counted.append(taskID)
        ach.countedTaskIds = counted
        ach.lifetimeTasksCompleted += 1
        achievementsData = ach // optimistic local update so checkAchievements() sees fresh numbers

        var focus = focusData ?? defaultFocusData()
        let dateKey = KairosDate.dayKey(for: Date())
        var tasksLog = focus.dailyTasksLog ?? [:]
        tasksLog[dateKey] = (tasksLog[dateKey] ?? 0) + 1
        focus.dailyTasksLog = tasksLog
        focusData = focus

        do {
            try await db.collection("users").document(uid).setData([
                "achievements.countedTaskIds": counted,
                "achievements.lifetimeTasksCompleted": ach.lifetimeTasksCompleted,
                "focusData.dailyTasksLog": tasksLog
            ], merge: true)
        } catch {
            errorMessage = "Failed to record task completion: \(error.localizedDescription)"
        }

        await checkAchievements()
    }

    // MARK: - Focus data

    func logFocusSession(seconds: Int64) async {
        guard let uid = Auth.auth().currentUser?.uid, seconds >= 1 else { return }
        var focus = focusData ?? defaultFocusData()
        focus.totalSeconds += seconds
        focus.longestSessionSeconds = max(focus.longestSessionSeconds, seconds)
        let dateKey = KairosDate.dayKey(for: Date())
        var log = focus.dailyFocusLog ?? [:]
        log[dateKey] = (log[dateKey] ?? 0) + seconds
        focus.dailyFocusLog = log
        focusData = focus // optimistic, same reasoning as above

        do {
            let encoded = try Firestore.Encoder().encode(focus)
            try await db.collection("users").document(uid).setData(["focusData": encoded], merge: true)
        } catch {
            errorMessage = "Failed to save focus data: \(error.localizedDescription)"
        }
        await checkAchievements()
    }
}

enum KairosDate {
    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
