import Foundation
import XCTest
@testable import FizzDeck

final class CommitActivityServiceTests: XCTestCase {
    func testParseAndFilterLogMatchesOnlyUserEmailsCaseInsensitively() {
        let log = [
            "1700000300\u{1f}Alice@Example.COM\u{1f}Alice",
            "1700000100\u{1f}bob@other.com\u{1f}Bob",
            "1700000500\u{1f}alice@work.org\u{1f}Alice Work",
            "bad-line",
        ].joined(separator: "\n")

        let timestamps = CommitActivityService.parseAndFilterLog(
            log,
            matchingEmails: ["alice@example.com", "alice@work.org"],
            fallbackNames: ["Bob"]
        )

        XCTAssertEqual(timestamps, [1_700_000_500, 1_700_000_300])
    }

    func testParseAndFilterLogFallsBackToNameWhenNoEmailsConfigured() {
        let log = [
            "1700000100\u{1f}\u{1f}Lishan",
            "1700000200\u{1f}other@x.com\u{1f}Someone Else",
        ].joined(separator: "\n")

        let timestamps = CommitActivityService.parseAndFilterLog(
            log,
            matchingEmails: [],
            fallbackNames: ["lishan"]
        )

        XCTAssertEqual(timestamps, [1_700_000_100])
        XCTAssertEqual(
            CommitActivityService.parseAndFilterLog(log, matchingEmails: [], fallbackNames: []),
            []
        )
    }

    func testCacheRoundTripsInTemporaryDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-commit-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("commit-activity.json")

        let snapshot = CommitActivitySnapshot(byProject: [
            "/tmp/repo": RepoCommitActivity(
                path: "/tmp/repo",
                head: "abc123",
                authorEmails: ["me@example.com"],
                windowDays: 371,
                timestamps: [1_700_000_500, 1_700_000_100],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_600)
            ),
        ])

        CommitActivityService.saveCache(snapshot, to: file)
        let loaded = CommitActivityService.loadCache(from: file)
        XCTAssertEqual(loaded, snapshot)
    }
}
