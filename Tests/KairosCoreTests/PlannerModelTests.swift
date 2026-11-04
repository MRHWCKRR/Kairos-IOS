import XCTest
@testable import KairosCore

final class PlannerModelTests: XCTestCase {
    func testTaskDetailsSurviveLoadingAndEditing() throws {
        let data = Data(#"{"id":"t","title":"Essay","taskDescription":"Draft introduction","dueTime":"16:30","parentTaskID":"parent","date":"2026-11-04"}"#.utf8)
        var task = try JSONDecoder().decode(KairosTask.self, from: data)
        XCTAssertEqual(task.taskDescription, "Draft introduction")
        XCTAssertEqual(task.dueTime, "16:30")
        XCTAssertEqual(task.parentTaskID, "parent")
        XCTAssertEqual(task.date, "2026-11-04")
        XCTAssertFalse(task.completed)
        XCTAssertFalse(task.archived)
        task.title = "Renamed"
        let reloaded = try JSONDecoder().decode(KairosTask.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(reloaded, task)
        XCTAssertEqual(reloaded.parentTaskID, "parent")
    }

    func testBoardDescriptionSurvivesRoundTrip() throws {
        let data = Data(#"{"id":"b","title":"School","boardDescription":"Term four"}"#.utf8)
        let board = try JSONDecoder().decode(KairosBoard.self, from: data)
        XCTAssertEqual(board.boardDescription, "Term four")
        XCTAssertFalse(board.archived)
        XCTAssertTrue(board.sections.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(KairosBoard.self, from: JSONEncoder().encode(board)), board)
    }

    func testLegacyTasksStillDefaultMissingOptionalFields() throws {
        let task = try JSONDecoder().decode(KairosTask.self, from: Data(#"{"id":"t","title":"Legacy"}"#.utf8))
        XCTAssertNil(task.taskDescription)
        XCTAssertNil(task.dueTime)
        XCTAssertNil(task.parentTaskID)
        XCTAssertNil(task.date)
        XCTAssertFalse(task.completed)
        XCTAssertFalse(task.archived)
    }

    func testMalformedKnownFieldsAreRejected() {
        for json in [
            #"{"id":"t","title":"Task","dueTime":42}"#,
            #"{"id":"t","title":"Task","taskDescription":[]}"#,
            #"{"id":"t","title":"Task","parentTaskID":false}"#,
            #"{"title":"Missing ID"}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(KairosTask.self, from: Data(json.utf8)))
        }
    }
}
