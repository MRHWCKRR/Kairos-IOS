import XCTest
@testable import KairosCore

final class TaskFocusTests: XCTestCase {
    private let now = 1_793_980_800_000.0
    private func plan() -> [String: Any] { ["userID": "one", "boards": [["id": "b", "sections": [["id": "s", "tasks": [["id": "t", "title": "Read", "unknown": Date(), "estimatedMinutes": 30]]]]]]] }
    func testLogPreservesRawMetadataAndRetryIsIdempotent() throws {
        let source = plan(), target = try XCTUnwrap(KairosFocus.target(plan: source, taskID: "t").0)
        let entry = KairosFocusLog(id: "f", ownerId: "one", planId: "p", createdAt: now - 60000, endedAt: now, seconds: 60, target: target)
        let first = try KairosFocus.apply(user: ["focusData": ["dailyTasksLog": ["keep": 2], "unknown": Date()]], plan: source, entry: entry, now: now)
        let user = try XCTUnwrap(first.userPatch), focus = user["focusData"] as! [String: Any]
        XCTAssertEqual(focus["totalSeconds"] as? Int, 60); XCTAssertNotNil(focus["unknown"]); XCTAssertNotNil(focus["dailyTasksLog"])
        let boards = try XCTUnwrap(first.planBoards), sections = boards[0]["sections"] as! [[String: Any]], tasks = sections[0]["tasks"] as! [[String: Any]]
        XCTAssertNotNil(tasks[0]["unknown"]); XCTAssertNil(tasks[0]["completed"])
        var saved = source; saved["boards"] = boards
        let retry = try KairosFocus.apply(user: user, plan: saved, entry: entry, now: now)
        XCTAssertNil(retry.userPatch); XCTAssertNil(retry.planBoards)
    }
    func testRecoveryNeverAddsClosedAppTimeAndPendingIsImmutable() throws {
        let session = KairosFocusSession(id: "f", ownerId: "one", planId: nil, createdAt: now - 20000, accumulatedMs: 1000, startedAt: now - 10000, lastSeenAt: now - 5000, target: nil)
        let recovered = try session.recovered(now: now)
        XCTAssertNil(recovered.startedAt); XCTAssertEqual(recovered.accumulatedMs, 6000)
        XCTAssertEqual(recovered.elapsed(now: now + 3_600_000), 6000)
        let prepared = try recovered.preparedLog(now: now)
        XCTAssertEqual(try prepared.preparedLog(now: now + 5000).pending, prepared.pending)
        XCTAssertThrowsError(try prepared.validated(owner: "other"))
    }
    func testDurableStoreSeparatesOwnersAndGuardsRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KairosFocusRecoveryStore(directory: directory)
        let session = KairosFocusSession(id: "f", ownerId: "one", planId: nil, createdAt: now, startedAt: nil, lastSeenAt: now, target: nil)
        try store.write(session)
        XCTAssertEqual(try store.read(owner: "one"), session); XCTAssertNil(try store.read(owner: "two"))
        XCTAssertThrowsError(try store.remove(owner: "one", expectedID: "other"))
        try store.remove(owner: "one", expectedID: "f"); XCTAssertNil(try store.read(owner: "one"))
    }
    func testMalformedReceiptStateCannotLoseRetryProtection() throws {
        let entry = KairosFocusLog(id: "f", ownerId: "one", planId: nil, createdAt: now - 1000, endedAt: now, seconds: 1, target: nil)
        XCTAssertThrowsError(try KairosFocus.apply(user: ["focusLogReceipts": "invalid"], plan: nil, entry: entry, now: now))
        XCTAssertThrowsError(try KairosFocus.apply(user: ["focusLogReceiptFloor": -1], plan: nil, entry: entry, now: now))
    }
    func testRetainedReceiptAndHistoryNestedMetadataStayRaw() throws {
        let source = plan(), target = try XCTUnwrap(KairosFocus.target(plan: source, taskID: "t").0)
        let first = KairosFocusLog(id: "first", ownerId: "one", planId: "p", createdAt: now - 60000, endedAt: now, seconds: 60, target: target)
        var user = try XCTUnwrap(KairosFocus.apply(user: [:], plan: source, entry: first, now: now).userPatch)
        var receipts = user["focusLogReceipts"] as! [[String: Any]], result = receipts[0]["result"] as! [String: Any], task = result["task"] as! [String: Any]
        task["extra"] = Date(); result["task"] = task; result["extra"] = Date(); receipts[0]["result"] = result; user["focusLogReceipts"] = receipts
        var history = user["focusHistory"] as! [String: Any], rows = history["sessions"] as! [[String: Any]]
        rows[0]["extra"] = Date(); history["sessions"] = rows; user["focusHistory"] = history
        let second = KairosFocusLog(id: "second", ownerId: "one", planId: "p", createdAt: now - 60000, endedAt: now, seconds: 60, target: target)
        let updated = try XCTUnwrap(KairosFocus.apply(user: user, plan: source, entry: second, now: now).userPatch)
        let savedReceipts = updated["focusLogReceipts"] as! [[String: Any]], savedResult = savedReceipts[0]["result"] as! [String: Any]
        XCTAssertNotNil(savedResult["extra"]); XCTAssertNotNil((savedResult["task"] as! [String: Any])["extra"])
        XCTAssertNotNil(((updated["focusHistory"] as! [String: Any])["sessions"] as! [[String: Any]])[0]["extra"])
    }
    func testOccurrenceChecklistMetadataDoesNotEnterFocusProjection() throws {
        let source: [String: Any] = ["userID": "one", "boards": [["id": "b", "sections": [["id": "s", "tasks": [["id": "r", "title": "Read", "recurrence": ["enabled": true, "frequency": "daily", "startDate": "2026-11-01", "exceptions": ["2026-11-07": ["override": ["checklist": [["id": "c", "title": "Read", "completed": true, "custom": Date()]]]]]]]]]]]]]
        let target = try XCTUnwrap(KairosFocus.target(plan: source, taskID: "r", occurrenceDate: "2026-11-07").0)
        let entry = KairosFocusLog(id: "r", ownerId: "one", planId: "p", createdAt: now - 60000, endedAt: now, seconds: 60, target: target)
        let result = try KairosFocus.apply(user: [:], plan: source, entry: entry, now: now)
        let b = try XCTUnwrap(result.planBoards), s = b[0]["sections"] as! [[String: Any]], t = s[0]["tasks"] as! [[String: Any]], rule = t[0]["recurrence"] as! [String: Any], exceptions = rule["exceptions"] as! [String: Any], e = exceptions["2026-11-07"] as! [String: Any], override = e["override"] as! [String: Any], checklist = override["checklist"] as! [[String: Any]]
        XCTAssertNotNil(checklist[0]["custom"]); XCTAssertEqual(e["focusLoggedSeconds"] as? Int, 60)
    }
}
