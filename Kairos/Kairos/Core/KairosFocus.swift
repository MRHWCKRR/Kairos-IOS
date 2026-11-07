import Foundation
import JavaScriptCore

struct KairosFocusTarget: Codable, Equatable, Sendable {
    let taskId: String
    let boardId: String
    let sectionId: String
    let assignmentId: String?
    let title: String
    let occurrenceDate: String?
    let recurrenceSignature: String?
}
struct KairosFocusSummary: Decodable, Sendable {
    let plannedMinutes: Int
    let loggedSeconds: Int64
    let remainingMinutes: Int
    let assignment: Bool
}
struct KairosFocusLog: Codable, Equatable, Sendable {
    let id: String
    let ownerId: String
    let planId: String?
    let createdAt: Double
    let endedAt: Double
    let seconds: Int64
    let target: KairosFocusTarget?
    var mode = "log"
}
struct KairosFocusResult: Decodable, Sendable {
    let seconds: Int64
    let attributed: Bool
    let taskId: String?
}
struct KairosFocusBreakdown: Decodable, Sendable {
    struct Row: Decodable, Identifiable, Sendable {
        let key: String
        let title: String
        let archived: Bool
        let loggedSeconds: Int64
        let estimatedMinutes: Int?
        let remainingMinutes: Int?
        let kind: String?
        let occurrenceDate: String?
        let displayDate: String?
        let occurrences: [Row]?
        var id: String { key }
    }
    let totalSeconds: Int64
    let boards: [Row]
    let assignments: [Row]
    let tasks: [Row]
}

