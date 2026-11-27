import XCTest
@testable import FizzDeck

final class ProjectFocusPolicyTests: XCTestCase {
    func testPartitionPrioritizesManualCapsAtEightAndIdentifiesIdle() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let tenDaysAgo = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let fortyDaysAgo = now.addingTimeInterval(-40 * 24 * 60 * 60)

        var projects: [RepoProject] = []
        // 2 manual starred projects (even if one is older)
        projects.append(makeProject(path: "/tmp/manual-1", recent: fortyDaysAgo, starred: true))
        projects.append(makeProject(path: "/tmp/manual-2", recent: twoDaysAgo, starred: true))

        // 8 auto-active projects within 7 days (total capacity 8 -> 6 fit, 2 overflow)
        for index in 1...8 {
            projects.append(
                makeProject(
                    path: "/tmp/active-\(index)",
                    recent: now.addingTimeInterval(-Double(index) * 3_600),
                    starred: false
                )
            )
        }

        // 1 mid-range project (10 days ago -> neither focused nor idle)
        projects.append(makeProject(path: "/tmp/mid", recent: tenDaysAgo, starred: false))
        // 1 idle project (40 days ago -> idle)
        projects.append(makeProject(path: "/tmp/idle", recent: fortyDaysAgo, starred: false))

        let result = ProjectFocusPolicy.partition(projects: projects, now: now)

        XCTAssertEqual(result.focused.count, 8)
        XCTAssertEqual(result.overflowActiveCount, 2)
        XCTAssertEqual(result.focused.prefix(2).map(\.id), ["/tmp/manual-2", "/tmp/manual-1"])
        XCTAssertEqual(result.focused.prefix(2).map(\.reason), [.manual, .manual])
        XCTAssertTrue(result.focused.dropFirst(2).allSatisfy { $0.reason == .recentActivity })
        XCTAssertEqual(result.idle.map(\.path), ["/tmp/idle"])
    }

    func testStatusDotPriorityOrder() {
        let now = Date()
        let failingSession = SessionRecord(
            tool: "claude",
            id: "s1",
            cwd: "/tmp/app",
            startedAt: nil,
            modified: now,
            lastUser: "fix build",
            endedWithError: true
        )
        let dirtyWithError = makeProject(
            path: "/tmp/app",
            recent: now,
            dirtyCount: 3,
            sessions: [failingSession]
        )

        // aiWorking beats broken & unsaved
        XCTAssertEqual(
            ProjectFocusPolicy.statusDot(
                for: dirtyWithError,
                testRuns: [:],
                activeAIProjectPaths: ["/tmp/app"]
            ),
            .aiWorking
        )

        // broken (via endedWithError) beats unsaved
        XCTAssertEqual(
            ProjectFocusPolicy.statusDot(
                for: dirtyWithError,
                testRuns: [:],
                activeAIProjectPaths: []
            ),
            .broken
        )

        // test failure also yields broken
        let dirtyCleanSession = makeProject(path: "/tmp/app2", recent: now, dirtyCount: 2)
        let failedTest = TestRunState(
            path: "/tmp/app2",
            status: .failed,
            output: "failed",
            startedAt: now,
            duration: 1,
            exitCode: 1,
            command: "npm test",
            logPath: "/tmp/test.log"
        )
        XCTAssertEqual(
            ProjectFocusPolicy.statusDot(
                for: dirtyCleanSession,
                testRuns: ["/tmp/app2": failedTest],
                activeAIProjectPaths: []
            ),
            .broken
        )

        // unsaved when dirty or ahead
        XCTAssertEqual(
            ProjectFocusPolicy.statusDot(
                for: dirtyCleanSession,
                testRuns: [:],
                activeAIProjectPaths: []
            ),
            .unsaved
        )

        // clean project yields none
        let clean = makeProject(path: "/tmp/clean", recent: now, dirtyCount: 0)
        XCTAssertEqual(
            ProjectFocusPolicy.statusDot(
                for: clean,
                testRuns: [:],
                activeAIProjectPaths: []
            ),
            .none
        )
    }

    private func makeProject(
        path: String,
        recent: Date?,
        dirtyCount: Int = 0,
        starred: Bool = false,
        sessions: [SessionRecord] = []
    ) -> RepoProject {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return RepoProject(
            path: path,
            name: name,
            displayName: name,
            group: "网页",
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
            cleanup: .empty,
            run: nil,
            sessions: SessionSummary(
                detected: Array(Set(sessions.map(\.tool))),
                lastSessionAt: sessions.map(\.modified).max(),
                lastUserMessage: sessions.last?.lastUser,
                lastSessionID: sessions.last?.id,
                lastTool: sessions.last?.tool,
                sessionCount: sessions.count,
                byTool: [],
                recentSessions: sessions
            ),
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: starred,
            color: nil,
            note: "",
            port: .stopped
        )
    }
}
