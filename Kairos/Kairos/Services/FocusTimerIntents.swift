import AppIntents

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
            intent: StartFocusTimerIntent(),
            phrases: [
                "Start my focus timer in Kairos",
                "Start a focus session in Kairos"
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
