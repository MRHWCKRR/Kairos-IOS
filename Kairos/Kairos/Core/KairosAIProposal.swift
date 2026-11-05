import Foundation
import CryptoKit

struct KairosAIProposal: Codable, Identifiable, Sendable {
    struct Row: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let action: String
        let before: String
        let after: String
        let destructive: Bool
    }
    let version: Int
    let id: String
    let ownerID: String
    let chatID: String
    let planID: String
    let timezone: String
    let createdAt: Double
    let beforeFingerprint: String
    let request: String
    let actions: [KairosChatAction]
    let rows: [Row]
}

enum KairosAIProposalEngine {
    struct Invalid: LocalizedError {
        let message: String
        nonisolated var errorDescription: String? { message }
        nonisolated init(_ message: String) { self.message = message }
    }
    struct Prepared {
        let before: [String: Any]
        let after: [String: Any]
        let rows: [KairosAIProposal.Row]
        let completedTaskIDs: [String]
    }
    nonisolated static func digest(_ value: Any) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func maps(_ value: Any?) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let items = value as? [[String: Any]] else { throw Invalid("This planner has unreadable data. Review it on the web.") }
        return items
    }
    nonisolated static func reviewState(_ plan: [String: Any]) throws -> [String: Any] {
        let boards = try maps(plan["boards"]).map { board in
            var value = board.filter { ["id","title","archived","boardDescription"].contains($0.key) }
            value["sections"] = try maps(board["sections"]).map { section in
                var sectionValue = section.filter { ["id","title","archived"].contains($0.key) }
                sectionValue["tasks"] = try maps(section["tasks"]).map { task in
                    var selected = task.filter { ["id","title","archived","completed","date","startTime","endTime","dueTime","dueDate","taskDescription","notes","priority","estimatedMinutes","lastScheduledMinutes","parentTaskID","checklist","reminderMinutes","scheduleLocked","schedulingPreference"].contains($0.key) }
                    if task["recurrence"] != nil { selected["recurrence"] = try KairosRecurrence.input(task)["recurrence"] }
                    return selected
                }
                return sectionValue
            }
            return value
        }
        return ["boards": boards, "scheduleEvents": KairosScheduleProjection.eventInput(try maps(plan["scheduleEvents"]))]
    }
    nonisolated static func fingerprint(_ plan: [String: Any]) throws -> String { try digest(reviewState(plan)) }
    nonisolated static func validate(_ proposal: KairosAIProposal) throws {
        guard proposal.version == 1, !proposal.id.isEmpty, !proposal.ownerID.isEmpty, !proposal.chatID.isEmpty, !proposal.planID.isEmpty,
              proposal.createdAt.isFinite, proposal.createdAt > 0, TimeZone(identifier: proposal.timezone) != nil,
              (1...10).contains(proposal.actions.count), proposal.rows.count == proposal.actions.count,
              proposal.beforeFingerprint.count == 64 else { throw Invalid("This saved preview cannot be read safely. Update Kairos or discard it.") }
    }
    static func make(actions: [KairosChatAction], plan: [String: Any], ownerID: String, chatID: String, planID: String, timezone: String, request: String) throws -> KairosAIProposal {
        let id = "proposal-" + UUID().uuidString
        let initial = KairosAIProposal(version: 1, id: id, ownerID: ownerID, chatID: chatID, planID: planID, timezone: timezone, createdAt: Date().timeIntervalSince1970 * 1000, beforeFingerprint: try fingerprint(plan), request: String(request.prefix(4000)), actions: actions, rows: [])
        let prepared = try transform(initial, plan: plan)
        let proposal = KairosAIProposal(version: 1, id: id, ownerID: ownerID, chatID: chatID, planID: planID, timezone: timezone, createdAt: initial.createdAt, beforeFingerprint: initial.beforeFingerprint, request: initial.request, actions: actions, rows: prepared.rows)
        try validate(proposal)
        return proposal
    }
    static func prepare(_ proposal: KairosAIProposal, plan: [String: Any]) throws -> Prepared {
        try validate(proposal)
        guard try fingerprint(plan) == proposal.beforeFingerprint else { throw Invalid("Your planner changed since this preview. Discard it and ask Kairos for an updated preview.") }
        return try transform(proposal, plan: plan)
    }
    nonisolated static func payloadFingerprint(_ proposal: KairosAIProposal) throws -> String {
        let data = try JSONEncoder().encode(proposal)
        return try digest(JSONSerialization.jsonObject(with: data))
    }
    nonisolated static func receipt(_ proposal: KairosAIProposal) throws -> [String: Any] {
        ["id": proposal.id, "createdAt": proposal.createdAt, "fingerprint": try payloadFingerprint(proposal)]
    }
    nonisolated static func wasApplied(_ proposal: KairosAIProposal, plan: [String: Any]) throws -> Bool {
        let receipts = try maps(plan["aiNativeActionReceipts"])
        if let receipt = receipts.first(where: { $0["id"] as? String == proposal.id }) {
            guard receipt["fingerprint"] as? String == (try payloadFingerprint(proposal)) else { throw Invalid("This operation identity belongs to another preview.") }
            return true
        }
        guard proposal.createdAt > (plan["aiNativeActionReceiptFloor"] as? Double ?? 0) else { throw Invalid("This preview is too old to retry safely. Check your planner before requesting a new change.") }
        return false
    }

    private static func transform(_ proposal: KairosAIProposal, plan: [String: Any]) throws -> Prepared {
        guard (1...10).contains(proposal.actions.count) else { throw Invalid("Review from 1 to 10 changes at a time.") }
        var next = plan, rows: [KairosAIProposal.Row] = [], completedIDs: [String] = []
        for (index, action) in proposal.actions.enumerated() {
            let before = next
            switch action.type {
            case "set_task_reminder", "remove_task_reminder", "update_task_occurrence":
                try editTask(action, plan: &next)
            case "create_schedule_event", "update_schedule_event", "delete_schedule_event":
                try editEvent(action, plan: &next, timezone: proposal.timezone, createdAt: proposal.createdAt, identity: proposal.id + "-\(index)")
            default:
                let known = try reviewState(next)
                let boards = try JSONDecoder().decode([KairosBoard].self, from: JSONSerialization.data(withJSONObject: known["boards"] ?? []))
                let changed = try KairosChatActions.apply([action], to: boards, idPrefix: proposal.id + "-\(index)")
                let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed))
                next = try KairosPlannerMerge.applyingKnownEdits(base: ["boards": known["boards"] ?? []], local: ["boards": encoded], to: next)
                if (action.type == "complete_task" || action.args.completed == true), let id = action.args.taskId, let old = try? task(id, plan: before), old["completed"] as? Bool != true { completedIDs.append(id) }
            }
            let title = targetTitle(action, before: before)
            rows.append(.init(id: proposal.id + "-\(index)", title: title, action: action.type.replacingOccurrences(of: "_", with: " ").capitalized,
                              before: describe(action, plan: before), after: describe(action, plan: next), destructive: action.type.hasPrefix("delete_")))
        }
        return Prepared(before: plan, after: next, rows: rows, completedTaskIDs: completedIDs)
    }
    private static func task(_ id: String, plan: [String: Any]) throws -> [String: Any] {
        var found: [[String: Any]] = []
        for board in try maps(plan["boards"]) where board["archived"] as? Bool != true {
            for section in try maps(board["sections"]) where section["archived"] as? Bool != true {
                found += try maps(section["tasks"]).filter { $0["id"] as? String == id && $0["archived"] as? Bool != true }
            }
        }
        guard found.count == 1 else { throw Invalid("The target task is missing, archived, or ambiguous.") }
        return found[0]
    }
    private static func editTask(_ action: KairosChatAction, plan: inout [String: Any]) throws {
        guard let id = action.args.taskId else { throw Invalid("Choose an exact task.") }
        var updated = try task(id, plan: plan)
        if action.type == "update_task_occurrence" {
            guard updated["scheduleLocked"] as? Bool != true, let original = action.args.occurrenceDate, KairosScheduleProjection.validDay(original) else { throw Invalid("Choose an unlocked task and its original occurrence date.") }
            let rule = updated["recurrence"] as? [String: Any] ?? [:]
            let exception = (rule["exceptions"] as? [String: Any])?[original] as? [String: Any] ?? [:]
            let display = (exception["override"] as? [String: Any])?["date"] as? String ?? original
            guard let occurrence = try KairosRecurrence.occurrences(task: updated, on: display).first(where: { $0.occurrenceDate == original }) else { throw Invalid("This recurring occurrence no longer exists.") }
            if action.args.date != nil || action.args.startTime != nil || action.args.endTime != nil {
                let date = action.args.date ?? occurrence.displayDate
                let start = action.args.startTime ?? occurrence.startTime
                var end = action.args.endTime ?? occurrence.endTime
                if let shifted = action.args.startTime, action.args.endTime == nil, let minutes = KairosScheduleProjection.minutes(shifted) { end = KairosScheduleProjection.clock(minutes + KairosScheduleProjection.duration(occurrence.task)) }
                updated = try KairosRecurrence.settingSchedule(task: updated, occurrence: occurrence, schedule: .init(date: date, startTime: start, endTime: end))
            }
            if let status = action.args.status {
                let date = action.args.date ?? display
                guard let fresh = try KairosRecurrence.occurrences(task: updated, on: date).first(where: { $0.occurrenceDate == original }) else { throw Invalid("Could not re-read the moved occurrence.") }
                updated = try KairosRecurrence.settingStatus(task: updated, occurrence: fresh, status: status, timestamp: ISO8601DateFormatter().string(from: Date()))
            }
            guard action.args.status != nil || action.args.date != nil || action.args.startTime != nil || action.args.endTime != nil else { throw Invalid("Choose a date, time, or status change.") }
        } else {
            if action.type == "set_task_reminder" {
                guard let minutes = action.args.minutesBefore, (1...10080).contains(minutes) else { throw Invalid("Choose a reminder from 1 to 10080 minutes before the task.") }
                updated["reminderMinutes"] = minutes
            } else { updated["reminderMinutes"] = NSNull() }
            if var recurrence = updated["recurrence"] as? [String: Any], var exceptions = recurrence["exceptions"] as? [String: Any] {
                for date in Array(exceptions.keys) {
                    if var item = exceptions[date] as? [String: Any], var override = item["override"] as? [String: Any] { override.removeValue(forKey: "reminderMinutes"); item["override"] = override; exceptions[date] = item }
                }
                recurrence["exceptions"] = exceptions; updated["recurrence"] = recurrence
            }
        }
        var boards = try maps(plan["boards"])
        for bi in boards.indices {
            var sections = try maps(boards[bi]["sections"])
            for si in sections.indices {
                var tasks = try maps(sections[si]["tasks"])
                for ti in tasks.indices where tasks[ti]["id"] as? String == id { tasks[ti] = updated }
                sections[si]["tasks"] = tasks
            }
            boards[bi]["sections"] = sections
        }
        plan["boards"] = boards
    }
    private static func editEvent(_ action: KairosChatAction, plan: inout [String: Any], timezone: String, createdAt: Double, identity: String) throws {
        let a = action.args
        let events = try maps(plan["scheduleEvents"])
        let creating = action.type == "create_schedule_event"
        var existing: [String: Any]?
        var effective: [String: Any] = [:]
        if !creating {
            guard let id = a.eventId else { throw Invalid("Choose an exact event.") }
            let matches = events.filter { $0["id"] as? String == id }
            guard matches.count == 1 else { throw Invalid("This event is missing or ambiguous.") }
            existing = matches[0]; effective = matches[0]
            guard effective["archived"] as? Bool != true else { throw Invalid("This event is archived.") }
            if let original = a.occurrenceDate {
                let exception = (effective["exceptions"] as? [String: Any])?[original] as? [String: Any] ?? [:]
                let override = exception["override"] as? [String: Any] ?? [:]
                let date = override["date"] as? String ?? original
                guard try KairosScheduleProjection.events([effective], on: date).contains(where: { $0.occurrenceDate == original }) else { throw Invalid("Choose an existing original weekly occurrence date.") }
                effective.merge(override) { _, new in new }; effective["date"] = date
            } else if effective["date"] == nil { throw Invalid("Choose one original occurrence date to change a weekly event.") }
        }
        let calendar = calendar(timezone)
        let today = dayKey(Date(timeIntervalSince1970: createdAt / 1000), calendar: calendar)
        let date = a.date ?? effective["date"] as? String ?? today
        let start = a.start ?? effective["start"] as? String ?? ""
        var end = a.end ?? effective["end"] as? String ?? ""
        if !creating, a.start != nil, a.end == nil, let oldStart = KairosScheduleProjection.minutes(effective["start"] as? String), let oldEnd = KairosScheduleProjection.minutes(effective["end"] as? String), let shifted = KairosScheduleProjection.minutes(start) { end = KairosScheduleProjection.clock(shifted + (oldEnd - oldStart + 1440) % 1440) }
        if creating { guard (a.date != nil) != (a.day != nil) else { throw Invalid("Choose either a date or a weekly weekday for the new event.") } }
        let edit = KairosEventEdit(eventID: creating ? nil : a.eventId, occurrenceDate: a.occurrenceDate, title: a.newTitle ?? a.title ?? effective["title"] as? String ?? "", date: date, start: start, end: end, category: a.category ?? effective["category"] as? String ?? "other", weeklyDay: creating ? a.day : nil, removing: action.type == "delete_schedule_event")
        var changed = try KairosEventMutation.apply(edit, to: events, expected: existing)
        if creating { changed[changed.count - 1]["id"] = "event-" + identity }
        plan["scheduleEvents"] = changed
    }
    nonisolated static func calendar(_ timezone: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: timezone) ?? .current; return c }
    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String { let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    private static func targetTitle(_ action: KairosChatAction, before: [String: Any]) -> String {
        if let id = action.args.taskId, let item = try? task(id, plan: before) { return item["title"] as? String ?? id }
        if let id = action.args.eventId, let events = try? maps(before["scheduleEvents"]) { return events.first(where: { $0["id"] as? String == id })?["title"] as? String ?? id }
        return action.args.newTitle ?? action.args.title ?? action.args.boardId ?? action.args.sectionId ?? "Planner change"
    }
    private static func describe(_ action: KairosChatAction, plan: [String: Any]) -> String {
        var item: [String: Any]?
        if let id = action.args.taskId { item = try? task(id, plan: plan) }
        else if let id = action.args.eventId { item = (try? maps(plan["scheduleEvents"]))?.first(where: { $0["id"] as? String == id }) }
        if let item {
            var parts = [item["title"] as? String ?? ""]
            if let date = item["date"] as? String { parts.append(date) }
            if let day = item["day"] as? Int { parts.append("Weekly weekday \(day)") }
            parts.append([item["startTime"] as? String ?? item["start"] as? String, item["endTime"] as? String ?? item["end"] as? String].compactMap { $0 }.joined(separator: "–"))
            if action.type.contains("reminder") { parts.append((item["reminderMinutes"] as? Int).map { "Reminder: \($0) min before" } ?? "No task reminder") }
            if action.type == "update_task_occurrence", let date = action.args.occurrenceDate {
                let r = item["recurrence"] as? [String: Any] ?? [:]
                let exception = (r["exceptions"] as? [String: Any])?[date] as? [String: Any] ?? [:]
                let override = exception["override"] as? [String: Any] ?? [:]
                parts = ["Occurrence " + date, override["date"] as? String ?? date, override["startTime"] as? String ?? item["startTime"] as? String ?? "Flexible", override["endTime"] as? String ?? item["endTime"] as? String ?? "", exception["status"] as? String ?? "pending"]
            }
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if action.type.hasPrefix("delete_") { return "Removed" }
        return action.args.newTitle ?? action.args.title ?? "New item"
    }
}
