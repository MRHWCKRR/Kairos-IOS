import AppIntents

struct OpenKairosIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Kairos"
    static let description = IntentDescription("Open the Kairos study planner.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct StartFocusTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Timer"
    static let description = IntentDescription("Start the Kairos focus timer.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocusTimerCoordinator.shared.start()
        }
        return .result()
    }
}

struct PauseFocusTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Focus Timer"
    static let description = IntentDescription("Pause the Kairos focus timer and keep the elapsed time.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocusTimerCoordinator.shared.pause()
        }
        return .result()
    }
}

struct KairosAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenKairosIntent(),
            phrases: [
                "Open Kairos",
                "Open my Kairos study planner"
            ],
            shortTitle: "Open Kairos",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: StartFocusTimerIntent(),
            phrases: [
                "Start my focus timer in Kairos",
                "Start a focus session in Kairos",
                "Resume my focus timer in Kairos"
            ],
            shortTitle: "Start Focus",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: PauseFocusTimerIntent(),
            phrases: [
                "Pause my focus timer in Kairos",
                "Pause my focus session in Kairos"
            ],
            shortTitle: "Pause Focus",
            systemImageName: "pause.circle"
        )
    }
}
