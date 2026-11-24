import XCTest
@testable import FizzDeck

final class GitServiceTests: XCTestCase {
    func testTrackingCountsUseBehindThenAhead() {
        XCTAssertEqual(
            GitService.trackingCounts("3\t5\n"),
            GitTrackingCounts(behind: 3, ahead: 5)
        )
    }

    func testTrackingCountsHandleZero() {
        XCTAssertEqual(
            GitService.trackingCounts("0 0"),
            GitTrackingCounts(behind: 0, ahead: 0)
        )
    }

    func testTrackingCountsDefaultWhenUpstreamIsMissing() {
        XCTAssertEqual(GitService.trackingCounts(nil), GitTrackingCounts())
        XCTAssertEqual(GitService.trackingCounts(""), GitTrackingCounts())
    }

    func testTrackingCountsRejectMalformedOutput() {
        XCTAssertEqual(GitService.trackingCounts("4"), GitTrackingCounts())
        XCTAssertEqual(GitService.trackingCounts("4\tfive"), GitTrackingCounts())
        XCTAssertEqual(GitService.trackingCounts("1\t2\t3"), GitTrackingCounts())
    }

    func testSSHRemoteConvertsToBrowserURL() {
        let remote = GitRemote(raw: "git@github.com:CClishan/Fizzdeck.git")

        XCTAssertEqual(
            remote?.webURL?.absoluteString,
            "https://github.com/CClishan/Fizzdeck"
        )
    }
}
