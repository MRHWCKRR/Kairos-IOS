import XCTest
@testable import KairosCore

final class ScheduleProjectionTests: XCTestCase {
    func testWebFixedEventsRespectSkipMoveAndOvernight() throws {
        let events: [[String: Any]] = [
            ["id": "skip", "title": "Class", "day": 4, "start": "09:00", "end": "10:00", "exceptions": ["2026-11-05": ["skipped": true]]],
            ["id": "night", "title": "Night", "date": "2026-11-04", "start": "23:00", "end": "01:00"],
            ["id": "moved", "title": "Moved", "day": 3, "start": "08:00", "end": "09:00", "exceptions": ["2026-11-04": ["override": ["date": "2026-11-05", "start": "12:00", "end": "13:00"]]]]
        ]
        let result = try KairosScheduleProjection.events(events, on: "2026-11-05")
        XCTAssertEqual(result.map(\.eventID), ["night", "moved"])
        XCTAssertEqual(result.map(\.startMin), [0, 720])
        XCTAssertEqual(result.map(\.endMin), [60, 780])
        XCTAssertTrue(result[0].continued)
        XCTAssertEqual(result[1].occurrenceDate, "2026-11-04")
    }
    func testAlternatingWeeklyBoundsAndDateWinsOverDay() throws {
        let events: [[String: Any]] = [["id": "weekly", "title": "Class", "day": 4, "start": "09:00", "end": "10:00", "intervalWeeks": 2, "anchorDate": "2026-11-05", "endDate": "2026-11-19"], ["id": "dated", "title": "One off", "date": "2026-11-06", "day": 4, "start": "10:00", "end": "11:00"]]
        XCTAssertEqual(try KairosScheduleProjection.events(events, on: "2026-11-05").count, 1)
        XCTAssertEqual(try KairosScheduleProjection.events(events, on: "2026-11-12").count, 0)
        XCTAssertEqual(try KairosScheduleProjection.events(events, on: "2026-11-19").count, 1)
        XCTAssertEqual(try KairosScheduleProjection.events(events, on: "2026-12-03").count, 0)
    }
    func testDurationUsesScheduledTimeBeforeEstimate() throws {
        let task = try JSONDecoder().decode(KairosTask.self, from: Data(#"{"id":"t","title":"Work","startTime":"14:00","endTime":"15:30","dueTime":"23:00","estimatedMinutes":10}"#.utf8))
        XCTAssertEqual(KairosScheduleProjection.duration(task), 90)
        XCTAssertTrue(KairosScheduleProjection.validDay("2028-02-29"))
        XCTAssertFalse(KairosScheduleProjection.validDay("2026-02-29"))
    }
    func testReviewedActionsAreAtomicAndRejectRecurringTemplates() throws {
        let task = try JSONDecoder().decode(KairosTask.self, from: Data(#"{"id":"t","title":"Work","date":"2026-11-05","startTime":"09:00","endTime":"10:00"}"#.utf8))
        let boards = [KairosBoard(id: "b", title: "School", archived: false, sections: [.init(id: "s", title: "Work", archived: false, tasks: [task])])]
        let response = try KairosChatResponse.parse(#"{"reply":"Review this move","actions":[{"type":"update_task","args":{"taskId":"t","date":"2026-11-06","startTime":"10:00","endTime":"11:00"}}]}"#)
        let changed = try KairosChatActions.apply(response.actions, to: boards)
        XCTAssertEqual(changed[0].sections[0].tasks[0].date, "2026-11-06")
        XCTAssertEqual(changed[0].sections[0].tasks[0].startTime, "10:00")
        let bad = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"complete_task","args":{"taskId":"t"}},{"type":"delete_task","args":{"taskId":"missing"}}]}"#)
        XCTAssertThrowsError(try KairosChatActions.apply(bad.actions, to: boards))
        XCTAssertFalse(boards[0].sections[0].tasks[0].completed)
        var series = boards; series[0].sections[0].tasks[0].recurrence = try JSONDecoder().decode(KairosRecurrenceMarker.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertThrowsError(try KairosChatActions.apply(response.actions, to: series))
    }
}
