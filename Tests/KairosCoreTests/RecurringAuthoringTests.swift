import XCTest
@testable import KairosCore

final class RecurringAuthoringTests: XCTestCase {
    private func plan() -> [String: Any] {
        let json = #"{"boards":[{"id":"b","sections":[{"id":"s","tasks":[{"id":"t","title":"Study","date":"2026-11-01","custom":"keep","recurrence":{"enabled":true,"frequency":"daily","interval":1,"startDate":"2026-11-01","mode":"fixed","endType":"count","count":5,"customRule":"keep","exceptions":{"2026-11-03":{"status":"completed","focusLoggedSeconds":60,"customException":"keep","override":{"checklist":[{"id":"c","title":"Read","completed":true,"customStep":"keep"}]}}}}}]}]}]}"#
        return try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }
    func testSplitPreservesRawMetadataAndRejectsStaleLocation() throws {
        let source = plan(), baseline = try KairosRecurringEdit.capture(source, taskID: "t")
        let rule = try KairosRecurringEdit.seed(baseline).rule
        let request = KairosRecurringEditRequest(scope: "future", day: "2026-11-02", rule: rule, title: "Updated", startTime: nil, endTime: nil)
        let result = try KairosRecurringEdit.apply(source, baseline: baseline, request: request, newTaskID: "new")
        let tasks = ((result["boards"] as! [[String: Any]])[0]["sections"] as! [[String: Any]])[0]["tasks"] as! [[String: Any]]
        XCTAssertEqual(tasks.count, 2); XCTAssertEqual(tasks[0]["custom"] as? String, "keep")
        let oldRule = tasks[0]["recurrence"] as! [String: Any], exceptions = oldRule["exceptions"] as! [String: Any], saved = exceptions["2026-11-03"] as! [String: Any]
        XCTAssertEqual(oldRule["customRule"] as? String, "keep"); XCTAssertEqual(saved["customException"] as? String, "keep")
        let checklist = (saved["override"] as! [String: Any])["checklist"] as! [[String: Any]]
        XCTAssertEqual(checklist[0]["customStep"] as? String, "keep"); XCTAssertEqual(saved["focusLoggedSeconds"] as? Int, 60)
        var moved = source, boards = source["boards"] as! [[String: Any]]; boards[0]["id"] = "elsewhere"; moved["boards"] = boards
        XCTAssertThrowsError(try KairosRecurringEdit.apply(moved, baseline: baseline, request: request, newTaskID: "new"))
        XCTAssertThrowsError(try KairosRecurringEdit.apply(source, baseline: baseline, request: request, newTaskID: "t"))
    }
    func testCreationRejectsDuplicateSectionAndNestedTaskConversion() throws {
        let rule = KairosRepeatRule(startDate: "2026-11-07")
        let empty: [String: Any] = ["boards": [["id": "b", "sections": [["id": "s", "tasks": []]]]]]
        let result = try KairosRecurringEdit.create(empty, sectionID: "s", taskID: "new", title: "Read", rule: rule)
        XCTAssertNotNil(result["boards"])
        var duplicate = empty; duplicate["boards"] = (empty["boards"] as! [[String: Any]]) + (empty["boards"] as! [[String: Any]])
        XCTAssertThrowsError(try KairosRecurringEdit.create(duplicate, sectionID: "s", taskID: "new", title: "Read", rule: rule))
    }
    func testPreviewAndApplyUseSameDates() throws {
        let source = plan(), baseline = try KairosRecurringEdit.capture(source, taskID: "t"), rule = try KairosRecurringEdit.seed(baseline).rule
        let request = KairosRecurringEditRequest(scope: "series", day: "2026-11-01", rule: rule, title: "Study", startTime: "11:00", endTime: "12:00")
        let preview = try KairosRecurringEdit.preview(baseline, request: request)
        XCTAssertEqual(preview.preserved, 1); XCTAssertFalse(preview.after.isEmpty)
        var changed = source, boards = source["boards"] as! [[String: Any]], sections = boards[0]["sections"] as! [[String: Any]], tasks = sections[0]["tasks"] as! [[String: Any]]
        tasks[0]["title"] = "Remote"; sections[0]["tasks"] = tasks; boards[0]["sections"] = sections; changed["boards"] = boards
        XCTAssertThrowsError(try KairosRecurringEdit.apply(changed, baseline: baseline, request: request, newTaskID: "new"))
    }
    private func wrapping(_ task: [String: Any]) -> [String: Any] { ["boards": [["id": "b", "sections": [["id": "s", "tasks": [task]]]]]] }
    func testLegacyPresetAndInferredMonthlyDateSurviveSeed() throws {
        for (source, frequency, day) in [
            (["enabled": true, "preset": "weekdays", "startDate": "2026-11-07"] as [String: Any], "weekly", 7),
            (["enabled": true, "frequency": "monthly", "startDate": "2026-11-07"], "monthly", 7)
        ] {
            let baseline = try KairosRecurringEdit.capture(wrapping(["id": "t", "title": "Study", "recurrence": source]), taskID: "t")
            let seed = try KairosRecurringEdit.seed(baseline)
            XCTAssertEqual(seed.rule.frequency, frequency)
            if frequency == "weekly" { XCTAssertEqual(seed.rule.weekdays, [1, 2, 3, 4, 5]) }
            else { XCTAssertEqual(seed.rule.monthDay, day) }
        }
    }
    func testOccurrenceResetRemovesKnownOverrideButRetainsUnknownMetadata() throws {
        let rule: [String: Any] = ["enabled": true, "frequency": "daily", "startDate": "2026-11-01", "exceptions": ["2026-11-02": ["override": ["title": "Custom", "customOverride": "keep"]]]]
        let source = wrapping(["id": "t", "title": "Template", "recurrence": rule]), baseline = try KairosRecurringEdit.capture(source, taskID: "t")
        let request = KairosRecurringEditRequest(scope: "occurrence", day: "2026-11-02", rule: try KairosRecurringEdit.seed(baseline).rule, title: "Template", startTime: nil, endTime: nil)
        let result = try KairosRecurringEdit.apply(source, baseline: baseline, request: request, newTaskID: "new")
        let b = result["boards"] as! [[String: Any]], sections = b[0]["sections"] as! [[String: Any]], tasks = sections[0]["tasks"] as! [[String: Any]], updatedRule = tasks[0]["recurrence"] as! [String: Any], exceptions = updatedRule["exceptions"] as! [String: Any], exception = exceptions["2026-11-02"] as! [String: Any]
        let override = exception["override"] as! [String: Any]
        XCTAssertNil(override["title"]); XCTAssertEqual(override["customOverride"] as? String, "keep")
    }

