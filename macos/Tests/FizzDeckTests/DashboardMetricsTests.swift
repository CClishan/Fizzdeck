import Foundation
import XCTest
@testable import FizzDeck

final class DashboardMetricsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func makeProject(
        path: String,
        displayName: String? = nil,
        group: String = "网页",
        recent: Date? = nil,
        dirtyCount: Int = 0,
        cleanupBytes: Int64 = 0,
        starred: Bool = false,
        port: PortState = .stopped,
        sessions: [SessionRecord] = []
    ) -> RepoProject {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let cleanupItems = cleanupBytes > 0
            ? [CleanupItem(label: "dist", path: "\(path)/dist", bytes: cleanupBytes, reason: "", regen: "", kind: "build")]
            : []
        let summary = SessionSummary(
            detected: Array(Set(sessions.map(\.tool))),
            lastSessionAt: sessions.map(\.modified).max(),
            lastUserMessage: sessions.last?.lastUser,
            lastSessionID: sessions.last?.id,
            lastTool: sessions.last?.tool,
            sessionCount: sessions.count,
            byTool: [],
            recentSessions: sessions
        )
        return RepoProject(
            path: path,
            name: name,
            displayName: displayName ?? name,
            group: group,
            kind: .web,
            detectedTools: [],
            recent: recent,
            branch: "main",
            lastCommit: nil,
            dirtyCount: dirtyCount,
            changes: ChangeStats(tracked: dirtyCount, untracked: 0, total: dirtyCount),
            ahead: 0,
            behind: 0,
            weekly: [:],
            stacks: [],
            size: .empty,
            cleanup: CleanupInfo(reusableBytes: cleanupBytes, items: cleanupItems),
            run: nil,
            sessions: summary,
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: starred,
            color: nil,
            note: "",
            port: port
        )
    }

    func testHeatmapBuildsExpectedColumnsStreaksAndDayLookup() {
        let now = date("2026-11-26 15:00") // Thursday
        let d1 = Int(date("2026-11-24 10:00").timeIntervalSince1970)
        let d2 = Int(date("2026-11-25 11:00").timeIntervalSince1970)
        let d3 = Int(date("2026-11-25 14:00").timeIntervalSince1970)
        let d4 = Int(date("2026-11-26 09:00").timeIntervalSince1970)

        let pA = makeProject(path: "/tmp/a", displayName: "Alpha")
        let pB = makeProject(path: "/tmp/b", displayName: "Beta")

        let snapshot = CommitActivitySnapshot(byProject: [
            "/tmp/a": RepoCommitActivity(path: "/tmp/a", head: "1", authorEmails: [], windowDays: 371, timestamps: [d1, d2, d4], updatedAt: now),
            "/tmp/b": RepoCommitActivity(path: "/tmp/b", head: "2", authorEmails: [], windowDays: 371, timestamps: [d3], updatedAt: now),
        ])

        let summary26 = DashboardMetrics.buildHeatmap(
            snapshot: snapshot,
            projects: [pA, pB],
            range: .weeks26,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(summary26.columns.count, 26)
        XCTAssertTrue(summary26.columns.allSatisfy { $0.count == 7 })
        XCTAssertEqual(summary26.totalCommits, 4)
        XCTAssertEqual(summary26.currentStreak, 3)
        XCTAssertEqual(summary26.longestStreak, 3)
        XCTAssertEqual(summary26.weekCommits, 4)

        let summary12 = DashboardMetrics.buildHeatmap(
            snapshot: snapshot,
            projects: [pA, pB],
            range: .months12,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(summary12.columns.count, 52)

        let committedNov25 = DashboardMetrics.projectPathsCommitted(
            onDayKey: "2026-11-25",
            snapshot: snapshot,
            projects: [pA, pB],
            calendar: calendar
        )
        XCTAssertEqual(committedNov25, Set(["/tmp/a", "/tmp/b"]))
    }

    func testWeeklyToolSharesKPIAndCostBreakdown() {
        let now = date("2026-11-26 15:00")
        let s1 = SessionRecord(
            tool: "codex",
            id: "1",
            cwd: "/tmp/a",
            startedAt: date("2026-11-25 10:00"),
            modified: date("2026-11-25 11:00"),
            lastUser: "Fix auth",
            usage: TokenUsage(totalTokens: 3_000),
            costUSD: 1.5,
            costIsEstimate: true
        )
        let s2 = SessionRecord(
            tool: "claude",
            id: "2",
            cwd: "/tmp/b",
            startedAt: date("2026-11-24 09:00"),
            modified: date("2026-11-24 10:00"),
            lastUser: "Add tests",
            usage: TokenUsage(totalTokens: 1_000),
            costUSD: 0.5,
            costIsEstimate: false
        )
        let prev = SessionRecord(
            tool: "codex",
            id: "0",
            cwd: "/tmp/a",
            startedAt: nil,
            modified: date("2026-11-16 10:00"),
            usage: TokenUsage(totalTokens: 1_000),
            costUSD: 1.0,
            costIsEstimate: false
        )

        let pA = makeProject(path: "/tmp/a", sessions: [s1, prev])
        let pB = makeProject(path: "/tmp/b", sessions: [s2])

        let shares = DashboardMetrics.weeklyToolShares(projects: [pA, pB], now: now, calendar: calendar)
        XCTAssertEqual(shares.map(\.tool), ["codex", "claude"])
        XCTAssertEqual(shares[0].fraction, 0.75, accuracy: 0.001)
        XCTAssertEqual(shares[1].fraction, 0.25, accuracy: 0.001)

        let kpi = DashboardMetrics.kpiSummary(
            projects: [pA, pB],
            commitActivity: .empty,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(kpi.weeklySessions, 2)
        XCTAssertEqual(kpi.weeklyTokens, 4_000)
        XCTAssertEqual(kpi.weeklyCostUSD ?? 0, 2.0, accuracy: 0.001)
        XCTAssertEqual(kpi.monthlyCostUSD ?? 0, 3.0, accuracy: 0.001)
        XCTAssertTrue(kpi.costIsEstimate)
        XCTAssertEqual(kpi.weekOverWeekCostDeltaPercent ?? 0, 100.0, accuracy: 0.01)

        let byTool = DashboardMetrics.costBreakdown(projects: [pA, pB], mode: .byTool, now: now, calendar: calendar)
        XCTAssertEqual(byTool.count, 2)
        XCTAssertEqual(byTool[0].fraction, 0.75, accuracy: 0.001)
    }

    func testCostBreakdownMergesTailIntoOther() {
        let now = date("2026-11-26 15:00")
        let projects = (1...7).map { idx in
            makeProject(
                path: "/tmp/p\(idx)",
                displayName: "P\(idx)",
                sessions: [
                    SessionRecord(
                        tool: "codex",
                        id: "\(idx)",
                        cwd: "/tmp/p\(idx)",
                        startedAt: nil,
                        modified: now,
                        usage: TokenUsage(totalTokens: idx * 100),
                        costUSD: Double(idx)
                    ),
                ]
            )
        }

        let segments = DashboardMetrics.costBreakdown(projects: projects, mode: .byProject, now: now, calendar: calendar)
        XCTAssertEqual(segments.count, 6)
        XCTAssertEqual(segments.last?.id, "other")
        XCTAssertEqual(segments.last?.label, "其他")
        XCTAssertEqual(segments.last?.costUSD ?? 0, 3.0, accuracy: 0.001)
    }

    func testContinueWorkTimelineHealthAlertsAndIdlePartition() {
        let now = date("2026-11-26 15:00")
        let stale = date("2026-09-01 10:00")

        let s1 = SessionRecord(
            tool: "codex",
            id: "c1",
            cwd: "/tmp/a",
            startedAt: date("2026-11-26 10:00"),
            modified: date("2026-11-26 11:30"),
            lastUser: "Refactor sidebar"
        )
        let pActive = makeProject(
            path: "/tmp/a",
            displayName: "ActiveApp",
            recent: now,
            cleanupBytes: 6_000_000_000,
            sessions: [s1]
        )
        let pIdleDirty = makeProject(
            path: "/tmp/b",
            displayName: "OldDirty",
            recent: stale,
            dirtyCount: 4
        )
        let pIdleStarred = makeProject(
            path: "/tmp/c",
            displayName: "StarredIdle",
            recent: stale,
            starred: true
        )

        let continueItems = DashboardMetrics.continueWorkItems(projects: [pActive, pIdleDirty, pIdleStarred])
        XCTAssertEqual(continueItems.map(\.project.path), ["/tmp/a"])
        XCTAssertEqual(continueItems.first?.summary, "Refactor sidebar")

        let commitTs1 = Int(now.timeIntervalSince1970)
        let commitTs2 = Int(now.addingTimeInterval(-3600).timeIntervalSince1970)
        let commitActivity = CommitActivitySnapshot(
            byProject: [
                "/tmp/a": RepoCommitActivity(
                    path: "/tmp/a",
                    head: "abc",
                    authorEmails: [],
                    windowDays: 371,
                    timestamps: [commitTs1, commitTs2],
                    updatedAt: now
                )
            ]
        )
        let timeline = DashboardMetrics.weeklyTimeline(
            projects: [pActive],
            commitActivity: commitActivity,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(timeline.count, 7)
        XCTAssertEqual(timeline.last?.blocks.count, 2)
        XCTAssertEqual(timeline.last?.blocks.first(where: { $0.kind == .commit })?.detail, "2 次提交")
        XCTAssertTrue(timeline.last?.isToday == true)

        let alerts = DashboardMetrics.healthAlerts(
            projects: [pActive, pIdleDirty],
            freeDiskBytes: 10_000_000_000,
            now: now
        )
        XCTAssertEqual(Set(alerts.map(\.kind)), Set([.lowDisk, .highCleanup, .staleDirty]))

        let partitioned = DashboardMetrics.partitionByActivity([pActive, pIdleDirty, pIdleStarred], now: now)
        XCTAssertEqual(partitioned.active.map(\.path), ["/tmp/a", "/tmp/c"])
        XCTAssertEqual(partitioned.idle.map(\.path), ["/tmp/b"])
    }
}
