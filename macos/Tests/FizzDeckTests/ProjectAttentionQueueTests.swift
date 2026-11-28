import XCTest
@testable import FizzDeck

final class ProjectAttentionQueueTests: ChineseInterfaceTestCase {
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

    func testPlainModeFocusFilteringSessionErrorAndUrgencyOrder() {
        let now = Date()
        let failingSession = SessionRecord(
            tool: "claude",
            id: "s1",
            cwd: "/tmp/focused",
            startedAt: nil,
            modified: now,
            lastUser: "build",
            lastError: "Compile failed",
            endedWithError: true
        )
        let focused = makeProject(
            path: "/tmp/focused",
            recent: now,
            changes: ChangeStats(tracked: 2, untracked: 0, total: 2),
            ahead: 1,
            behind: 1,
            cleanupBytes: 2_000_000_000,
            cleanupItems: 1,
            sessions: [failingSession]
        )
        let unfocused = makeProject(
            path: "/tmp/unfocused",
            recent: now,
            changes: ChangeStats(tracked: 5, untracked: 0, total: 5)
        )
        let testRuns = [
            focused.path: TestRunState(
                path: focused.path,
                status: .failed,
                output: "",
                startedAt: now,
                duration: 0.2,
                exitCode: 1,
                command: "npm test",
                logPath: ""
            ),
        ]

        let items = ProjectAttentionQueue.items(
            projects: [focused, unfocused],
            testRuns: testRuns,
            focusedPaths: [focused.path],
            copyMode: .plain
        )

        XCTAssertTrue(items.allSatisfy { $0.project.path == focused.path })
        XCTAssertEqual(
            items.map(\.kind),
            [.testFailed, .sessionError, .dirty, .unpushed, .behind]
        )
        XCTAssertTrue(ProjectAttentionKind.testFailed.isCritical)
        XCTAssertTrue(ProjectAttentionKind.sessionError.isCritical)
        XCTAssertFalse(ProjectAttentionKind.dirty.isCritical)
        XCTAssertEqual(items.first?.title, "跑不起来：检查没通过")
        XCTAssertEqual(items[1].title, "上次 AI 对话报错结束")
    }

    @MainActor
    func testExpiringMarksGroupByFocusAndRouteToExactMarkEvenWithoutRecentSessions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FizzDeck-queue-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var focused = makeProject(path: root.appendingPathComponent("focused").path)
        focused.starred = true
        let idle = makeProject(path: root.appendingPathComponent("idle").path)
        let projects = [focused, idle]
        let focusedPaths = ProjectFocusPolicy.partition(projects: projects, now: now).focusedPaths
        let marks = [("later", focused, 10), ("first", focused, 13), ("idle", idle, 12)].map { id, project, age in
            // A persisted checkpoint may use a different spelling of the indexed directory.
            SessionMark(id: id, projectPath: project.path + "/.", createdAt: now.addingTimeInterval(-Double(age) * 86_400),
                        kind: .gitSnapshot, snapshotSHA: String(repeating: "a", count: 40), label: "还原前自动备份")
        }
        let reminders = SessionMarkExpiryPolicy.attentionCandidates(in: marks, focusedPaths: focusedPaths, now: now)
        let file = root.appendingPathComponent("marks.json")
        for mark in marks { try MarkStore.upsertChecked(mark, in: file) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        defaults.setVolatileDomain(["fizzdeck.recentProjects": [focused.path]], forName: UserDefaults.argumentDomain)
        let store = RepositoryStore(preferences: defaults, marksFile: file)
        store.projects = projects

        for mode in [CopyMode.plain, .pro] {
            let items = ProjectAttentionQueue.items(projects: projects, testRuns: [:], focusedPaths: mode == .plain ? focusedPaths : nil,
                                                  copyMode: mode, expiringMarks: reminders)
            XCTAssertEqual(items.map(\.kind), [.expiringMarks])
            let row = try XCTUnwrap(items.first)
            XCTAssertEqual(row.expiringMarks.map(\.mark.id), ["first", "later"])
            XCTAssertFalse(row.kind.isCritical)
            store.openDashboard()
            store.openAttentionItem(row)
            XCTAssertEqual(store.selectedProject?.path, focused.path)
            XCTAssertEqual(store.requestedTab, .progress)
            XCTAssertEqual(store.requestedMarkIDForDiff, "first")
        }
    }

    private func makeProject(
        path: String = "/tmp/project",
        recent: Date? = nil,
        branch: String? = "main",
        changes: ChangeStats = .zero,
        ahead: Int = 0,
        behind: Int = 0,
        cleanupBytes: Int64 = 0,
        cleanupItems: Int = 0,
        sessions: [SessionRecord] = []
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
            starred: false,
            color: nil,
            note: "",
            port: .noPreview
        )
    }
}
