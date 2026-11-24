import XCTest
@testable import FizzDeck

final class ProjectAttentionQueueTests: XCTestCase {
    func testItemsFollowPriorityOrder() {
        let now = Date()
        let project = makeProject(
            recent: now,
            changes: ChangeStats(tracked: 1, untracked: 0, total: 1),
            ahead: 1,
            behind: 2,
            cleanupBytes: 1_000_000_000,
            cleanupItems: 1
        )
        let testRuns = [
            project.path: TestRunState(
                path: project.path,
                status: .failed,
                output: "",
                startedAt: now,
                duration: 0.2,
                exitCode: 1,
                command: "npm test",
                logPath: ""
            ),
        ]

        let items = ProjectAttentionQueue.items(projects: [project], testRuns: testRuns)

        XCTAssertEqual(
            items.map(\.kind),
            [.testFailed, .behind, .unpushed, .dirty, .cleanup]
        )
    }

    func testMoreRecentProjectWinsTie() {
        let older = makeProject(path: "/tmp/older", recent: Date(timeIntervalSince1970: 100))
        let newer = makeProject(path: "/tmp/newer", recent: Date(timeIntervalSince1970: 200))
        let olderWithCommit = withAhead(older)
        let newerWithCommit = withAhead(newer)

        let items = ProjectAttentionQueue.items(
            projects: [olderWithCommit, newerWithCommit],
            testRuns: [:]
        )

        XCTAssertEqual(items.map(\.project.path), ["/tmp/newer", "/tmp/older"])
    }

    func testCleanupRequiresOneGigabyte() {
        let belowThreshold = makeProject(
            path: "/tmp/below",
            cleanupBytes: 999_999_999,
            cleanupItems: 1
        )
        let atThreshold = makeProject(
            path: "/tmp/at",
            cleanupBytes: 1_000_000_000,
            cleanupItems: 1
        )

        XCTAssertTrue(
            ProjectAttentionQueue.items(projects: [belowThreshold], testRuns: [:]).isEmpty
        )
        XCTAssertEqual(
            ProjectAttentionQueue.items(projects: [atThreshold], testRuns: [:]).map(\.kind),
            [.cleanup]
        )
    }

    func testAttentionPreferenceSnoozeExpires() {
        let now = Date(timeIntervalSince1970: 1_000)
        let future = AttentionPreference(muted: false, snoozedUntil: now.addingTimeInterval(60))
        let past = AttentionPreference(muted: false, snoozedUntil: now.addingTimeInterval(-60))

        XCTAssertTrue(future.suppresses(at: now))
        XCTAssertTrue(future.isSnoozed(at: now))
        XCTAssertFalse(past.suppresses(at: now))
        XCTAssertTrue(AttentionPreference(muted: true).suppresses(at: now))
    }

    private func withAhead(_ project: RepoProject) -> RepoProject {
        var project = project
        project.ahead = 1
        return project
    }

    private func makeProject(
        path: String = "/tmp/project",
        recent: Date? = nil,
        branch: String? = "main",
        changes: ChangeStats = .zero,
        ahead: Int = 0,
        behind: Int = 0,
        cleanupBytes: Int64 = 0,
        cleanupItems: Int = 0
    ) -> RepoProject {
        let cleanup = CleanupInfo(
            reusableBytes: cleanupBytes,
            items: (0..<cleanupItems).map { index in
                CleanupItem(
                    label: "cache-\(index)",
                    path: "\(path)/cache-\(index)",
                    bytes: 0,
                    reason: "test",
                    regen: "test",
                    kind: "cache"
                )
            }
        )

        return RepoProject(
            path: path,
            name: "project",
            displayName: "Project",
            group: "工具库",
            recent: recent,
            branch: branch,
            lastCommit: nil,
            dirtyCount: changes.total,
            changes: changes,
            ahead: ahead,
            behind: behind,
            weekly: [:],
            stacks: [],
            size: .empty,
            cleanup: cleanup,
            run: nil,
            sessions: .empty,
            intro: .empty,
            artwork: nil,
            test: nil,
            starred: false,
            color: nil,
            note: "",
            port: .noPreview
        )
    }
}
