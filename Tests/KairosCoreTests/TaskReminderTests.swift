import XCTest
@testable import KairosCore

final class TaskReminderTests: XCTestCase {
    func testDSTGapSkippedAndRepeatedHourUsesEarlierOccurrence() throws {
        XCTAssertNil(KairosTaskReminders.wallDate(day: "2026-03-08", time: "02:30", timezone: "America/New_York"))
        let repeated = try XCTUnwrap(KairosTaskReminders.wallDate(day: "2026-11-01", time: "01:30", timezone: "America/New_York"))
        XCTAssertEqual(ISO8601DateFormatter().string(from: repeated), "2026-11-01T05:30:00Z")
    }
    func testAccountIdentityRemovalAndBoundedPlanning() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z"))
        let candidate = KairosReminderCandidate(id: "t", title: "Essay", date: "2026-11-06", startTime: "09:00", minutesBefore: 15)
        let a = KairosTaskReminders.plan([candidate, candidate], ownerID: "a", timezone: "Australia/Brisbane", now: now)
        let b = KairosTaskReminders.plan([candidate], ownerID: "b", timezone: "Australia/Brisbane", now: now)
        XCTAssertEqual(a.count, 1)
        XCTAssertNotEqual(a.first?.id, b.first?.id)
        XCTAssertEqual(a.first?.startsAt.timeIntervalSince(a.first!.dueAt), 900)
        XCTAssertTrue(KairosTaskReminders.plan([], ownerID: "a", timezone: "Australia/Brisbane", now: now).isEmpty)
    }
}
