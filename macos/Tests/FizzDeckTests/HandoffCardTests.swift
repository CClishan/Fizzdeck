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

    func testDefaultCardContinuesLatestGoalAndKeepsCopyModeAndLengthLimit() {
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
        XCTAssertEqual(plainResult.redactedCount, 1)
        XCTAssertTrue(plainResult.markdown.contains("# 项目接力：todo-app"))
        XCTAssertTrue(plainResult.markdown.contains("React / Vite"))
        XCTAssertTrue(plainResult.markdown.contains("`npm run dev`"))
        XCTAssertTrue(plainResult.markdown.contains("有 3 个改动还没存成版本"))
        XCTAssertTrue(plainResult.markdown.contains("当前目标（最近对话）：Continue touch support"))
        XCTAssertTrue(plainResult.markdown.contains("加上拖拽排序"))
        XCTAssertTrue(plainResult.markdown.contains("src/App.jsx, src/TodoList.jsx"))
        XCTAssertTrue(plainResult.markdown.contains("报错结束"))
        XCTAssertTrue(plainResult.markdown.contains("建议下一步：先复查最近对话报告的失败"))
        XCTAssertFalse(plainResult.markdown.contains("Cannot find module"))
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

    func testRepairChoosesNewestDatedEvidenceAndRedactsLocalOutput() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let failedSession = SessionRecord(
            tool: "codex", id: "failed", cwd: nil, startedAt: nil, modified: now.addingTimeInterval(-120),
            touchedFiles: ["Sources/Feed.swift"], lastError: "Session diagnostic", endedWithError: true
        )
        let newerWorkspaceSummary = SessionRecord(
            tool: "cursor", id: "workspace", cwd: nil, startedAt: nil, modified: now,
            kind: .workspaceSummary, lastError: "Unrelated IDE diagnostic", endedWithError: true
        )
        let newerConversation = SessionRecord(
            tool: "claude", id: "conversation", cwd: nil, startedAt: nil, modified: now,
            lastError: "Undated previous diagnostic"
        )
        let project = makeProject(stacks: [StackGroup(key: "swift", label: "Swift", items: ["SwiftUI"])],
                                  sessions: [newerWorkspaceSummary, failedSession, newerConversation])
        let fixtureTail = "fizzdeck-log-fixture-tail"
        let fixtureValue = String(repeating: "a", count: 760) + fixtureTail
        let local = HandoffFailure(
            source: "测试", timestamp: now.addingTimeInterval(-60),
            output: "Sources/Feed.swift:12: error: missing decoder\nTEST_API_KEY=\(fixtureValue)", exitCode: 1
        )

        let repair = HandoffCardBuilder.build(project: project, scenario: .fixError, localFailure: local, now: now)
        XCTAssertTrue(repair.markdown.contains("测试 · 1 分钟前 · 退出码 1"))
        XCTAssertTrue(repair.markdown.contains("技术栈：SwiftUI"))
        XCTAssertTrue(repair.markdown.contains("Sources/Feed.swift:12: error: missing decoder"))
        XCTAssertTrue(repair.markdown.contains("TEST_API_KEY=[已脱敏]"))
        XCTAssertFalse(repair.markdown.contains(fixtureTail))
        XCTAssertFalse(repair.markdown.contains("Session diagnostic"))
        XCTAssertFalse(repair.markdown.contains("Undated previous diagnostic"))
        XCTAssertEqual(repair.redactedCount, 1)

        let olderLocal = HandoffFailure(source: "开发服务", timestamp: now.addingTimeInterval(-180), output: "Older log")
        let sessionRepair = HandoffCardBuilder.build(
            project: project, scenario: .fixError, sessionLimit: 1, localFailure: olderLocal, now: now
        )
        XCTAssertTrue(sessionRepair.markdown.contains("Session diagnostic"))
        XCTAssertTrue(sessionRepair.markdown.contains("报错会话记录的文件：Sources/Feed.swift"))
        XCTAssertFalse(sessionRepair.markdown.contains("Older log"))
        XCTAssertFalse(sessionRepair.markdown.contains("Unrelated IDE diagnostic"))
    }

    @MainActor
    func testManagedFailuresUseCompletionTimeAndBelongToTheSelectedProject() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let project = makeProject(path: "/tmp/fizzdeck-handoff-\(UUID().uuidString)")
        let actions = ProjectActions()
        actions.testRuns[project.path] = TestRunState(
            path: project.path, status: .failed, output: "Test failure", startedAt: now.addingTimeInterval(-30),
            duration: 5, exitCode: 1, command: "swift test", logPath: ""
        )

        let script = ProjectScript(id: "build", name: "build", command: "make build", source: .make)
        actions.scriptRuns["same"] = ScriptRunState(
            key: "same", projectPath: project.path, script: script, status: .failed,
            output: "Managed failure", startedAt: now.addingTimeInterval(-120), duration: 110,
            exitCode: 2, logPath: ""
        )
        actions.scriptRuns["other"] = ScriptRunState(
            key: "other", projectPath: project.path + "-other", script: script, status: .failed,
            output: "Another project's failure", startedAt: now, duration: 2, exitCode: 2, logPath: ""
        )

        let paths = [project.path, project.path + "-other"]
        let latest = await HandoffCardBuilder.loadLocalFailure(for: project, actions: actions, projectPaths: paths)
        XCTAssertEqual(latest?.source, "受管脚本：build")
        XCTAssertEqual(latest?.timestamp, now.addingTimeInterval(-10))
        XCTAssertEqual(latest?.output, "Managed failure")

        actions.scriptRuns["same"]?.status = .stopped
        let latestTest = await HandoffCardBuilder.loadLocalFailure(for: project, actions: actions, projectPaths: paths)
        XCTAssertEqual(latestTest?.source, "测试")
        XCTAssertEqual(latestTest?.output, "Test failure")
    }

    func testDevExcerptNeverMixesRunsOrGuessesWhenTheHeaderIsMissing() {
        let log = """
        --- 2026-11-28T01:00:00Z npm run dev
        Previous run failure

        --- 2026-11-28T02:00:00Z npm run dev
        Current run failure
        """
        XCTAssertEqual(HandoffCardBuilder.currentDevOutput(in: log, command: "npm run dev"), "Current run failure")
        XCTAssertNil(HandoffCardBuilder.currentDevOutput(in: "An undated log tail", command: "npm run dev"))
        XCTAssertNil(HandoffCardBuilder.currentDevOutput(in: log + "\n--- 2026-11-28T03:00:00Z npm start", command: "npm run dev"))
    }

    @MainActor
    func testAmbiguousDevLogDoesNotExposeTheTailEmbeddedInStatus() async {
        let name = "fizzdeck-handoff-\(UUID().uuidString)"
        let project = makeProject(path: "/tmp/left/\(name)",
                                  run: RunConfig(command: "npm run dev", port: 3000, previewURL: nil))
        let actions = ProjectActions()
        actions.messages[project.path] = "启动失败：无法确认来源的日志内容"

        let failure = await HandoffCardBuilder.loadLocalFailure(
            for: project, actions: actions, projectPaths: [project.path, "/tmp/right/\(name)"]
        )
        XCTAssertEqual(failure?.source, "开发服务")
        XCTAssertNil(failure?.timestamp)
        XCTAssertEqual(failure?.output, "")
    }

    func testNotesUseKnownBackgroundAndCommandsAndRedactBeforeCopy() {
        let session = SessionRecord(tool: "codex", id: "error", cwd: nil, startedAt: nil, modified: Date(),
                                    lastError: "Private diagnostic", endedWithError: true)
        var project = makeProject(run: RunConfig(command: "  npm run dev  ", port: 3000, previewURL: nil),
                                  sessions: [session])
        project.intro = ProjectIntro(text: "本地任务面板。", source: "README.md")
        let fixtureValue = ["fizzdeck", "notes", "fixture"].joined(separator: "-")
        project.note = "TEST_API_KEY=\(fixtureValue)"
        project.test = TestCommand(label: "测试", command: "npm test")

        let notes = HandoffCardBuilder.build(project: project, scenario: .notes)
        XCTAssertTrue(notes.markdown.contains("# 交接说明：todo-app"))
        XCTAssertTrue(notes.markdown.contains("本地任务面板"))
        XCTAssertTrue(notes.markdown.contains("启动命令：`npm run dev`"))
        XCTAssertTrue(notes.markdown.contains("测试命令：`npm test`"))
        XCTAssertTrue(notes.markdown.contains("项目备注：TEST_API_KEY=[已脱敏]"))
        XCTAssertFalse(notes.markdown.contains(fixtureValue))
        XCTAssertFalse(notes.markdown.contains("Private diagnostic"))
        XCTAssertEqual(notes.includedSessionCount, 0)
    }

    func testMissingDataAndFailureWithoutOutputAreReportedSeparately() {
        var project = makeProject()
        project.branch = nil
        project.gitLoadState = .pending
        let resume = HandoffCardBuilder.build(project: project)
        XCTAssertTrue(resume.markdown.contains("未取得可确认的 Git 工作区状态"))
        XCTAssertTrue(resume.markdown.contains("先确认要接着做的目标"))

        let repair = HandoffCardBuilder.build(project: project, scenario: .fixError)
        XCTAssertTrue(repair.markdown.contains("未找到可核对的失败日志或对话报错"))
        XCTAssertTrue(repair.markdown.contains("文件：暂无可关联记录"))

        let fail = HandoffFailure(source: "开发服务", timestamp: nil, output: "", exitCode: 1)
        let noOutput = HandoffCardBuilder.build(project: project, scenario: .fixError, localFailure: fail)
        XCTAssertTrue(noOutput.markdown.contains("时间未记录 · 退出码 1"))
        XCTAssertTrue(noOutput.markdown.contains("有失败记录，但没有可核对的报错输出"))

        let notes = HandoffCardBuilder.build(project: project, scenario: .notes)
        XCTAssertTrue(notes.markdown.contains("未记录项目简介或备注"))
        XCTAssertTrue(notes.markdown.contains("未识别到启动命令"))
        XCTAssertTrue(notes.markdown.contains("未识别到测试命令"))
    }

    func testOldAIPolishPromptUsesResumeContextWithoutDiagnosticOutput() {
        let session = SessionRecord(tool: "codex", id: "error", cwd: nil, startedAt: nil, modified: Date(),
                                    lastUser: "完善导入", lastError: "LOCAL-ONLY-DIAGNOSTIC", endedWithError: true)
        let project = makeProject(sessions: [session])
        let prompt = SummaryPromptBuilder.handoffPrompt(project: project)
        XCTAssertTrue(prompt.userPrompt.contains("完善导入"))
        XCTAssertFalse(prompt.userPrompt.contains("LOCAL-ONLY-DIAGNOSTIC"))
        XCTAssertTrue(HandoffCardBuilder.build(project: project, scenario: .fixError).markdown.contains("LOCAL-ONLY-DIAGNOSTIC"))
    }

    private func makeProject(
        path: String = "/tmp/todo-app",
        displayName: String = "todo-app",
        dirtyCount: Int = 0,
        ahead: Int = 0,
        stacks: [StackGroup] = [],
        run: RunConfig? = nil,
        sessions: [SessionRecord] = []
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
