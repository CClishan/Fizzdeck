import XCTest
@testable import FizzDeck

final class PartCPolishTests: XCTestCase {
    func testCommitHeatmapLayoutFitsNarrowAndWideWidths() {
        for range in HeatmapRange.allCases {
            let cols = range == .weeks26 ? 26 : 53
            for width in [CGFloat(220), CGFloat(300), CGFloat(360), CGFloat(520)] {
                let metrics = CommitHeatmapLayout.metrics(
                    availableWidth: width,
                    columnCount: cols,
                    range: range
                )
                let totalWidth = CGFloat(cols) * metrics.dotSize
                    + CGFloat(max(0, cols - 1)) * metrics.spacing
                XCTAssertGreaterThanOrEqual(metrics.dotSize, 3.0)
                XCTAssertGreaterThanOrEqual(metrics.spacing, 1.0)
                XCTAssertLessThanOrEqual(
                    totalWidth,
                    width + 0.5,
                    "Heatmap overflowed width=\(width) range=\(range.rawValue)"
                )
            }
        }
    }

    @MainActor
    func testToastCenterReplacesAndDismissesCleanly() {
        let center = ToastCenter()
        XCTAssertNil(center.current)

        center.show("已复制命令", duration: 0)
        XCTAssertEqual(center.current?.title, "已复制命令")

        center.show("备注已保存", duration: 0)
        XCTAssertEqual(center.current?.title, "备注已保存")

        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testFizzMotionHonorsReduceMotion() {
        XCTAssertNil(FizzMotion.resolved(true, FizzMotion.spring))
        XCTAssertNotNil(FizzMotion.resolved(false, FizzMotion.spring))
        XCTAssertNil(FizzMotion.resolved(true, FizzMotion.morph))
        XCTAssertNotNil(FizzMotion.resolved(false, FizzMotion.morph))
    }
}
