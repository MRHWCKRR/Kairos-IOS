import XCTest
@testable import KairosCore

final class AIWorkspaceTests: XCTestCase {
    func testLegacyHistoryMigratesOnlyWhenWorkspaceAbsent() throws {
        let legacy: [[String: Any]] = [["role": "user", "content": "Hello"]]
        let value = try KairosAIWorkspace.read(nil, legacy: legacy, owner: "u")
        XCTAssertEqual(value.chats.first?.messages.first?.content, "Hello")
        let empty: [String: Any] = ["version": 2, "chats": [], "projects": []]
        XCTAssertTrue(try KairosAIWorkspace.read(empty, legacy: legacy, owner: "u").chats.isEmpty)
        XCTAssertThrowsError(try KairosAIWorkspace.read(["version": 3, "chats": []], legacy: legacy, owner: "u"))
        XCTAssertThrowsError(try KairosAIWorkspace.read(["chats": "bad"], legacy: legacy, owner: "u"))
        XCTAssertThrowsError(try KairosAIWorkspace.read(nil, legacy: [["role": "user"]], owner: "u"))
    }

    func testAppendPreservesRemoteChatsAndUnknownMemory() throws {
        let source: [String: Any] = ["version": 2, "unknown": "kept", "projects": [], "chats": [
            ["id": "c", "title": "", "summary": "Memory", "pendingActionBatch": ["x": 1], "messages": [["role": "user", "content": "web"]]],
            ["id": "other", "messages": []]
        ]]
        let message = KairosAIWorkspace.Message(id: "m", role: "assistant", content: "mobile")
        let result = try KairosAIWorkspace.applying(.append(chatID: "c", messages: [message]), to: source, legacy: [], owner: "u")
        let chats = try XCTUnwrap(result["chats"] as? [[String: Any]])
        XCTAssertEqual(chats.count, 2)
        XCTAssertEqual(chats[0]["summary"] as? String, "Memory")
        XCTAssertNotNil(chats[0]["pendingActionBatch"])
        XCTAssertEqual((chats[0]["messages"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(result["unknown"] as? String, "kept")
        let again = try KairosAIWorkspace.applying(.append(chatID: "c", messages: [message]), to: result, legacy: [], owner: "u")
        XCTAssertEqual(try KairosAIWorkspace.read(again, legacy: [], owner: "u").chats[0].messages.count, 2)
    }

    func testDeletedChatCannotBeResurrectedByPendingResponse() throws {
        XCTAssertThrowsError(try KairosAIWorkspace.applying(.append(chatID: "gone", messages: [.init(id: "m", role: "assistant", content: "Late")]), to: ["version": 2, "chats": [], "projects": []], legacy: [], owner: "u"))
    }
    func testDisabledMemoryAndPendingWebActionsAreRespected() throws {
        let source: [String: Any] = ["version": 2, "projects": [], "chats": [["id": "c", "messages": [], "summary": "Manual", "autoSummary": "Disabled", "autoMemoryEnabled": false, "pendingActionBatch": ["ownerId": "u"]]]]
        let snapshot = try KairosAIWorkspace.read(source, legacy: [], owner: "u")
        XCTAssertEqual(snapshot.chats[0].summary, "Manual")
        XCTAssertTrue(snapshot.chats[0].hasUnfinishedWebActions)
        XCTAssertThrowsError(try KairosAIWorkspace.applying(.append(chatID: "c", messages: [.init(id: "m", role: "user", content: "Next")]), to: source, legacy: [], owner: "u"))
    }

    func testProjectDeletionKeepsConversations() throws {
        let source: [String: Any] = ["version": 2, "projects": [["id": "p", "title": "School"]], "chats": [["id": "c", "projectId": "p", "messages": []]]]
        let result = try KairosAIWorkspace.applying(.deleteProject(id: "p"), to: source, legacy: [], owner: "u")
        let value = try KairosAIWorkspace.read(result, legacy: [], owner: "u")
        XCTAssertTrue(value.projects.isEmpty)
        XCTAssertEqual(value.chats.count, 1)
        XCTAssertEqual(value.chats[0].projectID, "")
    }

    func testBlankChatReusedAndLimitsDoNotDeleteExistingHistory() throws {
        let source: [String: Any] = ["version": 2, "projects": [], "chats": [["id": "blank", "messages": []]]]
        let result = try KairosAIWorkspace.applying(.createChat(id: "new", projectID: ""), to: source, legacy: [], owner: "u")
        XCTAssertEqual(try KairosAIWorkspace.read(result, legacy: [], owner: "u").chats.map(\.id), ["blank"])
        let full: [String: Any] = ["version": 2, "projects": [], "chats": (0..<12).map { ["id": "c\($0)", "messages": [["role": "user", "content": "Keep"]]] }]
        XCTAssertThrowsError(try KairosAIWorkspace.applying(.createChat(id: "extra", projectID: ""), to: full, legacy: [], owner: "u"))
    }
}
