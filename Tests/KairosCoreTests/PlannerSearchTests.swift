import XCTest
@testable import KairosCore

final class PlannerSearchTests: XCTestCase {
    private func makeIndex(_ tasks: [[String: Any]]) throws -> KairosSearchIndex {
        let plan: [String: Any] = ["boards": [["id": "b", "title": "Science", "sections": [["id": "s", "title": "Homework", "tasks": tasks]]]]]
        return try KairosPlannerSearch.build(planJSON: KairosPlannerSearch.inputJSON(plan), today: "2026-11-05")
    }
    func testSearchNormalizesNotesAndAssignmentNamesAndKeepsDestination() throws {
        let index = try makeIndex([["id": "a", "title": "Café report", "notes": "Cell biology"], ["id": "c", "title": "Introduction", "assignmentId": "a"]])
        let note = try KairosPlannerSearch.search(index, query: "biology homework", status: .all)
        XCTAssertEqual(note.total, 1); XCTAssertEqual(note.rows.first?.target.taskId, "a")
        let child = try KairosPlannerSearch.search(index, query: "cafe introduction", status: .all)
        XCTAssertEqual(child.rows.first?.label, "Assignment session")
        XCTAssertEqual(child.rows.first?.target.boardId, "b"); XCTAssertEqual(child.rows.first?.target.sectionId, "s")
    }
    func testDeadlineTakesPrecedenceAndBoardsOnlyAppearInAll() throws {
        let index = try makeIndex([["id": "a", "title": "Future deadline", "date": "2026-11-01", "dueDate": "2026-11-10"], ["id": "b", "title": "Overdue", "date": "2026-11-01"], ["id": "c", "title": "Complete", "completed": true]])
        XCTAssertEqual(try KairosPlannerSearch.search(index, query: "", status: .overdue).rows.map(\.title), ["Overdue"])
        XCTAssertEqual(try KairosPlannerSearch.search(index, query: "", status: .completed).rows.map(\.title), ["Complete"])
        XCTAssertFalse(try KairosPlannerSearch.search(index, query: "", status: .unfinished).rows.contains { $0.kind == "board" })
    }
    func testDuplicateAndArchivedIdentitiesAreExcludedAndResultsAreBounded() throws {
        var tasks: [[String: Any]] = (0..<65).map { ["id": "t\($0)", "title": "Report \($0)"] }
        tasks += [["id": "dup", "title": "Duplicate"], ["id": "dup", "title": "Archived duplicate", "archived": true]]
        let index = try makeIndex(tasks)
        let result = try KairosPlannerSearch.search(index, query: "Report", status: .all)
        XCTAssertEqual(result.total, 65); XCTAssertEqual(result.rows.count, 50)
        XCTAssertEqual(try KairosPlannerSearch.search(index, query: "Duplicate", status: .all).total, 0)
    }
    func testMalformedDateCannotIndexPlanner() throws {
        XCTAssertThrowsError(try KairosPlannerSearch.build(planJSON: "{\"boards\":[]}", today: "2026-02-30"))
    }
    func testArchivedMalformedRecurrenceDoesNotHideReadableTasks() throws {
        let index = try makeIndex([["id": "a", "title": "Readable"], ["id": "old", "title": "Legacy", "archived": true, "recurrence": ["enabled": true, "exceptions": "legacy"]], ["id": "dup", "title": "Duplicate", "recurrence": ["enabled": true, "exceptions": "legacy"]], ["id": "dup", "title": "Other duplicate"], ["id": "off", "title": "Disabled recurrence", "recurrence": ["enabled": false, "exceptions": "legacy"]]])
        XCTAssertEqual(try KairosPlannerSearch.search(index, query: "Readable", status: .all).total, 1)
        XCTAssertEqual(try KairosPlannerSearch.search(index, query: "Duplicate", status: .all).total, 0)
        XCTAssertEqual(try KairosPlannerSearch.search(index, query: "Disabled recurrence", status: .all).total, 1)
    }
}
