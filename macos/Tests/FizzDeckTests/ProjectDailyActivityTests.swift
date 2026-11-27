import Foundation
import XCTest
@testable import FizzDeck

final class ProjectDailyActivityTests: XCTestCase {
    func testLocalDayWindowsAcrossDSTKeepUnknownZeroPartialAndEmptySeparate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-15T12:00:00Z"))
        let today = calendar.startOfDay(for: now)
        func session(_ offset: Int, _ price: Double? = nil) -> SessionRecord {
            SessionRecord(tool: "fixture", id: UUID().uuidString, cwd: nil, startedAt: nil,
                          modified: calendar.date(byAdding: .day, value: offset, to: today)!, costUSD: price)
        }
        var metered = session(-7)
        metered.model = "gpt-5-mini"
        metered.usage = TokenUsage(inputTokens: 1_000_000, totalTokens: 1_000_000)
        var summary = session(-1, 99); summary.kind = .workspaceSummary
        let future = SessionRecord(tool: "fixture", id: "future", cwd: nil, startedAt: nil, modified: now.addingTimeInterval(1), costUSD: 80)
        let sessions = [session(-30, 9), session(-29, 7), session(-14, 2), session(-13, 0), metered, session(-7), session(-1), summary, future]
        let counts = ["2026-02-14": 4, "2026-03-08": 2]
        let month = ProjectActivityDay.series(sessions: sessions, commits: counts, days: 30, now: now, calendar: calendar)
        let fortnight = ProjectActivityDay.series(sessions: sessions, commits: counts, days: 14, now: now, calendar: calendar)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(fortnight.count, 14)
        XCTAssertEqual(fortnight, Array(month.suffix(14)))
        XCTAssertEqual(month.first?.commits, 4)
        XCTAssertEqual(month.first?.cost.amount, 7)
        XCTAssertEqual(fortnight.first?.cost.description, "$0")
        XCTAssertEqual(fortnight[6].commits, 2)
        XCTAssertEqual(fortnight[6].cost.amount, 0.25)
        XCTAssertEqual(fortnight[6].cost.unpriced, 1)
        XCTAssertEqual(fortnight[12].cost.description, "未计价")
        XCTAssertEqual(fortnight[13].cost.description, "无会话")
        XCTAssertEqual(fortnight[13].commits, 0)
        XCTAssertNil(ProjectActivityDay.series(sessions: [], commits: nil, days: 14).last?.commits)
    }

    func testGitCountsIncludeAllAuthorsAndUseLocalMidnight() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let initialized = await Shell.run("git", ["init", "-q"], cwd: dir)
        XCTAssertTrue(initialized?.succeeded == true)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-27T09:00:00Z"))
        for (i, stamp) in ["2026-10-28T15:59:59Z", "2026-10-28T16:00:00Z", "2026-11-26T16:01:00Z", "2026-11-27T08:59:00Z"].enumerated() {
            let result = await Shell.run("git", ["-c", "user.name=Author \(i)", "-c", "user.email=a\(i)@example.com", "-c", "commit.gpgSign=false", "commit", "--allow-empty", "-qm", "fixture"],
                                         cwd: dir, extraEnvironment: ["GIT_COMMITTER_DATE": stamp, "GIT_AUTHOR_DATE": stamp])
            XCTAssertTrue(result?.succeeded == true, result?.text ?? "")
        }
        let counts = await GitService.dailyCommitCounts(dir, days: 30, now: now, calendar: cal)
        XCTAssertEqual(counts, ["2026-10-29": 1, "2026-11-27": 2])
    }
}
