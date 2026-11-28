import XCTest
@testable import FizzDeck

final class FizzCopyTests: ChineseInterfaceTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "fizzdeck.tests.copy.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCopyModeDefaultsToPlainAndRoundTrips() {
        XCTAssertEqual(CopyModePreferences.mode(in: defaults), .plain)

        CopyModePreferences.set(.pro, in: defaults)
        XCTAssertEqual(CopyModePreferences.mode(in: defaults), .pro)

        defaults.set("invalid", forKey: CopyModePreferences.key)
        XCTAssertEqual(CopyModePreferences.mode(in: defaults), .plain)
    }

    func testTermMappingsProvideHintsOnlyInPlainMode() {
        let plainDirty = FizzCopy.uncommittedChanges(count: 4, mode: .plain)
        let proDirty = FizzCopy.uncommittedChanges(count: 4, mode: .pro)
        XCTAssertEqual(plainDirty.text, "有 4 个改动还没存成版本")
        XCTAssertNotNil(plainDirty.proHint)
        XCTAssertEqual(proDirty.text, "4 个文件未提交")
        XCTAssertNil(proDirty.proHint)

        XCTAssertEqual(FizzCopy.commitAction(.plain).text, "存个版本")
        XCTAssertEqual(FizzCopy.commitAction(.pro).text, "Commit")
        XCTAssertEqual(FizzCopy.tabTitle(.progress, mode: .plain), "进度")
        XCTAssertEqual(FizzCopy.tabTitle(.progress, mode: .pro), "概览")
        XCTAssertEqual(FizzCopy.tabTitle(.info, mode: .plain), "项目信息")
        XCTAssertEqual(FizzCopy.tabTitle(.info, mode: .pro), "项目信息")
        XCTAssertEqual(FizzCopy.focusSectionTitle(.plain), "关注")
        XCTAssertEqual(FizzCopy.focusSectionTitle(.pro), "星标")
    }

    func testGreetingAndDashboardStatusLine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func makeHour(_ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: hour, minute: 0))!
        }

        XCTAssertEqual(FizzCopy.greeting(for: makeHour(7), calendar: calendar), "早上好")
        XCTAssertEqual(FizzCopy.greeting(for: makeHour(10), calendar: calendar), "上午好")
        XCTAssertEqual(FizzCopy.greeting(for: makeHour(15), calendar: calendar), "下午好")
        XCTAssertEqual(FizzCopy.greeting(for: makeHour(21), calendar: calendar), "晚上好")

        XCTAssertEqual(
            FizzCopy.dashboardStatusLine(activeCount: 2, brokenCount: 1, attentionCount: 3, mode: .plain),
            "2 个项目在进行，1 个跑不起来"
        )
        XCTAssertEqual(
            FizzCopy.dashboardStatusLine(activeCount: 2, brokenCount: 0, attentionCount: 0, mode: .plain),
            "2 个项目在进行，状态都挺好"
        )
        XCTAssertEqual(
            FizzCopy.dashboardStatusLine(activeCount: 0, brokenCount: 0, attentionCount: 0, mode: .plain),
            "一切顺利，没有需要处理的项目"
        )
    }
}
