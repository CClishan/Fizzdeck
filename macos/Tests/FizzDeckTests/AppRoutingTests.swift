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

extension AppRoutingTests {
    func testExternalURLsRequireAnExactManagedProjectAndKnownAction() throws {
        let roots = ["/Users/test/茶 Room"]
        var url = URLComponents()
        url.scheme = "fizzdeck"; url.host = "open"
        url.queryItems = [.init(name: "path", value: roots[0]), .init(name: "tab", value: "run")]
        XCTAssertEqual(AppRouting.projectRequest(from: try XCTUnwrap(url.url), managedRoots: roots)?.tab, .run)
        url.host = "handoff"; url.queryItems?.removeLast()
        XCTAssertEqual(AppRouting.projectRequest(from: try XCTUnwrap(url.url), managedRoots: roots)?.showHandoff, true)
        for raw in ["fizzdeck://open?path=/tmp", "fizzdeck://open?path=/p&path=/p", "fizzdeck://open?path=/p&tab=push", "fizzdeck://open?path=/p&cmd=test", "https://open?path=/p", "fizzdeck://stop?path=/p", "fizzdeck://handoff?path=/p&tab=run", "fizzdeck://open:7?path=/p"] {
            XCTAssertNil(AppRouting.projectRequest(from: try XCTUnwrap(URL(string: raw)), managedRoots: ["/p"]), raw)
        }
    }
}
