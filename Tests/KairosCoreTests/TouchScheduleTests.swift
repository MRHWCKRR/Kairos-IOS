import XCTest
@testable import KairosCore

final class TouchScheduleTests: XCTestCase {
    private func plan(_ extra: [String: Any] = [:]) -> [String: Any] {
        var task: [String: Any] = ["id": "t", "title": "Essay", "date": "2026-11-05", "startTime": "09:00", "endTime": "10:00", "notes": "Keep", "dueDate": "2026-11-10", "dueTime": "23:00", "custom": "web"]
        task.merge(extra) { _, new in new }
        return ["boards": [["id": "b", "title": "Study", "sections": [["id": "s", "title": "Work", "tasks": [task]]]]], "scheduleEvents": []]
    }
    private func draft(_ plan: [String: Any], occurrence: String? = nil, allow: Bool = false) throws -> KairosTouchDraft {
        try KairosTouchSchedule.begin(plan: plan, target: .init(taskId: "t", occurrenceDate: occurrence), ownerID: "u", planID: "p", timezone: "Australia/Brisbane", allowCompleted: allow)
    }
    private func task(_ plan: [String: Any]) -> [String: Any] {
        let b = plan["boards"] as! [[String: Any]], s = b[0]["sections"] as! [[String: Any]], t = s[0]["tasks"] as! [[String: Any]]; return t[0]
    }
    func testFiveMinuteSnappingPreservesMoveDurationAndStaysInDay() throws {
        let moved = try KairosTouchSchedule.move(date: "2026-11-06", targetStart: 602, duration: 37)
        XCTAssertEqual(moved.start, 600); XCTAssertEqual(moved.duration, 37)
        let late = try KairosTouchSchedule.move(date: "2026-11-06", targetStart: 1440, duration: 37)
        XCTAssertEqual(late.start % 5, 0); XCTAssertLessThanOrEqual(late.end, 1440)
        XCTAssertEqual(try KairosTouchSchedule.resize(date: "2026-11-06", start: 540, targetEnd: 622).end, 620)
        XCTAssertEqual(try KairosTouchSchedule.resize(date: "2026-11-06", start: 540, targetEnd: 500).duration, 5)
        XCTAssertThrowsError(try KairosTouchSchedule.move(date: "2026-11-06", targetStart: .nan, duration: 60))
    }
    func testMoveAndUndoTouchOnlySchedulingFields() throws {
        let raw = plan(), start = try draft(raw)
        let moved = try KairosTouchSchedule.apply(plan: raw, draft: start, placement: .init(date: "2026-11-06", start: 600, end: 660), allowCompleted: false)
        XCTAssertEqual(task(moved.plan)["date"] as? String, "2026-11-06")
        XCTAssertEqual(task(moved.plan)["dueDate"] as? String, "2026-11-10")
        XCTAssertEqual(task(moved.plan)["custom"] as? String, "web")
        let restored = try KairosTouchSchedule.undo(plan: moved.plan, record: moved.undo, allowCompleted: false)
        XCTAssertEqual(task(restored)["date"] as? String, "2026-11-05")
        XCTAssertEqual(task(restored)["startTime"] as? String, "09:00")
        XCTAssertNil(task(restored)["lastScheduledMinutes"])
    }
    func testLocksStatusChangesAndNewerScheduleRejectStaleWork() throws {
        XCTAssertThrowsError(try draft(plan(["scheduleLocked": true])))
        XCTAssertThrowsError(try draft(plan(["completed": true])))
        XCTAssertNoThrow(try draft(plan(["completed": true]), allow: true))
        let start = try draft(plan())
        XCTAssertThrowsError(try KairosTouchSchedule.apply(plan: plan(["startTime": "11:00"]), draft: start, placement: .init(date: "2026-11-06", start: 600, end: 660), allowCompleted: false))
    }
    func testSingleOccurrenceUndoPreservesNewUnknownExceptionMetadata() throws {
        let rule: [String: Any] = ["enabled": true, "frequency": "daily", "mode": "fixed", "interval": 1, "startDate": "2026-11-05", "endType": "never", "customRule": "keep", "exceptions": [:]]
        let raw = plan(["recurrence": rule]), start = try draft(raw, occurrence: "2026-11-05")
        var moved = try KairosTouchSchedule.apply(plan: raw, draft: start, placement: .init(date: "2026-11-07", start: 720, end: 780), allowCompleted: false)
        var b = moved.plan["boards"] as! [[String: Any]], s = b[0]["sections"] as! [[String: Any]], tasks = s[0]["tasks"] as! [[String: Any]], r = tasks[0]["recurrence"] as! [String: Any], exceptions = r["exceptions"] as! [String: Any], selected = exceptions["2026-11-05"] as! [String: Any]
        selected["futureMetadata"] = "keep"; exceptions["2026-11-05"] = selected
        exceptions["2026-11-06"] = ["status": "skipped", "focusLoggedSeconds": 90]
        r["exceptions"] = exceptions; tasks[0]["recurrence"] = r; s[0]["tasks"] = tasks; b[0]["sections"] = s; moved.plan["boards"] = b
        let restored = try KairosTouchSchedule.undo(plan: moved.plan, record: moved.undo, allowCompleted: false)
        let restoredRule = task(restored)["recurrence"] as! [String: Any], dates = restoredRule["exceptions"] as! [String: Any]
        XCTAssertEqual(restoredRule["customRule"] as? String, "keep")
        XCTAssertEqual((dates["2026-11-05"] as? [String: Any])?["futureMetadata"] as? String, "keep")
        XCTAssertEqual((dates["2026-11-06"] as? [String: Any])?["focusLoggedSeconds"] as? Int, 90)
        XCTAssertNil((dates["2026-11-05"] as? [String: Any])?["override"])
    }
}
