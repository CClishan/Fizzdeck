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
        XCTAssertEqual(request?.tab, .run)

        XCTAssertEqual(
            AppRouting.projectRequest(from: ["projectPath": "/tmp/p", "tab": "git"])?.tab,
            .version
        )
        XCTAssertEqual(
            AppRouting.projectRequest(from: ["projectPath": "/tmp/p", "tab": "overview"])?.tab,
            .progress
        )
        XCTAssertEqual(
            AppRouting.projectRequest(from: ["projectPath": "/tmp/p", "tab": "sessions"])?.tab,
            .progress
        )
        XCTAssertEqual(
            AppRouting.projectRequest(from: ["projectPath": "/tmp/p", "tab": "progress"])?.tab,
            .progress
        )
        XCTAssertEqual(
            AppRouting.projectRequest(from: ["projectPath": "/tmp/p", "tab": "info"])?.tab,
            .info
        )
        XCTAssertEqual(
            AppRouting.projectRequest(from: ["projectPath": "/tmp/p", "tab": "docs"])?.tab,
            .info
        )
    }

    @MainActor
    func testNotificationRouteRequiresProjectPath() {
        XCTAssertNil(AppRouting.projectRequest(from: ["tab": "overview"]))
        XCTAssertNil(AppRouting.projectRequest(from: ["projectPath": ""]))
    }
}
