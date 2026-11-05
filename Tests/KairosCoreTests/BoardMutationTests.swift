import XCTest
@testable import KairosCore

final class BoardMutationTests: XCTestCase {
    private func fixture() -> [KairosBoard] {
        [KairosBoard(id: "b", title: "Board", archived: false, sections: [
            KairosSection(id: "s", title: "Section", archived: false, tasks: [
                KairosTask(id: "t", title: "Task", completed: false, archived: true, date: "2026-11-05")
            ])
        ], boardDescription: "Keep description")]
    }

    func testRenameTrimsNameAndPreservesBoardDetails() throws {
        let result = try KairosBoardMutation.apply(.renameBoard(boardID: "b", title: "  Renamed  "), to: fixture())
        XCTAssertEqual(result[0].title, "Renamed")
        XCTAssertEqual(result[0].boardDescription, "Keep description")
        XCTAssertEqual(result[0].sections[0].tasks[0].date, "2026-11-05")
    }

    func testSectionRenamePreservesTasks() throws {
        let result = try KairosBoardMutation.apply(.renameSection(sectionID: "s", title: " New section "), to: fixture())
        XCTAssertEqual(result[0].sections[0].title, "New section")
        XCTAssertTrue(result[0].sections[0].tasks[0].archived)
    }

    func testArchiveAndRestoreBoardPreservesChildArchiveState() throws {
        let archived = try KairosBoardMutation.apply(.archiveBoard(boardID: "b", archived: true), to: fixture())
        XCTAssertTrue(archived[0].archived)
        XCTAssertFalse(archived[0].sections[0].archived)
        XCTAssertTrue(archived[0].sections[0].tasks[0].archived)
        let restored = try KairosBoardMutation.apply(.archiveBoard(boardID: "b", archived: false), to: archived)
        XCTAssertFalse(restored[0].archived)
        XCTAssertTrue(restored[0].sections[0].tasks[0].archived)
    }

    func testSectionArchiveAndRestoreRequiresActiveBoard() throws {
        let archived = try KairosBoardMutation.apply(.archiveSection(sectionID: "s", archived: true), to: fixture())
        XCTAssertTrue(archived[0].sections[0].archived)
        let restored = try KairosBoardMutation.apply(.archiveSection(sectionID: "s", archived: false), to: archived)
        XCTAssertFalse(restored[0].sections[0].archived)
        var hidden = archived
        hidden[0].archived = true
        XCTAssertThrowsError(try KairosBoardMutation.apply(.archiveSection(sectionID: "s", archived: false), to: hidden))
        XCTAssertThrowsError(try KairosBoardMutation.apply(.renameSection(sectionID: "s", title: "Hidden"), to: hidden))
    }

    func testRejectsMissingAmbiguousAndArchivedRenameTargets() {
        var value = fixture()
        XCTAssertThrowsError(try KairosBoardMutation.apply(.renameBoard(boardID: "missing", title: "Name"), to: value))
        XCTAssertThrowsError(try KairosBoardMutation.apply(.renameSection(sectionID: "s", title: " \n "), to: value))
        value[0].archived = true
        XCTAssertThrowsError(try KairosBoardMutation.apply(.renameBoard(boardID: "b", title: "Hidden"), to: value))
        value = fixture(); value.append(value[0])
        XCTAssertThrowsError(try KairosBoardMutation.apply(.archiveBoard(boardID: "b", archived: true), to: value))
        value = fixture(); value[0].sections.append(value[0].sections[0])
        XCTAssertThrowsError(try KairosBoardMutation.apply(.renameSection(sectionID: "s", title: "Name"), to: value))
    }
}
