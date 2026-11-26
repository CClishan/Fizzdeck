import XCTest
@testable import FizzDeck

final class FormattingTests: XCTestCase {
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
