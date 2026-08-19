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
    var date: Date?
}

// Shape unconfirmed — empty in your sample data, and I didn't find explicit
// scheduleEvents field writes in app.js beyond passing scheduleData through.
// Flag for follow-up once you have a populated example.
struct KairosScheduleEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var startDate: Date?
    var endDate: Date?
}

// MARK: - User document (`users/{uid}`)

struct KairosUserDocument: Codable, Equatable {
    var settings: KairosUserSettings?
    var achievements: KairosAchievementsData?
    var focusData: KairosFocusData?
    // aiChatHistory intentionally omitted from MVP scope.
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

struct KairosAchievementsData: Codable, Equatable {
    var unlocked: [String: Bool]?
    var countedTaskIds: [String]?
    var lifetimeTasksCompleted: Int
    var goals: [String]?
}

struct KairosFocusData: Codable, Equatable {
    var totalSeconds: Int
    var longestSessionSeconds: Int
    var dailyFocusLog: [String: Int]?
    var dailyTasksLog: [String: Int]?
}
