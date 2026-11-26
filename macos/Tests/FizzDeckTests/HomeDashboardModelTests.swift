import Foundation
import XCTest
@testable import FizzDeck

final class HomeDashboardModelTests: XCTestCase {
    private func makeProject(
        path: String,
        displayName: String? = nil,
        group: String = "网页",
        detectedTools: [DetectedTool] = [],
        recent: Date? = nil,
        dirtyCount: Int = 0,
        totalBytes: Int64 = 0,
        cleanupItems: [CleanupItem] = [],
        starred: Bool = false,
        color: TagColor? = nil,
        port: PortState = .stopped,
        sessionTools: [String] = []
    ) -> RepoProject {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let sessions = SessionSummary(
            detected: sessionTools,
            lastSessionAt: nil,
            lastUserMessage: nil,
            lastSessionID: nil,
            lastTool: sessionTools.first,
            sessionCount: sessionTools.count,
            byTool: [],
            recentSessions: []
        )
        let cleanup = CleanupInfo(
            reusableBytes: cleanupItems.reduce(0) { $0 + $1.bytes },
            items: cleanupItems
        )
        return RepoProject(
            path: path,
            name: name,
            displayName: displayName ?? name,
            group: group,
            kind: .web,
            detectedTools: detectedTools,
            recent: recent,
            branch: "main",
            lastCommit: nil,
            dirtyCount: dirtyCount,
            changes: ChangeStats(tracked: dirtyCount, untracked: 0, total: dirtyCount),
            ahead: 0,
            behind: 0,
            weekly: [:],
            stacks: [],
            size: SizeInfo(totalBytes: totalBytes, breakdown: []),
            cleanup: cleanup,
            run: nil,
            sessions: sessions,
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: starred,
            color: color,
            note: "",
            port: port
        )
    }

    func testSortOrdersByRecentNameAndSize() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        let p1 = makeProject(path: "/tmp/Item 10", displayName: "Item 10", recent: older, totalBytes: 300)
        let p2 = makeProject(path: "/tmp/beta", displayName: "beta", recent: nil, totalBytes: 900)
        let p3 = makeProject(path: "/tmp/Item 2", displayName: "Item 2", recent: newer, totalBytes: 100)
        let p4 = makeProject(path: "/tmp/Alpha", displayName: "Alpha", recent: Date(timeIntervalSince1970: 1_500), totalBytes: 500)

