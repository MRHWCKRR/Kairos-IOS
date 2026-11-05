import Foundation

struct KairosEventEdit: Sendable {
    var eventID: String?
    var occurrenceDate: String?
    var title: String
    var date: String
    var start: String
    var end: String
    var category: String
    var weeklyDay: Int?
    var removing = false
}

enum KairosEventMutation {
    nonisolated static func apply(_ edit: KairosEventEdit, to source: [[String: Any]], expected: [String: Any]?) throws -> [[String: Any]] {
        var events = source
        let ids = events.compactMap { $0["id"] as? String }
        guard ids.count == events.count, Set(ids).count == ids.count else { throw KairosPlannerMerge.Conflict() }
        if !edit.removing {
            guard !edit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, edit.title.utf16.count <= 180,
                  KairosScheduleProjection.validDay(edit.date), KairosScheduleProjection.minutes(edit.start) != nil, KairosScheduleProjection.minutes(edit.end) != nil,
                  ["sleep","class","tutoring","training","other"].contains(edit.category) else { throw KairosTaskMutation.Invalid() }
        }
        guard let id = edit.eventID else {
            guard !edit.removing else { throw KairosTaskMutation.Invalid() }
            var event: [String: Any] = ["id": "event-" + UUID().uuidString, "title": edit.title, "category": edit.category, "start": edit.start, "end": edit.end]
            if let day = edit.weeklyDay {
                guard (0...6).contains(day) else { throw KairosTaskMutation.Invalid() }
                event["day"] = day; event["startDate"] = edit.date
            } else { event["date"] = edit.date }
            events.append(event); return events
        }
        guard let index = events.firstIndex(where: { $0["id"] as? String == id }), let expected,
              NSDictionary(dictionary: events[index]).isEqual(to: expected),
              events[index]["readOnly"] as? Bool != true, events[index]["calendarSourceId"] == nil else { throw KairosPlannerMerge.Conflict() }
        if let original = edit.occurrenceDate {
            guard KairosScheduleProjection.validDay(original), events[index]["date"] == nil,
                  (events[index]["day"] as? Int).map({ (0...6).contains($0) }) == true else { throw KairosTaskMutation.Invalid() }
            var exceptions = events[index]["exceptions"] as? [String: Any] ?? [:]
            var exception = exceptions[original] as? [String: Any] ?? [:]
            if edit.removing { exception["skipped"] = true }
            else {
                exception["skipped"] = false
                var override = exception["override"] as? [String: Any] ?? [:]
                override["title"] = edit.title; override["date"] = edit.date; override["start"] = edit.start; override["end"] = edit.end; override["category"] = edit.category
                exception["override"] = override
            }
            exceptions[original] = exception; events[index]["exceptions"] = exceptions
        } else if edit.removing { events.remove(at: index) }
        else {
            // A dated item may be moved; a weekly series needs an occurrence ID.
            guard events[index]["date"] is String else { throw KairosTaskMutation.Invalid() }
            events[index]["title"] = edit.title; events[index]["date"] = edit.date
            events[index]["start"] = edit.start; events[index]["end"] = edit.end; events[index]["category"] = edit.category
        }
        return events
    }
}
