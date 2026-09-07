// Kairos/Kairos/Models/KairosModels.swift
import Foundation
import FirebaseFirestore

// MARK: - Study Plan (top-level document in `study_plans`)

struct KairosStudyPlan: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var userID: String
    @ServerTimestamp var createdAt: Date?
    var boards: [KairosBoard]
    var dayInsights: [String: String]?
    var scheduleEvents: [KairosScheduleEvent]?
}

struct KairosBoard: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var archived: Bool
    var sections: [KairosSection]
}

struct KairosSection: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var archived: Bool
    var tasks: [KairosTask]
}

struct KairosTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var completed: Bool
    var archived: Bool
    // FIX: Android/Web store this as a plain "yyyy-MM-dd" string (used for
    // calendar lookups by exact key match), not a Firestore Date/Timestamp.
    // Was `Date?` — that would fail to decode existing docs and would write
    // a Timestamp that Android's date == dateKey string comparison can't match.
    var date: String?
}

struct KairosScheduleEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var category: String
    var day: Int
    var start: String
    var end: String
}

// MARK: - User document (`users/{uid}`)

struct KairosUserDocument: Codable, Equatable {
    var settings: KairosUserSettings?
    var achievements: KairosAchievementsData?
    var focusData: KairosFocusData?
    var aiChatHistory: [ChatMessage]?
    var notifications: [KairosNotification]?
}

struct KairosUserSettings: Codable, Equatable {
    var profile: KairosUserProfile
    var accessibility: KairosAccessibilitySettings
    var appearance: KairosAppearanceSettings
    var notifications: KairosNotificationSettings
}

struct KairosUserProfile: Codable, Equatable {
    var displayName: String
    var avatarURL: String
    var birthday: String
    var timezone: String
}

struct KairosAccessibilitySettings: Codable, Equatable {
    var density: String
    var timeFormat: String
    var reduceMotion: Bool
    var language: String
}

struct KairosAppearanceSettings: Codable, Equatable {
    var mode: String
    var theme: String
    var textColor: String
    var font: String
    var background: String
    var customBackground: String?
    var cursor: String
    var ambientSound: String
    var ambientVolume: Int
    var customAmbientYoutubeUrl: String
    var confetti: Bool
}

struct KairosNotificationSettings: Codable, Equatable {
    var enabled: Bool
    var boardCompletion: Bool
    var bedtimeReminders: Bool
    var browserPush: Bool
}

struct KairosNotification: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var message: String
    var time: Int64
    var read: Bool
}

struct KairosAchievementsData: Codable, Equatable {
    // FIX: was [String: Bool] — Android stores the UNLOCK TIMESTAMP
    // (System.currentTimeMillis()) per achievement id, used for the
    // "Earned on <date>" line in the detail dialog. Bool loses that data
    // and would desync the moment iOS writes to this field.
    var unlocked: [String: Int64]?
    var countedTaskIds: [String]?
    var lifetimeTasksCompleted: Int
    // FIX: was [String]? — Android's goals is a fixed 3-slot array where
    // POSITION matters (dashboard goal slot 0/1/2), and slots can be nil.
    // A plain [String]? can't represent an empty middle slot correctly.
    var goals: [String?]?
}

struct KairosFocusData: Codable, Equatable {
    var totalSeconds: Int64
    var longestSessionSeconds: Int64
    var dailyFocusLog: [String: Int64]?
    var dailyTasksLog: [String: Int]?
}

// MARK: - Chat (used by AI Helper — matches Android's ChatMessage / Web's role+content shape)

struct ChatMessage: Codable, Equatable {
    var role: String   // "user" | "assistant" | "system"
    var content: String
    var timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
}

// MARK: - Achievement catalog
// Ported 1:1 from Android's KAIROS_ACHIEVEMENTS (KairosModels.kt) and Web's
// ACHIEVEMENTS (app.js). IDs, thresholds, and order MUST match exactly —
// achievement docs are keyed by these ids across all three platforms.

struct AchievementDef: Identifiable, Equatable {
    let id: String
    let category: String   // "focus" | "tasks" | "misc"
    let name: String
    let desc: String
    let icon: String
    let type: String       // "focus_seconds" | "tasks_completed" | "event"
    let threshold: Int64
    let event: String?
    let limitedAvailability: Bool
    let rarity: String

    init(_ id: String, _ category: String, _ name: String, _ desc: String, _ icon: String,
         _ type: String, threshold: Int64 = 0, event: String? = nil,
         limitedAvailability: Bool = false, rarity: String = "Common") {
        self.id = id; self.category = category; self.name = name; self.desc = desc
        self.icon = icon; self.type = type; self.threshold = threshold
        self.event = event; self.limitedAvailability = limitedAvailability; self.rarity = rarity
    }
}