        XCTAssertEqual(
            HomeSort.recent.sort([p1, p2, p3, p4]).map(\.displayName),
            ["Item 2", "Alpha", "Item 10", "beta"]
        )
        XCTAssertEqual(
            HomeSort.name.sort([p1, p2, p3, p4]).map(\.displayName),
            ["Alpha", "beta", "Item 2", "Item 10"]
        )
        XCTAssertEqual(
            HomeSort.size.sort([p1, p2, p3, p4]).map(\.displayName),
            ["beta", "Alpha", "Item 10", "Item 2"]
        )
    }

    func testVisibleProjectsAppliesFilterFacetsAndSort() {
        let d1 = Date(timeIntervalSince1970: 1_000)
        let d2 = Date(timeIntervalSince1970: 2_000)

        let a = makeProject(path: "/tmp/a", group: "网页", detectedTools: [.codex], recent: d1, dirtyCount: 2, color: .blue)
        let b = makeProject(path: "/tmp/b", group: "网页", detectedTools: [.codex], recent: d2, dirtyCount: 1, color: .blue)
        let c = makeProject(path: "/tmp/c", group: "网页", detectedTools: [.codex], recent: d2, dirtyCount: 0, color: .blue)
        let d = makeProject(path: "/tmp/d", group: "工具", detectedTools: [.claude], recent: d2, dirtyCount: 3, color: .amber)

        let matching = HomeDashboardModel.matchingProjects(from: [a, b, c, d], filter: .dirty)
        XCTAssertEqual(matching.map(\.name), ["a", "b", "d"])

        let facets = HomeFacets(group: "网页", color: .blue, tool: "codex")
        let visible = HomeDashboardModel.visibleProjects(from: matching, facets: facets, sort: .recent)
        XCTAssertEqual(visible.map(\.name), ["b", "a"])
    }

    func testFacetCountsExcludeOwnFacetAndRespectOthers() {
        let a = makeProject(path: "/tmp/a", group: "网页", detectedTools: [.codex], color: .blue)
        let b = makeProject(path: "/tmp/b", group: "网页", detectedTools: [.claude], color: .blue)
        let c = makeProject(path: "/tmp/c", group: "工具", detectedTools: [.codex], color: .red)
        let matching = [a, b, c]

        let facets = HomeFacets(group: "网页", color: .blue, tool: "codex")
        XCTAssertEqual(HomeDashboardModel.groupCount("网页", in: matching, facets: facets), 1)
        XCTAssertEqual(HomeDashboardModel.groupCount("工具", in: matching, facets: facets), 0)
        XCTAssertEqual(HomeDashboardModel.colorCount(.blue, in: matching, facets: facets), 1)
        XCTAssertEqual(HomeDashboardModel.colorCount(.red, in: matching, facets: facets), 0)
        XCTAssertEqual(HomeDashboardModel.toolCount("codex", in: matching, facets: facets), 1)
        XCTAssertEqual(HomeDashboardModel.toolCount("claude", in: matching, facets: facets), 1)
    }

    func testAvailableToolsFollowsPreferredDetectedToolOrder() {
        let p1 = makeProject(path: "/tmp/a", detectedTools: [.claude], sessionTools: ["zeta", "codex"])
        let p2 = makeProject(path: "/tmp/b", sessionTools: ["alpha"])

        let tools = HomeDashboardModel.availableTools(in: [p1, p2])
        XCTAssertEqual(tools, ["codex", "claude", "alpha", "zeta"])
    }

    func testSummaryStatsAggregatesProjectsRunningBytesAndCleanup() {
        let item1 = CleanupItem(label: "node_modules", path: "/tmp/a/node_modules", bytes: 400, reason: "", regen: "", kind: "")
        let item2 = CleanupItem(label: "dist", path: "/tmp/a/dist", bytes: 100, reason: "", regen: "", kind: "")
        let item3 = CleanupItem(label: ".build", path: "/tmp/b/.build", bytes: 250, reason: "", regen: "", kind: "")

        let p1 = makeProject(path: "/tmp/a", totalBytes: 1_000, cleanupItems: [item1, item2], port: .running)
        let p2 = makeProject(path: "/tmp/b", totalBytes: 2_500, cleanupItems: [item3], port: .stopped)

        let stats = HomeDashboardModel.summaryStats(for: [p1, p2])
        XCTAssertEqual(stats, HomeSummaryStats(
            projectCount: 2,
            runningCount: 1,
            totalBytes: 3_500,
            cleanupBytes: 750,
            cleanupItemCount: 3
        ))
    }

    func testHeaderDetailFormatsFacetsRunningAndScanStates() {
        XCTAssertEqual(
            HomeDashboardModel.headerDetail(
                visibleCount: 5,
                matchingCount: 5,
                hasFacets: false,
                filter: .all,
                runningCount: 2,
                isScanning: false,
                pendingSizeCount: 0,
                relativeScannedAt: "3 分钟前"
            ),
            "5 个项目 · 2 个运行中 · 3 分钟前更新"
        )

        XCTAssertEqual(
            HomeDashboardModel.headerDetail(
                visibleCount: 2,
                matchingCount: 5,
                hasFacets: true,
                filter: .running,
                runningCount: 2,
                isScanning: true,
                pendingSizeCount: 4,
                relativeScannedAt: "3 分钟前"
            ),
            "显示 2 / 5 个项目 · 正在扫描"
        )

        XCTAssertEqual(
            HomeDashboardModel.headerDetail(
                visibleCount: 3,
                matchingCount: 3,
                hasFacets: false,
                filter: .all,
                runningCount: 0,
                isScanning: false,
                pendingSizeCount: 2,
                relativeScannedAt: "刚刚"
            ),
            "3 个项目 · 正在统计体积 (2)"
        )
    }

    func testBatchCleanupCommandsBuildsScriptAndFeedback() {
        let cleanItem = CleanupItem(label: "dist", path: "/tmp/a/dist", bytes: 100, reason: "", regen: "", kind: "")
        let p1 = makeProject(path: "/tmp/a", displayName: "AppA", cleanupItems: [cleanItem])
        let p2 = makeProject(path: "/tmp/b", displayName: "AppB", cleanupItems: [])
        let p3 = makeProject(path: "/tmp/c", displayName: "AppC", cleanupItems: [
            CleanupItem(label: "build", path: "/tmp/c/build", bytes: 50, reason: "", regen: "", kind: ""),
        ])

        let none = HomeDashboardModel.batchCleanupCommands(for: [p2])
        XCTAssertNil(none.script)
        XCTAssertEqual(none.feedback, "所选项目没有可清理项")

        let partial = HomeDashboardModel.batchCleanupCommands(for: [p1, p2])
        XCTAssertEqual(partial.script, "# AppA\nrm -rf '/tmp/a/dist'")
        XCTAssertEqual(partial.feedback, "已复制 1 个；1 个没有可清理项")

        let all = HomeDashboardModel.batchCleanupCommands(for: [p1, p3])
        XCTAssertEqual(all.script, "# AppA\nrm -rf '/tmp/a/dist'\n# AppC\nrm -rf '/tmp/c/build'")
        XCTAssertEqual(all.feedback, "已复制 2 个项目的清理命令")
    }

    func testLibraryProjectsFilterSortAndDirtySort() {
        var p1 = makeProject(
            path: "/tmp/a",
            displayName: "Alpha",
            group: "网页",
            recent: Date(timeIntervalSince1970: 2_000),
            dirtyCount: 2,
            starred: true,
            port: .running,
            sessionTools: ["codex"]
        )
        p1.ahead = 3
        p1.stacks = [StackGroup(key: "framework", label: "框架", items: ["Next.js"])]

        var p2 = makeProject(
            path: "/tmp/b",
            displayName: "Beta",
            group: "工具",
            recent: Date(timeIntervalSince1970: 3_000),
            dirtyCount: 8,
            starred: false,
            port: .stopped
        )
        p2.stacks = [StackGroup(key: "framework", label: "框架", items: ["SwiftUI"])]

        XCTAssertEqual(HomeSort.dirty.sort([p1, p2]).map(\.name), ["b", "a"])
        XCTAssertEqual(HomeDashboardModel.availableFrameworks(in: [p1, p2]), ["Next.js", "SwiftUI"])

        var query = LibraryQuery()
        query.starredOnly = true
        query.dirtyOnly = true
        query.runningOnly = true
        query.hasSessionsOnly = true
        query.unpushedOnly = true
        query.framework = "Next.js"
        query.searchText = "alpha"

        let matched = HomeDashboardModel.libraryProjects(
            from: [p1, p2],
            query: query,
            sort: .dirty,
            commitActivity: .empty
        )
        XCTAssertEqual(matched.map(\.path), ["/tmp/a"])

        var tzCal = Calendar(identifier: .gregorian)
        tzCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let commitDay = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let snapshot = CommitActivitySnapshot(byProject: [
            "/tmp/b": RepoCommitActivity(
                path: "/tmp/b",
                head: "1",
                authorEmails: [],
                windowDays: 371,
                timestamps: [1_700_000_100],
                updatedAt: commitDay
            ),
        ])
        let dayMatches = HomeDashboardModel.libraryProjects(
            from: [p1, p2],
            query: LibraryQuery(commitDayKey: "2023-11-14"),
            sort: .recent,
            commitActivity: snapshot,
            calendar: tzCal
        )
        XCTAssertEqual(dayMatches.map(\.path), ["/tmp/b"])
    }
}