enum KairosFocus {
    struct Failure: LocalizedError, CustomNSError {
        let code: String
        let message: String
        nonisolated var errorDescription: String? { message }
        nonisolated static var errorDomain: String { "KairosFocus" }
        nonisolated var errorCode: Int { code == "focus-log-expired" ? 1 : 0 }
        nonisolated var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: message, "focusCode": code] }
    }
    nonisolated static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
    nonisolated static func object(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KairosPlannerMerge.Conflict() }
        return value
    }
    nonisolated private static func run(_ value: [String: Any]) throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "focus-engine", withExtension: "js"), let context = JSContext() else { throw KairosRecurrence.Unavailable() }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil else { throw KairosRecurrence.Unavailable() }
        let text = context.objectForKeyedSubscript("kairosFocusRequest")?.call(withArguments: [try json(value)])?.toString()
        if let error = context.exception { throw Failure(code: error.forProperty("code")?.toString() ?? "", message: error.toString() ?? "Could not log focus. Your session is retained.") }
        guard let text else { throw KairosRecurrence.Unavailable() }
        return try object(text)
    }
    nonisolated private static func pick(_ value: [String: Any], _ fields: [String]) -> [String: Any] { value.filter { fields.contains($0.key) } }
    nonisolated private static func maps(_ value: Any?) throws -> [[String: Any]] { try KairosAIProposalEngine.maps(value) }
    nonisolated static func planInput(_ raw: [String: Any]) throws -> [String: Any] {
        var result = pick(raw, ["userID"])
        result["boards"] = try maps(raw["boards"]).map { board in
            var b = pick(board, ["id","title","archived"])
            b["sections"] = try maps(board["sections"]).map { section in
                var s = pick(section, ["id","title","archived"])
                s["tasks"] = try maps(section["tasks"]).map { task in
                    var t = pick(task, ["id","title","archived","completed","assignmentId","date","startTime","endTime","estimatedMinutes","lastScheduledMinutes","remainingMinutes","focusLoggedSeconds"])
                    if var rule = (try KairosRecurrence.input(task))["recurrence"] as? [String: Any] {
                        var exceptions: [String: Any] = [:]
                        for (date, value) in rule["exceptions"] as? [String: Any] ?? [:] {
                            guard let value = value as? [String: Any] else { throw KairosPlannerMerge.Conflict() }
                            var item = pick(value, ["status","focusLoggedSeconds","remainingMinutes"])
                            if let override = value["override"] as? [String: Any] {
                                item["override"] = pick(override, ["date","startTime","endTime","durationMinutes","title","estimatedMinutes"])
                            }
                            exceptions[date] = item
                        }
                        rule["exceptions"] = exceptions
                        let dates = Array((rule["exceptions"] as? [String: Any] ?? [:]).keys).sorted()
                        guard dates.count <= 10000, dates.allSatisfy(KairosScheduleProjection.validDay) else { throw KairosRecurrence.Unavailable() }
                        if let first = dates.first, let last = dates.last {
                            guard let a = Int(first.prefix(4)), let z = Int(last.prefix(4)), z - a <= 200 else { throw KairosRecurrence.Unavailable() }
                        }
                        t["recurrence"] = rule
                    }
                    return t
                }
                return s
            }
            return b
        }
        return result
    }
    nonisolated static func target(plan: [String: Any], taskID: String, occurrenceDate: String? = nil) throws -> (KairosFocusTarget?, KairosFocusSummary?) {
        let input = try planInput(plan)
        let result = try run(["operation": "target", "plan": input, "taskId": taskID, "occurrenceDate": occurrenceDate as Any? ?? NSNull()])
        let decoder = JSONDecoder()
        let target = try decoder.decode(KairosFocusTarget?.self, from: JSONSerialization.data(withJSONObject: result["target"] as Any, options: [.fragmentsAllowed]))
        let summary = try decoder.decode(KairosFocusSummary?.self, from: JSONSerialization.data(withJSONObject: result["summary"] as Any, options: [.fragmentsAllowed]))
        return (target, summary)
    }
    nonisolated static func breakdown(inputJSON: String) throws -> KairosFocusBreakdown {
        let result = try run(["operation": "breakdown", "plan": object(inputJSON)])
        return try JSONDecoder().decode(KairosFocusBreakdown.self, from: JSONSerialization.data(withJSONObject: result))
    }
    nonisolated private static func userInput(_ raw: [String: Any]) throws -> [String: Any] {
        var user: [String: Any] = [:]
        if let value = raw["focusData"] {
            guard let focus = value as? [String: Any] else { throw KairosPlannerMerge.Conflict() }
            user["focusData"] = pick(focus, ["totalSeconds","longestSessionSeconds","dailyFocusLog"])
        }
        if let value = raw["focusLogReceipts"] {
            guard let receipts = value as? [[String: Any]], receipts.count <= 100,
                  Set(receipts.compactMap { $0["id"] as? String }).count == receipts.count else { throw KairosPlannerMerge.Conflict() }
            user["focusLogReceipts"] = receipts.map { receipt in
                var item = pick(receipt, ["id","createdAt","fingerprint"])
                if let result = receipt["result"] as? [String: Any] {
                    var r = pick(result, ["type","seconds","attributed","taskId","completedTaskIds","occurrenceDisplayDate"])
                    if let task = result["task"] as? [String: Any] { r["task"] = pick(task, ["id","title","completed"]) }
                    item["result"] = r
                }
                return item
            }
        }
        user["focusLogReceiptFloor"] = raw["focusLogReceiptFloor"]
        if let value = raw["focusHistory"] {
            guard let history = value as? [String: Any], let sessions = history["sessions"] as? [[String: Any]], sessions.count <= 100 else { throw KairosPlannerMerge.Conflict() }
            user["focusHistory"] = ["baselineLongest": history["baselineLongest"] ?? 0, "sessions": sessions.map { pick($0, ["id","planId","endedAt","day","seconds","revision","taskId","title","assignmentTitle","attributed","source","occurrenceDate","occurrenceDisplayDate","removed"]) }]
        }
        if let settings = raw["settings"] as? [String: Any], let profile = settings["profile"] as? [String: Any], let timezone = profile["timezone"] as? String {
            user["settings"] = ["profile": ["timezone": timezone]]
        }
        return user
    }
    nonisolated static func entryObject(_ entry: KairosFocusLog) throws -> [String: Any] {
        var target: Any = NSNull()
        if let value = entry.target {
            var t: [String: Any] = ["taskId": value.taskId, "boardId": value.boardId, "sectionId": value.sectionId, "assignmentId": value.assignmentId as Any? ?? NSNull(), "title": value.title]
            t["occurrenceDate"] = value.occurrenceDate; t["recurrenceSignature"] = value.recurrenceSignature
            target = t
        }
        return ["id": entry.id, "ownerId": entry.ownerId, "planId": entry.planId as Any? ?? NSNull(), "createdAt": entry.createdAt, "endedAt": entry.endedAt, "seconds": entry.seconds, "target": target, "mode": entry.mode]
    }
    struct Applied {
        let userPatch: [String: Any]?
        let planBoards: [[String: Any]]?
        let result: KairosFocusResult
    }
    nonisolated static func apply(user: [String: Any], plan: [String: Any]?, entry: KairosFocusLog, now: Double) throws -> Applied {
        guard entry.mode == "log" else { throw KairosPlannerMerge.Conflict() }
        let response = try run(["operation": "log", "user": userInput(user), "plan": try plan.map(planInput) as Any? ?? NSNull(), "entry": entryObject(entry), "now": now])
        let result = try JSONDecoder().decode(KairosFocusResult.self, from: JSONSerialization.data(withJSONObject: response["result"] as Any))
        guard let projected = response["userPatch"] as? [String: Any] else { return .init(userPatch: nil, planBoards: nil, result: result) }
        var focus = user["focusData"] as? [String: Any] ?? [:]
        for (key, value) in projected["focusData"] as? [String: Any] ?? [:] { focus[key] = value }
        func preserveRows(_ projected: Any?, _ existing: Any?) throws -> [[String: Any]] {
            let raw = try maps(existing)
            return try maps(projected).map { row in
                // Logging only appends immutable receipts/history rows.
                // Retained rows keep their complete raw nested metadata.
                if let original = raw.first(where: { ($0["id"] as? String) == (row["id"] as? String) }) { return original }
                return row
            }
        }
        var history = user["focusHistory"] as? [String: Any] ?? [:]
        let newHistory = projected["focusHistory"] as? [String: Any] ?? [:]
        history["baselineLongest"] = newHistory["baselineLongest"]
        history["sessions"] = try preserveRows(newHistory["sessions"], history["sessions"])
        let patch: [String: Any] = ["focusData": focus, "focusHistory": history, "focusLogReceipts": try preserveRows(projected["focusLogReceipts"], user["focusLogReceipts"]), "focusLogReceiptFloor": projected["focusLogReceiptFloor"] ?? 0]
        var boards: [[String: Any]]?
        if response["planPatch"] is [String: Any], let plan, let target = entry.target {
            var raw = try maps(plan["boards"]), locations: [(Int, Int, Int)] = []
            for bi in raw.indices {
                let sections = try maps(raw[bi]["sections"])
                for si in sections.indices { let tasks = try maps(sections[si]["tasks"]); for ti in tasks.indices where tasks[ti]["id"] as? String == target.taskId { locations.append((bi, si, ti)) } }
            }
            guard locations.count == 1, let (bi, si, ti) = locations.first else { throw KairosPlannerMerge.Conflict() }
            var sections = try maps(raw[bi]["sections"]), tasks = try maps(sections[si]["tasks"])
            guard raw.filter({ $0["id"] as? String == target.boardId }).count == 1, sections.filter({ $0["id"] as? String == target.sectionId }).count == 1 else { throw KairosPlannerMerge.Conflict() }
            let nextBoards = try maps((response["planPatch"] as? [String: Any])?["boards"]), nextSections = try maps(nextBoards[bi]["sections"]), nextTasks = try maps(nextSections[si]["tasks"])
            if let date = target.occurrenceDate {
                var rule = tasks[ti]["recurrence"] as? [String: Any] ?? [:], exceptions = rule["exceptions"] as? [String: Any] ?? [:], exception = exceptions[date] as? [String: Any] ?? [:]
                let nextRule = nextTasks[ti]["recurrence"] as? [String: Any], nextExceptions = nextRule?["exceptions"] as? [String: Any], next = nextExceptions?[date] as? [String: Any]
                exception["focusLoggedSeconds"] = next?["focusLoggedSeconds"]; exceptions[date] = exception; rule["exceptions"] = exceptions; tasks[ti]["recurrence"] = rule
            } else { tasks[ti]["focusLoggedSeconds"] = nextTasks[ti]["focusLoggedSeconds"] }
            sections[si]["tasks"] = tasks; raw[bi]["sections"] = sections; boards = raw
        }
        return .init(userPatch: patch, planBoards: boards, result: result)
    }
}