let KAIROS_ACHIEVEMENTS: [AchievementDef] = [
    // Focus time
    AchievementDef("focus_25m", "focus", "Novice", "Log 25 minutes of focus time", "🔥", "focus_seconds", threshold: 25 * 60, rarity: "Common"),
    AchievementDef("focus_1h", "focus", "Apprentice", "Log 1 hour of focus time", "⚡", "focus_seconds", threshold: 3600, rarity: "Common"),
    AchievementDef("focus_2h", "focus", "Adept", "Log 2 hours of focus time", "🌀", "focus_seconds", threshold: 2 * 3600, rarity: "Rare"),
    AchievementDef("focus_5h", "focus", "Specialist", "Log 5 hours of focus time", "🎯", "focus_seconds", threshold: 5 * 3600, rarity: "Rare"),
    AchievementDef("focus_10h", "focus", "Expert", "Log 10 hours of focus time", "🛡️", "focus_seconds", threshold: 10 * 3600, rarity: "Epic"),
    AchievementDef("focus_20h", "focus", "Veteran", "Log 20 hours of focus time", "🏅", "focus_seconds", threshold: 20 * 3600, rarity: "Epic"),
    AchievementDef("focus_50h", "focus", "Master", "Log 50 hours of focus time", "👑", "focus_seconds", threshold: 50 * 3600, rarity: "Legendary"),
    AchievementDef("focus_100h", "focus", "Grandmaster", "Log 100 hours of focus time", "💎", "focus_seconds", threshold: 100 * 3600, rarity: "Legendary"),
    AchievementDef("focus_300h", "focus", "Legend", "Log 300 hours of focus time", "⭐", "focus_seconds", threshold: 300 * 3600, rarity: "Mythic"),
    AchievementDef("focus_500h", "focus", "Mythic", "Log 500 hours of focus time", "🌟", "focus_seconds", threshold: 500 * 3600, rarity: "Mythic"),
    AchievementDef("focus_1000h", "focus", "DEVELOPER???", "Log 1000 hours of focus time", "🧠", "focus_seconds", threshold: 1000 * 3600, rarity: "Mythic"),

    // Tasks
    AchievementDef("tasks_5", "tasks", "Getting Started", "Complete 5 tasks", "📝", "tasks_completed", threshold: 5, rarity: "Common"),
    AchievementDef("tasks_15", "tasks", "Warming Up", "Complete 15 tasks", "📋", "tasks_completed", threshold: 15, rarity: "Common"),
    AchievementDef("tasks_30", "tasks", "Task Tackler", "Complete 30 tasks", "✅", "tasks_completed", threshold: 30, rarity: "Rare"),
    AchievementDef("tasks_50", "tasks", "On A Roll", "Complete 50 tasks", "🎲", "tasks_completed", threshold: 50, rarity: "Rare"),
    AchievementDef("tasks_100", "tasks", "Centurion of Checkboxes", "Complete 100 tasks", "🏆", "tasks_completed", threshold: 100, rarity: "Epic"),
    AchievementDef("tasks_200", "tasks", "Double Century", "Complete 200 tasks", "🎖️", "tasks_completed", threshold: 200, rarity: "Epic"),
    AchievementDef("tasks_500", "tasks", "Half-K Hero", "Complete 500 tasks", "🚀", "tasks_completed", threshold: 500, rarity: "Legendary"),
    AchievementDef("tasks_800", "tasks", "Almost There...", "Complete 800 tasks", "🔟", "tasks_completed", threshold: 800, rarity: "Legendary"),
    AchievementDef("tasks_1000", "tasks", "Kilo-Tasker", "Complete 1,000 tasks", "🗻", "tasks_completed", threshold: 1000, rarity: "Mythic"),
    AchievementDef("tasks_20000", "tasks", "Task Titan", "Complete 20,000 tasks", "🗿", "tasks_completed", threshold: 20000, rarity: "Mythic"),
    AchievementDef("tasks_50000", "tasks", "CHECKLIST MASTER", "Complete 50,000 tasks", "👑", "tasks_completed", threshold: 50000, rarity: "Mythic"),

    // Milestones
    AchievementDef("misc_welcome", "misc", "Welcome to Kairos", "Join Kairos", "👋", "event", event: "signup", rarity: "Common"),
    AchievementDef("misc_og", "misc", "OG", "One of the original Kairos users", "🥇", "event", event: "og", limitedAvailability: true, rarity: "Rare"),
    AchievementDef("misc_lofi", "misc", "LOFIIII", "Turn on the Lo-fi ambient sound", "🎧", "event", event: "lofi", rarity: "Rare"),
    AchievementDef("misc_light", "misc", "Come To the Light", "Switch to Light mode", "☀️", "event", event: "light_mode", rarity: "Rare"),
    AchievementDef("misc_busy", "misc", "Real Busy", "Schedule more than 10 tasks on a single day", "📅", "event", event: "busy_day", rarity: "Epic")
]

func defaultAchievementsData() -> KairosAchievementsData {
    KairosAchievementsData(unlocked: [:], countedTaskIds: [], lifetimeTasksCompleted: 0, goals: [nil, nil, nil])
}

func defaultFocusData() -> KairosFocusData {
    KairosFocusData(totalSeconds: 0, longestSessionSeconds: 0, dailyFocusLog: [:], dailyTasksLog: [:])
}
