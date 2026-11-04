import XCTest
@testable import KairosCore

final class TaskMutationTests: XCTestCase {
    private func boards() -> [KairosBoard] {
        [KairosBoard(id: "b", title: "Board", archived: false, sections: [
            KairosSection(id: "s", title: "Section", archived: false, tasks: [
                KairosTask(id: "p", title: "Parent", completed: false, archived: false, date: nil),
                KairosTask(id: "t", title: "Task", completed: false, archived: false, date: "2026-11-04", taskDescription: "Keep me", dueTime: "16:30", parentTaskID: "p")
            ])
        ])]
    }
    func testRenamePreservesDetailsAndExplicitClearWorks() throws {
        var value = boards()
        var patch = KairosTaskPatch()
        patch.title = .set("Renamed")
        value = try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: nil), to: value)
        let task = value[0].sections[0].tasks[1]
        XCTAssertEqual(task.taskDescription, "Keep me")
        XCTAssertEqual(task.date, "2026-11-04")
        XCTAssertEqual(task.dueTime, "16:30")
        XCTAssertEqual(task.parentTaskID, "p")
        patch = KairosTaskPatch()
        patch.date = .set(nil)
        patch.parentTaskID = .set(nil)
        value = try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: nil), to: value)
        XCTAssertNil(value[0].sections[0].tasks[1].date)
        XCTAssertNil(value[0].sections[0].tasks[1].parentTaskID)
        XCTAssertEqual(value[0].sections[0].tasks[1].taskDescription, "Keep me")
    }
    func testStaleEditorMergesUneditedFieldsButRejectsCompetingTitle() throws {
        let original = boards()[0].sections[0].tasks[1]
        var remote = boards()
        remote[0].sections[0].tasks[1].taskDescription = "Changed on web"
        var patch = KairosTaskPatch()
        patch.title = .set("Local title")
        let merged = try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: original), to: remote)
        XCTAssertEqual(merged[0].sections[0].tasks[1].taskDescription, "Changed on web")
        remote[0].sections[0].tasks[1].title = "Remote title"
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: original), to: remote))
    }
    func testDeletedAndAmbiguousTargetsFail() {
        var value = boards()
        XCTAssertThrowsError(try KairosTaskMutation.apply(.delete(sectionID: "s", taskID: "missing"), to: value))
        let task = value[0].sections[0].tasks[1]
        value[0].sections[0].tasks.append(task)
        XCTAssertThrowsError(try KairosTaskMutation.apply(.setCompleted(taskID: "t", completed: true), to: value))
    }
    func testCreateCompleteArchiveAndDeleteUseSamePath() throws {
        var value = boards()
        value = try KairosTaskMutation.apply(.create(sectionID: "s", taskID: "new", title: "Child", parentTaskID: "p"), to: value)
        value = try KairosTaskMutation.apply(.setCompleted(taskID: "t", completed: true), to: value)
        XCTAssertFalse(value[0].sections[0].tasks[0].completed)
        value = try KairosTaskMutation.apply(.setCompleted(taskID: "new", completed: true), to: value)
        XCTAssertTrue(value[0].sections[0].tasks[0].completed)
        value = try KairosTaskMutation.apply(.setCompleted(taskID: "t", completed: false), to: value)
        XCTAssertFalse(value[0].sections[0].tasks[0].completed)
        value = try KairosTaskMutation.apply(.archive(taskID: "new", archived: true), to: value)
        XCTAssertTrue(value[0].sections[0].tasks[2].archived)
        value = try KairosTaskMutation.apply(.delete(sectionID: "s", taskID: "new"), to: value)
        XCTAssertEqual(value[0].sections[0].tasks.count, 2)
    }
    func testInvalidParentAndEmptyNamesFailWithoutChangingInput() {
        let value = boards()
        XCTAssertThrowsError(try KairosTaskMutation.apply(.create(sectionID: "s", taskID: "new", title: " ", parentTaskID: nil), to: value))
        XCTAssertThrowsError(try KairosTaskMutation.apply(.create(sectionID: "s", taskID: "new", title: "Child", parentTaskID: "missing"), to: value))
        var patch = KairosTaskPatch()
        patch.parentTaskID = .set("t")
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: nil), to: value))
        XCTAssertEqual(value, boards())
    }
    func testCyclesFailRatherThanRecursingForever() {
        var value = boards()
        value[0].sections[0].tasks[0].parentTaskID = "t"
        XCTAssertThrowsError(try KairosTaskMutation.apply(.setCompleted(taskID: "t", completed: false), to: value))
    }
    func testArchivingParentDoesNotBlockEditingExistingChildren() throws {
        var value = try KairosTaskMutation.apply(.archive(taskID: "p", archived: true), to: boards())
        var patch = KairosTaskPatch()
        patch.title = .set("Child renamed")
        value = try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: nil), to: value)
        XCTAssertEqual(value[0].sections[0].tasks[1].title, "Child renamed")
        XCTAssertEqual(value[0].sections[0].tasks[1].parentTaskID, "p")
        XCTAssertThrowsError(try KairosTaskMutation.apply(.create(sectionID: "s", taskID: "new", title: "New", parentTaskID: "p"), to: value))
    }

    func testClearingOptionalFieldDetectsConcurrentChangesFromNil() {
        let original = boards()[0].sections[0].tasks[0]
        var value = boards()
        value[0].sections[0].tasks[0].taskDescription = "Remote notes"
        var patch = KairosTaskPatch()
        patch.description = .set(nil)
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "p", patch: patch, expected: original), to: value))
    }

    func testConcurrentDeletionAndTaskEditConflict() throws {
        let task: [String: Any] = ["id": "t", "title": "Task", "notes": "web metadata"]
        let base: [String: Any] = ["tasks": [task]]
        let local: [String: Any] = ["tasks": []]
        let remote: [String: Any] = ["tasks": [["id": "t", "title": "Remote", "notes": "web metadata"]]]
        XCTAssertThrowsError(try KairosPlannerMerge.merge(base: base, local: local, remote: remote))
    }
}
