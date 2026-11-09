import XCTest
@testable import KairosCore

final class IntegrationTestsTimerAppearance: XCTestCase {
    func testUnknownValuesFallBackToDigitalVioletGlow() {
        let appearance = KairosTimerAppearance(type: "hourglass", theme: "lava", border: "spikes")

        XCTAssertEqual(appearance.type, "digital")
        XCTAssertEqual(appearance.theme, "violet")
        XCTAssertEqual(appearance.border, "glow")
    }
}
