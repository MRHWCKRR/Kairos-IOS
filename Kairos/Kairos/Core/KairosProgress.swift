import Foundation

enum KairosProgress {
    struct InvalidData: LocalizedError {
        nonisolated var errorDescription: String? { "Your progress could not be updated safely. Please refresh Kairos and try again." }
    }

    nonisolated private static func number(_ value: Any?) throws -> Int64 {
        guard let value else { return 0 }
        guard let number = value as? NSNumber, number.doubleValue.isFinite,
              number.doubleValue >= 0, number.doubleValue == Double(number.int64Value) else { throw InvalidData() }
        return number.int64Value
    }

    nonisolated private static func add(_ value: Any?, _ increment: Int64) throws -> Int64 {
        let (sum, overflow) = try number(value).addingReportingOverflow(increment)
        guard !overflow, increment >= 0 else { throw InvalidData() }
        return sum
    }

    nonisolated private static func map(_ value: Any?) throws -> [String: Any] {
        guard let value else { return [:] }
        guard let map = value as? [String: Any] else { throw InvalidData() }
        return map
    }

    nonisolated static func focusSession(data: [String: Any], seconds: Int64, dayKey: String) throws -> [String: Any] {
        guard seconds > 0 else { throw InvalidData() }
        var focus = try map(data["focusData"])
        var log = try map(focus["dailyFocusLog"])
        focus["totalSeconds"] = try add(focus["totalSeconds"], seconds)
        focus["longestSessionSeconds"] = try max(number(focus["longestSessionSeconds"]), seconds)
        log[dayKey] = try add(log[dayKey], seconds)
        focus["dailyFocusLog"] = log
        return ["focusData": focus]
    }

    nonisolated static func taskCompletion(data: [String: Any], taskID: String, dayKey: String) throws -> [String: Any] {
        var achievements = try map(data["achievements"])
        guard achievements["countedTaskIds"] == nil || achievements["countedTaskIds"] is [String] else { throw InvalidData() }
        var counted = achievements["countedTaskIds"] as? [String] ?? []
        guard !counted.contains(taskID) else { return [:] }
        counted.append(taskID)
        achievements["countedTaskIds"] = counted
        achievements["lifetimeTasksCompleted"] = try add(achievements["lifetimeTasksCompleted"], 1)
        var focus = try map(data["focusData"])
        var log = try map(focus["dailyTasksLog"])
        log[dayKey] = try add(log[dayKey], 1)
        focus["dailyTasksLog"] = log
        // Complete the required fields when a new user has no progress maps yet.
        focus["totalSeconds"] = try number(focus["totalSeconds"])
        focus["longestSessionSeconds"] = try number(focus["longestSessionSeconds"])
        return ["achievements": achievements, "focusData": focus]
    }
}
