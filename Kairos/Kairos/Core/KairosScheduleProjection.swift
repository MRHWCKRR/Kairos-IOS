import Foundation
import JavaScriptCore

struct KairosEventSegment: Decodable, Identifiable, Sendable {
    let id: String
    let eventID: String
    let title: String
    let category: String
    let date: String
    let effectiveDate: String
    let startTime: String
    let endTime: String
    let occurrenceDate: String?
    let startMin: Int
    let endMin: Int
    let continued: Bool
    let readOnly: Bool
    let transparent: Bool
}

enum KairosScheduleProjection {
    nonisolated static func validDay(_ key: String) -> Bool {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: key) else { return false }
        return formatter.string(from: date) == key
    }
    nonisolated static func minutes(_ time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
    nonisolated static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }
    nonisolated static func eventDates(day: String, start: String, end: String, calendar: Calendar) -> (start: Date, end: Date)? {
        guard validDay(day), let a = minutes(start), let b = minutes(end) else { return nil }
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        guard let base = formatter.date(from: day), let startDate = calendar.date(bySettingHour: a / 60, minute: a % 60, second: 0, of: base) else { return nil }
        let endDay = b <= a ? calendar.date(byAdding: .day, value: 1, to: base) : base
        guard let endDay, let endDate = calendar.date(bySettingHour: b / 60, minute: b % 60, second: 0, of: endDay), endDate > startDate else { return nil }
        return (startDate, endDate)
    }
    nonisolated static func duration(_ task: KairosTask) -> Int {
        if let start = minutes(task.startTime), let end = minutes(task.endTime) { return (end - start + 1440) % 1440 == 0 ? 1440 : (end - start + 1440) % 1440 }
        return max(1, min(1440, task.estimatedMinutes ?? 60))
    }
    nonisolated static func eventInput(_ events: [[String: Any]]) -> [[String: Any]] {
        events.map { event in
            var result = event.filter { ["id","title","category","date","day","start","end","archived","readOnly","calendarSourceId","transparent","allDay","startDate","endDate","intervalWeeks","anchorDate"].contains($0.key) }
            result["exceptions"] = (event["exceptions"] as? [String: Any] ?? [:]).mapValues { value -> [String: Any] in
                let map = value as? [String: Any] ?? [:]
                var selected = map.filter { $0.key == "skipped" }
                if let override = map["override"] as? [String: Any] { selected["override"] = override.filter { ["date","title","start","end","category","allDay","transparent"].contains($0.key) } }
                return selected
            }
            return result
        }
    }
    nonisolated static func events(_ events: [[String: Any]], on date: String) throws -> [KairosEventSegment] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "schedule-engine", withExtension: "js"), let context = JSContext() else { throw KairosRecurrence.Unavailable() }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        let data = try JSONSerialization.data(withJSONObject: ["events": eventInput(events), "date": date])
        guard let json = String(data: data, encoding: .utf8), let result = context.objectForKeyedSubscript("kairosScheduleEvents")?.call(withArguments: [json])?.toString(), context.exception == nil else { throw KairosRecurrence.Unavailable() }
        return try JSONDecoder().decode([KairosEventSegment].self, from: Data(result.utf8))
    }
}
