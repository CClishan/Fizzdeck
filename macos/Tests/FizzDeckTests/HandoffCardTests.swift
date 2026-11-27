import XCTest
@testable import FizzDeck

final class HandoffCardTests: XCTestCase {
    func testSecretRedactorMasksKnownFormatsAndCountsMatches() {
        let input = """
        OpenAI: sk-proj-1234567890abcdefghij
        Claude: sk-ant-api03-abcdef1234567890
        GitHub: ghp_1234567890abcdefghij123456
        AWS: AKIA1234567890ABCDEF
        Header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload
        Env: OPENAI_API_KEY="my_plain_secret_value_999"
        """

        let result = SecretRedactor.redact(input)

        XCTAssertEqual(result.redactedCount, 6)
        XCTAssertFalse(result.text.contains("sk-proj-1234567890"))
        XCTAssertFalse(result.text.contains("sk-ant-api03"))
        XCTAssertFalse(result.text.contains("ghp_1234567890"))
        XCTAssertFalse(result.text.contains("AKIA1234567890ABCDEF"))
        XCTAssertFalse(result.text.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
        XCTAssertFalse(result.text.contains("my_plain_secret_value_999"))
        XCTAssertTrue(result.text.contains("OPENAI_API_KEY=\"[已脱敏]\""))
        XCTAssertTrue(result.text.contains("Bearer [已脱敏]"))
        XCTAssertTrue(SecretRedactor.containsSecret(input))
    }

    func testSecretRedactorLeavesNormalTextUntouched() {
        let input = "Fix sidebar layout and run swift test on App.swift (sk-short)."
        let result = SecretRedactor.redact(input)

        XCTAssertEqual(result.redactedCount, 0)
        XCTAssertEqual(result.text, input)
        XCTAssertFalse(SecretRedactor.containsSecret(input))
    }

    func testHandoffCardBuilderAssemblesSessionsRedactsAndTruncates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let s1 = SessionRecord(
            tool: "claude",
            id: "s1",
            cwd: "/tmp/todo-app",
            startedAt: now.addingTimeInterval(-600),
            modified: now.addingTimeInterval(-300),
            lastUser: "Continue touch support",
            kind: .conversation,
            firstUser: "加上拖拽排序，密钥是 sk-proj-1234567890abcdefghij",
            touchedFiles: ["src/App.jsx", "src/TodoList.jsx"],
            lastError: "Error: Cannot find module 'react-dnd' using ghp_1234567890abcdefghij1234",
            endedWithError: true,
            turnCount: 2,
            durationMinutes: 5
        )
        let s2 = SessionRecord(
            tool: "codex",
            id: "s2",
            cwd: "/tmp/todo-app",
            startedAt: now.addingTimeInterval(-3_600),
            modified: now.addingTimeInterval(-3_000),
            lastUser: "Init app",
            kind: .conversation,
            firstUser: "初始化待办应用",
            touchedFiles: ["package.json"],
            endedWithError: false
        )
        let ideSummary = SessionRecord(
            tool: "cursor",
            id: "ide-1",
            cwd: "/tmp/todo-app",
            startedAt: nil,
            modified: now,
            lastUser: "Cursor 工作区活动",
            kind: .workspaceSummary
        )

        let project = makeProject(
            path: "/tmp/todo-app",
            displayName: "todo-app",
            dirtyCount: 3,
            ahead: 1,
            stacks: [StackGroup(key: "fe", label: "前端", items: ["React", "Vite"])],
            run: RunConfig(command: "npm run dev", port: 3000, previewURL: nil),
            sessions: [s2, s1, ideSummary]
        )

        let plainResult = HandoffCardBuilder.build(
            project: project,
            sessionLimit: 1,
            copyMode: .plain,
            now: now
        )

        XCTAssertEqual(plainResult.includedSessionCount, 1)
        XCTAssertEqual(plainResult.redactedCount, 2)
        XCTAssertTrue(plainResult.markdown.contains("# 项目接力：todo-app"))
        XCTAssertTrue(plainResult.markdown.contains("React / Vite"))
        XCTAssertTrue(plainResult.markdown.contains("`npm run dev`"))
        XCTAssertTrue(plainResult.markdown.contains("有 3 个改动还没存成版本"))
        XCTAssertTrue(plainResult.markdown.contains("加上拖拽排序"))
        XCTAssertTrue(plainResult.markdown.contains("src/App.jsx, src/TodoList.jsx"))
        XCTAssertTrue(plainResult.markdown.contains("报错结束"))
        XCTAssertFalse(plainResult.markdown.contains("Cursor 工作区活动"))
        XCTAssertFalse(plainResult.markdown.contains("初始化待办应用"))
        XCTAssertFalse(plainResult.markdown.contains("sk-proj-"))
        XCTAssertFalse(plainResult.markdown.contains("ghp_1234"))

        let proResult = HandoffCardBuilder.build(
            project: project,
            sessionLimit: 3,
            copyMode: .pro,
            now: now
        )
        XCTAssertEqual(proResult.includedSessionCount, 2)
        XCTAssertTrue(proResult.markdown.contains("3 个文件未提交"))

        let truncated = HandoffCardBuilder.build(
            project: project,
            sessionLimit: 3,
            copyMode: .plain,
            maxCharacters: 120,
            now: now
        )
        XCTAssertLessThanOrEqual(truncated.characterCount, 120)
        XCTAssertTrue(truncated.markdown.hasSuffix("…（已截断）"))
    }

    private func makeProject(
        path: String,
        displayName: String,
        dirtyCount: Int,
        ahead: Int,
        stacks: [StackGroup],
        run: RunConfig?,
        sessions: [SessionRecord]
    ) -> RepoProject {
        RepoProject(
            path: path,
            name: displayName,
            displayName: displayName,
            group: "网页",
            recent: Date(),
            branch: "main",
            lastCommit: nil,
            dirtyCount: dirtyCount,
            changes: ChangeStats(tracked: dirtyCount, untracked: 0, total: dirtyCount),
            ahead: ahead,
            behind: 0,
            weekly: [:],
            stacks: stacks,
            size: .empty,
            cleanup: .empty,
            run: run,
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
            port: .stopped
        )
    }
}
