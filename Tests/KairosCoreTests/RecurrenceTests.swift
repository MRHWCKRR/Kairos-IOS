import XCTest
@testable import KairosCore

final class RecurrenceTests: XCTestCase {
    private func task(_ rule: [String: Any]) -> [String: Any] {
        ["id":"series","title":"Study","date":"2026-03-01","completed":false,"recurrence":rule]
    }
    private func rule(_ edits: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["enabled":true,"frequency":"daily","interval":1,"startDate":"2026-03-01","endType":"never","mode":"flexible"]
        result.merge(edits) { _, new in new }
        return result
    }
    func testDailyCountAndWeeklyIntervals() throws {
        let daily = task(rule(["endType":"count","count":2]))
        XCTAssertEqual(try KairosRecurrence.occurrences(task: daily, on: "2026-03-02").count, 1)
        XCTAssertTrue(try KairosRecurrence.occurrences(task: daily, on: "2026-03-03").isEmpty)
        let weekly = task(rule(["frequency":"weekly","interval":2,"weekdays":[1,3]]))
        XCTAssertEqual(try KairosRecurrence.occurrences(task: weekly, on: "2026-03-02").count, 1)
        XCTAssertTrue(try KairosRecurrence.occurrences(task: weekly, on: "2026-03-09").isEmpty)
        XCTAssertEqual(try KairosRecurrence.occurrences(task: weekly, on: "2026-03-16").count, 1)
    }
    func testMonthlyAndLeapYearRules() throws {
        let monthly = task(rule(["frequency":"monthly","monthDay":31]))
        XCTAssertTrue(try KairosRecurrence.occurrences(task: monthly, on: "2026-04-30").isEmpty)
        let lastFriday = task(rule(["frequency":"monthly","monthlyMode":"weekdayPosition","weekdayPosition":"last","weekday":5]))
        XCTAssertEqual(try KairosRecurrence.occurrences(task: lastFriday, on: "2026-03-27").count, 1)
        let yearly = task(rule(["frequency":"yearly","month":2,"monthDay":29]))
        XCTAssertEqual(try KairosRecurrence.occurrences(task: yearly, on: "2028-02-29").count, 1)
        XCTAssertTrue(try KairosRecurrence.occurrences(task: yearly, on: "2027-02-28").isEmpty)
    }
    func testLogicalDatesAcrossDSTAndInclusiveEnd() throws {
        let value = task(rule(["endType":"date","endDate":"2026-03-09"]))
        for day in ["2026-03-07","2026-03-08","2026-03-09"] {
            XCTAssertEqual(try KairosRecurrence.occurrences(task: value, on: day).first?.occurrenceDate, day)
        }
        XCTAssertTrue(try KairosRecurrence.occurrences(task: value, on: "2026-03-10").isEmpty)
    }
    func testMovedAndDeletedExceptions() throws {
        let value = task(rule(["exceptions":["2026-03-02":["override":["date":"2026-03-05","startTime":"14:00"]],"2026-03-05":["status":"deleted"]]]))
        XCTAssertTrue(try KairosRecurrence.occurrences(task: value, on: "2026-03-02").isEmpty)
        let result = try KairosRecurrence.occurrences(task: value, on: "2026-03-05")
        XCTAssertEqual(result.map(\.id), ["series::2026-03-02"])
        XCTAssertEqual(result.first?.displayDate, "2026-03-05")
        XCTAssertEqual(result.first?.startTime, "14:00")
    }
    func testStatusChangesPreserveSeriesUnknownMetadataAndOtherOccurrences() throws {
        var value = task(rule(["exceptions":["2026-03-02":["focusLoggedSeconds":60,"custom":"keep"],"2026-03-03":["status":"skipped"]],"customRule":"keep"]))
        value["nativeMetadata"] = Date() // intentionally not JSON-serializable
        let occurrence = try XCTUnwrap(KairosRecurrence.occurrences(task: value, on: "2026-03-02").first)
        let updated = try KairosRecurrence.settingStatus(task: value, occurrence: occurrence, status: "completed", timestamp: "2026-03-02T10:00:00Z")
        XCTAssertEqual(updated["completed"] as? Bool, false)
        XCTAssertNotNil(updated["nativeMetadata"] as? Date)
        let recurrence = try XCTUnwrap(updated["recurrence"] as? [String: Any])
        XCTAssertEqual(recurrence["customRule"] as? String, "keep")
        let exceptions = try XCTUnwrap(recurrence["exceptions"] as? [String: [String: Any]])
        XCTAssertEqual(exceptions["2026-03-02"]?["status"] as? String, "completed")
        XCTAssertEqual(exceptions["2026-03-02"]?["focusLoggedSeconds"] as? Int, 60)
        XCTAssertEqual(exceptions["2026-03-02"]?["custom"] as? String, "keep")
        XCTAssertEqual(exceptions["2026-03-03"]?["status"] as? String, "skipped")
    }
    func testHistoricalReopenPinsOccurrenceAfterRuleChange() throws {
        let value = task(rule(["frequency":"weekly","weekdays":[1],"exceptions":["2026-03-03":["status":"completed","completedAt":"old"]]]))
        let occurrence = try XCTUnwrap(KairosRecurrence.occurrences(task: value, on: "2026-03-03").first)
        let updated = try KairosRecurrence.settingStatus(task: value, occurrence: occurrence, status: "pending", timestamp: "now")
        XCTAssertEqual(try KairosRecurrence.occurrences(task: updated, on: "2026-03-03").first?.status, "pending")
    }
    func testCompetingChangesAndInvalidActionsFail() throws {
        let value = task(rule())
        let occurrence = try XCTUnwrap(KairosRecurrence.occurrences(task: value, on: "2026-03-02").first)
        var changed = value; changed["recurrence"] = rule(["interval":2])
        XCTAssertThrowsError(try KairosRecurrence.settingStatus(task: changed, occurrence: occurrence, status: "completed", timestamp: "now"))
        XCTAssertThrowsError(try KairosRecurrence.settingStatus(task: value, occurrence: occurrence, status: "deleted", timestamp: "now"))
        XCTAssertThrowsError(try KairosRecurrence.occurrences(task: value, on: "2026-02-30"))
    }
}
