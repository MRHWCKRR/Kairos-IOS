import Foundation

struct KairosChatAction: Codable, Identifiable, Sendable {
    struct Arguments: Codable, Sendable {
        var taskId: String?
        var boardId: String?
        var sectionId: String?
        var title: String?
        var newTitle: String?
        var date: String?
        var startTime: String?
        var endTime: String?
        var completed: Bool?
        var minutesBefore: Int?
        var eventId: String?
        var occurrenceDate: String?
        var status: String?
        var day: Int?
        var start: String?
        var end: String?
        var category: String?
    }
    let type: String
    let args: Arguments
    // Proposals are immutable; the full payload identifies a preview row.
    var id: String { type + ":" + (args.taskId ?? args.sectionId ?? args.boardId ?? args.title ?? "") }
}

struct KairosChatResponse: Decodable {
    let reply: String
    let actions: [KairosChatAction]
    nonisolated static func parse(_ text: String) throws -> KairosChatResponse {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = cleaned.hasPrefix("```") ? cleaned.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n") : cleaned
        guard let data = json.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let actions = root["actions"] as? [[String: Any]], actions.count <= 10 else { throw KairosTaskMutation.Invalid() }
        for action in actions {
            guard let type = action["type"] as? String, let allowed = KairosChatActions.allowedFields[type], let args = action["args"] as? [String: Any], Set(args.keys).isSubset(of: allowed), args.values.allSatisfy({ !($0 is NSNull) }) else { throw KairosTaskMutation.Invalid() }
        }
        guard let response = try? JSONDecoder().decode(Self.self, from: data) else { throw KairosTaskMutation.Invalid() }
        return response
    }
}

enum KairosChatActions {
    nonisolated static let allowedFields: [String: Set<String>] = [
        "create_task": ["sectionId","title","date","startTime","endTime"], "update_task": ["taskId","newTitle","date","startTime","endTime","completed"], "complete_task": ["taskId"], "delete_task": ["taskId"],
        "create_board": ["title"], "update_board": ["boardId","newTitle"], "delete_board": ["boardId"], "create_section": ["boardId","title"], "update_section": ["sectionId","newTitle"], "delete_section": ["boardId","sectionId"],
        "set_task_reminder": ["taskId","minutesBefore"], "remove_task_reminder": ["taskId"], "update_task_occurrence": ["taskId","occurrenceDate","date","startTime","endTime","status"],
        "create_schedule_event": ["title","date","day","start","end","category"], "update_schedule_event": ["eventId","occurrenceDate","newTitle","date","start","end","category"], "delete_schedule_event": ["eventId","occurrenceDate"]
    ]
    static let instructions = """
    Return ONLY JSON {"reply":"Markdown response","actions":[]}. Omit unspecified argument fields; do not use null.
    You may propose these actions only, with args exactly as listed:
    create_schedule_event {title,date?,day?,start,end,category?}; update_schedule_event {eventId,occurrenceDate?,newTitle?,date?,start?,end?,category?}; delete_schedule_event {eventId,occurrenceDate?}; set_task_reminder {taskId,minutesBefore}; remove_task_reminder {taskId}; update_task_occurrence {taskId,occurrenceDate,date?,startTime?,endTime?,status?}.
    create_task {sectionId,title,date?,startTime?,endTime?}; update_task {taskId,newTitle?,date?,startTime?,endTime?,completed?}; complete_task {taskId}; delete_task {taskId};
    create_board {title}; update_board {boardId,newTitle}; delete_board {boardId}; create_section {boardId,title}; update_section {sectionId,newTitle}; delete_section {boardId,sectionId}.
    Dates are YYYY-MM-DD and times HH:MM. Use actual IDs from the current planner, never invent target IDs. Actions are proposals awaiting review, not executed changes. Do not claim success. Do not propose multiple actions targeting the same item. For a weekly fixed event update/delete require its original occurrenceDate. Never silently edit a series. For a recurring task use update_task_occurrence with its original occurrenceDate and status pending/completed/skipped. Task reminder minutesBefore is 1–10080; a series reminder applies to every occurrence. Create events with exactly one of date or day (0=Sunday to6=Saturday); weekly events start from today. Categories: sleep,class,tutoring,training,other. Automatic multi-assignment planning, whole-series edits, event import/feed actions remain web-only. Ask a clarification if a target or required field is unclear.
    """

