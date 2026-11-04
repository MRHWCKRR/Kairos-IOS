import XCTest
@testable import KairosCore

final class WebTaskDetailsTests: XCTestCase {
    private func task() throws -> KairosTask {
        try JSONDecoder().decode(KairosTask.self, from: Data(#"{"id":"t","title":"Essay","notes":"Web notes","priority":"high","estimatedMinutes":45,"checklist":[{"id":"a","title":"Research","completed":true},{"id":"b","title":"Write","completed":false}],"recurrence":{"enabled":true,"frequency":"weekly","exceptions":{}}}"#.utf8))
    }
    private func boards(_ task: KairosTask) -> [KairosBoard] {
        [KairosBoard(id: "b", title: "Board", archived: false, sections: [KairosSection(id: "s", title: "Section", archived: false, tasks: [task])])]
    }
    func testWebFieldsDecodeAndRoundTrip() throws {
        let value = try task()
        XCTAssertEqual(value.notes, "Web notes")
        XCTAssertEqual(value.priority, "high")
        XCTAssertEqual(value.estimatedMinutes, 45)
        XCTAssertEqual(value.checklist?.map(\.completed), [true, false])
        XCTAssertTrue(value.recurrence?.enabled == true)
        XCTAssertEqual(try JSONDecoder().decode(KairosTask.self, from: JSONEncoder().encode(value)), value)
    }
    func testPartialEditsPreserveNewFieldsAndCanClearEstimate() throws {
        var value = try task(); value.recurrence = nil
        var patch = KairosTaskPatch(); patch.title = .set("Renamed"); patch.estimatedMinutes = .set(nil)
        let result = try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: value), to: boards(value))[0].sections[0].tasks[0]
        XCTAssertEqual(result.notes, value.notes)
        XCTAssertEqual(result.priority, value.priority)
        XCTAssertEqual(result.checklist, value.checklist)
        XCTAssertNil(result.estimatedMinutes)
    }
    func testConflictingNotesFail() throws {
        let before = try task()
        var remote = before; remote.notes = "Remote"
        var patch = KairosTaskPatch(); patch.notes = .set("Local")
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: before), to: boards(remote)))
    }
    func testChecklistMergesSeparateStepEdits() throws {
        let base = [KairosChecklistItem(id: "a", title: "A", completed: false), KairosChecklistItem(id: "b", title: "B", completed: false)]
        var local = base; local[0].completed = true
        var remote = base; remote[1].title = "Remote B"
        let merged = try KairosChecklist.merge(base: base, local: local, remote: remote)
        XCTAssertTrue(merged[0].completed)
        XCTAssertEqual(merged[1].title, "Remote B")
        remote = base; remote[0].title = "Web A"; local = base; local[0].title = "Local A"
        XCTAssertThrowsError(try KairosChecklist.merge(base: base, local: local, remote: remote))
    }
    func testChecklistReorderAndDeletionConflicts() throws {
        let base = ["a","b","c"].map { KairosChecklistItem(id: $0, title: $0, completed: false) }
        XCTAssertEqual(try KairosChecklist.merge(base: base, local: [base[2],base[0],base[1]], remote: base).map(\.id), ["c","a","b"])
        var remote = base; remote[0].completed = true
        XCTAssertThrowsError(try KairosChecklist.merge(base: base, local: Array(base.dropFirst()), remote: remote))
    }
    func testWebLimitsAndDuplicateIDsAreRejected() throws {
        var value = try task(); value.recurrence = nil
        for minutes in [0, 1441] {
            var patch = KairosTaskPatch(); patch.estimatedMinutes = .set(minutes)
            XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: value), to: boards(value)))
        }
        var patch = KairosTaskPatch(); patch.notes = .set(String(repeating: "a", count: 3001))
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: value), to: boards(value)))
        patch = KairosTaskPatch(); patch.priority = .set("urgent")
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: value), to: boards(value)))
        let item = KairosChecklistItem(id: "a", title: "Step", completed: false)
        XCTAssertThrowsError(try KairosChecklist.validate([item,item]))
        XCTAssertThrowsError(try KairosChecklist.validate([KairosChecklistItem(id: "a", title: " ", completed: false)]))
        XCTAssertThrowsError(try KairosChecklist.validate([KairosChecklistItem(id: "a", title: String(repeating: "x", count: 181), completed: false)]))
        XCTAssertThrowsError(try KairosChecklist.validate((0...100).map { KairosChecklistItem(id: String($0), title: "Step", completed: false) }))
    }
    func testRecurringTemplatesCannotBeCompleted() throws {
        let value = try task()
        XCTAssertThrowsError(try KairosTaskMutation.apply(.setCompleted(taskID: "t", completed: true), to: boards(value)))
        var patch = KairosTaskPatch(); patch.checklist = .set(value.checklist ?? [])
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: value), to: boards(value)))
    }
    func testKnownEditsPreserveRecurrenceAndUnknownMetadata() throws {
        let base: [String: Any] = ["id":"t", "title":"Old", "recurrence":["enabled":true]]
        let local: [String: Any] = ["id":"t", "title":"New", "recurrence":["enabled":true]]
        let raw: [String: Any] = ["id":"t", "title":"Old", "recurrence":["enabled":true,"frequency":"weekly","exceptions":["2026-11-04":["status":"completed"]]], "color":"blue"]
        let saved = try KairosPlannerMerge.applyingKnownEdits(base: base, local: local, to: raw)
        XCTAssertEqual(saved["color"] as? String, "blue")
        XCTAssertEqual((saved["recurrence"] as? [String: Any])?["frequency"] as? String, "weekly")
        XCTAssertNotNil((saved["recurrence"] as? [String: Any])?["exceptions"])
    }

    func testRemoteReorderSurvivesLocalDeletion() throws {
        let base = ["a","b","c"].map { KairosChecklistItem(id: $0, title: $0, completed: false) }
        XCTAssertEqual(try KairosChecklist.merge(base: base, local: [base[0],base[2]], remote: [base[2],base[0],base[1]]).map(\.id), ["c","a"])
    }
    func testFinalPlannerRejectsConcurrentChecklistOverflowAndRecurringProgress() throws {
        func planner(_ items: [[String: Any]], repeating: Bool = false) -> [String: Any] {
            ["boards":[["id":"b","sections":[["id":"s","tasks":[["id":"t","checklist":items,"recurrence":["enabled":repeating]]]]]]]]
        }
        let baseItems: [[String: Any]] = (0..<99).map { ["id":String($0),"title":"Step","completed":false] }
        let base = planner(baseItems)
        let local = planner(baseItems + [["id":"local","title":"Local","completed":false]])
        let remote = planner(baseItems + [["id":"remote","title":"Remote","completed":false]])
        let merged = try KairosPlannerMerge.merge(base: base, local: local, remote: remote)
        XCTAssertThrowsError(try KairosChecklist.validateMergedPlanner(base: base, merged: merged))
        let unchecked = planner([["id":"a","title":"Step","completed":false]])
        let checked = planner([["id":"a","title":"Step","completed":true]], repeating: true)
        XCTAssertThrowsError(try KairosChecklist.validateMergedPlanner(base: unchecked, merged: checked))
    }
    func testRecurringAncestorCannotBeCompletedThroughChild() throws {
        var parent = try task(); parent.id = "parent"; parent.completed = false
        let child = KairosTask(id: "child", title: "Child", completed: false, archived: false, date: nil, parentTaskID: "parent")
        var value = boards(parent); value[0].sections[0].tasks.append(child)
        XCTAssertThrowsError(try KairosTaskMutation.apply(.setCompleted(taskID: "child", completed: true), to: value))
    }
}
