import XCTest
@testable import KairosCore

final class SessionPlanningTests: XCTestCase {
    func testPreviewApplyAndGuardedUndoKeepUnknownMetadata() throws {
        let task: [String: Any] = ["id": "essay", "title": "Essay", "dueDate": "2026-11-14", "unknown": ["keep": true]]
        let plan: [String: Any] = ["boards": [["id": "b", "sections": [["id": "s", "tasks": [task]]]]], "scheduleEvents": []]
        let settings = KairosPlanningSettings(timezone: "UTC", timeFormat: "24", dailyLimitMinutes: 120, gapMinutes: 5, rescheduleCompleted: false, weeklyAvailability: nil)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-08T08:00:00Z"))
        let review = try KairosSessionPlanning.preview(state: KairosFindTime.state(plan), taskID: "essay", total: 60, size: 30, ordered: true, labels: [], settings: settings, ownerID: "u", planID: "p", now: now)
        XCTAssertEqual(review.rows.count, 2)
        let profile: [String: Any] = ["settings": ["profile": ["timezone": "UTC"], "planning": ["dailyLimitMinutes": 120, "gapMinutes": 5]]]
        var changedTitle = plan
        var titleBoards = try KairosAIProposalEngine.maps(changedTitle["boards"])
        var titleSections = try KairosAIProposalEngine.maps(titleBoards[0]["sections"])
        var titleTasks = try KairosAIProposalEngine.maps(titleSections[0]["tasks"])
        titleTasks[0]["title"] = "Revised essay"
        titleSections[0]["tasks"] = titleTasks; titleBoards[0]["sections"] = titleSections; changedTitle["boards"] = titleBoards
        XCTAssertThrowsError(try KairosSessionPlanning.apply(plan: changedTitle, profile: profile, review: review, now: now))
        let applied = try KairosSessionPlanning.apply(plan: plan, profile: profile, review: review, now: now)
        let tasks = try KairosAIProposalEngine.maps(applied.plan["boards"]).flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual((tasks[0]["unknown"] as? [String: Bool])?["keep"], true)
        XCTAssertEqual(tasks[0]["sessionOrder"] as? String, "sequential")
        XCTAssertEqual(tasks[1]["assignmentId"] as? String, "essay")
        XCTAssertEqual(tasks[2]["sessionIndex"] as? Int, 2)
        let undone = try KairosSessionPlanning.undo(plan: applied.plan, saved: applied.undo)
        let restored = try KairosAIProposalEngine.maps(undone["boards"]).flatMap { try KairosAIProposalEngine.maps($0["sections"]) }.flatMap { try KairosAIProposalEngine.maps($0["tasks"]) }
        XCTAssertNil(restored[0]["sessionOrder"])
        XCTAssertEqual(restored[1]["archived"] as? Bool, true)
        XCTAssertEqual(restored[2]["archived"] as? Bool, true)
        var modified = applied.plan
        var boards = try KairosAIProposalEngine.maps(modified["boards"])
        var sections = try KairosAIProposalEngine.maps(boards[0]["sections"])
        var changed = try KairosAIProposalEngine.maps(sections[0]["tasks"])
        changed[1]["completed"] = true
        sections[0]["tasks"] = changed; boards[0]["sections"] = sections; modified["boards"] = boards
        XCTAssertThrowsError(try KairosSessionPlanning.undo(plan: modified, saved: applied.undo))
    }
}
