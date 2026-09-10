import Foundation

enum AiRepositoryError: LocalizedError {
    case badResponse(Int)
    case malformedResponse
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Chat proxy error \(code)"
        case .malformedResponse: return "Malformed AI response"
        case .invalidJSON(let msg): return "AI response was not valid JSON: \(msg)"
        }
    }
}

struct AiPlanResult {
    var sections: [KairosSection]
    var recurringEvents: [KairosScheduleEvent]
}

/// Talks to the same Kairos Relay (Hack Club AI proxy) that Android's
/// AiRepository.sendChatRequest and Web's sendHackClubChatMessage use.
/// No server-side or endpoint differences — same URL, same auth header,
/// same per-message truncation limit, so history stays interchangeable
/// across platforms.
final class AiRepository {
    private let relayURL = URL(string: "https://kairos.kirosapp.workers.dev")!

    private var relaySecret: String {
        Bundle.main.object(forInfoDictionaryKey: "KAIROS_RELAY_SECRET") as? String ?? ""
    }

    func sendChatRequest(messages: [ChatMessage]) async throws -> String {
        var request = URLRequest(url: relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(relaySecret, forHTTPHeaderField: "X-Kairos-Auth")
        request.timeoutInterval = 60

        // Truncate to 4000 chars per message to match the proxy's limit
        // (mirrors Android's AiRepository.sendChatRequest truncation).
        let payloadMessages = messages.map { msg -> [String: String] in
            let content = msg.content.count > 4000
                ? String(msg.content.prefix(3997)) + "..."
                : msg.content
            return ["role": msg.role, "content": content]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["messages": payloadMessages])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AiRepositoryError.malformedResponse }
        guard http.statusCode == 200 else { throw AiRepositoryError.badResponse(http.statusCode) }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AiRepositoryError.malformedResponse
        }
        return content
    }

    func generateText(prompt: String) async throws -> String {
        let messages = [
            ChatMessage(role: "system", content: "You are a supportive productivity coach."),
            ChatMessage(role: "user", content: String(prompt.prefix(4000)))
        ]
        return try await sendChatRequest(messages: messages)
    }

    /// Extracts a structured routine (sections/tasks + recurring weekly
    /// events) from free text. Prompt shape mirrors Android's
    /// AiRepository.generatePlan and Web's generatePlanFromText.
    func generatePlan(input: String, languageName: String = "English") async throws -> AiPlanResult {
        let prompt = """
        You are an expert AI Study Coach. The user will provide a syllabus, assignment, or goal.
        Break it down into logical, actionable study sections and tasks.
        IMPORTANT: Write all section titles and task titles in \(languageName).
        ADDITIONALLY: if the user's text mentions any RECURRING weekly commitment, extract each one as a recurring event. Only extract things that repeat weekly on a fixed day/time.

        CRITICAL INSTRUCTION: You MUST respond with ONLY a valid, raw JSON object.
        Do NOT include markdown formatting, backticks, or the word 'json'.
        Just the raw object, using this exact structure:
        {
          "sections": [
            {
              "title": "Section 1: Research",
              "tasks": [
                { "title": "Find 3 academic sources" },
                { "title": "Read and highlight sources" }
              ]
            }
          ],
          "recurringEvents": [
            { "title": "Football Training", "category": "training", "day": 2, "start": "16:00", "end": "18:00" }
          ]
        }
        "day" is 0-6 where 0=Sunday. "category" is one of: sleep, class, tutoring, training, other. Times are 24-hour "HH:MM".

        User's Request:
        \(input)
        """

        let messages = [
            ChatMessage(role: "system", content: "You are an expert study coach that outputs raw JSON."),
            ChatMessage(role: "user", content: String(prompt.prefix(4000)))
        ]

        let raw = try await sendChatRequest(messages: messages)
        let text = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AiRepositoryError.invalidJSON(text)
        }

        let uniqueId = Int(Date().timeIntervalSince1970 * 1000)

        let sectionsArray = root["sections"] as? [[String: Any]] ?? []
        let sections: [KairosSection] = sectionsArray.enumerated().map { sIndex, secObj in
            let tasksArray = secObj["tasks"] as? [[String: Any]] ?? []
            let tasks: [KairosTask] = tasksArray.enumerated().map { tIndex, taskObj in
                KairosTask(
                    id: "ai-task-\(uniqueId)-\(sIndex)-\(tIndex)",
                    title: (taskObj["title"] as? String) ?? "Untitled Task",
                    completed: false,
                    archived: false,
                    date: nil
                )
            }
            return KairosSection(
                id: "ai-sec-\(uniqueId)-\(sIndex)",
                title: (secObj["title"] as? String) ?? "Untitled Section",
                archived: false,
                tasks: tasks
            )
        }

        let eventsArray = root["recurringEvents"] as? [[String: Any]] ?? []
        let events: [KairosScheduleEvent] = eventsArray.enumerated().compactMap { i, evObj in
            guard let title = evObj["title"] as? String,
                  let start = evObj["start"] as? String,
                  let end = evObj["end"] as? String else { return nil }
            let category = (evObj["category"] as? String) ?? "other"
            let day: Int
            if let d = evObj["day"] as? Int { day = d }
            else if let d = evObj["day"] as? String, let parsed = Int(d) { day = parsed }
            else { return nil }
            guard (0...6).contains(day) else { return nil }
            return KairosScheduleEvent(id: "ai-sched-\(uniqueId)-\(i)", title: title, category: category, day: day, start: start, end: end)
        }

        return AiPlanResult(sections: sections, recurringEvents: events)
    }
}
