import Foundation

struct KairosSessionRow: Decodable, Identifiable, Sendable {
    let taskId: String
    let title: String
    let minutes: Int
    let date: String
    let startTime: String
    let endTime: String
    var id: String { taskId }
}
struct KairosSessionReview: Sendable, Identifiable {
    let id: String
    let ownerID: String
    let planID: String
    let createdAt: Double
    let commandJSON: String
    let expectedJSON: String
    let sourceJSON: String
    let rows: [KairosSessionRow]
}
struct KairosSessionUndo: Codable, Sendable, Identifiable {
    let id: String
    let ownerID: String
    let planID: String
    let recordJSON: String
}
enum KairosSessionPlanning {
    nonisolated static func preview(state: [String: Any], taskID: String, total: Int, size: Int, ordered: Bool, labels: [String], revising: Bool = false, settings: KairosPlanningSettings, ownerID: String, planID: String, now: Date = Date()) throws -> KairosSessionReview {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: settings.timezone) else { throw KairosTouchSchedule.Failure("Review your timezone.") }
        calendar.timeZone = zone
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = zone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: now)
        guard let end = calendar.date(byAdding: .day, value: 30, to: now) else { throw KairosTouchSchedule.Failure("Cannot determine a planning range.") }
        let input: [String: Any] = ["taskId": taskID, revising ? "remainingMinutes" : "totalMinutes": total, "sessionMinutes": size, "ordered": ordered, "labels": labels,
                                    "from": date, "to": formatter.string(from: end), "timezone": settings.timezone,
                                    "dayStart": "07:00", "dayEnd": "22:00", "gapMinutes": settings.gapMinutes, "dailyLimitMinutes": settings.dailyLimitMinutes,
                                    "weeklyAvailability": try settings.weeklyAvailability.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()]
        let ids = (0..<40).map { _ in "session-" + UUID().uuidString }
        let output = try KairosTouchSchedule.object(KairosFindTime.run(["mode": revising ? "preview-revision" : "preview", "state": state, "input": input, "ids": ids, "now": now.timeIntervalSince1970 * 1000, "timezone": settings.timezone], entry: "kairosSessionRequest"))
        guard let command = output["command"] as? [String: Any], let expected = output["expected"] as? [String: Any], let rows = output["rows"] else { throw KairosTouchSchedule.Failure("Could not review these sessions.") }
        let source = try sourceFields(state, taskID: taskID)
        return .init(id: "native-sessions-" + UUID().uuidString, ownerID: ownerID, planID: planID, createdAt: now.timeIntervalSince1970 * 1000, commandJSON: try KairosTouchSchedule.json(command), expectedJSON: try KairosTouchSchedule.json(expected), sourceJSON: try KairosTouchSchedule.json(source), rows: try JSONDecoder().decode([KairosSessionRow].self, from: JSONSerialization.data(withJSONObject: rows)))
    }
    nonisolated static func apply(plan: [String: Any], profile: [String: Any], review: KairosSessionReview, now: Date = Date()) throws -> (plan: [String: Any], undo: KairosSessionUndo) {
        let state = try KairosFindTime.state(plan), command = try KairosTouchSchedule.object(review.commandJSON), expected = try KairosTouchSchedule.object(review.expectedJSON)
        guard let parentID = command["parentId"] as? String, try KairosTouchSchedule.json(sourceFields(state, taskID: parentID)) == review.sourceJSON else { throw KairosTouchSchedule.Failure("The assignment title or priority changed. Review these sessions again.") }
        let output = try KairosTouchSchedule.object(KairosFindTime.run(["mode": "apply", "state": state, "command": command, "expected": expected, "profile": ["settings": profile["settings"] ?? [:]], "now": now.timeIntervalSince1970 * 1000, "timezone": (command["options"] as? [String: Any])?["timezone"] ?? "UTC"], entry: "kairosSessionRequest"))
        guard let next = output["next"] as? [String: Any], let result = output["result"] as? [String: Any], let record = result["planningUndo"] as? [String: Any], let entries = record["entries"] as? [[String: Any]] else { throw KairosTouchSchedule.Failure("Could not save a reversible session plan.") }
        var boards = try KairosAIProposalEngine.maps(plan["boards"])
        let projected = try KairosAIProposalEngine.maps(next["boards"])
        var matches = 0
        for bi in boards.indices {
            var sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
            let newSections = try KairosAIProposalEngine.maps(projected[bi]["sections"])
            for si in sections.indices {
                var tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"])
                let newTasks = try KairosAIProposalEngine.maps(newSections[si]["tasks"])
                for ti in tasks.indices {
                    guard let id = tasks[ti]["id"] as? String else { continue }
                    if id == parentID { matches += 1 }
                    guard let entry = entries.first(where: { $0["id"] as? String == id }), entry["created"] as? Bool != true,
                          let changed = newTasks.first(where: { $0["id"] as? String == id }) else { continue }
                    for key in entry["keys"] as? [String] ?? [] { tasks[ti][key] = changed[key] }
                }
                for created in newTasks where entries.contains(where: { $0["id"] as? String == created["id"] as? String && $0["created"] as? Bool == true }) { tasks.append(created) }
                sections[si]["tasks"] = tasks
            }
            boards[bi]["sections"] = sections
        }
        guard matches == 1 else { throw KairosTouchSchedule.Failure("This assignment moved or is ambiguous.") }
        var updated = plan; updated["boards"] = boards
        return (updated, .init(id: review.id, ownerID: review.ownerID, planID: review.planID, recordJSON: try KairosTouchSchedule.json(record)))
    }
    nonisolated private static func sourceFields(_ state: [String: Any], taskID: String) throws -> [String: Any] {
        let tasks = try KairosAIProposalEngine.maps(state["boards"]).flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        let matches = tasks.filter { $0["id"] as? String == taskID }
        guard matches.count == 1 else { throw KairosTouchSchedule.Failure("This assignment is missing or ambiguous.") }
        return matches[0].filter { ["title", "priority"].contains($0.key) }
    }
    nonisolated static func undo(plan: [String: Any], saved: KairosSessionUndo) throws -> [String: Any] {
        let record = try KairosTouchSchedule.object(saved.recordJSON), state = try KairosFindTime.state(plan)
        let output = try KairosTouchSchedule.object(KairosFindTime.run(["mode": "undo", "state": state, "record": record, "timezone": record["timezone"] ?? "UTC"], entry: "kairosSessionRequest"))
        guard let next = output["next"] as? [String: Any], let entries = record["entries"] as? [[String: Any]] else { throw KairosTouchSchedule.Failure("Could not confirm Undo.") }
        let projected = try KairosAIProposalEngine.maps(next["boards"])
        var boards = try KairosAIProposalEngine.maps(plan["boards"])
        for bi in boards.indices {
            var sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
            let newSections = try KairosAIProposalEngine.maps(projected[bi]["sections"])
            for si in sections.indices {
                var tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"])
                let newTasks = try KairosAIProposalEngine.maps(newSections[si]["tasks"])
                for ti in tasks.indices {
                    guard let id = tasks[ti]["id"] as? String, let entry = entries.first(where: { $0["id"] as? String == id }), let changed = newTasks.first(where: { $0["id"] as? String == id }) else { continue }
                    if entry["created"] as? Bool == true { tasks[ti]["archived"] = true }
                    else { for key in entry["keys"] as? [String] ?? [] { tasks[ti][key] = changed[key] } }
                }
                sections[si]["tasks"] = tasks
            }
            boards[bi]["sections"] = sections
        }
        var updated = plan; updated["boards"] = boards; return updated
    }
}
