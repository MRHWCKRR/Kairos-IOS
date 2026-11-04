import Foundation
import JavaScriptCore

struct KairosRecurringOccurrence: Decodable, Identifiable, Sendable {
    let occurrenceId: String
    let seriesId: String
    let occurrenceDate: String
    let displayDate: String
    let status: String
    let startTime: String?
    let endTime: String?
    let task: KairosTask
    var revision: String = ""
    var id: String { occurrenceId }
    enum CodingKeys: String, CodingKey {
        case occurrenceId, seriesId, occurrenceDate, displayDate, status, startTime, endTime, task
    }
}

enum KairosRecurrence {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "This recurring task cannot be read safely. Review it on the web before retrying." }
    }

    // Project only engine inputs. Unknown Firestore metadata never has to pass
    // through JSON/JavaScript and remains untouched when writing an exception.
    nonisolated static func input(_ task: [String: Any]) throws -> [String: Any] {
        func pick(_ map: [String: Any], _ keys: [String]) -> [String: Any] {
            map.filter { keys.contains($0.key) }
        }
        var result = pick(task, ["id","title","date","startTime","endTime","estimatedMinutes","notes","priority","checklist"])
        if let raw = task["recurrence"] as? [String: Any] {
            var rule = pick(raw, ["enabled","preset","frequency","interval","weekdays","monthlyMode","monthDay","weekdayPosition","weekday","month","startDate","endType","endDate","count","mode"])
            if let value = raw["exceptions"], !(value is NSNull), !(value is [String: Any]) { throw Unavailable() }
            var exceptions: [String: Any] = [:]
            for (date, value) in raw["exceptions"] as? [String: Any] ?? [:] {
                guard let value = value as? [String: Any] else { throw Unavailable() }
                var exception = pick(value, ["status","completedAt","skippedAt","focusLoggedSeconds","remainingMinutes"])
                if let override = value["override"] as? [String: Any] {
                    exception["override"] = pick(override, ["date","startTime","endTime","durationMinutes","title","notes","estimatedMinutes","checklist"])
                }
                exceptions[date] = exception
            }
            rule["exceptions"] = exceptions
            result["recurrence"] = rule
        }
        return result
    }

    nonisolated static func revision(_ task: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: try input(task), options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw Unavailable() }
        return text
    }

    nonisolated private static func run(task: [String: Any], day: String, status: String? = nil, timestamp: String = "", checklist: [KairosChecklistItem]? = nil) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "recurrence-engine", withExtension: "js"),
              let context = JSContext() else { throw Unavailable() }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        if context.exception != nil { throw Unavailable() }
        var args: [String: Any] = ["task": try input(task), "day": day, "status": status.map { $0 as Any } ?? NSNull(), "timestamp": timestamp]
        if let checklist {
            args["checklist"] = checklist.map { ["id": $0.id, "title": $0.title, "completed": $0.completed] as [String: Any] }
        }
        let json = try JSONSerialization.data(withJSONObject: args)
        guard let argument = String(data: json, encoding: .utf8),
              let output = context.objectForKeyedSubscript("kairosOccurrenceRequest")?.call(withArguments: [argument])?.toString(),
              context.exception == nil, let data = output.data(using: .utf8) else { throw Unavailable() }
        return data
    }

    nonisolated static func occurrences(task: [String: Any], on day: String) throws -> [KairosRecurringOccurrence] {
        let data = try run(task: task, day: day)
        var result = try JSONDecoder().decode([KairosRecurringOccurrence].self, from: data)
        let version = try revision(task)
        for i in result.indices { result[i].revision = version }
        return result
    }

    nonisolated static func settingStatus(task: [String: Any], occurrence: KairosRecurringOccurrence, status: String, timestamp: String) throws -> [String: Any] {
        guard ["pending","completed","skipped"].contains(status),
              try revision(task) == occurrence.revision else { throw KairosPlannerMerge.Conflict() }
        let data = try run(task: task, day: occurrence.occurrenceDate, status: status, timestamp: timestamp)
        guard let update = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var rule = task["recurrence"] as? [String: Any], rule["enabled"] as? Bool == true else { throw Unavailable() }
        var exceptions = rule["exceptions"] as? [String: Any] ?? [:]
        var exception = exceptions[occurrence.occurrenceDate] as? [String: Any] ?? [:]
        // Only these status fields and a historical schedule pin may change.
        exception.removeValue(forKey: "completedAt")
        exception.removeValue(forKey: "skippedAt")
        for key in ["status","completedAt","skippedAt"] { exception[key] = update[key] }
        if let pin = update["override"] as? [String: Any] {
            var existing = exception["override"] as? [String: Any] ?? [:]
            for (key, value) in pin { existing[key] = value }
            exception["override"] = existing
        }
        exceptions[occurrence.occurrenceDate] = exception
        rule["exceptions"] = exceptions
        var result = task
        result["recurrence"] = rule
        return result
    }

    nonisolated private static func checklistContext(_ task: [String: Any], date: String) throws -> Data {
        var value = try input(task)
        value.removeValue(forKey: "checklist")
        guard var rule = value["recurrence"] as? [String: Any] else { throw Unavailable() }
        let exceptions = rule["exceptions"] as? [String: Any] ?? [:]
        var selected = exceptions[date] as? [String: Any] ?? [:]
        selected["status"] = selected["status"] as? String ?? "pending"
        selected.removeValue(forKey: "focusLoggedSeconds")
        selected.removeValue(forKey: "remainingMinutes")
        if var override = selected["override"] as? [String: Any] {
            override.removeValue(forKey: "checklist")
            selected["override"] = override.isEmpty ? nil : override
        }
        rule["exceptions"] = [date: selected]
        value["recurrence"] = rule
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    nonisolated static func settingChecklist(task: [String: Any], occurrence: KairosRecurringOccurrence, items: [KairosChecklistItem]) throws -> [String: Any] {
        try KairosChecklist.validate(items)
        guard let baselineData = occurrence.revision.data(using: .utf8),
              let baseline = try JSONSerialization.jsonObject(with: baselineData) as? [String: Any],
              task["id"] as? String == occurrence.seriesId,
              try checklistContext(baseline, date: occurrence.occurrenceDate) == checklistContext(task, date: occurrence.occurrenceDate),
              let current = try occurrences(task: task, on: occurrence.displayDate).first(where: { $0.id == occurrence.id }) else {
            throw KairosPlannerMerge.Conflict()
        }
        let merged = try KairosChecklist.merge(base: occurrence.task.checklist ?? [], local: items, remote: current.task.checklist ?? [])
        let data = try run(task: task, day: occurrence.occurrenceDate, checklist: merged)
        guard let update = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var rule = task["recurrence"] as? [String: Any] else { throw Unavailable() }
        var exceptions = rule["exceptions"] as? [String: Any] ?? [:]
        var selected = exceptions[occurrence.occurrenceDate] as? [String: Any] ?? [:]
        var override = selected["override"] as? [String: Any] ?? [:]
        let rawItems = override["checklist"] as? [[String: Any]] ?? task["checklist"] as? [[String: Any]] ?? []
        // Retain unknown metadata on surviving steps while applying explicit
        // title/completion edits, insertion, removal and reordering.
        var rawByID: [String: [String: Any]] = [:]
        for item in rawItems {
            guard let id = item["id"] as? String, rawByID[id] == nil else { throw Unavailable() }
            rawByID[id] = item
        }
        if let pin = update["override"] as? [String: Any] {
            for (key, value) in pin where key != "checklist" { override[key] = value }
        }
        override["checklist"] = merged.map { item -> [String: Any] in
            var raw = rawByID[item.id] ?? [:]
            raw["id"] = item.id
            raw["title"] = item.title
            raw["completed"] = item.completed
            return raw
        }
        selected["override"] = override
        exceptions[occurrence.occurrenceDate] = selected
        rule["exceptions"] = exceptions
        var result = task
        result["recurrence"] = rule
        return result
    }
}
