import XCTest
@testable import KairosCore

final class FindTimeTests: XCTestCase {
    func testOccurrencePlanningOverridesSurviveProjection() throws {
        let task: [String: Any] = ["id": "r", "date": "2026-11-01", "recurrence": ["enabled": true, "frequency": "daily", "interval": 1, "mode": "flexible", "startDate": "2026-11-01", "endType": "never", "exceptions": ["2026-11-02": ["override": ["scheduleLocked": true, "dueDate": "2026-11-03", "assignmentId": "a", "schedulingPreference": "evening"]]]]]
        let plan: [String: Any] = ["boards": [["id": "b", "sections": [["id": "s", "tasks": [task]]]]]]
        let state = try KairosFindTime.state(plan)
        let tasks = try KairosAIProposalEngine.maps(state["boards"]).flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        let rule = try XCTUnwrap(tasks[0]["recurrence"] as? [String: Any])
        let exceptions = try XCTUnwrap(rule["exceptions"] as? [String: Any])
        let exception = try XCTUnwrap(exceptions["2026-11-02"] as? [String: Any])
        let override = try XCTUnwrap(exception["override"] as? [String: Any])
        XCTAssertEqual(override["scheduleLocked"] as? Bool, true)
        XCTAssertEqual(override["dueDate"] as? String, "2026-11-03")
        XCTAssertEqual(override["assignmentId"] as? String, "a")
        XCTAssertEqual(override["schedulingPreference"] as? String, "evening")
    }

    func testPreviewApplyAndUndoPreserveUnknownFields() throws {
        let task: [String: Any] = ["id": "t", "title": "Work", "estimatedMinutes": 30, "webOnly": ["keep": true]]
        let plan: [String: Any] = ["boards": [["id": "b", "sections": [["id": "s", "tasks": [task]]]]]]
        let settings = KairosPlanningSettings(timezone: "UTC", timeFormat: "24", dailyLimitMinutes: 0, gapMinutes: 0, rescheduleCompleted: false, weeklyAvailability: nil)
        let review = try KairosFindTime.preview(state: KairosFindTime.state(plan), target: .init(taskId: "t"), recovery: false, settings: settings, ownerID: "u", planID: "p")
        let placement = try XCTUnwrap(review.slots.first)
        try KairosFindTime.validate(plan: plan, profile: [:], draft: review.draft, placement: placement, review: try XCTUnwrap(review.draft.planningReviewJSON))
        let applied = try KairosTouchSchedule.apply(plan: plan, draft: review.draft, placement: placement, allowCompleted: false)
        let tasks = try KairosAIProposalEngine.maps(applied.plan["boards"]).flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        XCTAssertEqual((tasks[0]["webOnly"] as? [String: Bool])?["keep"], true)
        let restored = try KairosTouchSchedule.undo(plan: applied.plan, record: applied.undo, allowCompleted: false)
        XCTAssertEqual(try KairosTouchSchedule.json(restored), try KairosTouchSchedule.json(plan))
    }
}
