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
}
