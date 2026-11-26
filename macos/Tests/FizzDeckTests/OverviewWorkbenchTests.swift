import Foundation
import XCTest
@testable import FizzDeck

final class OverviewWorkbenchTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func makeFile(_ data: Data) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-log-\(UUID().uuidString)")
        try data.write(to: url)
        return url.path
    }

    func testLastSevenDaysAlignsKeysAndFillsZeros() {
        let now = date("2026-11-26 12:00")
        let days = WorkbenchMetrics.lastSevenDays(
            counts: ["2026-11-20": 2, "2026-11-26": 3],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(days.map(\.key), [
            "2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23",
            "2026-11-24", "2026-11-25", "2026-11-26",
        ])
        XCTAssertEqual(days.map(\.count), [2, 0, 0, 0, 0, 0, 3])
    }

    func testSessionDayCountsAggregateWithinSevenDayWindow() {
        let now = date("2026-11-26 12:00")
        let sessions = [
            SessionRecord(tool: "codex", id: "a", cwd: nil, startedAt: nil, modified: now),
            SessionRecord(tool: "codex", id: "b", cwd: nil, startedAt: nil, modified: now),
            SessionRecord(tool: "claude", id: "c", cwd: nil, startedAt: nil, modified: date("2026-11-25 09:00")),
            SessionRecord(tool: "grok", id: "d", cwd: nil, startedAt: nil, modified: date("2026-11-20 09:00")),
            SessionRecord(tool: "gemini", id: "e", cwd: nil, startedAt: nil, modified: date("2026-11-19 09:00")),
        ]

        let counts = WorkbenchMetrics.sessionDayCounts(sessions, now: now, calendar: calendar)

        XCTAssertEqual(counts, [1, 0, 0, 0, 0, 1, 2])
    }

    func testNormalizedBarsHandleAllZeroAndSinglePeak() {
        XCTAssertEqual(WorkbenchMetrics.normalized([0, 0, 0, 0, 0, 0, 0]), Array(repeating: 0, count: 7))
        XCTAssertEqual(WorkbenchMetrics.normalized([0, 0, 5, 0]), [0, 0, 1, 0])
        XCTAssertEqual(WorkbenchMetrics.normalized([1, 2, 4]), [0.25, 0.5, 1])
    }

    func testEmphasisPrefersLatestPeakAndIgnoresZero() {
        XCTAssertEqual(WorkbenchMetrics.emphasisIndex([0, 0, 5, 0, 5]), 4)
        XCTAssertEqual(WorkbenchMetrics.emphasisIndex([3, 0, 0]), 0)
        XCTAssertNil(WorkbenchMetrics.emphasisIndex([0, 0, 0]))
    }

    func testCleanupBarsNormalizeAndPadToSeven() {
        let items = [
            CleanupItem(label: "a", path: "/tmp/a", bytes: 100, reason: "", regen: "", kind: ""),
            CleanupItem(label: "b", path: "/tmp/b", bytes: 400, reason: "", regen: "", kind: ""),
            CleanupItem(label: "c", path: "/tmp/c", bytes: 200, reason: "", regen: "", kind: ""),
        ]
        let bars = WorkbenchMetrics.cleanupBars(items)

        XCTAssertEqual(bars.count, 7)
        XCTAssertEqual(bars[0], 100)
        XCTAssertEqual(bars[1], 400)
        XCTAssertEqual(bars[2], 200)
        XCTAssertEqual(Array(bars[3...]), [0, 0, 0, 0])
        XCTAssertEqual(WorkbenchMetrics.normalized(bars), [0.25, 1, 0.5, 0, 0, 0, 0])
    }

    func testSplitBytesKeepsValueAndUnitSeparate() {
        XCTAssertEqual(WorkbenchMetrics.splitBytes(0), ByteParts(value: "0", unit: "B"))
        XCTAssertEqual(WorkbenchMetrics.splitBytes(999), ByteParts(value: "999", unit: "B"))
        XCTAssertEqual(WorkbenchMetrics.splitBytes(1_500), ByteParts(value: "1.5", unit: "KB"))
        XCTAssertEqual(WorkbenchMetrics.splitBytes(3_400_000), ByteParts(value: "3.4", unit: "MB"))
        XCTAssertEqual(WorkbenchMetrics.splitBytes(12_000_000_000), ByteParts(value: "12", unit: "GB"))
    }

    func testSplitBytesCarriesRoundedValuesIntoNextUnit() {
        XCTAssertEqual(WorkbenchMetrics.splitBytes(999_940), ByteParts(value: "999.9", unit: "KB"))
        XCTAssertEqual(WorkbenchMetrics.splitBytes(999_960), ByteParts(value: "1", unit: "MB"))
        XCTAssertEqual(WorkbenchMetrics.splitBytes(1_999_960), ByteParts(value: "2", unit: "MB"))
        XCTAssertEqual(WorkbenchMetrics.splitBytes(999_999_999), ByteParts(value: "1", unit: "GB"))
    }

    func testLogTailMissingAndEmptyFile() throws {
        XCTAssertEqual(LogTailReader.read(path: "/tmp/fizzdeck-missing-\(UUID().uuidString).log"), "")

        let path = try makeFile(Data())
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(LogTailReader.read(path: path), "")
    }

    func testLogTailKeepsLastFortyLines() throws {
        let lines = (1...60).map { "line-\($0)" }
        let path = try makeFile(Data(lines.joined(separator: "\n").utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tail = LogTailReader.read(path: path)
        let output = tail.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(output.count, 40)
        XCTAssertEqual(output.first, "line-21")
        XCTAssertEqual(output.last, "line-60")
    }

    func testLogTailReadsOnlyFileEndAndTruncates() throws {
        let lines = (1...1_000).map { "line-\($0)-\(String(repeating: "x", count: 20))" }
        let path = try makeFile(Data(lines.joined(separator: "\n").utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tail = LogTailReader.read(path: path)

        XCTAssertLessThanOrEqual(tail.utf8.count, LogTailReader.defaultMaxBytes)
        XCTAssertTrue(tail.hasSuffix(lines.last!))
        XCTAssertLessThanOrEqual(
            tail.split(separator: "\n", omittingEmptySubsequences: false).count,
            LogTailReader.defaultMaxLines
        )
    }

    func testLogTailHandlesTruncatedUTF8Boundary() throws {
        let data = Data(String(repeating: "a", count: 20_000).utf8) + Data("中b".utf8)
        let path = try makeFile(data)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(LogTailReader.read(path: path, maxBytes: 3), "b")
        XCTAssertEqual(LogTailReader.read(path: path, maxBytes: 5), "a中b")
    }

    func testOverviewLayoutPolicyAdaptsSummaryColumns() {
        XCTAssertEqual(OverviewLayoutPolicy.summaryLayout(width: 800, hasArtwork: true), .threeColumns)
        XCTAssertEqual(OverviewLayoutPolicy.summaryLayout(width: 600, hasArtwork: true), .twoPlusBottom)
        XCTAssertEqual(OverviewLayoutPolicy.summaryLayout(width: 480, hasArtwork: true), .stacked)
        XCTAssertEqual(OverviewLayoutPolicy.summaryLayout(width: 600, hasArtwork: false), .twoColumns)
        XCTAssertEqual(OverviewLayoutPolicy.summaryLayout(width: 480, hasArtwork: false), .stacked)
    }

    func testOverviewLayoutPolicySideBySideLogsAndActivity() {
        XCTAssertTrue(OverviewLayoutPolicy.showsLogsAndActivitySideBySide(
            width: 800,
            hasLogs: true,
            hasActivity: true
        ))
        XCTAssertFalse(OverviewLayoutPolicy.showsLogsAndActivitySideBySide(
            width: 760,
            hasLogs: true,
            hasActivity: true
        ))
        XCTAssertFalse(OverviewLayoutPolicy.showsLogsAndActivitySideBySide(
            width: 960,
            hasLogs: false,
            hasActivity: true
        ))
        XCTAssertFalse(OverviewLayoutPolicy.showsLogsAndActivitySideBySide(
            width: 960,
            hasLogs: true,
            hasActivity: false
        ))

        let split = OverviewLayoutPolicy.splitWidths(totalWidth: 912, spacing: 12)
        XCTAssertEqual(split.leading + split.trailing, 900)
        XCTAssertGreaterThan(split.leading, split.trailing)

        let clamped = OverviewLayoutPolicy.splitWidths(totalWidth: 8, spacing: 12)
        XCTAssertEqual(clamped.leading, 0)
        XCTAssertEqual(clamped.trailing, 0)
    }
}
