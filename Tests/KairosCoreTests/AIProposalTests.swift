import XCTest
@testable import KairosCore

final class AIProposalTests: XCTestCase {
    private var plan: [String: Any] { ["boards": [["id": "b", "title": "Study", "sections": [["id": "s", "title": "Work", "tasks": [["id": "t", "title": "Essay", "date": "2026-11-06", "startTime": "09:00", "endTime": "10:00", "webMetadata": "keep"]]]]]], "scheduleEvents": []] }
    func testSavedProposalRestoresAndDetectsStaleState() throws {
        let actions = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"set_task_reminder","args":{"taskId":"t","minutesBefore":15}}]}"#).actions
        let proposal = try KairosAIProposalEngine.make(actions: actions, plan: plan, ownerID: "u", chatID: "c", planID: "p", timezone: "Australia/Brisbane", request: "Remind me")
        let restored = try JSONDecoder().decode(KairosAIProposal.self, from: JSONEncoder().encode(proposal))
        XCTAssertEqual(restored.id, proposal.id)
        XCTAssertEqual(restored.rows.first?.title, "Essay")
        let applied = try KairosAIProposalEngine.prepare(restored, plan: plan)
        let tasks = ((applied.after["boards"] as? [[String: Any]])?.first?["sections"] as? [[String: Any]])?.first?["tasks"] as? [[String: Any]]
        XCTAssertEqual(tasks?.first?["reminderMinutes"] as? Int, 15)
        XCTAssertEqual(tasks?.first?["webMetadata"] as? String, "keep")
        var changed = plan; changed["scheduleEvents"] = [["id": "e", "title": "Class", "date": "2026-11-06", "start": "09:00", "end": "10:00"]]
        XCTAssertThrowsError(try KairosAIProposalEngine.prepare(restored, plan: changed))
    }
    func testReceiptConfirmsRetryAndRejectsPayloadReuse() throws {
        let actions = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"create_board","args":{"title":"New"}}]}"#).actions
        let proposal = try KairosAIProposalEngine.make(actions: actions, plan: plan, ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Create board")
        let receipt = try KairosAIProposalEngine.receipt(proposal)
        XCTAssertTrue(try KairosAIProposalEngine.wasApplied(proposal, plan: ["aiNativeActionReceipts": [receipt]]))
        var changed = receipt; changed["fingerprint"] = "different"
        XCTAssertThrowsError(try KairosAIProposalEngine.wasApplied(proposal, plan: ["aiNativeActionReceipts": [changed]]))
        XCTAssertThrowsError(try KairosAIProposalEngine.wasApplied(proposal, plan: ["aiNativeActionReceiptFloor": proposal.createdAt]))
    }
    func testOrdinaryActionsPreserveFieldsOmittedByTypedModels() throws {
        let raw: [String: Any] = ["boards": [["id": "b", "title": "Study", "sections": [["id": "s", "title": "Work", "tasks": [["id": "t", "title": "Essay", "lastScheduledMinutes": 45, "scheduleLocked": true, "schedulingPreference": "morning", "recurrence": ["enabled": true, "frequency": "daily", "mode": "fixed", "startDate": "2026-11-05", "endType": "never", "exceptions": ["2026-11-06": ["custom": "keep"]]]]]]]]], "scheduleEvents": []]
        let actions = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"update_board","args":{"boardId":"b","newTitle":"Renamed"}}]}"#).actions
        let p = try KairosAIProposalEngine.make(actions: actions, plan: raw, ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Rename")
        let updated = try KairosAIProposalEngine.prepare(p, plan: raw).after
        let boards = try XCTUnwrap(updated["boards"] as? [[String: Any]])
        let sections = try XCTUnwrap(boards[0]["sections"] as? [[String: Any]])
        let tasks = try XCTUnwrap(sections[0]["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks[0]["lastScheduledMinutes"] as? Int, 45)
        XCTAssertEqual(tasks[0]["scheduleLocked"] as? Bool, true)
        XCTAssertEqual(tasks[0]["schedulingPreference"] as? String, "morning")
        XCTAssertEqual((tasks[0]["recurrence"] as? [String: Any])?["frequency"] as? String, "daily")
        XCTAssertNotNil((tasks[0]["recurrence"] as? [String: Any])?["exceptions"])
    }
    func testDiscardAndApplyHistoryPreventLateReplyResurrection() throws {
        let actions = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"create_board","args":{"title":"New"}}]}"#).actions
        let p = try KairosAIProposalEngine.make(actions: actions, plan: plan, ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Create")
        for state in ["applied", "discarded"] {
            let retired = try KairosAIProposalHistory.retire(p, state: state, user: [:])
            XCTAssertTrue(try KairosAIProposalHistory.isRetired(p, user: retired))
            XCTAssertEqual((try KairosAIProposalHistory.retire(p, state: state, user: retired)["aiNativeProposalHistory"] as? [[String: Any]])?.count, 1)
        }
        XCTAssertThrowsError(try KairosAIProposalHistory.isRetired(p, user: ["aiNativeProposalHistoryFloor": p.createdAt]))
        XCTAssertNoThrow(try KairosAIProposalHistory.retire(p, state: "discarded", user: ["aiNativeProposalHistoryFloor": p.createdAt]))
    }
    func testMixedBatchPreservesMetadataAndPinnedCreationIdentity() throws {
        let actions = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"create_schedule_event","args":{"title":"Training","date":"2026-11-06","start":"17:00","end":"18:00"}},{"type":"set_task_reminder","args":{"taskId":"t","minutesBefore":15}}]}"#).actions
        let p = try KairosAIProposalEngine.make(actions: actions, plan: plan, ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Plan")
        let first = try KairosAIProposalEngine.prepare(p, plan: plan)
        let second = try KairosAIProposalEngine.prepare(p, plan: plan)
        XCTAssertEqual((first.after["scheduleEvents"] as? [[String: Any]])?.first?["id"] as? String, (second.after["scheduleEvents"] as? [[String: Any]])?.first?["id"] as? String)
        XCTAssertTrue(p.rows[0].after.contains("17:00–18:00"))
        XCTAssertEqual(p.rows[0].before, "Not created")
        let bad = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"create_board","args":{"title":"New"}},{"type":"set_task_reminder","args":{"taskId":"missing","minutesBefore":15}}]}"#).actions
        XCTAssertThrowsError(try KairosAIProposalEngine.make(actions: bad, plan: plan, ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Plan"))
    }
    func testUnsupportedFieldsAreRejectedInsteadOfSilentlyIgnored() throws {
        XCTAssertThrowsError(try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"complete_task","args":{"taskId":"t","date":"2026-11-08"}}]}"#))
    }
    func testScheduleLocksAndCompletedPreferenceAreHonoured() throws {
        let actions = try KairosChatResponse.parse(#"{"reply":"Review","actions":[{"type":"update_task","args":{"taskId":"t","date":"2026-11-08"}}]}"#).actions
        func altered(_ fields: [String: Any]) -> [String: Any] {
            var task: [String: Any] = ["id": "t", "title": "Essay", "date": "2026-11-06", "startTime": "09:00", "endTime": "10:00"]
            task.merge(fields) { _, new in new }
            return ["boards": [["id": "b", "title": "Board", "sections": [["id": "s", "title": "Work", "tasks": [task]]]]], "scheduleEvents": []]
        }
        XCTAssertThrowsError(try KairosAIProposalEngine.make(actions: actions, plan: altered(["scheduleLocked": true]), ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Move"))
        XCTAssertThrowsError(try KairosAIProposalEngine.make(actions: actions, plan: altered(["completed": true]), ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Move"))
        XCTAssertNoThrow(try KairosAIProposalEngine.make(actions: actions, plan: altered(["completed": true]), ownerID: "u", chatID: "c", planID: "p", timezone: "UTC", request: "Move", allowCompletedRescheduling: true))
    }
}
