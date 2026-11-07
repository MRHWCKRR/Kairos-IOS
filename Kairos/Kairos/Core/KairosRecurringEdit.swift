import Foundation
import JavaScriptCore

struct KairosRepeatRule: Codable, Equatable, Sendable {
    var enabled = true
    var frequency = "daily"
    var interval = 1
    var weekdays: [Int] = []
    var monthlyMode: String? = "date"
    var monthDay: Int? = 1
    var weekdayPosition: String? = "first"
    var weekday: Int? = 1
    var month: Int? = 1
    var startDate: String
    var endType = "never"
    var endDate: String?
    var count: Int?
    var mode = "flexible"
}

struct KairosSeriesBaseline: Equatable, Sendable {
    let boardID: String
    let sectionID: String
    let taskID: String
    let taskJSON: String
}
struct KairosRecurringEditRequest: Codable, Equatable, Sendable {
    var scope: String
    var day: String
    var rule: KairosRepeatRule
    var title: String
    var startTime: String?
    var endTime: String?
    var allowCompleted = false
}
struct KairosRecurringEditPreview: Decodable, Sendable {
    struct Placement: Decodable, Sendable {
        let date: String
        let startTime: String?
        let endTime: String?
    }
    let description: String
    let before: [Placement]
    let after: [Placement]
    let preserved: Int
}
struct KairosRecurringSeed: Sendable {
    var rule: KairosRepeatRule
    var title: String
    var startTime: String?
    var endTime: String?
    var recurring: Bool
}

