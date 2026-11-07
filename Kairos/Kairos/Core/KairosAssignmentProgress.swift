import Foundation
import JavaScriptCore

struct KairosSessionReadiness: Decodable, Sendable {
    let state: String
    let waitingTitle: String?
    let needsReschedule: Bool?
}
struct KairosAssignmentSession: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let completed: Bool
    let date: String?
    let startTime: String?
    let minutes: Int
    let readiness: KairosSessionReadiness?
}
struct KairosAssignmentSummary: Decodable, Sendable {
    let parentId: String
    let parentTitle: String
    let total: Int
    let completed: Int
    let remainingMinutes: Int
    let dueDate: String?
    let status: String
    let lateSessions: Int
    let sessions: [KairosAssignmentSession]
    let ordered: Bool
    let readyCount: Int
    let waitingCount: Int
    let orderNeedsReview: Bool
    let isSession: Bool?
    let sessionIndex: Int?
    let readiness: KairosSessionReadiness?
}
enum KairosAssignmentProgress {
    nonisolated static func inputJSON(_ plan: [String: Any]) throws -> String {
        let boards = try KairosAIProposalEngine.maps(plan["boards"]).map { board -> [String: Any] in
            var value = board.filter { ["id", "title", "archived"].contains($0.key) }
            value["sections"] = try KairosAIProposalEngine.maps(board["sections"]).map { section -> [String: Any] in
                var selected = section.filter { ["id", "title", "archived"].contains($0.key) }
                selected["tasks"] = try KairosAIProposalEngine.maps(section["tasks"]).map { task -> [String: Any] in
                    var t = task.filter { ["id", "title", "archived", "completed", "date", "startTime", "endTime", "estimatedMinutes", "lastScheduledMinutes", "remainingMinutes", "dueDate", "assignmentId", "sessionIndex", "sessionOrder"].contains($0.key) }
                    if let rule = task["recurrence"] as? [String: Any] { t["recurrence"] = ["enabled": rule["enabled"] as? Bool == true] }
                    return t
                }
                return selected
            }
            return value
        }
        return try KairosTouchSchedule.json(["boards": boards])
    }
    nonisolated static func read(planJSON: String, taskID: String, today: String) throws -> KairosAssignmentSummary? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "assignment-progress-engine", withExtension: "js"), let context = JSContext() else { throw KairosPlannerSearch.Unavailable() }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil else { throw KairosPlannerSearch.Unavailable() }
        let arguments: [String: Any] = ["state": try KairosTouchSchedule.object(planJSON), "taskID": taskID, "today": today]
        let output = context.objectForKeyedSubscript("kairosAssignmentProgress")?.call(withArguments: [try KairosTouchSchedule.json(arguments)])?.toString()
        guard context.exception == nil, let data = output?.data(using: .utf8) else { throw KairosPlannerSearch.Unavailable() }
        return try JSONDecoder().decode(KairosAssignmentSummary?.self, from: data)
    }
}

struct KairosTaskEditGuard: Sendable {
    let taskID: String
    let boardID: String
    let sectionID: String
    let changesSchedule: Bool
    let unlocking: Bool
    nonisolated init(taskID: String, boardID: String, sectionID: String, changesSchedule: Bool, unlocking: Bool) {
        self.taskID = taskID; self.boardID = boardID; self.sectionID = sectionID; self.changesSchedule = changesSchedule; self.unlocking = unlocking
    }
    nonisolated static func capture(plan: [String: Any], taskID: String, changesSchedule: Bool, unlocking: Bool) throws -> Self {
        var found: [(String, String, Bool)] = []
        for board in try KairosAIProposalEngine.maps(plan["boards"]) {
            for section in try KairosAIProposalEngine.maps(board["sections"]) {
                for task in try KairosAIProposalEngine.maps(section["tasks"]) where task["id"] as? String == taskID {
                    guard let boardID = board["id"] as? String, let sectionID = section["id"] as? String,
                          board["archived"] as? Bool != true, section["archived"] as? Bool != true, task["archived"] as? Bool != true else { throw KairosPlannerMerge.Conflict() }
                    let locked = task["scheduleLocked"] as? Bool == true
                    if changesSchedule && (task["recurrence"] as? [String: Any])?["enabled"] as? Bool == true { throw KairosPlannerMerge.Conflict() }
                    if changesSchedule && locked && !unlocking { throw KairosPlannerMerge.Conflict() }
                    found.append((boardID, sectionID, locked))
                }
            }
        }
        guard found.count == 1, let target = found.first else { throw KairosPlannerMerge.Conflict() }
        return .init(taskID: taskID, boardID: target.0, sectionID: target.1, changesSchedule: changesSchedule, unlocking: unlocking && target.2)
    }
    nonisolated func validate(_ remote: [String: Any]) throws {
        let target = try Self.capture(plan: remote, taskID: taskID, changesSchedule: changesSchedule, unlocking: unlocking)
        guard target.boardID == boardID, target.sectionID == sectionID else { throw KairosPlannerMerge.Conflict() }
    }
}
