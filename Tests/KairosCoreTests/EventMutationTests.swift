import XCTest
@testable import KairosCore

final class EventMutationTests: XCTestCase {
    func testWeeklyOccurrenceMoveKeepsSeriesAndOtherExceptions() throws {
        let raw: [String: Any] = ["id": "e", "title": "Class", "day": 4, "start": "09:00", "end": "10:00", "category": "class", "color": "purple", "exceptions": ["2026-11-12": ["skipped": true]]]
        let edit = KairosEventEdit(eventID: "e", occurrenceDate: "2026-11-05", title: "Moved class", date: "2026-11-06", start: "11:00", end: "12:00", category: "class")
        let updated = try KairosEventMutation.apply(edit, to: [raw], expected: raw)
        XCTAssertEqual(updated[0]["day"] as? Int, 4)
        XCTAssertEqual(updated[0]["color"] as? String, "purple")
        XCTAssertTrue(try KairosScheduleProjection.events(updated, on: "2026-11-05").isEmpty)
        XCTAssertEqual(try KairosScheduleProjection.events(updated, on: "2026-11-06").first?.title, "Moved class")
        XCTAssertTrue(try KairosScheduleProjection.events(updated, on: "2026-11-12").isEmpty)
    }
    func testRemoteChangesAndManagedEventsRejectEdits() throws {
        let raw: [String: Any] = ["id": "e", "title": "Class", "date": "2026-11-05", "start": "09:00", "end": "10:00"]
        let edit = KairosEventEdit(eventID: "e", title: "New", date: "2026-11-06", start: "11:00", end: "12:00", category: "other")
        var remote = raw; remote["title"] = "Web edit"
        XCTAssertThrowsError(try KairosEventMutation.apply(edit, to: [remote], expected: raw))
        var imported = raw; imported["readOnly"] = true
        XCTAssertThrowsError(try KairosEventMutation.apply(edit, to: [imported], expected: imported))
    }
    func testExportUsesWallClockAcrossDSTAndOvernight() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for day in ["2026-03-08", "2026-11-01"] {
            let dates = try XCTUnwrap(KairosScheduleProjection.eventDates(day: day, start: "09:00", end: "10:00", calendar: calendar))
            XCTAssertEqual(calendar.component(.hour, from: dates.start), 9)
            XCTAssertEqual(calendar.component(.hour, from: dates.end), 10)
        }
        let dates = try XCTUnwrap(KairosScheduleProjection.eventDates(day: "2026-03-07", start: "23:00", end: "09:00", calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: dates.end), 8)
        XCTAssertEqual(calendar.component(.hour, from: dates.end), 9)
    }
    func testRecurringTaskMovePreservesLogicalIdentityAndMetadata() throws {
        let task: [String: Any] = ["id": "t", "title": "Work", "date": "2026-11-05", "startTime": "09:00", "endTime": "10:00", "recurrence": ["enabled": true, "frequency": "daily", "interval": 1, "startDate": "2026-11-05", "endType": "never", "exceptions": ["2026-11-05": ["focusLoggedSeconds": 600, "custom": "keep"]]]]
        let original = try XCTUnwrap(KairosRecurrence.occurrences(task: task, on: "2026-11-05").first)
        let range = try KairosRecurrence.occurrences(task: task, onDays: ["2026-11-05", "2026-11-06"])
        XCTAssertEqual(range["2026-11-05"]?.first?.id, original.id)
        XCTAssertEqual(range["2026-11-06"]?.count, 1)
        let updated = try KairosRecurrence.settingSchedule(task: task, occurrence: original, schedule: .init(date: "2026-11-07", startTime: "11:00", endTime: "12:00"))
        XCTAssertTrue(try KairosRecurrence.occurrences(task: updated, on: "2026-11-05").isEmpty)
        let moved = try XCTUnwrap(KairosRecurrence.occurrences(task: updated, on: "2026-11-07").first(where: { $0.id == original.id }))
        XCTAssertEqual(moved.occurrenceDate, "2026-11-05")
        XCTAssertEqual(moved.startTime, "11:00")
        let exceptions = (updated["recurrence"] as? [String: Any])?["exceptions"] as? [String: Any]
        let selected = exceptions?["2026-11-05"] as? [String: Any]
        XCTAssertEqual(selected?["custom"] as? String, "keep")
        XCTAssertEqual(selected?["focusLoggedSeconds"] as? Int, 600)
    }
}
