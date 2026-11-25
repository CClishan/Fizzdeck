import XCTest
@testable import FizzDeck

final class AppUpdateTests: XCTestCase {
    func testNewerVersionComparison() {
        XCTAssertTrue(AppUpdateService.isNewer("v0.2.3", than: "0.2.2"))
        XCTAssertFalse(AppUpdateService.isNewer("v0.2.2", than: "0.2.2"))
    }

    func testVersionComparisonHandlesDifferentComponentCounts() {
        XCTAssertTrue(AppUpdateService.isNewer("0.3", than: "0.2.9"))
        XCTAssertFalse(AppUpdateService.isNewer("0.2", than: "0.2.0"))
    }
}
