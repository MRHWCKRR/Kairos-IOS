import XCTest
@testable import KairosCore

final class OccurrenceChecklistTests: XCTestCase {
    private func task() -> [String: Any] {
        ["id":"t","title":"Revision","date":"2026-11-05","checklist":[
            ["id":"a","title":"Read","completed":true,"webMetadata":"keep"],
            ["id":"b","title":"Practice","completed":false]
        ],"recurrence":["enabled":true,"frequency":"daily","startDate":"2026-11-05","interval":1,"endType":"never","mode":"flexible","exceptions":[:]]]
    }
    private func occurrence(_ task: [String: Any], _ date: String = "2026-11-05") throws -> KairosRecurringOccurrence {
        try XCTUnwrap(KairosRecurrence.occurrences(task: task, on: date).first)
    }
    private func exception(_ task: [String: Any], _ date: String = "2026-11-05") throws -> [String: Any] {
        let rule = try XCTUnwrap(task["recurrence"] as? [String: Any])
        let exceptions = try XCTUnwrap(rule["exceptions"] as? [String: Any])
        return try XCTUnwrap(exceptions[date] as? [String: Any])
    }
    func testProgressBelongsToOneOccurrenceAndTemplateIsPreserved() throws {
        let original = task()
        let selected = try occurrence(original)
        var items = selected.task.checklist ?? []
        XCTAssertFalse(items[0].completed)
        items[0].completed = true
        let updated = try KairosRecurrence.settingChecklist(task: original, occurrence: selected, items: items)
        XCTAssertTrue(try occurrence(updated).task.checklist?[0].completed == true)
        XCTAssertFalse(try occurrence(updated, "2026-11-06").task.checklist?[0].completed == true)
        XCTAssertEqual((updated["checklist"] as? [[String: Any]])?[0]["completed"] as? Bool, true)
        let saved = try exception(updated)["override"] as? [String: Any]
        XCTAssertEqual((saved?["checklist"] as? [[String: Any]])?[0]["webMetadata"] as? String, "keep")
    }
    func testSeparateStepEditsMergeButCompetingEditsFail() throws {
        let original = task()
        let selected = try occurrence(original)
        var first = selected.task.checklist ?? []
        first[0].completed = true
        let remote = try KairosRecurrence.settingChecklist(task: original, occurrence: selected, items: first)
        var second = selected.task.checklist ?? []
        second[1].title = "Remote-compatible edit"
        let merged = try KairosRecurrence.settingChecklist(task: remote, occurrence: selected, items: second)
        let result = try occurrence(merged)
        XCTAssertTrue(result.task.checklist?[0].completed == true)
        XCTAssertEqual(result.task.checklist?[1].title, "Remote-compatible edit")
        var rename = first; rename[0].title = "Device one"
        let renamed = try KairosRecurrence.settingChecklist(task: original, occurrence: selected, items: rename)
        var competing = first; competing[0].title = "Device two"
        XCTAssertThrowsError(try KairosRecurrence.settingChecklist(task: renamed, occurrence: selected, items: competing))
    }
    func testOtherOccurrenceAndFocusChangesArePreserved() throws {
        let original = task()
        let selected = try occurrence(original)
        var remote = original
        var rule = try XCTUnwrap(remote["recurrence"] as? [String: Any])
        rule["exceptions"] = ["2026-11-05":["focusLoggedSeconds":120,"custom":"keep"],"2026-11-06":["status":"completed"]]
        remote["recurrence"] = rule
        var items = selected.task.checklist ?? []; items[1].completed = true
        let updated = try KairosRecurrence.settingChecklist(task: remote, occurrence: selected, items: items)
        XCTAssertEqual(try exception(updated)["focusLoggedSeconds"] as? Int, 120)
        XCTAssertEqual(try exception(updated)["custom"] as? String, "keep")
        XCTAssertEqual(try exception(updated, "2026-11-06")["status"] as? String, "completed")
        XCTAssertNil(try exception(updated)["status"])
    }
    func testRuleOrStatusChangesRejectStaleChecklist() throws {
        let original = task()
        let selected = try occurrence(original)
        let items = selected.task.checklist ?? []
        let skipped = try KairosRecurrence.settingStatus(task: original, occurrence: selected, status: "skipped", timestamp: "now")
        XCTAssertThrowsError(try KairosRecurrence.settingChecklist(task: skipped, occurrence: selected, items: items))
        var changed = original
        var rule = try XCTUnwrap(changed["recurrence"] as? [String: Any])
        rule["interval"] = 2; changed["recurrence"] = rule
        XCTAssertThrowsError(try KairosRecurrence.settingChecklist(task: changed, occurrence: selected, items: items))
    }
    func testMovedOccurrenceKeepsItsLogicalKey() throws {
        var original = task()
        var rule = try XCTUnwrap(original["recurrence"] as? [String: Any])
        rule["exceptions"] = ["2026-11-05":["override":["date":"2026-11-07"]]]
        original["recurrence"] = rule
        let selected = try XCTUnwrap(KairosRecurrence.occurrences(task: original, on: "2026-11-07").first(where: { $0.occurrenceDate == "2026-11-05" }))
        var items = selected.task.checklist ?? []; items[0].completed = true
        let updated = try KairosRecurrence.settingChecklist(task: original, occurrence: selected, items: items)
        XCTAssertNotNil(try exception(updated)["override"])
        let savedOverride = try exception(updated)["override"] as? [String: Any]
        XCTAssertEqual(savedOverride?["date"] as? String, "2026-11-07")
        XCTAssertNotNil(savedOverride?["checklist"])
    }
    func testInvalidStepsAreRejected() throws {
        let original = task()
        let selected = try occurrence(original)
        XCTAssertThrowsError(try KairosRecurrence.settingChecklist(task: original, occurrence: selected, items: [KairosChecklistItem(id:"a",title:" ",completed:false)]))
    }

    func testHistoricalChecklistKeepsStatusAndEmptyOverrideClearsSteps() throws {
        var original = task()
        var rule = try XCTUnwrap(original["recurrence"] as? [String: Any])
        rule["endType"] = "date"; rule["endDate"] = "2026-11-04"
        rule["exceptions"] = ["2026-11-05":["status":"completed","completedAt":"saved","focusLoggedSeconds":120]]
        original["recurrence"] = rule
        let selected = try occurrence(original)
        let updated = try KairosRecurrence.settingChecklist(task: original, occurrence: selected, items: [])
        let saved = try exception(updated)
        XCTAssertEqual(saved["status"] as? String, "completed")
        XCTAssertEqual(saved["completedAt"] as? String, "saved")
        XCTAssertEqual(saved["focusLoggedSeconds"] as? Int, 120)
        XCTAssertTrue(try occurrence(updated).task.checklist?.isEmpty == true)
    }
}
