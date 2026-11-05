import XCTest
@testable import KairosCore

final class TodayTests: XCTestCase {
    func testTodayUsesWebGroupsAndOrdersEventsBeforeUntimedDeadlines() throws {
        let plan: [String: Any] = ["boards": [["id": "b", "sections": [["id": "s", "tasks": [
            ["id": "old", "title": "Old", "date": "2026-11-01", "dueDate": "2026-11-10"],
            ["id": "due", "title": "Due", "dueDate": "2026-11-05"], ["id": "free", "title": "Free"], ["id": "done", "title": "Done", "completed": true]
        ]]]]], "scheduleEvents": [["id": "class", "title": "Class", "date": "2026-11-05", "start": "08:00", "end": "09:00"]]]
        let result = try KairosToday.build(planJSON: KairosTouchSchedule.json(plan), today: "2026-11-05")
        XCTAssertEqual(result.overdue.map(\.title), ["Old"])
        XCTAssertEqual(result.today.map(\.title), ["Class", "Due"])
        XCTAssertEqual(result.unscheduled.map(\.title), ["Free"])
        XCTAssertEqual(result.today.last?.searchRow.target.taskId, "due")
    }
    func testMovedRecurringOccurrenceUsesLogicalIdentity() throws {
        let plan: [String: Any] = ["boards": [["id": "b", "sections": [["id": "s", "tasks": [["id": "r", "title": "Review", "date": "2026-11-03", "recurrence": ["enabled": true, "frequency": "daily", "interval": 1, "startDate": "2026-11-03", "endType": "count", "count": 1, "mode": "fixed", "exceptions": ["2026-11-03": ["override": ["date": "2026-11-05"]]]]]]]]]]]
        let result = try KairosToday.build(planJSON: KairosTouchSchedule.json(plan), today: "2026-11-05")
        XCTAssertEqual(result.today.first?.occurrenceDate, "2026-11-03")
        XCTAssertEqual(result.today.first?.date, "2026-11-05")
        XCTAssertEqual(result.today.first?.canComplete, false)
        XCTAssertTrue(result.overdue.isEmpty)
    }
    func testInvalidTodayIsRejected() throws {
        XCTAssertThrowsError(try KairosToday.build(planJSON: "{}", today: "2026-02-30"))
    }
}
