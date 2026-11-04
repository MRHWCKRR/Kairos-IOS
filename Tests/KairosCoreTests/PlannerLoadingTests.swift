import XCTest
@testable import KairosCore

final class PlannerLoadingTests: XCTestCase {
    func testDatedWebEventDoesNotRequireWeekday() throws {
        let data = Data(#"{"id":"e","title":"Appointment","date":"2026-11-05","start":"09:00","end":"10:00"}"#.utf8)
        let event = try JSONDecoder().decode(KairosScheduleEvent.self, from: data)
        XCTAssertNil(event.day)
        XCTAssertEqual(event.date, "2026-11-05")
        XCTAssertEqual(event.category, "other")
        XCTAssertEqual(try JSONDecoder().decode(KairosScheduleEvent.self, from: JSONEncoder().encode(event)), event)
    }

    func testWeeklySundayZeroIsPreserved() throws {
        let data = Data(#"{"id":"e","title":"Weekly","day":0,"start":"09:00","end":"10:00","category":"work"}"#.utf8)
        let event = try JSONDecoder().decode(KairosScheduleEvent.self, from: data)
        XCTAssertEqual(event.day, 0)
        XCTAssertNil(event.date)
        XCTAssertEqual(event.scheduleLabel, "Sunday")
    }

    func testDatedEventWinsOverLegacyWeekdayOnExport() throws {
        let event = KairosScheduleEvent(id: "e", title: "Dated", category: "work", day: 0, start: "09:00", end: "10:00", date: "2026-11-05")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(event.scheduledDay(relativeTo: Date(timeIntervalSince1970: 0), calendar: calendar))
        XCTAssertEqual(calendar.component(.year, from: date), 2026)
        XCTAssertEqual(calendar.component(.month, from: date), 11)
        XCTAssertEqual(calendar.component(.day, from: date), 5)
    }

    func testInvalidExplicitDateDoesNotFallBackToWeekday() {
        let event = KairosScheduleEvent(id: "e", title: "Invalid", category: "work", day: 0, start: "09:00", end: "10:00", date: "2026-02-30")
        XCTAssertNil(event.scheduledDay(relativeTo: Date()))
    }

    func testMissingRequiredTaskStillFailsWithPreciseField() {
        struct Document: Decodable { let boards: [KairosBoard] }
        let data = Data(#"{"boards":[{"id":"b","title":"Board","sections":[{"id":"s","title":"Section","tasks":[{"title":"Missing ID"}]}]}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Document.self, from: data)) { error in
            let message = KairosPlannerDecoding.message(for: error)
            XCTAssertTrue(message.contains("boards[0].sections[0].tasks[0].id"))
            XCTAssertTrue(message.contains("is missing"))
            XCTAssertFalse(message.contains("Missing ID"))
        }
    }

    func testMalformedEventShowsCorrectPath() {
        struct Document: Decodable { let scheduleEvents: [KairosScheduleEvent] }
        let data = Data(#"{"scheduleEvents":[{"id":"e","title":"Event","day":"Monday","start":"09:00","end":"10:00"}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Document.self, from: data)) { error in
            XCTAssertTrue(KairosPlannerDecoding.message(for: error).contains("scheduleEvents[0].day"))
        }
    }

    func testAppendingEventPreservesDatedWebFields() throws {
        let existing: [String: Any] = ["id":"e","title":"Appointment","date":"2026-11-05","start":"09:00","end":"10:00"]
        var rawEvent = existing
        rawEvent["calendarSourceId"] = "external-source"
        let added: [String: Any] = ["id":"new","title":"Study","day":1,"start":"10:00","end":"11:00"]
        let result = try KairosPlannerMerge.applyingKnownEdits(
            base: ["scheduleEvents":[existing]],
            local: ["scheduleEvents":[existing,added]],
            to: ["scheduleEvents":[rawEvent]]
        )
        let events = try XCTUnwrap(result["scheduleEvents"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0]["calendarSourceId"] as? String, "external-source")
        XCTAssertEqual(events[0]["date"] as? String, "2026-11-05")
        XCTAssertNil(events[0]["day"])
    }
}
