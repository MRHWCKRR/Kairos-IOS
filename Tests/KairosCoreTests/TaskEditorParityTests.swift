import XCTest
@testable import KairosCore

final class TaskEditorParityTests: XCTestCase {
    private func boards() -> [KairosBoard] { [.init(id: "b", title: "Study", archived: false, sections: [.init(id: "s", title: "Work", archived: false, tasks: [.init(id: "t", title: "Essay", completed: false, archived: false, date: "2026-11-06")])])] }
    func testReminderLockPreferencePatchPreservesOtherFields() throws {
        let original = boards()[0].sections[0].tasks[0]
        var patch = KairosTaskPatch(); patch.reminderMinutes = .set(30); patch.scheduleLocked = .set(true); patch.schedulingPreference = .set("morning")
        let changed = try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: original), to: boards())[0].sections[0].tasks[0]
        XCTAssertEqual(changed.reminderMinutes, 30); XCTAssertEqual(changed.scheduleLocked, true); XCTAssertEqual(changed.schedulingPreference, "morning")
        XCTAssertEqual(changed.date, original.date); XCTAssertEqual(changed.title, original.title)
    }
    func testInvalidReminderPreferenceAndConflictingEditReject() throws {
        let original = boards()[0].sections[0].tasks[0]
        for bad in [0, -1, 10081] {
            var patch = KairosTaskPatch(); patch.reminderMinutes = .set(bad)
            XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: original), to: boards()))
        }
        var patch = KairosTaskPatch(); patch.schedulingPreference = .set("midnight")
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: original), to: boards()))
        patch = KairosTaskPatch(); patch.reminderMinutes = .set(15)
        var remote = boards(); remote[0].sections[0].tasks[0].reminderMinutes = 60
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: original), to: remote))
    }
    func testRemovingReminderDoesNotChangeDateOrLock() throws {
        var initial = boards(); initial[0].sections[0].tasks[0].reminderMinutes = 30; initial[0].sections[0].tasks[0].scheduleLocked = true
        var patch = KairosTaskPatch(); patch.reminderMinutes = .set(nil)
        let result = try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: initial[0].sections[0].tasks[0]), to: initial)[0].sections[0].tasks[0]
        XCTAssertNil(result.reminderMinutes); XCTAssertEqual(result.scheduleLocked, true); XCTAssertEqual(result.date, "2026-11-06")
    }
    func testFreshRemoteLockArchiveOrLocationRejectsSchedulingWrite() throws {
        func plan(locked: Bool = false, archived: Bool = false, board: String = "b") -> [String: Any] {
            ["boards": [["id": board, "sections": [["id": "s", "tasks": [["id": "t", "scheduleLocked": locked, "archived": archived]]]]]]]
        }
        let guardValue = try KairosTaskEditGuard.capture(plan: plan(), taskID: "t", changesSchedule: true, unlocking: false)
        XCTAssertNoThrow(try guardValue.validate(plan()))
        XCTAssertThrowsError(try guardValue.validate(plan(locked: true)))
        XCTAssertThrowsError(try guardValue.validate(plan(archived: true)))
        XCTAssertThrowsError(try guardValue.validate(plan(board: "other")))
        let unlock = try KairosTaskEditGuard.capture(plan: plan(locked: true), taskID: "t", changesSchedule: true, unlocking: true)
        XCTAssertNoThrow(try unlock.validate(plan(locked: true)))
        let fakeUnlock = try KairosTaskEditGuard.capture(plan: plan(), taskID: "t", changesSchedule: true, unlocking: true)
        XCTAssertThrowsError(try fakeUnlock.validate(plan(locked: true)))
    }
    func testAssignmentBridgeReturnsParentAndReadySession() throws {
        let raw: [String: Any] = ["boards": [["id": "b", "sections": [["id": "s", "tasks": [
            ["id": "a", "title": "Essay", "sessionOrder": "sequential", "dueDate": "2026-11-06"],
            ["id": "s1", "title": "Research", "assignmentId": "a", "sessionIndex": 1, "completed": true, "estimatedMinutes": 45],
            ["id": "s2", "title": "Draft", "assignmentId": "a", "sessionIndex": 2, "remainingMinutes": 25, "date": "2026-11-07"]
        ]]]]]]
        let summary = try XCTUnwrap(KairosAssignmentProgress.read(planJSON: KairosAssignmentProgress.inputJSON(raw), taskID: "s2", today: "2026-11-06"))
        XCTAssertEqual(summary.parentId, "a"); XCTAssertEqual(summary.total, 2); XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.remainingMinutes, 25); XCTAssertEqual(summary.readiness?.state, "ready"); XCTAssertEqual(summary.lateSessions, 1)
        XCTAssertEqual(summary.isSession, true)
    }
}
