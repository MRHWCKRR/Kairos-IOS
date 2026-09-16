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

/// Talks to the Kairos AI API used by the web app.
/// The server-side relay keeps the AI provider credentials out of the app.
final class AiRepository {
    private let relayURL = URL(string: "https://kairos-xi-two.vercel.app/api/ai")!

    func sendChatRequest(messages: [ChatMessage]) async throws -> String {
        var request = URLRequest(url: relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

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
        var sections: [KairosSection] = []
        sections.reserveCapacity(sectionsArray.count)

        for (sIndex, secObj) in sectionsArray.enumerated() {
            guard let rawTitle = secObj["title"] as? String else { continue }
            let sectionTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sectionTitle.isEmpty else { continue }

            let tasksArray = secObj["tasks"] as? [[String: Any]] ?? []
            var tasks: [KairosTask] = []
            tasks.reserveCapacity(tasksArray.count)

            for (tIndex, taskObj) in tasksArray.enumerated() {
                guard let rawTaskTitle = taskObj["title"] as? String else { continue }
                let taskTitle = rawTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !taskTitle.isEmpty else { continue }

                tasks.append(KairosTask(
                    id: "ai-task-\(uniqueId)-\(sIndex)-\(tIndex)",
                    title: taskTitle,
                    completed: false,
                    archived: false,
                    date: nil
                ))
            }

            sections.append(KairosSection(
                id: "ai-sec-\(uniqueId)-\(sIndex)",
                title: sectionTitle,
                archived: false,
                tasks: tasks
            ))
        }

        guard !sections.isEmpty, sections.contains(where: { !$0.tasks.isEmpty }) else {
            throw AiRepositoryError.malformedResponse
        }

        let eventsArray = root["recurringEvents"] as? [[String: Any]] ?? []
        let allowedCategories = Set(["sleep", "class", "tutoring", "training", "other"])
        let events: [KairosScheduleEvent] = eventsArray.enumerated().compactMap { i, evObj in
            guard let rawTitle = evObj["title"] as? String,
                  let rawStart = evObj["start"] as? String,
                  let rawEnd = evObj["end"] as? String else { return nil }

            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = rawStart.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = rawEnd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, isValidTime(start), isValidTime(end), isStartBeforeEnd(start, end) else { return nil }

            let category = (evObj["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "other"
            guard allowedCategories.contains(category) else { return nil }

            let day: Int
            if let d = evObj["day"] as? Int { day = d }
            else if let d = evObj["day"] as? String, let parsed = Int(d) { day = parsed }
            else { return nil }
            guard (0...6).contains(day) else { return nil }

            return KairosScheduleEvent(id: "ai-sched-\(uniqueId)-\(i)", title: title, category: category, day: day, start: start, end: end)
        }

        return AiPlanResult(sections: sections, recurringEvents: events)
    }

    private func isValidTime(_ value: String) -> Bool {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0].count == 2,
              components[1].count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    private func isStartBeforeEnd(_ start: String, _ end: String) -> Bool {
        let startMinutes = minutesSinceMidnight(start)
        let endMinutes = minutesSinceMidnight(end)
        guard let startMinutes, let endMinutes else { return false }
        return startMinutes < endMinutes
    }

    private func minutesSinceMidnight(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
}
