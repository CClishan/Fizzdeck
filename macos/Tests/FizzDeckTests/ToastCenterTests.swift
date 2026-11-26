import XCTest
@testable import FizzDeck

@MainActor
final class ToastCenterTests: XCTestCase {
    func testQueueKeepsNewestFirstAndCapsAtTwenty() {
        let center = ToastCenter()

        for index in 1...25 {
            center.show("提示 \(index)", duration: nil)
        }

        XCTAssertEqual(center.messages.count, 20)
        XCTAssertEqual(center.current?.title, "提示 25")
        XCTAssertEqual(center.messages[1].title, "提示 24")
        XCTAssertEqual(center.messages.last?.title, "提示 6")
    }

    func testUpdateMutatesInPlaceWithoutReordering() {
        let center = ToastCenter()
        let first = center.show("下载中", duration: nil)
        center.show("第二条", duration: nil)

        let updated = center.update(first) { message in
            message.title = "校验中"
            message.subtitle = "SHA-256"
            message.microViz = .pipeline(step: 1, state: .running)
            message.duration = nil
        }

        XCTAssertTrue(updated)
        XCTAssertEqual(center.messages.count, 2)
        XCTAssertEqual(center.messages[1].id, first)
        XCTAssertEqual(center.messages[1].title, "校验中")
        XCTAssertEqual(center.messages[1].subtitle, "SHA-256")
        XCTAssertEqual(center.messages[1].microViz, .pipeline(step: 1, state: .running))
    }

    func testActionToastStaysUntilExplicitlyDismissed() async {
        let center = ToastCenter()
        let id = center.show(
            "端口被占用",
            duration: 0.05,
            microViz: .pipeline(step: 0, state: .failed),
            action: ToastAction(title: "释放并重试", symbol: "arrow.clockwise") {}
        )

        try? await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(center.current?.id, id)
        XCTAssertNil(center.current?.duration)

        center.dismiss(id: id)
        XCTAssertNil(center.current)
    }

    func testAutoDismissAndCancellationRemoveOnlyTarget() async {
        let center = ToastCenter()
        let first = center.show("自动收起", duration: 0.12)
        let second = center.show("保持", duration: nil)

        try? await Task.sleep(for: .milliseconds(260))

        XCTAssertNil(center.messages.first(where: { $0.id == first }))
        XCTAssertEqual(center.messages.map(\.id), [second])

        center.dismiss(id: second)
        XCTAssertTrue(center.messages.isEmpty)
    }

    func testMicroVizCellMappingsClampAndFillInOrder() {
        let tests = ToastMicroViz.testCells(passed: 5, failed: 2)
        XCTAssertEqual(tests.count, 52)
        XCTAssertEqual(Array(tests.prefix(5)), Array(repeating: .positive, count: 5))
        XCTAssertEqual(Array(tests.dropFirst(5).prefix(2)), Array(repeating: .negative, count: 2))
        XCTAssertTrue(tests.dropFirst(7).allSatisfy { $0 == .empty })

        let clamped = ToastMicroViz.testCells(passed: 60, failed: -3)
        XCTAssertEqual(clamped.filter { $0 == .positive }.count, 52)
        XCTAssertFalse(clamped.contains(.negative))

        let diff = ToastMicroViz.diffCells(added: 6, removed: 2)
        XCTAssertEqual(diff.count, 40)
        XCTAssertEqual(diff.filter { $0 == .positive }.count, 6)
        XCTAssertEqual(diff.filter { $0 == .negative }.count, 2)
        XCTAssertEqual(diff.filter { $0 == .empty }.count, 32)
    }

    func testNormalizedBarsUsesPeakAndPadsToEight() {
        let bars = ToastMicroViz.normalizedBars([4, 8, 2])
        XCTAssertEqual(bars.count, 8)
        XCTAssertEqual(bars[0], 0.5)
        XCTAssertEqual(bars[1], 1)
        XCTAssertEqual(bars[2], 0.25)
        XCTAssertEqual(bars[3], 0.08)

        let empty = ToastMicroViz.normalizedBars([])
        XCTAssertEqual(empty, Array(repeating: 0.08, count: 8))
    }

    func testTestOutcomeSummaryParsesCommonFormatsAndFallsBack() {
        XCTAssertEqual(
            TestOutcomeSummary.parse(
                "Tests run: 206, Failures: 0",
                status: .passed
            ),
            TestOutcomeSummary(passed: 206, failed: 0)
        )
        XCTAssertEqual(
            TestOutcomeSummary.parse(
                "Tests  12 passed (12)\nTests  2 failed (2)",
                status: .failed
            ),
            TestOutcomeSummary(passed: 12, failed: 2)
        )
        XCTAssertEqual(
            TestOutcomeSummary.parse("no test counts here", status: .passed),
            TestOutcomeSummary(passed: 1, failed: 0)
        )
    }

    func testStageHeightScalesWithVisibleToastCount() {
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 0, expanded: false), 0)
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 0, expanded: true), 0)
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 1, expanded: false), 64)
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 1, expanded: true), 64)
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 2, expanded: false), 74)
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 2, expanded: true), 138)
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 3, expanded: false), 84)
        XCTAssertEqual(ToastOverlayView.stageHeight(visibleCount: 3, expanded: true), 212)
    }
}
