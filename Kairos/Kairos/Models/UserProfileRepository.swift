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
    private var listeningUserID: String?
    private var generation = UUID()
    private var writableUserID: String? {
        guard let user = Auth.auth().currentUser, user.isEmailVerified, user.uid == listeningUserID else { return nil }
        return user.uid
    }

    func startListening(userID: String) {
        stopListening()
        listeningUserID = userID
        let token = generation
        isLoading = true
        listener = db.collection("users").document(userID).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
            guard let self, self.generation == token, Auth.auth().currentUser?.uid == userID else { return }
            self.isLoading = false
            if let error {
                self.errorMessage = error.localizedDescription
                return
            }
            guard let snapshot else {
                self.errorMessage = "Kairos could not read your profile right now."
                return
            }

            // Decode each top-level section independently. A legacy or malformed
            // field elsewhere in the user document must not prevent saved settings
            // from being restored after a cold launch.
            self.clearValues()
            let raw = snapshot.data() ?? [:]
            let decoder = Firestore.Decoder()

            if let settings = raw["settings"] as? [String: Any] {
                if let map = settings["profile"] as? [String: Any],
                   let value = try? decoder.decode(KairosUserProfile.self, from: map) {
                    self.profile = value
                }
                if let map = settings["accessibility"] as? [String: Any],
                   let value = try? decoder.decode(KairosAccessibilitySettings.self, from: map) {
                    self.accessibilitySettings = value
                }
                if let map = settings["appearance"] as? [String: Any],
                   let value = try? decoder.decode(KairosAppearanceSettings.self, from: map) {
                    self.appearanceSettings = value
                }
                if let map = settings["notifications"] as? [String: Any],
                   let value = try? decoder.decode(KairosNotificationSettings.self, from: map) {
                    self.notificationSettings = value
                }
            }

            if let map = raw["focusData"] as? [String: Any],
               let value = try? decoder.decode(KairosFocusData.self, from: map) {
                self.focusData = value
            }
            if let map = raw["achievements"] as? [String: Any],
               let value = try? decoder.decode(KairosAchievementsData.self, from: map) {
                self.achievementsData = value
            }
            if let history = raw["aiChatHistory"] as? [[String: Any]] {
                self.aiChatHistory = history.compactMap {
                    try? decoder.decode(ChatMessage.self, from: $0)
                }
            }

            self.errorMessage = nil
            await self.checkAchievements()
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningUserID = nil
        generation = UUID()
        isLoading = false
        errorMessage = nil
        clearValues()
    }

    private func clearValues() {
        profile = nil
        focusData = nil
        achievementsData = nil
        accessibilitySettings = nil
        notificationSettings = nil
        appearanceSettings = nil
        aiChatHistory = []
    }

    // MARK: - Settings
    func saveSettings(_ settings: KairosUserSettings) async {
        guard let uid = writableUserID else { return }
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            try await db.collection("users").document(uid).setData(["settings": encoded], merge: true)
        } catch { errorMessage = "Failed to save settings: \(error.localizedDescription)" }
    }

    func saveAppearanceSettings(_ settings: KairosAppearanceSettings) async {
        guard let uid = writableUserID else { return }
        let previous = appearanceSettings
        appearanceSettings = settings
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            try await db.collection("users").document(uid).setData(["settings": ["appearance": encoded]], merge: true)
        } catch {
            appearanceSettings = previous
            errorMessage = "Failed to save appearance settings: \(error.localizedDescription)"
        }
    }

    func saveAccessibilitySettings(_ settings: KairosAccessibilitySettings) async {
        guard let uid = writableUserID else { return }
        let previous = accessibilitySettings
        accessibilitySettings = settings
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            try await db.collection("users").document(uid).setData(["settings": ["accessibility": encoded]], merge: true)
        } catch {
            accessibilitySettings = previous
            errorMessage = "Failed to save accessibility settings: \(error.localizedDescription)"
        }
    }

    func saveNotificationSettings(_ settings: KairosNotificationSettings) async {
        guard let uid = writableUserID else { return }
        let previous = notificationSettings
        notificationSettings = settings
        do {
            let encoded = try Firestore.Encoder().encode(settings)
            try await db.collection("users").document(uid).setData(["settings": ["notifications": encoded]], merge: true)
        } catch {
            notificationSettings = previous
            errorMessage = "Failed to save notification settings: \(error.localizedDescription)"
        }
    }

    // MARK: - AI chat history
    func saveAiChatHistory(_ messages: [ChatMessage]) async {
        guard let uid = writableUserID else { return }
        do {
            let encoded = try messages.map { try Firestore.Encoder().encode($0) }
            try await db.collection("users").document(uid).setData(["aiChatHistory": encoded], merge: true)
        } catch { errorMessage = "Failed to save chat history: \(error.localizedDescription)" }
    }

    // MARK: - Achievements
    func setGoal(index: Int, achievementID: String?) async {
        guard let uid = writableUserID, index >= 0 else { return }
        let previous = achievementsData
        var goals = achievementsData?.goals ?? [nil, nil, nil]
        while goals.count <= index { goals.append(nil) }
        goals[index] = achievementID
        if var achievements = achievementsData {
            achievements.goals = goals
            achievementsData = achievements
        }
        do {
            try await db.collection("users").document(uid).setData(["achievements": ["goals": goals.map { $0 as Any? ?? NSNull() }]], merge: true)
        } catch {
            achievementsData = previous
            errorMessage = "Failed to set goal: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func unlockAchievement(id: String) async -> Bool {
        guard let uid = writableUserID else { return false }
        if achievementsData?.unlocked?[id] != nil { return false }
        let previous = achievementsData
        var unlocked = achievementsData?.unlocked ?? [:]
        unlocked[id] = Int64(Date().timeIntervalSince1970 * 1000)
        if var achievements = achievementsData {
            achievements.unlocked = unlocked
            achievementsData = achievements
        }
        do {
            try await db.collection("users").document(uid).setData(["achievements": ["unlocked": [id: unlocked[id]!]]], merge: true)
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

    // MARK: - Transactional progress accounting
    func recordTaskCompletion(taskID: String) async {
        await saveProgress { data, day in
            try KairosProgress.taskCompletion(data: data, taskID: taskID, dayKey: day)
        }
    }

    func logFocusSession(seconds: Int64) async {
        guard seconds >= 1 else { return }
        await saveProgress { data, day in
            try KairosProgress.focusSession(data: data, seconds: seconds, dayKey: day)
        }
    }

    private func saveProgress(_ build: @escaping @Sendable ([String: Any], String) throws -> [String: Any]) async {
        guard let uid = writableUserID else { return }
        let reference = db.collection("users").document(uid)
        let token = generation
        let date = Date()
        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    guard Auth.auth().currentUser?.uid == uid else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    let raw = snapshot.data() ?? [:]
                    let settings = raw["settings"] as? [String: Any]
                    let profile = settings?["profile"] as? [String: Any]
                    let timezone = (profile?["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
                    let patch = try build(raw, KairosDate.dayKey(for: date, timeZone: timezone))
                    if !patch.isEmpty { transaction.setData(patch, forDocument: reference, merge: true) }
                    return true
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            guard generation == token, writableUserID == uid else { return }
            errorMessage = nil
        } catch {
            guard generation == token else { return }
            errorMessage = "Failed to save progress: \(error.localizedDescription)"
        }
    }
}

enum KairosDate {
    nonisolated static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
