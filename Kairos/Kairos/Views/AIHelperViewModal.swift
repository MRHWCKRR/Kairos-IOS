import Foundation
import Observation

@Observable
@MainActor
final class AIHelperViewModel {
    enum TargetBoardMode { case new, existing }

    var chatMessages: [ChatMessage] = []
    var userInput: String = ""
    var isLoading = false
    var isGeneratingBoard = false
    var errorMessage: String?

    var pendingPlan: AiPlanResult?
    var showConfirmationDialog = false
    var targetBoardMode: TargetBoardMode = .new
    var newBoardName: String = "AI Plan"
    var selectedExistingBoardID: String = ""

    private let aiRepository = AiRepository()
    private let profileRepo: UserProfileRepository
    private let planRepo: StudyPlanRepository

    init(profileRepo: UserProfileRepository, planRepo: StudyPlanRepository) {
        self.profileRepo = profileRepo
        self.planRepo = planRepo
        self.chatMessages = profileRepo.aiChatHistory
    }

    /// Call when the view reappears — picks up history loaded by the
    /// snapshot listener after this view model was first created.
    func syncHistoryFromProfile() {
        if chatMessages.isEmpty && !profileRepo.aiChatHistory.isEmpty {
            chatMessages = profileRepo.aiChatHistory
        }
    }

    func handleSend() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        chatMessages.append(ChatMessage(role: "user", content: text))
        userInput = ""
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let systemMessage = ChatMessage(
                    role: "system",
                    content: "You are a helpful, friendly assistant inside the Kairos productivity app. Always respond in English, regardless of what language the user writes in, unless they explicitly ask you to reply in a different language."
                )
                let history = Array(chatMessages.suffix(38))
                let reply = try await aiRepository.sendChatRequest(messages: [systemMessage] + history)
                chatMessages.append(ChatMessage(role: "assistant", content: reply))
            } catch {
                errorMessage = "AI Error: \(error.localizedDescription)"
                chatMessages.append(ChatMessage(role: "assistant", content: "Sorry, I hit an error: \(error.localizedDescription)"))
            }
            isLoading = false
            await saveHistory()
        }
    }

    func createPlanFromChat() {
        guard !chatMessages.isEmpty else { return }
        isLoading = true
        isGeneratingBoard = true
        errorMessage = nil

        Task {
            do {
                let transcript = chatMessages.suffix(20)
                    .map { "\($0.role): \($0.content)" }
                    .joined(separator: "\n")
                let prompt = "Extract a structured routine from this chat into raw JSON sections and tasks.\n\n" + transcript
                let result = try await aiRepository.generatePlan(input: prompt)
                pendingPlan = result
                showConfirmationDialog = true
            } catch {
                errorMessage = "Board generation failed: \(error.localizedDescription)"
            }
            isLoading = false
            isGeneratingBoard = false
        }
    }

    func clearChat() {
        chatMessages = []
        Task { await saveHistory() }
    }

    func confirmPlan() {
        guard let plan = pendingPlan else { return }
        let sections = plan.sections
        let events = plan.recurringEvents
        let mode = targetBoardMode
        let newTitle = newBoardName
        let existingID = selectedExistingBoardID

        Task {
            await planRepo.applyAiPlan(
                sections: sections,
                recurringEvents: events,
                newBoardTitle: mode == .new ? newTitle : nil,
                existingBoardID: mode == .existing ? existingID : nil
            )
            showConfirmationDialog = false
            pendingPlan = nil
        }
    }

    func dismissDialog() {
        showConfirmationDialog = false
        pendingPlan = nil
    }

    private func saveHistory() async {
        await profileRepo.saveAiChatHistory(Array(chatMessages.suffix(38)))
    }
}
