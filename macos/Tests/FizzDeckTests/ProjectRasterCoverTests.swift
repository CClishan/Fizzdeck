import Foundation
import XCTest
@testable import FizzDeck

final class ProjectRasterCoverTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-03-11T19:00:00Z")!
    private let size = CGSize(width: 257, height: 48)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    func testRasterIsDeterministicAndActivityStaysInItsDay() throws {
        let commits = [("2026-03-07", 2), ("2026-03-11", 1)]
        let sessions = try [session("2026-03-07T18:00:00Z"), session("2026-03-11T18:00:00Z")]
        let original = pattern(weekly: Dictionary(uniqueKeysWithValues: commits), sessions: sessions)
        let reordered = pattern(
            weekly: Dictionary(uniqueKeysWithValues: commits.reversed()), sessions: Array(sessions.reversed())
        )
        let bars = original.bars(in: size)
        XCTAssertEqual(original.dailyActivity, [0, 0, 3, 0, 0, 0, 2])
        XCTAssertEqual(bars, reordered.bars(in: size))
        XCTAssertEqual(Set(bars.map(\.height)).count, 3)

        for (bar, quiet) in zip(bars, pattern().bars(in: size)) {
            let day = Int(bar.midX / (size.width / 7))
            if day == 2 || day == 6 {
                XCTAssertGreaterThan(bar.height, quiet.height)
            } else {
                XCTAssertEqual(bar, quiet)
            }
        }
    }

    func testLocalSevenDayWindowIncludesStartAndNowAcrossDST() throws {
        let sessions = try [
            session("2026-03-05T07:59:59Z"), session("2026-03-05T08:00:00Z"), // first local midnight
            session("2026-03-08T09:59:59Z"), session("2026-03-08T10:00:00Z"), // spring forward
            session("2026-03-11T06:59:59Z"), session("2026-03-11T07:00:00Z"), // today's local midnight
            session("2026-03-11T19:00:00Z"), session("2026-03-11T19:00:01Z"),
            session("2026-03-11T19:00:00Z", kind: .workspaceSummary),
        ]
        let commits = ["2026-03-04": 99, "2026-03-05": 2, "2026-03-11": 1, "2026-03-12": 99]
        XCTAssertEqual(pattern(weekly: commits, sessions: sessions).dailyActivity, [3, 0, 0, 2, 0, 1, 3])
    }

    func testEmptyStaleAndUndatedActivityShareAnEvenLowBaseline() throws {
        let bars = pattern().bars(in: size)
        let stale = try pattern(
            weekly: ["other": 100, "2025-03-11": 100, "2026-03-10": -1],
            sessions: [session("2025-03-11T18:00:00Z")]
        )
        XCTAssertEqual(stale.dailyActivity, Array(repeating: 0, count: 7))
        XCTAssertEqual(stale.bars(in: size), bars)
        let first = try XCTUnwrap(bars.first)
        XCTAssertGreaterThan(bars.count, 1)
        XCTAssertGreaterThan(first.height, 0)
        XCTAssertLessThanOrEqual(first.height, 3)
        let pitch = size.width / CGFloat(bars.count)
        for (index, bar) in bars.enumerated() {
            XCTAssertEqual(bar.size, first.size)
            XCTAssertEqual(bar.midY, first.midY)
            XCTAssertEqual(bar.midX, (CGFloat(index) + 0.5) * pitch, accuracy: 0.000_001)
        }
    }

    private func pattern(weekly: [String: Int] = [:], sessions: [SessionRecord] = []) -> ProjectRasterPattern {
        ProjectRasterPattern(weekly: weekly, sessions: sessions, now: now, calendar: calendar)
    }

    private func session(_ stamp: String, kind: SessionRecordKind = .conversation) throws -> SessionRecord {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: stamp))
        return SessionRecord(tool: "codex", id: stamp, cwd: nil, startedAt: nil, modified: date, kind: kind)
    }
}
