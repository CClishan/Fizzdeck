import XCTest
@testable import FizzDeck

final class ProjectGroupingTests: XCTestCase {
    func testDetectsKnownGroups() {
        XCTAssertEqual(ProjectGrouping.detected(for: "/Users/me/zoopfizz"), "产品站")
        XCTAssertEqual(ProjectGrouping.detected(for: "/Users/me/dsh-workspace"), "工作区")
        XCTAssertEqual(ProjectGrouping.detected(for: "/Users/me/converter-tools"), "工具库")
        XCTAssertEqual(ProjectGrouping.detected(for: "/Users/me/noplan_officesite"), "官网")
        XCTAssertEqual(ProjectGrouping.detected(for: "/Users/me/tsys-web"), "上屏管家")
        XCTAssertEqual(ProjectGrouping.detected(for: "/Users/me/random-repo"), "其他")
    }

    func testOrdersDefaultGroupsBeforeCustomGroups() {
        let ordered = ProjectGrouping.ordered([
            "自定义 B", "其他", "产品站", "自定义 A", "工作区",
        ])

        XCTAssertEqual(ordered, ["产品站", "工作区", "其他", "自定义 A", "自定义 B"])
    }

    func testCustomGroupColorIsStable() {
        let first = ProjectGrouping.paletteIndex(for: "客户项目")
        let second = ProjectGrouping.paletteIndex(for: "客户项目")

        XCTAssertEqual(first, second)
        XCTAssertTrue((0..<8).contains(first))
    }
}
