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
