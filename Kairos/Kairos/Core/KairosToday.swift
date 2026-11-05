import Foundation
import JavaScriptCore

struct KairosTodayRow: Decodable, Identifiable, Sendable {
    let key: String
    let id: String
    let kind: String
    let taskId: String?
    let boardId: String?
    let sectionId: String?
    let title: String
    let path: String
    let occurrenceDate: String?
    let date: String?
    let dueDate: String?
    let start: String?
    let end: String?
    let continued: Bool?
    let canComplete: Bool
    var searchRow: KairosSearchRow {
        .init(key: key, kind: occurrenceDate == nil ? "task" : "occurrence", title: title, path: path, label: "Task", assignmentTitle: nil,
              target: .init(kind: "task", boardId: boardId, sectionId: sectionId, taskId: taskId, occurrenceDate: occurrenceDate), completed: false, overdue: false, date: date, dateKind: "Scheduled", occurrenceDate: occurrenceDate)
    }
}
struct KairosTodaySnapshot: Decodable, Sendable {
    let date: String
    let overdue: [KairosTodayRow]
    let today: [KairosTodayRow]
    let unscheduled: [KairosTodayRow]
}
enum KairosToday {
    nonisolated static func validateAction(_ row: KairosTodayRow, planning: Bool, in plan: [String: Any]) throws {
        let boards = try KairosAIProposalEngine.maps(plan["boards"])
        let matches = boards.filter { $0["id"] as? String == row.boardId }
        guard row.kind == "task", row.occurrenceDate == nil, matches.count == 1, let board = matches.first, board["archived"] as? Bool != true else { throw KairosPlannerMerge.Conflict() }
        let sections = try KairosAIProposalEngine.maps(board["sections"]).filter { $0["id"] as? String == row.sectionId }
        guard sections.count == 1, let section = sections.first, section["archived"] as? Bool != true else { throw KairosPlannerMerge.Conflict() }
        let all = try boards.flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }.filter { $0["id"] as? String == row.taskId }
        guard all.count == 1, let task = try KairosAIProposalEngine.maps(section["tasks"]).first(where: { $0["id"] as? String == row.taskId }),
              task["archived"] as? Bool != true, task["completed"] as? Bool != true,
              (task["recurrence"] as? [String: Any])?["enabled"] as? Bool != true,
              !planning || task["scheduleLocked"] as? Bool != true else { throw KairosPlannerMerge.Conflict() }
    }
    nonisolated static func build(planJSON: String, today: String) throws -> KairosTodaySnapshot {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let context = JSContext() else { throw KairosPlannerSearch.Unavailable() }
        for name in ["recurrence-engine", "schedule-engine", "today-engine"] {
            guard let url = bundle.url(forResource: name, withExtension: "js") else { throw KairosPlannerSearch.Unavailable() }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            guard context.exception == nil else { throw KairosPlannerSearch.Unavailable() }
        }
        let args: [String: Any] = ["state": try KairosTouchSchedule.object(planJSON), "today": today]
        let output = context.objectForKeyedSubscript("kairosTodayRequest")?.call(withArguments: [try KairosTouchSchedule.json(args)])?.toString()
        guard context.exception == nil, let data = output?.data(using: .utf8) else { throw KairosPlannerSearch.Unavailable() }
        return try JSONDecoder().decode(KairosTodaySnapshot.self, from: data)
    }
}
