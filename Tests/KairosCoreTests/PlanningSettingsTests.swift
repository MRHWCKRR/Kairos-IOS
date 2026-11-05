import XCTest
@testable import KairosCore

final class PlanningSettingsTests: XCTestCase {
    private func defaults() throws -> KairosPlanningSettings { try KairosPlanningSettingsStore.read([:], fallbackTimezone: "Australia/Brisbane") }
    func testWebDefaultsAndStrictLimits() throws {
        var draft = try defaults()
        XCTAssertEqual(draft.timeFormat, "12"); XCTAssertEqual(draft.dailyLimitMinutes, 0)
        XCTAssertNil(draft.weeklyAvailability); XCTAssertFalse(draft.rescheduleCompleted)
        draft.dailyLimitMinutes = 14
        XCTAssertThrowsError(try KairosPlanningSettingsStore.patch(expected: defaults(), draft: draft, remote: [:]))
        draft.dailyLimitMinutes = 15; draft.gapMinutes = 20
        XCTAssertThrowsError(try KairosPlanningSettingsStore.patch(expected: defaults(), draft: draft, remote: [:]))
        draft.gapMinutes = 5; draft.timezone = "Mars/Olympus"
        XCTAssertThrowsError(try KairosPlanningSettingsStore.patch(expected: defaults(), draft: draft, remote: [:]))
    }
    func testChangedLeavesPreserveRemoteUnrelatedSettings() throws {
        let before = try defaults(); var draft = before; draft.gapMinutes = 10
        let remote: [String: Any] = ["profile": ["displayName": "New name"], "appearance": ["mode": "dark"], "planning": ["futureMetadata": "keep", "dailyLimitMinutes": 120]]
        let patch = try KairosPlanningSettingsStore.patch(expected: before, draft: draft, remote: remote)
        XCTAssertEqual(patch.count, 1); XCTAssertEqual(patch["settings.planning.gapMinutes"] as? Int, 10)
        XCTAssertNil(patch["settings.planning.dailyLimitMinutes"])
    }
    func testConcurrentChangesRejectAndExactRetrySucceeds() throws {
        let before = try defaults(); var draft = before; draft.gapMinutes = 10
        XCTAssertThrowsError(try KairosPlanningSettingsStore.patch(expected: before, draft: draft, remote: ["planning": ["gapMinutes": 5]]))
        XCTAssertEqual(try KairosPlanningSettingsStore.patch(expected: before, draft: draft, remote: ["planning": ["gapMinutes": 10]]).count, 1)
    }
    func testWeeklyHoursCanonicalAndRejectOverlap() throws {
        let before = try defaults(); var draft = before
        draft.weeklyAvailability = Dictionary(uniqueKeysWithValues: (0..<7).map { (String($0), []) })
        draft.weeklyAvailability?["1"] = [.init(start: "17:00", end: "18:00"), .init(start: "09:00", end: "12:00")]
        let patch = try KairosPlanningSettingsStore.patch(expected: before, draft: draft, remote: [:])
        let week = patch["settings.planning.weeklyAvailability"] as? [String: [[String: String]]]
        XCTAssertEqual(week?["1"]?.first?["start"], "09:00")
        draft.weeklyAvailability?["1"] = [.init(start: "09:00", end: "12:00"), .init(start: "11:00", end: "13:00")]
        XCTAssertThrowsError(try KairosPlanningSettingsStore.patch(expected: before, draft: draft, remote: [:]))
    }
    func testTimeFormatChangesDisplayOnly() {
        XCTAssertEqual(KairosTimeDisplay.clock(0, format: "12"), "12:00 AM")
        XCTAssertEqual(KairosTimeDisplay.clock(780, format: "12"), "1:00 PM")
        XCTAssertEqual(KairosTimeDisplay.clock(780, format: "24"), "13:00")
        XCTAssertEqual(KairosTimeDisplay.time("09:05", format: "12"), "9:05 AM")
    }
}
