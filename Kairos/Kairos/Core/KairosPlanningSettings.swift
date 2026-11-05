import Foundation
import JavaScriptCore
import CoreFoundation

struct KairosWorkWindow: Codable, Equatable, Sendable {
    var start: String
    var end: String
}
struct KairosPlanningSettings: Codable, Equatable, Sendable {
    var timezone: String
    var timeFormat: String
    var dailyLimitMinutes: Int
    var gapMinutes: Int
    var rescheduleCompleted: Bool
    var weeklyAvailability: [String: [KairosWorkWindow]]?
}

enum KairosPlanningSettingsStore {
    struct Invalid: LocalizedError {
        let message: String
        nonisolated init(_ message: String) { self.message = message }
        nonisolated var errorDescription: String? { message }
    }
    nonisolated private static func map(_ value: Any?) throws -> [String: Any] {
        guard let value else { return [:] }
        guard let result = value as? [String: Any] else { throw Invalid("These saved settings cannot be read safely. Review them on the web.") }
        return result
    }
    nonisolated private static func preferences(_ value: [String: Any]) throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "planning-settings-engine", withExtension: "js"), let context = JSContext() else { throw Invalid("Planning settings could not load.") }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil else { throw Invalid("Planning settings could not load.") }
        let result = context.objectForKeyedSubscript("kairosPlanningSettings")?.call(withArguments: [try KairosTouchSchedule.json(value)])?.toString()
        if let exception = context.exception { throw Invalid(exception.toString() ?? "Review your planning settings.") }
        guard let result else { throw Invalid("Planning settings could not be validated.") }
        return try KairosTouchSchedule.object(result)
    }
    nonisolated static func read(_ settings: [String: Any], fallbackTimezone: String) throws -> KairosPlanningSettings {
        let planning = try map(settings["planning"]), profile = try map(settings["profile"]), accessibility = try map(settings["accessibility"])
        let chosen = try preferences(planning.filter { ["dailyLimitMinutes", "gapMinutes", "weeklyAvailability"].contains($0.key) })
        let timezone = profile["timezone"] == nil ? fallbackTimezone : profile["timezone"] as? String
        let format = accessibility["timeFormat"] == nil ? "12" : accessibility["timeFormat"] as? String
        guard let timezone, TimeZone(identifier: timezone) != nil, let format, ["12", "24"].contains(format) else { throw Invalid("Choose a valid profile timezone and 12- or 24-hour time format.") }
        if let completed = planning["rescheduleCompleted"] {
            guard let number = completed as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw Invalid("Review the saved completed-task rescheduling preference.") }
        }
        var week: [String: [KairosWorkWindow]]?
        if let value = chosen["weeklyAvailability"] as? [String: Any] {
            week = try JSONDecoder().decode([String: [KairosWorkWindow]].self, from: JSONSerialization.data(withJSONObject: value))
        }
        return .init(timezone: timezone, timeFormat: format, dailyLimitMinutes: chosen["dailyLimitMinutes"] as? Int ?? 0, gapMinutes: chosen["gapMinutes"] as? Int ?? 0, rescheduleCompleted: planning["rescheduleCompleted"] as? Bool ?? false, weeklyAvailability: week)
    }
    nonisolated private static func fields(_ value: KairosPlanningSettings) throws -> [String: Any] {
        var planning: [String: Any] = ["dailyLimitMinutes": value.dailyLimitMinutes, "gapMinutes": value.gapMinutes, "rescheduleCompleted": value.rescheduleCompleted]
        planning["weeklyAvailability"] = try value.weeklyAvailability.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        let checked = try read(["profile": ["timezone": value.timezone], "accessibility": ["timeFormat": value.timeFormat], "planning": planning], fallbackTimezone: value.timezone)
        let week: Any = try checked.weeklyAvailability.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        return ["settings.profile.timezone": checked.timezone, "settings.accessibility.timeFormat": checked.timeFormat,
                "settings.planning.dailyLimitMinutes": checked.dailyLimitMinutes, "settings.planning.gapMinutes": checked.gapMinutes,
                "settings.planning.rescheduleCompleted": checked.rescheduleCompleted, "settings.planning.weeklyAvailability": week]
    }
    // Only changed leaves are written. A whole settings section is never replaced.
    nonisolated static func validate(_ value: KairosPlanningSettings) throws { _ = try fields(value) }
    nonisolated static func patch(expected: KairosPlanningSettings, draft: KairosPlanningSettings, remote: [String: Any]) throws -> [String: Any] {
        let before = try fields(expected), after = try fields(draft)
        let current = try fields(read(remote, fallbackTimezone: expected.timezone))
        var patch: [String: Any] = [:]
        for key in before.keys {
            guard let old = before[key] as? NSObject, let new = after[key] as? NSObject, !old.isEqual(new) else { continue }
            guard let actual = current[key] as? NSObject, actual.isEqual(old) || actual.isEqual(new) else {
                throw Invalid("These settings changed on another device. Your draft is still here; reload the saved values before trying again.")
            }
            patch[key] = new
        }
        return patch
    }
}

enum KairosTimeDisplay {
    nonisolated static func clock(_ minute: Int, format: String) -> String {
        let value = ((minute % 1440) + 1440) % 1440, hour = value / 60
        if format == "24" { return String(format: "%02d:%02d", hour, value % 60) }
        return String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, value % 60, hour < 12 ? "AM" : "PM")
    }
    nonisolated static func time(_ stored: String, format: String) -> String {
        guard let minute = KairosScheduleProjection.minutes(stored) else { return stored }
        return clock(minute, format: format)
    }
    nonisolated static func locale(format: String) -> Locale {
        let base = Locale.current.identifier.components(separatedBy: "@")[0].components(separatedBy: "-u-")[0].replacingOccurrences(of: "_", with: "-")
        return Locale(identifier: base + (format == "24" ? "-u-hc-h23" : "-u-hc-h12"))
    }
}