    static func apply(_ actions: [KairosChatAction], to source: [KairosBoard], idPrefix: String? = nil) throws -> [KairosBoard] {
        guard !actions.isEmpty, actions.count <= 10 else { throw KairosTaskMutation.Invalid() }
        var boards = source
        for (actionIndex, action) in actions.enumerated() {
            let identity = idPrefix.map { $0 + "-\(actionIndex)" } ?? UUID().uuidString
            let a = action.args
            switch action.type {
            case "create_task":
                guard let section = a.sectionId, let title = a.title else { throw KairosTaskMutation.Invalid() }
                let id = "task-" + identity
                boards = try KairosTaskMutation.apply(.create(sectionID: section, taskID: id, title: title, parentTaskID: nil), to: boards)
                var patch = KairosTaskPatch()
                if let date = a.date { patch.date = .set(date) }
                if let start = a.startTime {
                    patch.startTime = .set(start)
                    if a.endTime == nil, let minutes = KairosScheduleProjection.minutes(start) { patch.endTime = .set(KairosScheduleProjection.clock((minutes + 60) % 1440)) }
                }
                if let end = a.endTime { patch.endTime = .set(end) }
                boards = try KairosTaskMutation.apply(.update(taskID: id, patch: patch, expected: nil), to: boards)
            case "update_task", "complete_task", "delete_task":
                guard let id = a.taskId, let task = boards.flatMap({ $0.sections.flatMap(\.tasks) }).first(where: { $0.id == id }), task.recurrence?.enabled != true else { throw KairosTaskMutation.Invalid() }
                if action.type == "delete_task" {
                    guard let section = boards.flatMap(\.sections).first(where: { $0.tasks.contains(where: { $0.id == id }) }) else { throw KairosTaskMutation.Invalid() }
                    boards = try KairosTaskMutation.apply(.delete(sectionID: section.id, taskID: id), to: boards)
                } else {
                    var patch = KairosTaskPatch()
                    if let title = a.newTitle { patch.title = .set(title) }
                    if let date = a.date { patch.date = .set(date) }
                    if let start = a.startTime {
                        patch.startTime = .set(start)
                        if a.endTime == nil, let minutes = KairosScheduleProjection.minutes(start) { patch.endTime = .set(KairosScheduleProjection.clock((minutes + KairosScheduleProjection.duration(task)) % 1440)) }
                    }
                    if let end = a.endTime { patch.endTime = .set(end) }
                    boards = try KairosTaskMutation.apply(.update(taskID: id, patch: patch, expected: task), to: boards)
                    if let completed = action.type == "complete_task" ? true : a.completed { boards = try KairosTaskMutation.apply(.setCompleted(taskID: id, completed: completed), to: boards) }
                }
            case "create_board":
                guard let title = a.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KairosTaskMutation.Invalid() }
                boards.append(.init(id: "board-" + identity, title: title, archived: false, sections: []))
            case "update_board", "delete_board", "create_section", "delete_section":
                guard let id = a.boardId, let bi = boards.firstIndex(where: { $0.id == id && !$0.archived }) else { throw KairosTaskMutation.Invalid() }
                if action.type == "delete_board" { boards.remove(at: bi) }
                else if action.type == "update_board" {
                    guard let title = a.newTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KairosTaskMutation.Invalid() }; boards[bi].title = title
                } else if action.type == "create_section" {
                    guard let title = a.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KairosTaskMutation.Invalid() }
                    boards[bi].sections.append(.init(id: "sec-" + identity, title: title, archived: false, tasks: []))
                } else {
                    guard let id = a.sectionId, boards[bi].sections.contains(where: { $0.id == id && !$0.archived }) else { throw KairosTaskMutation.Invalid() }
                    boards[bi].sections.removeAll { $0.id == id }
                }
            case "update_section":
                guard let id = a.sectionId, let bi = boards.firstIndex(where: { !$0.archived && $0.sections.contains(where: { $0.id == id && !$0.archived }) }), let si = boards[bi].sections.firstIndex(where: { $0.id == id }), let title = a.newTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KairosTaskMutation.Invalid() }
                boards[bi].sections[si].title = title
            default: throw KairosTaskMutation.Invalid()
            }
        }
        return boards
    }
}
