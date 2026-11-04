import XCTest
@testable import KairosCore

final class PlannerTimestampTests: XCTestCase {
    func testMissingNanosecondsMeansWholeSeconds() throws {
        let date = try XCTUnwrap(KairosPlannerTimestamp.date(from: ["seconds": 1_793_836_800]))
        XCTAssertEqual(date.timeIntervalSince1970, 1_793_836_800)
    }
    func testFractionalAndUnderscoredComponents() throws {
        let date = try XCTUnwrap(KairosPlannerTimestamp.date(from: ["seconds": 100, "nanoseconds": 500_000_000]))
        XCTAssertEqual(date.timeIntervalSince1970, 100.5, accuracy: 0.000001)
        XCTAssertEqual(KairosPlannerTimestamp.date(from: ["_seconds": 100, "_nanoseconds": 500_000_000]), date)
    }
    func testNativeDatesAndISOExports() throws {
        let expected = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(KairosPlannerTimestamp.date(from: expected), expected)
        XCTAssertEqual(KairosPlannerTimestamp.date(from: "1970-01-01T00:00:00Z"), expected)
        XCTAssertEqual(try XCTUnwrap(KairosPlannerTimestamp.date(from: "1970-01-01T00:00:00.500Z")).timeIntervalSince1970, 0.5, accuracy: 0.000001)
    }
    func testMalformedMetadataDoesNotProduceDates() {
        let values: [Any] = [
            ["seconds": true], ["seconds": "100"], ["seconds": 0, "nanoseconds": -1],
            ["seconds": 0, "nanoseconds": 1_000_000_000], ["seconds": 0, "nanoseconds": false],
            ["seconds": 1.5], ["seconds": 253_402_300_800], ["nanoseconds": 0], "invalid", NSNull()
        ]
        for value in values {
            XCTAssertNil(KairosPlannerTimestamp.date(from: value))
        }
        XCTAssertNil(KairosPlannerTimestamp.date(from: nil))
    }
    func testCreationOrderUsesLegacyTimestampComponents() throws {
        let values: [[String: Any]] = [["seconds": 200], ["seconds": 100, "nanoseconds": 1]]
        let newest = values.max {
            (KairosPlannerTimestamp.date(from: $0) ?? .distantPast) <
            (KairosPlannerTimestamp.date(from: $1) ?? .distantPast)
        }
        XCTAssertEqual(try XCTUnwrap(newest?["seconds"] as? Int), 200)
    }
}
