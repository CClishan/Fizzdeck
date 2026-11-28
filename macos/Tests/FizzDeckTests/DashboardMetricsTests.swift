import Foundation
import XCTest
@testable import FizzDeck

final class DashboardMetricsTests: ChineseInterfaceTestCase {
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

        let recap = WeeklyRecapService.build(projects: [pA, pB], now: now, calendar: calendar)
        let byTool = DashboardMetrics.costBreakdown(sessions: recap.analysis.sessions, mode: .byTool)
        XCTAssertEqual(byTool.count, 2)
        XCTAssertEqual(byTool[0].fraction, 0.75, accuracy: 0.001)
    }

    func testWorkbenchTrendsCompareAdjacentWeeksAndCountDistinctFiles() {
        let path = "/tmp/studio"
        let now = date("2026-11-26 15:00")
        let sessions = [
            SessionRecord(tool: "codex", id: "old", cwd: path, startedAt: nil, modified: date("2026-11-19 10:00"), usage: .init(totalTokens: 50), costUSD: 1, touchedFiles: ["README.md"]),
            SessionRecord(tool: "codex", id: "start", cwd: path, startedAt: nil, modified: date("2026-11-20 00:00"), usage: .init(totalTokens: 150), costUSD: 2, touchedFiles: ["README.md", "Sources/App.swift"]),
            SessionRecord(tool: "codex", id: "today", cwd: path, startedAt: nil, modified: now, usage: .init(totalTokens: 50), costUSD: 0, touchedFiles: ["README.md"]),
            SessionRecord(tool: "codex", id: "future", cwd: path, startedAt: nil, modified: date("2026-11-27 00:00"), costUSD: 99),
        ]
        let activity = RepoCommitActivity(path: path, head: "head", authorEmails: [], windowDays: 371,
            timestamps: [date("2026-11-19 10:00"), now, now].map { Int($0.timeIntervalSince1970) }, updatedAt: now)
        let kpi = DashboardMetrics.kpiSummary(projects: [makeProject(path: path, sessions: sessions)],
            commitActivity: .init(byProject: [path: activity]), now: now, calendar: calendar)

        XCTAssertEqual(kpi.sessions.samples, [1, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(kpi.touchedFiles.samples, [2, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(kpi.weeklyTouchedFiles, 2)
        XCTAssertEqual(kpi.touchedFiles.change, 1)
        XCTAssertEqual(kpi.commits.samples, [0, 0, 0, 0, 0, 0, 2])
        XCTAssertEqual(kpi.commits.change, 1)
        XCTAssertEqual(kpi.cost.samples, [2, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(kpi.cost.change, 1)
        XCTAssertNil(kpi.sessions.change)
        XCTAssertNil(kpi.tokens.change)
    }

    func testTrendSuppressesSmallBaselinesAndCapsOnlyGrowthAboveTwoHundredPercent() {
        func change(_ current: Double?, _ previous: Double?, minimum: Double) -> Double? {
            DashboardTrend(samples: [1, 2], current: current, previous: previous, minimumPrevious: minimum).change
        }

        XCTAssertNil(change(3, 2, minimum: 3))
        XCTAssertNil(change(0.60, 0.49, minimum: 0.50))
        XCTAssertEqual(change(1.50, 0.50, minimum: 0.50), 2)
        XCTAssertNil(change(1.51, 0.50, minimum: 0.50))
        XCTAssertEqual(change(9, 3, minimum: 3), 2)
        XCTAssertNil(change(10, 3, minimum: 3))
        XCTAssertEqual(change(0, 3, minimum: 3), -1)
        XCTAssertNil(change(0, 0, minimum: 0))
        XCTAssertNil(change(5, nil, minimum: 0))
        XCTAssertNil(change(.infinity, 5, minimum: 0))
    }

    func testWorkbenchTrendsKeepUnknownUsageAndAnEmptyBaselineDistinctFromZero() {
        let now = date("2026-11-26 15:00")
        let path = "/tmp/studio"
        let session = SessionRecord(tool: "codex", id: "new", cwd: path, startedAt: nil, modified: now)
        let kpi = DashboardMetrics.kpiSummary(projects: [makeProject(path: path, sessions: [session])],
            commitActivity: .empty, now: now, calendar: calendar)

        XCTAssertEqual(kpi.weeklySessions, 1)
        XCTAssertNil(kpi.sessions.change)
        XCTAssertNil(kpi.weeklyCostUSD)
        XCTAssertTrue(kpi.cost.samples.isEmpty)
        XCTAssertNil(kpi.cost.change)
        XCTAssertTrue(kpi.tokens.samples.isEmpty)
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

        let recap = WeeklyRecapService.build(projects: projects, now: now, calendar: calendar)
        let segments = DashboardMetrics.costBreakdown(sessions: recap.analysis.sessions, mode: .byProject)
        XCTAssertEqual(segments.count, 6)
        XCTAssertEqual(segments.last?.id, "other")
        XCTAssertEqual(segments.last?.label, "其他")
        FizzL10n.$languageOverride.withValue(.english) {
            XCTAssertEqual(segments.last?.id, "other")
            XCTAssertEqual(segments.last?.label, "Other")
        }
        XCTAssertEqual(segments.last?.costUSD ?? 0, 3.0, accuracy: 0.001)
    }

    func testCostCompositionFollowsRecapPeriodAndIgnoresZeroShareCategories() throws {
        let now = date("2026-11-26 15:00")
        let today = SessionRecord(tool: "codex", id: "1", cwd: "/tmp/a", startedAt: nil,
                                  modified: now, costUSD: 1.5)
        let unknown = SessionRecord(tool: "cursor", id: "2", cwd: "/tmp/b", startedAt: nil,
                                    modified: now, usage: .init(totalTokens: 2_000))
        let earlier = SessionRecord(tool: "claude", id: "3", cwd: "/tmp/b", startedAt: nil,
                                    modified: date("2026-11-12 10:00"), costUSD: 0.5)
        let projects = [makeProject(path: "/tmp/a", sessions: [today]), makeProject(path: "/tmp/b", sessions: [unknown, earlier])]
        let week = WeeklyRecapService.build(projects: projects, now: now, calendar: calendar)
        let month = WeeklyRecapService.build(projects: projects, range: .month, now: now, calendar: calendar)
        let single = DashboardMetrics.costBreakdown(sessions: week.analysis.sessions, mode: .byTool)
        XCTAssertEqual(single.map(\.id), ["codex"])
        XCTAssertEqual(try XCTUnwrap(single.first).fraction, 1)
        XCTAssertEqual(DashboardMetrics.costBreakdown(sessions: month.analysis.sessions, mode: .byProject).map(\.fraction), [0.75, 0.25])
        let tokenOnly = DashboardMetrics.costBreakdown(sessions: week.analysis.sessions.filter { $0.record.id == "2" }, mode: .byProject)
        XCTAssertEqual(try XCTUnwrap(tokenOnly.first).tokens, 2_000)
        XCTAssertEqual(try XCTUnwrap(tokenOnly.first).costUSD, 0)
        XCTAssertEqual(week.analysis.totals.cost.unpriced, 1)
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

    func testWeeklyTouchedFilesAIActivityHeatmapAndEnrichedContinueWork() {
        let now = date("2026-11-26 15:00")
        let s1 = SessionRecord(
            tool: "claude",
            id: "s1",
            cwd: "/tmp/a",
            startedAt: date("2026-11-26 10:00"),
            modified: date("2026-11-26 10:15"),
            lastUser: "Continue touch",
            firstUser: "添加拖拽排序",
            touchedFiles: ["src/App.jsx", "src/Todo.jsx"],
            lastError: "Build failed",
            endedWithError: true,
            turnCount: 2,
            durationMinutes: 15
        )
        let s2 = SessionRecord(
            tool: "codex",
            id: "s2",
            cwd: "/tmp/a",
            startedAt: date("2026-11-25 14:00"),
            modified: date("2026-11-25 14:10"),
            lastUser: "Init",
            firstUser: "初始化",
            touchedFiles: ["src/App.jsx", "package.json"] // src/App.jsx overlaps with s1
        )
        let pA = makeProject(path: "/tmp/a", displayName: "Alpha", recent: now, sessions: [s2, s1])

        let kpi = DashboardMetrics.kpiSummary(
            projects: [pA],
            commitActivity: .empty,
            now: now,
            calendar: calendar
        )
        // Unique across (project, file): App.jsx, Todo.jsx, package.json => 3
        XCTAssertEqual(kpi.weeklyTouchedFiles, 3)

        let aiHeatmap = DashboardMetrics.buildAIActivityHeatmap(
            projects: [pA],
            range: .weeks26,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(aiHeatmap.totalCommits, 4) // 2 + 2 touched files
        XCTAssertEqual(aiHeatmap.weekCommits, 4)
        XCTAssertEqual(aiHeatmap.currentStreak, 2)

        let continueItems = DashboardMetrics.continueWorkItems(projects: [pA])
        let item = try! XCTUnwrap(continueItems.first)
        XCTAssertEqual(item.summary, "添加拖拽排序")
        XCTAssertEqual(item.touchedFileCount, 2)
        XCTAssertEqual(item.durationMinutes, 15)
        XCTAssertTrue(item.endedWithError)
        XCTAssertEqual(item.lastError, "Build failed")
    }
}
