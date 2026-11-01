import XCTest
@testable import KairosCore

final class IntegrationTests: XCTestCase {
    func testWorkspaceRequiresVerifiedIdentity() {
        XCTAssertFalse(KairosAccess.canEnterWorkspace(userID: nil, emailVerified: true))
        XCTAssertFalse(KairosAccess.canEnterWorkspace(userID: "", emailVerified: true))
        XCTAssertFalse(KairosAccess.canEnterWorkspace(userID: "a", emailVerified: false))
        XCTAssertTrue(KairosAccess.canEnterWorkspace(userID: "a", emailVerified: true))
    }

    func testAIRequestUsesProductionAndBothTokens() throws {
        let request = try KairosAIContract.request(messages: [["role": "user", "content": "Hello"]], idToken: "identity", appCheckToken: "attestation")
        XCTAssertEqual(request.url?.absoluteString, "https://kairos-web.kirosapp.workers.dev/api/ai")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer identity")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "attestation")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual((body["messages"] as? [[String: String]])?.first?["content"], "Hello")
        XCTAssertNil(body["apiKey"])
    }

    func testAIRejectsMissingTokensInvalidRolesAndOversizedRequests() {
        let messages = [["role": "user", "content": "Hi"]]
        XCTAssertThrowsError(try KairosAIContract.request(messages: messages, idToken: "", appCheckToken: "app"))
        XCTAssertThrowsError(try KairosAIContract.request(messages: messages, idToken: "id", appCheckToken: ""))
        XCTAssertThrowsError(try KairosAIContract.request(messages: [["role": "tool", "content": "Hi"]], idToken: "id", appCheckToken: "app"))
        XCTAssertThrowsError(try KairosAIContract.request(messages: [["role": "user", "content": String(repeating: "a", count: 131072)]], idToken: "id", appCheckToken: "app"))
        XCTAssertThrowsError(try KairosAIContract.request(messages: Array(repeating: messages[0], count: 41), idToken: "id", appCheckToken: "app"))
    }

    func testAIResponsePreservesAllowanceErrors() throws {
        let data = Data(#"{"error":"You have reached your weekly Kairos AI allowance.","code":"weekly-account","resetsAt":"2026-11-02T00:00:00Z"}"#.utf8)
        XCTAssertThrowsError(try KairosAIContract.response(data: data, status: 429)) { error in
            let service = error as? KairosAIServiceError
            XCTAssertEqual(service?.status, 429)
            XCTAssertEqual(service?.code, "weekly-account")
            XCTAssertEqual(service?.resetsAt, "2026-11-02T00:00:00Z")
            XCTAssertEqual(service?.errorDescription, "You have reached your weekly Kairos AI allowance.")
        }
        XCTAssertEqual(try KairosAIContract.response(data: Data(#"{"choices":[{"message":{"content":"Hello"}}]}"#.utf8), status: 200), "Hello")
        XCTAssertThrowsError(try KairosAIContract.response(data: Data("<html>error</html>".utf8), status: 502))
        XCTAssertThrowsError(try KairosAIContract.response(data: Data(#"{"choices":[]}"#.utf8), status: 200))
    }

    private func plan(title: String = "Original", completed: Bool = false) -> [String: Any] {
        ["boards": [["id": "b", "title": "Board", "archived": false, "sections": [["id": "s", "title": "Section", "archived": false, "tasks": [["id": "t", "title": title, "completed": completed, "archived": false]]]]]]]
    }

    func testPlannerPreservesUnknownFieldsAndConcurrentEdits() throws {
        let base = plan()
        let local = plan(completed: true)
        var remote = plan(title: "Renamed on web")
        remote["calendarSources"] = [["id": "feed", "url": "https://example.com/calendar"]]
        let result = try KairosPlannerMerge.merge(base: base, local: local, remote: remote)
        let boards = try XCTUnwrap(result["boards"] as? [[String: Any]])
        let sections = try XCTUnwrap(boards[0]["sections"] as? [[String: Any]])
        let tasks = try XCTUnwrap(sections[0]["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks[0]["title"] as? String, "Renamed on web")
        XCTAssertEqual(tasks[0]["completed"] as? Bool, true)
        XCTAssertNotNil(result["calendarSources"])
        // An unknown task field must survive even though the iOS model never decoded it.
        var webTask = tasks[0]; webTask["estimatedMinutes"] = 35
        var webSection = sections[0]; webSection["tasks"] = [webTask]
        var webBoard = boards[0]; webBoard["sections"] = [webSection]
        let withUnknown = try KairosPlannerMerge.merge(base: base, local: local, remote: ["boards": [webBoard]])
        let changedBoard = (withUnknown["boards"] as! [[String: Any]])[0]
        let changedSection = (changedBoard["sections"] as! [[String: Any]])[0]
        XCTAssertEqual((changedSection["tasks"] as! [[String: Any]])[0]["estimatedMinutes"] as? Int, 35)
    }

    func testPlannerRejectsCompetingEditsAndRemoteDeletion() {
        XCTAssertThrowsError(try KairosPlannerMerge.merge(base: plan(), local: plan(title: "iOS"), remote: plan(title: "Web")))
        XCTAssertThrowsError(try KairosPlannerMerge.merge(base: plan(), local: plan(completed: true), remote: ["boards": []]))
    }

    func testPlannerPreservesRemoteAdditionAndClearsOptionalDate() throws {
        let base: [String: Any] = ["boards": [["id": "a", "date": "2026-11-01"]]]
        let local: [String: Any] = ["boards": [["id": "a"]]]
        let remote: [String: Any] = ["boards": [["id": "a", "date": "2026-11-01", "webOnly": "keep"], ["id": "b"]]]
        let result = try KairosPlannerMerge.merge(base: base, local: local, remote: remote)
        let boards = try XCTUnwrap(result["boards"] as? [[String: Any]])
        XCTAssertEqual(boards.count, 2)
        XCTAssertNil(boards[0]["date"])
        XCTAssertEqual(boards[0]["webOnly"] as? String, "keep")
    }

    func testPlannerRejectsDuplicateIDs() {
        let duplicate: [String: Any] = ["boards": [["id": "b"], ["id": "b"]]]
        XCTAssertThrowsError(try KairosPlannerMerge.merge(base: plan(), local: plan(completed: true), remote: duplicate))
    }
}
