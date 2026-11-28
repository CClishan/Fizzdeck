import XCTest
@testable import FizzDeck

final class FormattingTests: XCTestCase {
    func testChineseRelativeTimeSeparatesTheNumberFromItsUnit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let zh = Locale(identifier: "zh_CN")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-960), now: now, locale: zh), "16 分钟前")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(7200), now: now, locale: zh), "2 小时后")
        XCTAssertEqual(Format.relative(now, now: now, locale: zh), "刚刚")
        XCTAssertEqual(Format.relative(nil, now: now, locale: zh), "—")
    }

    func testTokenAndChartCountsUseTheSameLocalizedSpacing() {
        let zh = Locale(identifier: "zh_CN")
        XCTAssertEqual("\(Format.tokens(250_000, locale: zh)) tokens", "25 万 tokens")
        XCTAssertEqual(Format.compactCount(250_000, locale: zh), "25 万")
        XCTAssertEqual(Format.tokens(250_000, locale: Locale(identifier: "en_US")), "250K")
    }

    func testBytesUnderOneThousandUseCompactUnit() {
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(82), "82 B")
        XCTAssertEqual(Format.bytes(999), "999 B")
    }

    func testBytesMatchesWorkbenchSplitUnderOneThousand() {
        for value in [Int64(0), 1, 82, 999] {
            let parts = WorkbenchMetrics.splitBytes(value)
            XCTAssertEqual(Format.bytes(value), "\(parts.value) \(parts.unit)")
        }
    }
}
