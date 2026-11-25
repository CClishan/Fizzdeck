import XCTest
@testable import FizzDeck

final class AppRoutingTests: XCTestCase {
    @MainActor
    func testNotificationRouteDecodesProjectAndTab() {
        let request = AppRouting.projectRequest(from: [
            "projectPath": "/tmp/project",
            "tab": "tests",
        ])

        XCTAssertEqual(request?.path, "/tmp/project")
        XCTAssertEqual(request?.tab, .tests)
    }

    @MainActor
    func testNotificationRouteRequiresProjectPath() {
        XCTAssertNil(AppRouting.projectRequest(from: ["tab": "overview"]))
        XCTAssertNil(AppRouting.projectRequest(from: ["projectPath": ""]))
    }
}
