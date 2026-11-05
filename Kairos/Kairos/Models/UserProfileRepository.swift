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
    private(set) var aiWorkspace: KairosAIWorkspace.Snapshot?
    private(set) var aiWorkspaceError: String?
    private var rawAIWorkspace: [String: Any]?
    private var rawLegacyHistory: [[String: Any]] = []
    private var profileHasLoaded = false
    private(set) var aiProposals: [String: KairosAIProposal] = [:]
    private(set) var aiProposalError: String?
    var aiWorkspaceOwnerID: String? { profileHasLoaded ? writableUserID : nil }
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
            self.profileHasLoaded = true
            self.restoreAIProposals(raw, ownerID: userID)
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
                self.rawLegacyHistory = history
                self.aiChatHistory = history.compactMap {
                    try? decoder.decode(ChatMessage.self, from: $0)
                }
            }

            do {
                guard raw["aiWorkspace"] == nil || raw["aiWorkspace"] is [String: Any] else { throw KairosAIWorkspace.Invalid() }
                self.rawAIWorkspace = raw["aiWorkspace"] as? [String: Any]
                self.aiWorkspace = try KairosAIWorkspace.read(self.rawAIWorkspace, legacy: self.rawLegacyHistory, owner: userID)
                self.aiWorkspaceError = nil
            } catch { self.aiWorkspaceError = error.localizedDescription }

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
        aiWorkspace = nil
        aiWorkspaceError = nil
        rawAIWorkspace = nil
        rawLegacyHistory = []
        profileHasLoaded = false
        aiProposals = [:]
        aiProposalError = nil
    }

    private func restoreAIProposals(_ raw: [String: Any], ownerID: String) {
        do {
            guard raw["aiNativeProposals"] == nil || raw["aiNativeProposals"] is [String: Any] else { throw KairosAIProposalEngine.Invalid("Saved AI previews could not be read safely.") }
            var restored: [String: KairosAIProposal] = [:]
            for (chatID, value) in raw["aiNativeProposals"] as? [String: Any] ?? [:] {
                guard let map = value as? [String: Any] else { throw KairosAIProposalEngine.Invalid("A saved preview is unreadable. Update Kairos before continuing.") }
                let proposal = try JSONDecoder().decode(KairosAIProposal.self, from: JSONSerialization.data(withJSONObject: map))
                try KairosAIProposalEngine.validate(proposal)
                guard proposal.chatID == chatID, proposal.ownerID == ownerID else { throw KairosAIProposalEngine.Invalid("A saved preview belongs to another account or conversation.") }
                restored[chatID] = proposal
            }
            aiProposals = restored; aiProposalError = nil
        } catch { aiProposals = [:]; aiProposalError = error.localizedDescription }
    }

    @discardableResult
    func saveAIReply(_ message: KairosAIWorkspace.Message, proposal: KairosAIProposal?, chatID: String, ownerID: String) async -> Bool {
        guard profileHasLoaded, writableUserID == ownerID, aiWorkspaceError == nil, aiProposalError == nil else { errorMessage = "Wait for your AI workspace and previews to load."; return false }
        let token = generation, reference = db.collection("users").document(ownerID)
        do {
            let proposalMap: [String: Any]? = try proposal.map { value in
                try KairosAIProposalEngine.validate(value)
                return try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
            }
            let result = try await db.runTransaction { transaction, pointer in
                do {
                    guard let user = Auth.auth().currentUser, user.uid == ownerID, user.isEmailVerified else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    let raw = snapshot.data() ?? [:]
                    guard raw["aiWorkspace"] == nil || raw["aiWorkspace"] is [String: Any], raw["aiNativeProposals"] == nil || raw["aiNativeProposals"] is [String: Any] else { throw KairosAIWorkspace.Invalid() }
                    var proposals = raw["aiNativeProposals"] as? [String: Any] ?? [:]
                    if let proposal, let proposalMap {
                        guard proposal.ownerID == ownerID, proposal.chatID == chatID, proposals[chatID] == nil || (proposals[chatID] as? [String: Any])?["id"] as? String == proposal.id else { throw KairosAIProposalEngine.Invalid("This chat already has a saved preview. Review or discard it first.") }
                        if let existing = proposals[chatID] as? [String: Any] { guard try KairosAIProposalEngine.digest(existing) == KairosAIProposalEngine.digest(proposalMap) else { throw KairosAIProposalEngine.Invalid("This saved preview changed on another device.") } }
                        proposals[chatID] = proposalMap
                    }
                    guard try JSONSerialization.data(withJSONObject: proposals).count <= 100_000 else { throw KairosAIProposalEngine.Invalid("Saved previews are full. Review or discard an existing preview first.") }
                    let workspace = try KairosAIWorkspace.applying(.append(chatID: chatID, messages: [message]), to: raw["aiWorkspace"] as? [String: Any], legacy: raw["aiChatHistory"] as? [[String: Any]] ?? [], owner: ownerID)
                    transaction.setData(["aiWorkspace": workspace, "aiNativeProposals": proposals], forDocument: reference, merge: true)
                    return ["aiWorkspace": workspace, "aiNativeProposals": proposals]
                } catch { pointer?.pointee = error as NSError; return nil }
            }
            guard token == generation, writableUserID == ownerID, let raw = result as? [String: Any] else { return false }
            rawAIWorkspace = raw["aiWorkspace"] as? [String: Any]
            aiWorkspace = try KairosAIWorkspace.read(rawAIWorkspace, legacy: [], owner: ownerID)
            restoreAIProposals(raw, ownerID: ownerID)
            return true
        } catch { guard generation == token else { return false }; errorMessage = "Could not save the reply and preview: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func discardAIProposal(_ proposal: KairosAIProposal) async -> Bool {
        guard writableUserID == proposal.ownerID else { return false }
        let token = generation, reference = db.collection("users").document(proposal.ownerID)
        do {
            _ = try await db.runTransaction { transaction, pointer in
                do {
                    guard Auth.auth().currentUser?.uid == proposal.ownerID else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    let raw = snapshot.data() ?? [:]
                    guard var proposals = raw["aiNativeProposals"] as? [String: Any], (proposals[proposal.chatID] as? [String: Any])?["id"] as? String == proposal.id else { throw KairosAIProposalEngine.Invalid("The saved preview changed. Reopen this chat.") }
                    proposals.removeValue(forKey: proposal.chatID)
                    transaction.updateData(["aiNativeProposals": proposals], forDocument: reference)
                    return true
                } catch { pointer?.pointee = error as NSError; return nil }
            }
            guard token == generation, writableUserID == proposal.ownerID else { return false }
            aiProposals[proposal.chatID] = nil; return true
        } catch { guard token == generation else { return false }; errorMessage = error.localizedDescription; return false }
    }
    func acknowledgeAppliedAIProposal(_ proposal: KairosAIProposal) {
        guard writableUserID == proposal.ownerID, aiProposals[proposal.chatID]?.id == proposal.id else { return }
        aiProposals[proposal.chatID] = nil
    }

    @discardableResult
    func editAIWorkspace(_ command: KairosAIWorkspace.Command, ownerID: String) async -> Bool {
        guard profileHasLoaded, writableUserID == ownerID, aiWorkspaceError == nil else {
            aiWorkspaceError = "Wait for your verified account's AI workspace to load."
            return false
        }
        let token = generation
        let reference = db.collection("users").document(ownerID)
        do {
            let result = try await db.runTransaction { transaction, pointer in
                do {
                    guard let user = Auth.auth().currentUser, user.uid == ownerID, user.isEmailVerified else { throw CancellationError() }
                    let snapshot = try transaction.getDocument(reference)
                    let data = snapshot.data() ?? [:]
                    guard data["aiWorkspace"] == nil || data["aiWorkspace"] is [String: Any] else { throw KairosAIWorkspace.Invalid() }
                    if case .append(let chatID, let messages) = command, messages.contains(where: { $0.role == "user" }), (data["aiNativeProposals"] as? [String: Any])?[chatID] != nil { throw KairosAIProposalEngine.Invalid("Review or discard the saved preview before sending another message.") }
                    let updated = try KairosAIWorkspace.applying(command, to: data["aiWorkspace"] as? [String: Any], legacy: data["aiChatHistory"] as? [[String: Any]] ?? [], owner: ownerID)
                    transaction.setData(["aiWorkspace": updated], forDocument: reference, merge: true)
                    if case .deleteChat(let chatID) = command {
                        guard data["aiNativeProposals"] == nil || data["aiNativeProposals"] is [String: Any] else { throw KairosAIWorkspace.Invalid() }
                        var proposals = data["aiNativeProposals"] as? [String: Any] ?? [:]
                        proposals.removeValue(forKey: chatID)
                        transaction.updateData(["aiNativeProposals": proposals], forDocument: reference)
                    }
                    return updated
                } catch { pointer?.pointee = error as NSError; return nil }
            }
            guard generation == token, writableUserID == ownerID, let updated = result as? [String: Any] else { return false }
            rawAIWorkspace = updated
            aiWorkspace = try KairosAIWorkspace.read(updated, legacy: [], owner: ownerID)
            if case .deleteChat(let chatID) = command { aiProposals[chatID] = nil }
            return true
        } catch {
            guard generation == token else { return false }
            errorMessage = "Could not save the AI workspace: \(error.localizedDescription)"
            return false
        }
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
