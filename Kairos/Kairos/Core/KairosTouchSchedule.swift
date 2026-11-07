import Foundation
import JavaScriptCore

struct KairosTouchTarget: Codable, Equatable, Sendable {
    let taskId: String
    let occurrenceDate: String?
    nonisolated init(taskId: String, occurrenceDate: String? = nil) { self.taskId = taskId; self.occurrenceDate = occurrenceDate }
}
struct KairosSchedulePlacement: Codable, Equatable, Sendable {
    let date: String
    let start: Int
    let end: Int
    var duration: Int { end - start }
    nonisolated init(date: String, start: Int, end: Int) { self.date = date; self.start = start; self.end = end }
}
struct KairosTouchDraft: Sendable, Identifiable {
    let id: String
    let ownerID: String
    let planID: String
    let timezone: String
    let target: KairosTouchTarget
    let expectedJSON: String
    let title: String
    let original: KairosSchedulePlacement
    let createdAt: Double
    var planningReviewJSON: String? = nil
    nonisolated init(id: String, ownerID: String, planID: String, timezone: String, target: KairosTouchTarget, expectedJSON: String, title: String, original: KairosSchedulePlacement, createdAt: Double) {
        self.id = id; self.ownerID = ownerID; self.planID = planID; self.timezone = timezone; self.target = target; self.expectedJSON = expectedJSON; self.title = title; self.original = original; self.createdAt = createdAt
    }
}
struct KairosTouchUndo: Codable, Sendable, Identifiable {
    let id: String
    let ownerID: String
    let planID: String
    let timezone: String
    let recordJSON: String
    let title: String
    nonisolated init(id: String, ownerID: String, planID: String, timezone: String, recordJSON: String, title: String) { self.id = id; self.ownerID = ownerID; self.planID = planID; self.timezone = timezone; self.recordJSON = recordJSON; self.title = title }
}
enum KairosTouchSchedule {
    struct Failure: LocalizedError {
        let message: String
        nonisolated init(_ message: String) { self.message = message }
        nonisolated var errorDescription: String? { message }
    }
    nonisolated static func move(date: String, targetStart: Double, duration: Int) throws -> KairosSchedulePlacement {
        guard KairosScheduleProjection.validDay(date), targetStart.isFinite, (1...1440).contains(duration) else { throw Failure("Choose a valid date and session duration.") }
        let snapped = Int((min(1440, max(0, targetStart)) / 5).rounded()) * 5
        let latest = ((1440 - duration) / 5) * 5
        let start = min(latest, max(0, snapped))
        return .init(date: date, start: start, end: start + duration)
    }
    nonisolated static func resize(date: String, start: Int, targetEnd: Double) throws -> KairosSchedulePlacement {
        guard KairosScheduleProjection.validDay(date), targetEnd.isFinite, (0..<1440).contains(start) else { throw Failure("Choose a valid session time.") }
        let snapped = Int((min(1440, max(0, targetEnd)) / 5).rounded()) * 5
        let end = max(min(1440, start + 5), min(1440, snapped))
        return .init(date: date, start: start, end: end)
    }
    nonisolated static func json(_ value: Any) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let string = String(data: bytes, encoding: .utf8) else { throw Failure("Could not read this schedule change.") }
        return string
    }
    nonisolated static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let string = String(data: try encoder.encode(value), encoding: .utf8) else { throw Failure("Could not save this schedule change.") }
        return string
    }
    nonisolated static func object(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure("This schedule change cannot be read safely.") }
        return value
    }
    nonisolated static func run(_ arguments: [String: Any]) throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let context = JSContext() else { throw Failure("Schedule editing is unavailable.") }
        for name in ["recurrence-engine", "schedule-touch-engine"] {
            guard let url = bundle.url(forResource: name, withExtension: "js") else { throw Failure("The schedule editor could not load.") }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            if let error = context.exception { throw Failure(error.toString() ?? "The schedule editor could not load.") }
        }
        let output = context.objectForKeyedSubscript("kairosTouchScheduleRequest")?.call(withArguments: [try json(arguments)])
        if let error = context.exception { throw Failure(error.toString() ?? "Your schedule changed. Try again.") }
        guard let value = output?.toString() else { throw Failure("The schedule editor could not finish.") }
        return try object(value)
    }
    nonisolated private static func targetMap(_ target: KairosTouchTarget) -> [String: Any] {
        var value: [String: Any] = ["taskId": target.taskId]
        if let date = target.occurrenceDate { value["occurrenceDate"] = date }
        return value
    }
    nonisolated static func begin(plan: [String: Any], target: KairosTouchTarget, ownerID: String, planID: String, timezone: String, allowCompleted: Bool) throws -> KairosTouchDraft {
        let result = try run(["mode": "begin", "state": KairosAIProposalEngine.reviewState(plan), "target": targetMap(target), "options": ["allowCompleted": allowCompleted]])
        guard let expected = result["expected"] as? [String: Any], let start = result["start"] as? Int, let duration = result["duration"] as? Int, let date = result["date"] as? String else { throw Failure("This task has an invalid schedule.") }
        return .init(id: "schedule-" + UUID().uuidString, ownerID: ownerID, planID: planID, timezone: timezone, target: target, expectedJSON: try json(expected), title: result["title"] as? String ?? "Task", original: .init(date: date, start: start, end: start + duration), createdAt: Date().timeIntervalSince1970 * 1000)
    }
    nonisolated static func apply(plan: [String: Any], draft: KairosTouchDraft, placement: KairosSchedulePlacement, allowCompleted: Bool) throws -> (plan: [String: Any], undo: KairosTouchUndo) {
        guard KairosScheduleProjection.validDay(placement.date), placement.start >= 0, placement.end <= 1440, placement.end > placement.start else { throw Failure("The task must end after it starts and by midnight.") }
        var changes: [String: Any] = ["date": placement.date, "startTime": KairosScheduleProjection.clock(placement.start), "endTime": KairosScheduleProjection.clock(placement.end)]
        changes[draft.target.occurrenceDate == nil ? "lastScheduledMinutes" : "durationMinutes"] = placement.duration
        let result = try run(["mode": "apply", "state": KairosAIProposalEngine.reviewState(plan), "target": targetMap(draft.target), "expected": object(draft.expectedJSON), "changes": changes, "options": ["allowCompleted": allowCompleted]])
        guard let next = result["next"] as? [String: Any], let detail = result["result"] as? [String: Any], let record = detail["scheduleUndo"] as? [String: Any] else { throw Failure("Could not confirm this schedule change.") }
        let undo = KairosTouchUndo(id: draft.id, ownerID: draft.ownerID, planID: draft.planID, timezone: draft.timezone, recordJSON: try json(record), title: draft.title)
        return (try writeSchedulingFields(from: next, into: plan, target: draft.target), undo)
    }
    nonisolated static func undo(plan: [String: Any], record: KairosTouchUndo, allowCompleted: Bool) throws -> [String: Any] {
        let saved = try object(record.recordJSON)
        guard let map = saved["target"] as? [String: Any], let id = map["taskId"] as? String else { throw Failure("This Undo is unavailable.") }
        let target = KairosTouchTarget(taskId: id, occurrenceDate: map["occurrenceDate"] as? String)
        let result = try run(["mode": "undo", "state": KairosAIProposalEngine.reviewState(plan), "record": saved, "options": ["allowCompleted": allowCompleted]])
        guard let next = result["next"] as? [String: Any] else { throw Failure("Could not confirm Undo.") }
        return try writeSchedulingFields(from: next, into: plan, target: target)
    }
    nonisolated private static func writeSchedulingFields(from projected: [String: Any], into source: [String: Any], target: KairosTouchTarget) throws -> [String: Any] {
        // Copy only the fields this interaction owns. Never replace a whole raw
        // task, rule or exception with the engine's deliberately smaller input.
        let projectedTasks = try KairosAIProposalEngine.maps(projected["boards"]).flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        guard projectedTasks.filter({ $0["id"] as? String == target.taskId }).count == 1, let changed = projectedTasks.first(where: { $0["id"] as? String == target.taskId }) else { throw Failure("This task identity is ambiguous.") }
        var boards = try KairosAIProposalEngine.maps(source["boards"]), matches = 0
        for bi in boards.indices {
            var sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
            for si in sections.indices {
                var tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"])
                for ti in tasks.indices where tasks[ti]["id"] as? String == target.taskId {
                    matches += 1
                    if let date = target.occurrenceDate {
                        guard var rule = tasks[ti]["recurrence"] as? [String: Any], let projectedRule = changed["recurrence"] as? [String: Any] else { throw Failure("This recurring task changed.") }
                        var exceptions = rule["exceptions"] as? [String: Any] ?? [:]
                        var selected = exceptions[date] as? [String: Any] ?? [:]
                        var override = selected["override"] as? [String: Any] ?? [:]
                        let desired = (projectedRule["exceptions"] as? [String: Any])?[date] as? [String: Any]
                        let desiredOverride = desired?["override"] as? [String: Any]
                        for key in ["date", "startTime", "endTime", "durationMinutes"] { override[key] = desiredOverride?[key] }
                        selected["override"] = !override.isEmpty || desiredOverride != nil ? override : nil
                        exceptions[date] = !selected.isEmpty || desired != nil ? selected : nil
                        rule["exceptions"] = exceptions; tasks[ti]["recurrence"] = rule
                    } else {
                        for key in ["date", "startTime", "endTime", "estimatedMinutes", "lastScheduledMinutes"] { tasks[ti][key] = changed[key] }
                    }
                }
                sections[si]["tasks"] = tasks
            }
            boards[bi]["sections"] = sections
        }
        guard matches == 1 else { throw Failure("This task identity is ambiguous.") }
        var result = source; result["boards"] = boards; return result
    }
}

