import XCTest
@testable import KairosCore

final class MobileScheduleParityTests: XCTestCase {
    func testScheduledTimesRoundTripIndependentlyOfDueTime() throws {
        let json = #"{"id":"t","title":"Essay","date":"2026-11-05","startTime":"14:00","endTime":"15:30","dueTime":"23:00","dueDate":"2026-11-07","completed":false,"archived":false}"#
        let task = try JSONDecoder().decode(KairosTask.self, from: Data(json.utf8))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        XCTAssertEqual(encoded["startTime"] as? String, "14:00")
        XCTAssertEqual(encoded["endTime"] as? String, "15:30")
        XCTAssertEqual(encoded["dueDate"] as? String, "2026-11-07")
        XCTAssertEqual(encoded["dueTime"] as? String, "23:00")
    }
}
