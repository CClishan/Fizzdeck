import Foundation
import XCTest
@testable import FizzDeck

final class SessionSearchIndexTests: XCTestCase {
    private func makeTempDB(name: String) throws -> (dir: URL, db: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-search-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("session-search.sqlite"))
    }

    private func makeProject(
        path: String,
        name: String,
        sessions: [SessionRecord]
    ) -> RepoProject {
        RepoProject(
            path: path,
            name: name,
            displayName: name,
            group: "dev",
            kind: .web,
            detectedTools: [],
            recent: sessions.map(\.modified).max(),
            branch: "main",
            lastCommit: nil,
            dirtyCount: 0,
            changes: .zero,
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
                lastUserMessage: sessions.first?.lastUser,
                lastSessionID: sessions.first?.id,
                lastTool: sessions.first?.tool,
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

    func testSupportsTwoCharChineseFallbackAndTrigramSearchAndFilters() async throws {
        let (dir, dbURL) = try makeTempDB(name: "queries")
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date()
        let todoProject = makeProject(
            path: "/tmp/todo-app",
            name: "todo-app",
            sessions: [
                SessionRecord(
                    tool: "claude",
                    id: "s-drag",
                    cwd: "/tmp/todo-app",
                    startedAt: now.addingTimeInterval(-3_600),
                    modified: now.addingTimeInterval(-1_800),
                    lastUser: "顺便处理移动端 touch 事件",
                    firstUser: "给待办事项列表加上拖拽排序功能",
                    touchedFiles: ["/tmp/todo-app/src/TodoList.tsx"]
                ),
                SessionRecord(
                    tool: "codex",
                    id: "s-workspace",
                    cwd: "/tmp/todo-app",
                    startedAt: now.addingTimeInterval(-7_200),
                    modified: now.addingTimeInterval(-7_200),
                    kind: .workspaceSummary,
                    firstUser: "忽略的工作区摘要"
                ),
            ]
        )
        let shopProject = makeProject(
            path: "/tmp/shop-app",
            name: "shop-app",
            sessions: [
                SessionRecord(
                    tool: "codex",
                    id: "s-login-err",
                    cwd: "/tmp/shop-app",
                    startedAt: now.addingTimeInterval(-900),
                    modified: now.addingTimeInterval(-600),
                    lastUser: "登录页点击没反应",
                    firstUser: "修复登录弹窗和支付结算页报错",
                    touchedFiles: ["/tmp/shop-app/src/CheckoutView.swift"],
                    lastError: "Missing Stripe secret sk-live-1234567890abcdef1234",
                    endedWithError: true
                ),
            ]
        )

        let index = SessionSearchIndex(databaseURL: dbURL)
        await index.rebuild(
            from: [todoProject, shopProject],
            aiHeadlines: ["claude:s-drag": "已完成拖拽排序基础交互"]
        )

        // 2-char Chinese term uses LIKE fallback seamlessly
        let twoCharLogin = await index.search(query: "登录")
        XCTAssertEqual(twoCharLogin.map(\.sessionID), ["s-login-err"])

        // 3+ char Chinese & English terms work via trigram FTS5
        let dragHits = await index.search(query: "拖拽排序")
        XCTAssertEqual(dragHits.map(\.sessionID), ["s-drag"])

        let fileHits = await index.search(query: "CheckoutView")
        XCTAssertEqual(fileHits.map(\.sessionID), ["s-login-err"])
        XCTAssertEqual(fileHits.first?.matchedSnippet, "命中文件：CheckoutView.swift")

        // Multi-term AND + tool & error filters
        let filteredCodex = await index.search(query: "登录", toolFilter: "codex", errorOnly: true)
        XCTAssertEqual(filteredCodex.map(\.sessionID), ["s-login-err"])
        let filteredClaude = await index.search(query: "登录", toolFilter: "claude", errorOnly: true)
        XCTAssertTrue(filteredClaude.isEmpty)

        // Workspace summaries are excluded from conversation index
        let summaryHits = await index.search(query: "工作区摘要")
        XCTAssertTrue(summaryHits.isEmpty)

        // Secret tokens are redacted before persisting to SQLite
        let rawSecretHits = await index.search(query: "sk-live-1234567890abcdef1234")
        XCTAssertTrue(rawSecretHits.isEmpty)

        // Rebuild replaces stale sessions cleanly
        await index.rebuild(from: [todoProject])
        let afterRebuild = await index.search(query: "登录")
        XCTAssertTrue(afterRebuild.isEmpty)

        // In-memory parity for pre-index queries
        let memHits = SessionSearchIndex.inMemorySearch(
            projects: [todoProject, shopProject],
            query: "拖拽"
        )
        XCTAssertEqual(memHits.map(\.sessionID), ["s-drag"])
    }

    func testFindsSessionsByTouchedFilePathWithBoundaryMatchingAndMemoryFallback() async throws {
        let (dir, dbURL) = try makeTempDB(name: "file-history")
        defer { try? FileManager.default.removeItem(at: dir) }

        let projectPath = "/tmp/fizzdeck-file-history"
        let now = Date()
        let project = makeProject(
            path: projectPath,
            name: "file-history",
            sessions: [
                SessionRecord(
                    tool: "codex",
                    id: "s-exact",
                    cwd: projectPath,
                    startedAt: now.addingTimeInterval(-1_800),
                    modified: now.addingTimeInterval(-1_200),
                    firstUser: "修一下主入口",
                    touchedFiles: ["\(projectPath)/src/App.swift"]
                ),
                SessionRecord(
                    tool: "claude",
                    id: "s-boundary",
                    cwd: projectPath,
                    startedAt: now.addingTimeInterval(-3_600),
                    modified: now.addingTimeInterval(-3_000),
                    firstUser: "调整旁边的应用",
                    touchedFiles: ["\(projectPath)/src/MyApp.swift"]
                ),
                SessionRecord(
                    tool: "grok",
                    id: "s-chinese",
                    cwd: projectPath,
                    startedAt: now.addingTimeInterval(-5_400),
                    modified: now.addingTimeInterval(-5_000),
                    firstUser: "补中文说明",
                    touchedFiles: ["文档/使用说明.swift"]
                ),
            ]
        )

        let index = SessionSearchIndex(databaseURL: dbURL)
        await index.rebuild(from: [project])

        let exact = await index.sessions(
            touchingFile: "src/App.swift",
            projectPath: projectPath
        )
        XCTAssertEqual(exact.map(\.sessionID), ["s-exact"])

        let basename = await index.sessions(
            touchingFile: "App.swift",
            projectPath: projectPath
        )
        XCTAssertEqual(basename.map(\.sessionID), ["s-exact"])
        XCTAssertFalse(basename.contains { $0.sessionID == "s-boundary" })
        XCTAssertFalse(
            SessionSearchIndex.touchedPathMatches(
                "/tmp/other-project/src/App.swift",
                target: "src/App.swift",
                projectPath: projectPath
            )
        )

        let chinese = await index.sessions(
            touchingFile: "文档/使用说明.swift",
            projectPath: projectPath
        )
        XCTAssertEqual(chinese.map(\.sessionID), ["s-chinese"])

        let none = await index.sessions(
            touchingFile: "src/Missing.swift",
            projectPath: projectPath
        )
        XCTAssertTrue(none.isEmpty)

        let memory = SessionSearchIndex.inMemorySessions(
            touchingFile: "src/App.swift",
            projectPath: projectPath,
            projects: [project]
        )
        XCTAssertEqual(memory.map(\.sessionID), ["s-exact"])
        XCTAssertEqual(memory.first?.tool, "codex")
    }
}