    func testFutureSplitKeepsUnknownOverrideMetadataAndNoCopiedFocus() throws {
        let rule: [String: Any] = ["enabled": true, "frequency": "daily", "startDate": "2026-11-01", "exceptions": ["2026-11-05": ["override": ["title": "Custom", "unknown": "keep"]]]]
        let source = wrapping(["id": "t", "title": "Study", "focusLoggedSeconds": 900, "remainingMinutes": 30, "recurrence": rule]), baseline = try KairosRecurringEdit.capture(source, taskID: "t")
        let request = KairosRecurringEditRequest(scope: "future", day: "2026-11-03", rule: try KairosRecurringEdit.seed(baseline).rule, title: "Study", startTime: nil, endTime: nil)
        let result = try KairosRecurringEdit.apply(source, baseline: baseline, request: request, newTaskID: "new")
        let b = result["boards"] as! [[String: Any]], sections = b[0]["sections"] as! [[String: Any]], tasks = sections[0]["tasks"] as! [[String: Any]], oldRule = tasks[0]["recurrence"] as! [String: Any], exceptions = oldRule["exceptions"] as! [String: Any], saved = exceptions["2026-11-05"] as! [String: Any], override = saved["override"] as! [String: Any]
        XCTAssertEqual(override["unknown"] as? String, "keep"); XCTAssertNil(tasks[1]["focusLoggedSeconds"]); XCTAssertNil(tasks[1]["remainingMinutes"])
    }

    func testOrdinaryTaskEditorCannotBypassRecurringScheduleReview() throws {
        let source = plan()
        XCTAssertThrowsError(try KairosTaskEditGuard.capture(plan: source, taskID: "t", changesSchedule: true, unlocking: false))
        XCTAssertNoThrow(try KairosTaskEditGuard.capture(plan: source, taskID: "t", changesSchedule: false, unlocking: false))
        let task = try JSONDecoder().decode(KairosTask.self, from: Data(#"{"id":"t","title":"Study","recurrence":{"enabled":true}}"#.utf8))
        var patch = KairosTaskPatch(); patch.startTime = .set("11:00")
        let boards = [KairosBoard(id: "b", title: "Board", archived: false, sections: [KairosSection(id: "s", title: "Section", archived: false, tasks: [task])])]
        XCTAssertThrowsError(try KairosTaskMutation.apply(.update(taskID: "t", patch: patch, expected: task), to: boards))
    }

}
