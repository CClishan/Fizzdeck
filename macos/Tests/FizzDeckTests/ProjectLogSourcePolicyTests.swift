import XCTest
@testable import FizzDeck

final class ProjectLogSourcePolicyTests: XCTestCase {
    private func context(
        path: String = "/tmp/project-a",
        startedAt: Date? = nil,
        dev: Bool = true,
        test: Bool = false,
        active: Bool = false
    ) -> ProjectLogContext {
        ProjectLogContext(
            projectPath: path,
            testStartedAt: startedAt,
            devAvailable: dev,
            testAvailable: test,
            testActive: active
        )
    }

    func testSwitchingProjectDoesNotReusePreviousTestRunSignal() {
        let previous = context(path: "/tmp/project-a", startedAt: Date(), dev: true, test: true, active: true)
        let current = context(path: "/tmp/project-b", startedAt: Date(), dev: true, test: true)

        XCTAssertEqual(
            ProjectLogSourcePolicy.resolve(current: current, previous: previous, selected: .test),
            .dev
        )
    }

    func testNewTestRunInSameProjectSelectsTestLogs() {
        let previous = context(startedAt: nil, dev: true, test: true)
        let current = context(startedAt: Date(), dev: true, test: true, active: true)

        XCTAssertEqual(
            ProjectLogSourcePolicy.resolve(current: current, previous: previous, selected: .dev),
            .test
        )
    }

    func testExistingTestRunInSameProjectKeepsSelectedSource() {
        let startedAt = Date()
        let previous = context(startedAt: startedAt, dev: true, test: true)
        let current = context(startedAt: startedAt, dev: true, test: true)

        XCTAssertEqual(
            ProjectLogSourcePolicy.resolve(current: current, previous: previous, selected: .dev),
            .dev
        )
    }

    func testProjectSwitchPrefersRunningTestThenAvailableLogs() {
        XCTAssertEqual(
            ProjectLogSourcePolicy.initialSource(
                for: context(dev: true, test: true, active: true)
            ),
            .test
        )
        XCTAssertEqual(
            ProjectLogSourcePolicy.initialSource(
                for: context(dev: false, test: true)
            ),
            .test
        )
        XCTAssertEqual(
            ProjectLogSourcePolicy.initialSource(
                for: context(dev: true, test: false)
            ),
            .dev
        )
    }

    func testInitialAppearanceUsesAvailableSource() {
        XCTAssertEqual(
            ProjectLogSourcePolicy.resolve(
                current: context(dev: false, test: true),
                previous: nil,
                selected: .dev
            ),
            .test
        )
    }

    func testUnavailableSelectedSourceFallsBack() {
        XCTAssertEqual(
            ProjectLogSourcePolicy.normalized(.test, for: context(dev: true, test: false)),
            .dev
        )
        XCTAssertEqual(
            ProjectLogSourcePolicy.normalized(.dev, for: context(dev: false, test: true)),
            .test
        )
    }
}