enum KairosRecurringEdit {
    struct Invalid: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    nonisolated private static func object(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8), let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KairosRecurrence.Unavailable() }
        return result
    }
    nonisolated private static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
    nonisolated private static func run(_ args: [String: Any]) throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "recurrence-engine", withExtension: "js"), let context = JSContext() else { throw KairosRecurrence.Unavailable() }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil else { throw KairosRecurrence.Unavailable() }
        let output = context.objectForKeyedSubscript("kairosRecurringEditRequest")?.call(withArguments: [try json(args)])?.toString()
        if let error = context.exception { throw Invalid(message: error.toString() ?? "Review this repeat rule.") }
        guard let output else { throw KairosRecurrence.Unavailable() }
        return try object(output)
    }
    nonisolated private static func location(_ plan: [String: Any], taskID: String) throws -> (Int, Int, Int) {
        let boards = try KairosAIProposalEngine.maps(plan["boards"])
        var found: [(Int, Int, Int)] = []
        for bi in boards.indices {
            let sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
            for si in sections.indices {
                let tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"])
                for ti in tasks.indices where tasks[ti]["id"] as? String == taskID { found.append((bi, si, ti)) }
            }
        }
        guard found.count == 1, let (bi, si, ti) = found.first else { throw KairosPlannerMerge.Conflict() }
        let board = boards[bi], sections = try KairosAIProposalEngine.maps(board["sections"]), section = sections[si], tasks = try KairosAIProposalEngine.maps(section["tasks"])
        guard let bid = board["id"] as? String, let sid = section["id"] as? String,
              boards.filter({ $0["id"] as? String == bid }).count == 1,
              sections.filter({ $0["id"] as? String == sid }).count == 1,
              board["archived"] as? Bool != true, section["archived"] as? Bool != true, tasks[ti]["archived"] as? Bool != true else { throw KairosPlannerMerge.Conflict() }
        return (bi, si, ti)
    }
    nonisolated static func capture(_ plan: [String: Any], taskID: String) throws -> KairosSeriesBaseline {
        let (bi, si, ti) = try location(plan, taskID: taskID)
        let boards = try KairosAIProposalEngine.maps(plan["boards"]), sections = try KairosAIProposalEngine.maps(boards[bi]["sections"]), tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"])
        let raw = tasks[ti]
        var input = try KairosRecurrence.input(raw)
        for key in ["completed", "parentTaskID", "assignmentId", "sessionIndex", "sessionOrder", "focusLoggedSeconds", "remainingMinutes"] { input[key] = raw[key] }
        // Converting a task with children would orphan the ordinary-task relationship.
        let all = try boards.flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        input["hasChildren"] = all.contains { $0["parentTaskID"] as? String == taskID || $0["assignmentId"] as? String == taskID }
        return .init(boardID: boards[bi]["id"] as! String, sectionID: sections[si]["id"] as! String, taskID: taskID, taskJSON: try json(input))
    }
    nonisolated static func seed(_ baseline: KairosSeriesBaseline, on day: String? = nil) throws -> KairosRecurringSeed {
        let task = try object(baseline.taskJSON), recurring = (task["recurrence"] as? [String: Any])?["enabled"] as? Bool == true
        let date = (task["recurrence"] as? [String: Any])?["startDate"] as? String ?? task["date"] as? String ?? ""
        let result = try run(["scope": "seed", "task": task, "day": day as Any? ?? NSNull()])
        var rule = KairosRepeatRule(startDate: date)
        if recurring, let raw = result["rule"] as? [String: Any] {
            rule = try JSONDecoder().decode(KairosRepeatRule.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        let occurrence = result["occurrence"] as? [String: Any], effective = occurrence?["task"] as? [String: Any] ?? task
        return .init(rule: rule, title: effective["title"] as? String ?? "", startTime: effective["startTime"] as? String, endTime: effective["endTime"] as? String, recurring: recurring)
    }
    nonisolated private static func arguments(_ baseline: KairosSeriesBaseline, request: KairosRecurringEditRequest, newTaskID: String, preview: Bool) throws -> [String: Any] {
        let task = try object(baseline.taskJSON)
        guard task["hasChildren"] as? Bool != true, task["parentTaskID"] == nil, task["assignmentId"] == nil, task["sessionOrder"] == nil, task["sessionIndex"] == nil else { throw Invalid(message: "Repeat rules require a standalone task without linked sessions or subtasks.") }
        let rule = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request.rule))
        // Include explicit nulls so clearing the template's time is an intentional edit.
        let changes: [String: Any] = ["title": request.title.trimmingCharacters(in: .whitespacesAndNewlines), "startTime": request.startTime as Any? ?? NSNull(), "endTime": request.endTime as Any? ?? NSNull()]
        return ["task": task, "scope": request.scope, "day": request.day, "rule": rule, "changes": changes, "newTaskID": newTaskID, "preview": preview, "allowCompleted": request.allowCompleted]
    }
    nonisolated static func preview(_ baseline: KairosSeriesBaseline, request: KairosRecurringEditRequest) throws -> KairosRecurringEditPreview {
        let result = try run(arguments(baseline, request: request, newTaskID: "native-preview", preview: true))
        return try JSONDecoder().decode(KairosRecurringEditPreview.self, from: JSONSerialization.data(withJSONObject: result["preview"] as Any))
    }
    nonisolated private static func mergeTask(_ output: [String: Any], source: [String: Any], new: Bool) throws -> [String: Any] {
        var result = source
        for key in ["id", "title", "date", "startTime", "endTime", "completed"] { if let value = output[key] { result[key] = value } }
        if new { result.removeValue(forKey: "focusLoggedSeconds"); result.removeValue(forKey: "remainingMinutes") }
        let oldRule = source["recurrence"] as? [String: Any] ?? [:]
        guard let rule = output["recurrence"] as? [String: Any] else { throw KairosRecurrence.Unavailable() }
        var combined = oldRule
        let fields = ["enabled","frequency","interval","weekdays","monthlyMode","monthDay","weekdayPosition","weekday","month","startDate","endType","endDate","count","mode"]
        combined.removeValue(forKey: "preset")
        for key in fields { combined[key] = rule[key] ?? NSNull() }
        let old = oldRule["exceptions"] as? [String: Any] ?? [:]
        var exceptions: [String: Any] = [:]
        for (date, value) in rule["exceptions"] as? [String: Any] ?? [:] {
            guard let projected = value as? [String: Any] else { throw KairosRecurrence.Unavailable() }
            var raw = new ? [:] : old[date] as? [String: Any] ?? [:]
            for (key, value) in projected {
                if key == "override", let changes = value as? [String: Any] {
                    var override = raw["override"] as? [String: Any] ?? [:]
                    let known = Set(["date","startTime","endTime","durationMinutes","title","notes","estimatedMinutes","checklist","reminderMinutes"])
                    let oldItems = override["checklist"]
                    for field in known { override.removeValue(forKey: field) }
                    for (field, entry) in changes { override[field] = entry }
                    if changes["checklist"] != nil, let oldItems { override["checklist"] = oldItems }
                    raw["override"] = override
                } else { raw[key] = value }
            }
            if projected["override"] == nil, let oldOverride = raw["override"] as? [String: Any] {
                let known = Set(["date","startTime","endTime","durationMinutes","title","notes","estimatedMinutes","checklist","reminderMinutes"])
                let metadata = oldOverride.filter { !known.contains($0.key) }
                raw["override"] = metadata.isEmpty ? nil : metadata
            }
            exceptions[date] = raw
        }
        if !new {
            let known = Set(["status","completedAt","skippedAt","focusLoggedSeconds","remainingMinutes","override"])
            for (date, value) in old where exceptions[date] == nil {
                if let raw = value as? [String: Any] {
                    var metadata = raw.filter { !known.contains($0.key) }
                    if let override = raw["override"] as? [String: Any] {
                        let fields = Set(["date","startTime","endTime","durationMinutes","title","notes","estimatedMinutes","checklist","reminderMinutes"])
                        let extra = override.filter { !fields.contains($0.key) }
                        if !extra.isEmpty { metadata["override"] = extra }
                    }
                    if !metadata.isEmpty { exceptions[date] = metadata }
                }
            }
        }
        combined["exceptions"] = exceptions; result["recurrence"] = combined
        return result
    }
    nonisolated static func apply(_ plan: [String: Any], baseline: KairosSeriesBaseline, request: KairosRecurringEditRequest, newTaskID: String, allowCompleted: Bool = false) throws -> [String: Any] {
        if request.allowCompleted && !allowCompleted { throw Invalid(message: "Your completed-task rescheduling preference changed. Preview again.") }
        guard try capture(plan, taskID: baseline.taskID) == baseline else { throw KairosPlannerMerge.Conflict() }
        let (bi, si, ti) = try location(plan, taskID: baseline.taskID)
        var boards = try KairosAIProposalEngine.maps(plan["boards"]), sections = try KairosAIProposalEngine.maps(boards[bi]["sections"]), tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"])
        let all = try boards.flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        guard !newTaskID.isEmpty, !all.contains(where: { $0["id"] as? String == newTaskID }) else { throw KairosPlannerMerge.Conflict() }
        let result = try run(arguments(baseline, request: request, newTaskID: newTaskID, preview: false))
        let output = try KairosAIProposalEngine.maps(result["tasks"])
        guard (1...2).contains(output.count), output[0]["id"] as? String == baseline.taskID else { throw KairosRecurrence.Unavailable() }
        let source = tasks[ti]; tasks[ti] = try mergeTask(output[0], source: source, new: false)
        if output.count == 2 { tasks.insert(try mergeTask(output[1], source: source, new: true), at: ti + 1) }
        sections[si]["tasks"] = tasks; boards[bi]["sections"] = sections
        var updated = plan; updated["boards"] = boards; return updated
    }
    nonisolated static func create(_ plan: [String: Any], sectionID: String, taskID: String, title: String, rule: KairosRepeatRule, startTime: String? = nil, endTime: String? = nil) throws -> [String: Any] {
        var boards = try KairosAIProposalEngine.maps(plan["boards"])
        var locations: [(Int, Int)] = []
        for bi in boards.indices {
            let sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
            for si in sections.indices where sections[si]["id"] as? String == sectionID { locations.append((bi, si)) }
            for section in sections { guard !(try KairosAIProposalEngine.maps(section["tasks"])).contains(where: { $0["id"] as? String == taskID }) else { throw KairosPlannerMerge.Conflict() } }
        }
        guard locations.count == 1, let (bi, si) = locations.first, boards[bi]["archived"] as? Bool != true,
              let bid = boards[bi]["id"] as? String, boards.filter({ $0["id"] as? String == bid }).count == 1 else { throw KairosPlannerMerge.Conflict() }
        var sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
        guard sections[si]["archived"] as? Bool != true else { throw KairosPlannerMerge.Conflict() }
        let source: [String: Any] = ["id": taskID, "title": title, "completed": false, "archived": false]
        let baseline = KairosSeriesBaseline(boardID: bid, sectionID: sectionID, taskID: taskID, taskJSON: try json(source))
        let request = KairosRecurringEditRequest(scope: "create", day: rule.startDate, rule: rule, title: title, startTime: startTime, endTime: endTime)
        let result = try run(arguments(baseline, request: request, newTaskID: "unused", preview: false)), output = try KairosAIProposalEngine.maps(result["tasks"])
        guard let task = output.first else { throw KairosRecurrence.Unavailable() }
        var tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"]); tasks.append(task); sections[si]["tasks"] = tasks; boards[bi]["sections"] = sections
        var updated = plan; updated["boards"] = boards; return updated
    }
}
