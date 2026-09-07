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
                    return
                }

                self.profile = data.settings?.profile
                self.focusData = data.focusData
                self.achievementsData = data.achievements
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

    // MARK: - Achievements

    /// Mirrors Android's setGoal(index:achievementId:) — fixed 3-slot array, position matters.
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

    /// Unlocks an achievement if not already unlocked. Mirrors Android's unlockAchievement().
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

    /// Checks focus_seconds / tasks_completed thresholds and unlocks anything newly earned.
    /// Call after logging focus time or completing a task. Mirrors Android's checkAchievements().
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
        do {
            let encoded = try Firestore.Encoder().encode(focus)
            try await db.collection("users").document(uid).setData(["focusData": encoded], merge: true)
        } catch {
            errorMessage = "Failed to save focus data: \(error.localizedDescription)"
        }
        await checkAchievements()
    }
}

/// Small shared date-key helper — Android/Web use plain "yyyy-MM-dd" strings
/// (LocalDate.ISO_LOCAL_DATE / toDateKey()) as map keys for daily logs and
/// task scheduling, NOT a real ISO8601 timestamp. Keep this in sync with
/// StudyPlanRepository's date-key usage.
enum KairosDate {
    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
