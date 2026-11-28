import XCTest
@testable import FizzDeck

final class ProjectGroupingTests: XCTestCase {
    func testDetectsGroupsFromProjectKind() {
        XCTAssertEqual(ProjectGrouping.detected(for: "/tmp/nonexistent-web", kind: .web), "网页")
        XCTAssertEqual(ProjectGrouping.detected(for: "/tmp/nonexistent-mac", kind: .macApp), "Mac 应用")
        XCTAssertEqual(ProjectGrouping.detected(for: "/tmp/nonexistent-mini", kind: .miniProgram), "小程序")
        XCTAssertEqual(ProjectGrouping.detected(for: "/tmp/nonexistent-flutter", kind: .flutter), "Flutter")
        XCTAssertEqual(ProjectGrouping.detected(for: "/tmp/nonexistent-game", kind: .game), "游戏")
        XCTAssertEqual(ProjectGrouping.detected(for: "/tmp/nonexistent-cli", kind: .cli), "命令行脚本")
        XCTAssertEqual(ProjectGrouping.detected(for: "/tmp/nonexistent-other"), "其他")
    }

    func testOrdersDefaultKindGroupsBeforeCustomGroups() {
        let ordered = ProjectGrouping.ordered([
            "自定义 B", "其他", "网页", "自定义 A", "Mac 应用",
        ])

        XCTAssertEqual(ordered, ["网页", "Mac 应用", "其他", "自定义 A", "自定义 B"])
    }

    func testBothDetectedAndCustomGroupsUseTheProjectPalette() {
        for group in ["网页", "客户项目"] {
            XCTAssertEqual(ProjectGrouping.color(for: group), ProjectAccentColor.color(for: group))
        }
    }
}
