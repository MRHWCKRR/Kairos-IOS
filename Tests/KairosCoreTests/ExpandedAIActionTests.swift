import XCTest
@testable import KairosCore

final class ExpandedAIActionTests: XCTestCase {
    func testReminderArgumentsSurviveSavedPreviewRoundTrip() throws {
        let raw = #"{"reply":"Review the reminder","actions":[{"type":"set_task_reminder","args":{"taskId":"t","minutesBefore":15}}]}"#
        let response = try KairosChatResponse.parse(raw)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response.actions)) as? [[String: Any]]
        XCTAssertEqual((saved?.first?["args"] as? [String: Any])?["minutesBefore"] as? Int, 15)
    }
}
