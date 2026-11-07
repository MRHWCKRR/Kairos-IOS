import Foundation
import JavaScriptCore

struct KairosPlanningRow: Decodable, Identifiable, Sendable {
    let id: String
    let target: KairosTouchTarget
    let title: String
    let reason: String?
    let locked: Bool
}
struct KairosFindTimeReview: Identifiable, Sendable {
    var id: String { draft.id }
    let draft: KairosTouchDraft
    let slots: [KairosSchedulePlacement]
    let afterDeadline: String?
    let previous: String
}
enum KairosFindTime {
    nonisolated static func state(_ raw: [String: Any]) throws -> [String: Any] {
        var state = try KairosAIProposalEngine.reviewState(raw)
        let rawBoards = try KairosAIProposalEngine.maps(raw["boards"])
        var boards = try KairosAIProposalEngine.maps(state["boards"])
        for bi in boards.indices {
            let rawSections = try KairosAIProposalEngine.maps(rawBoards[bi]["sections"])
            var sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
            for si in sections.indices {
                let rawTasks = try KairosAIProposalEngine.maps(rawSections[si]["tasks"])
                var tasks = try KairosAIProposalEngine.maps(sections[si]["tasks"])
                for ti in tasks.indices {
                    tasks[ti]["assignmentId"] = rawTasks[ti]["assignmentId"]
                    if var rule = tasks[ti]["recurrence"] as? [String: Any], let rawRule = rawTasks[ti]["recurrence"] as? [String: Any] {
                        var exceptions = rule["exceptions"] as? [String: Any] ?? [:]
                        for (date, value) in rawRule["exceptions"] as? [String: Any] ?? [:] {
                            guard let rawException = value as? [String: Any], let rawOverride = rawException["override"] as? [String: Any] else { continue }
                            var exception = exceptions[date] as? [String: Any] ?? [:]
                            var override = exception["override"] as? [String: Any] ?? [:]
                            for key in ["scheduleLocked", "dueDate", "assignmentId", "schedulingPreference"] { override[key] = rawOverride[key] }
                            exception["override"] = override; exceptions[date] = exception
                        }
                        rule["exceptions"] = exceptions; tasks[ti]["recurrence"] = rule
                    }
                }
                sections[si]["tasks"] = tasks
            }
            boards[bi]["sections"] = sections
        }
        state["boards"] = boards
        return state
    }
    nonisolated static func run(_ request: [String: Any]) throws -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let context = JSContext() else { throw KairosTouchSchedule.Failure("Planning is unavailable.") }
        for name in ["recurrence-engine", "planning-engine"] {
            guard let url = bundle.url(forResource: name, withExtension: "js") else { throw KairosTouchSchedule.Failure("Planning could not load.") }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            if let error = context.exception { throw KairosTouchSchedule.Failure(error.toString() ?? "Planning could not load.") }
        }
        let result = context.objectForKeyedSubscript("kairosPlanningRequest")?.call(withArguments: [try KairosTouchSchedule.json(request)])?.toString()
        if let error = context.exception { throw KairosTouchSchedule.Failure(error.toString() ?? "Review a new preview.") }
        guard let result else { throw KairosTouchSchedule.Failure("Planning could not finish.") }
        return result
    }
    nonisolated static func preview(state: [String: Any], target: KairosTouchTarget, recovery: Bool, settings: KairosPlanningSettings, ownerID: String, planID: String) throws -> KairosFindTimeReview {
        let targetMap = try KairosTouchSchedule.object(KairosTouchSchedule.encode(target))
        let reportJSON = try run(["mode": "preview", "state": state, "timezone": settings.timezone, "target": targetMap, "recovery": recovery, "settings": KairosTouchSchedule.object(KairosTouchSchedule.encode(settings))])
        let report = try KairosTouchSchedule.object(reportJSON)
        let slots = (report["slots"] as? [[String: Any]] ?? []).compactMap { slot -> KairosSchedulePlacement? in
            guard let date = slot["date"] as? String, let start = KairosScheduleProjection.minutes(slot["startTime"] as? String), let duration = report["duration"] as? Int else { return nil }
            return .init(date: date, start: start, end: start + duration)
        }
        guard let first = slots.first else { throw KairosTouchSchedule.Failure("No available time in the next 14 days. Review availability, duration or deadline, then try again.") }
        let expected = try KairosTouchSchedule.run(["mode": "planning", "state": state, "target": targetMap, "changes": changes(target: target, placement: first)])
        var draft = KairosTouchDraft(id: "schedule-" + UUID().uuidString, ownerID: ownerID, planID: planID, timezone: settings.timezone, target: target, expectedJSON: try KairosTouchSchedule.json(expected), title: report["title"] as? String ?? "Task", original: first, createdAt: Date().timeIntervalSince1970 * 1000)
        draft.planningReviewJSON = reportJSON
        let previous = report["previous"] as? [String: Any] ?? [:]
        let date = previous["date"] as? String ?? "No date"
        let time = (previous["startTime"] as? String).map { KairosTimeDisplay.time($0, format: settings.timeFormat) } ?? "No time"
        return .init(draft: draft, slots: slots, afterDeadline: report["afterDeadline"] as? String, previous: date + " · " + time)
    }
    nonisolated static func changes(target: KairosTouchTarget, placement: KairosSchedulePlacement) -> [String: Any] {
        ["date": placement.date, "startTime": KairosScheduleProjection.clock(placement.start), "endTime": KairosScheduleProjection.clock(placement.end), target.occurrenceDate == nil ? "lastScheduledMinutes" : "durationMinutes": placement.duration]
    }
    nonisolated static func validate(plan: [String: Any], profile: [String: Any], draft: KairosTouchDraft, placement: KairosSchedulePlacement, review: String) throws {
        _ = try run(["mode": "validate", "state": state(plan), "profile": ["settings": profile["settings"] ?? [:]], "timezone": draft.timezone, "target": KairosTouchSchedule.object(KairosTouchSchedule.encode(draft.target)), "changes": changes(target: draft.target, placement: placement), "review": KairosTouchSchedule.object(review)])
    }
}
