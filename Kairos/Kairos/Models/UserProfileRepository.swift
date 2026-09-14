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
    var accessibilitySettings: KairosAccessibilitySettings?
    var notificationSettings: KairosNotificationSettings?
    var appearanceSettings: KairosAppearanceSettings?
    var aiChatHistory: [ChatMessage] = []
    var isLoading = false
    var errorMessage: String?

    let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(userID: String) {
        stopListening()
        isLoading = true
        listener = db.collection("users").document(userID).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            self.isLoading = false
            if let error {
                self.errorMessage = error.localizedDescription
                return
            }
            guard let snapshot else {
                self.errorMessage = "Kairos could not read your profile right now."
                return
            }

            do {
                let data = try snapshot.data(as: KairosUserDocument.self)
                self.profile = data.settings?.profile
                self.focusData = data.focusData
                self.achievementsData = data.achievements
                self.accessibilitySettings = data.settings?.accessibility
                self.notificationSettings = data.settings?.notifications
                self.appearanceSettings = data.settings?.appearance
                self.aiChatHistory = data.aiChatHistory ?? []
                self.errorMessage = nil
            } catch {
                // Do not clear valid in-memory settings when an unrelated field in
                // the user document fails to decode. This used to make a saved
                // appearance fall back to the device theme after task updates.
                self.errorMessage = "Some account data could not be refreshed. Your current settings were kept."
            }
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
        } catch { errorMessage = "Failed to save settings: \(error.localizedDescription)" }
    }

    func saveAppearanceSettings(_ settings: KairosAppearanceSettings) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let previous = appearanceSettings
        appearanceSettings = settings
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            // Use updateData for the nested field path. This guarantees that
            // `settings.appearance` is written as a nested map rather than relying
            // on setData's dictionary-key interpretation.
            try await db.collection("users").document(uid).updateData([
                "settings.appearance": encoded
            ])
        } catch {
            appearanceSettings = previous
            errorMessage = "Failed to save appearance settings: \(error.localizedDescription)"
        }
    }

    func saveAccessibilitySettings(_ settings: KairosAccessibilitySettings) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let previous = accessibilitySettings
        accessibilitySettings = settings
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            try await db.collection("users").document(uid).updateData([
                "settings.accessibility": encoded
            ])
        } catch {
            accessibilitySettings = previous
            errorMessage = "Failed to save accessibility settings: \(error.localizedDescription)"
        }
    }

    func saveNotificationSettings(_ settings: KairosNotificationSettings) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let previous = notificationSettings
        notificationSettings = settings
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            try await db.collection("users").document(uid).setData(["settings.notifications": encoded], merge: true)
        } catch {
            notificationSettings = previous
            errorMessage = "Failed to save notification settings: \(error.localizedDescription)"
        }
    }

    // MARK: - AI chat history
    func saveAiChatHistory(_ messages: [ChatMessage]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let encoded = try messages.map { try Firestore.Encoder().encode($0) }
            try await db.collection("users").document(uid).setData(["aiChatHistory": encoded], merge: true)
        } catch { errorMessage = "Failed to save chat history: \(error.localizedDescription)" }
    }

    // MARK: - Achievements
    func setGoal(index: Int, achievementID: String?) async {
        guard let uid = Auth.auth().currentUser?.uid, index >= 0 else { return }
        let previous = achievementsData
        var goals = achievementsData?.goals ?? [nil, nil, nil]
        while goals.count <= index { goals.append(nil) }
        goals[index] = achievementID
        if var achievements = achievementsData {
            achievements.goals = goals
            achievementsData = achievements
        }
        do {
            try await db.collection("users").document(uid).setData(["achievements.goals": goals], merge: true)
        } catch {
            achievementsData = previous
            errorMessage = "Failed to set goal: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func unlockAchievement(id: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        if achievementsData?.unlocked?[id] != nil { return false }
        let previous = achievementsData
        var unlocked = achievementsData?.unlocked ?? [:]
        unlocked[id] = Int64(Date().timeIntervalSince1970 * 1000)
        if var achievements = achievementsData {
            achievements.unlocked = unlocked
            achievementsData = achievements
        }
        do {
            try await db.collection("users").document(uid).setData(["achievements.unlocked": unlocked], merge: true)
            return true
        } catch {
            achievementsData = previous
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
    func recordTaskCompletion(taskID: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let previousAchievements = achievementsData
        let previousFocus = focusData
        var ach = achievementsData ?? defaultAchievementsData()
        var counted = ach.countedTaskIds ?? []
        guard !counted.contains(taskID) else { return }
        counted.append(taskID)
        ach.countedTaskIds = counted
        ach.lifetimeTasksCompleted += 1
        achievementsData = ach
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
            achievementsData = previousAchievements
            focusData = previousFocus
            errorMessage = "Failed to record task completion: \(error.localizedDescription)"
            return
        }
        await checkAchievements()
    }

    // MARK: - Focus data
    func logFocusSession(seconds: Int64) async {
        guard let uid = Auth.auth().currentUser?.uid, seconds >= 1 else { return }
        let previous = focusData
        var focus = focusData ?? defaultFocusData()
        focus.totalSeconds += seconds
        focus.longestSessionSeconds = max(focus.longestSessionSeconds, seconds)
        let dateKey = KairosDate.dayKey(for: Date())
        var log = focus.dailyFocusLog ?? [:]
        log[dateKey] = (log[dateKey] ?? 0) + seconds
        focus.dailyFocusLog = log
        focusData = focus
        do {
            let encoded = try Firestore.Encoder().encode(focus)
            try await db.collection("users").document(uid).setData(["focusData": encoded], merge: true)
        } catch {
            focusData = previous
            errorMessage = "Failed to save focus data: \(error.localizedDescription)"
            return
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