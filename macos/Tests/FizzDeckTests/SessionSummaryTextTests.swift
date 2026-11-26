import XCTest
@testable import FizzDeck

final class SessionSummaryTextTests: XCTestCase {
    func testStripsCodexFilePreambleAndKeepsRequest() {
        let value = """
        # Files mentioned by the user:

        ## /tmp/FizzDeck/App.swift:
        struct App {}

        ## My request for Codex:
        修复首屏滚动问题
        """

        XCTAssertEqual(SessionSummaryText.clean(value), "修复首屏滚动问题")
    }

    func testStripsIDETagsAndSystemReminder() {
        let value = """
        <ide_opened_file>/tmp/App.swift</ide_opened_file>
        <system-reminder>hidden context</system-reminder>
        保留这段需求
        <ide_selection>selected code</ide_selection>
        """

        XCTAssertEqual(SessionSummaryText.clean(value), "保留这段需求")
    }

    func testDropsFilePreambleWithoutActualRequest() {
        let value = """
        # Files mentioned by the user:

        ## /tmp/App.swift:
        struct App {}
        """

        XCTAssertEqual(SessionSummaryText.clean(value), "")
    }

    func testKeepsPlainSummaryUnchangedAndCapsLength() {
        XCTAssertEqual(SessionSummaryText.clean("  继续优化设置页  "), "继续优化设置页")
        XCTAssertEqual(SessionSummaryText.clean(String(repeating: "a", count: 500)).count, 400)
    }
}
