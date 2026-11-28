import XCTest
@testable import FizzDeck

final class MenuBarRemoteTests: ChineseInterfaceTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testStatusLabelOnlyWakesForADatedExpiryAndDoesNotRearmIt() {
        let starred = project("starred")
        XCTAssertNil(MenuBarLabel.nextExpiry(in: [starred], mode: .plain, after: now) { _, _ in nil })

        var recent = project("recent", starred: false)
        recent.recent = now.addingTimeInterval(-7 * 86_400 + 60)
        let snoozeEnd = now.addingTimeInterval(20)
        let focusEnd = now.addingTimeInterval(61)
        func deadline(at date: Date) -> Date? {
            MenuBarLabel.nextExpiry(in: [recent], mode: .plain, after: date) { _, kind in
                kind == .testFailed ? AttentionPreference(snoozedUntil: snoozeEnd) : nil
            }
        }
        XCTAssertEqual(deadline(at: now), snoozeEnd)
        XCTAssertEqual(deadline(at: now.addingTimeInterval(1)), snoozeEnd)
        XCTAssertEqual(deadline(at: snoozeEnd), focusEnd)
        XCTAssertNil(deadline(at: focusEnd))
    }

    func testTerminalOnlyResumeNeverFallsBackToAnInstalledDesktop() {
        for runtime: RuntimeAvailability in [.available, .missing, .broken("fixture")] {
            let capability = ToolResumeCapability(cli: runtime, desktopAvailable: true)
            XCTAssertFalse(capability.shouldUseDesktop(for: .cli))
            XCTAssertEqual(capability.shouldUseDesktop(for: .auto), !runtime.isAvailable)
        }
    }

    func testTopThreeUseFocusThenLiveAIAndActualConversationDates() {
        let live = project("live", sessions: [session("old", age: 600)])
        let readOnly = project("read-only", starred: false, sessions: [session("new", tool: "cursor", age: 10)])
        let recent = project("recent", sessions: [session("middle", age: 60)])
        let ide = project("ide", sessions: [session("workspace", age: 0, kind: .workspaceSummary)])
        var gitOnly = project("git")
        gitOnly.recent = now
        let outside = project("outside", starred: false, sessions: [session("idle", age: 40 * 86_400)])

        let rows = ranked([outside, ide, recent, gitOnly, readOnly, live], active: [live.path, outside.path])

        XCTAssertEqual(rows.map(\.id), [live.path, readOnly.path, recent.path])
        XCTAssertTrue(rows[0].isAIActive)
        XCTAssertNil(rows[1].resumableSession)
    }

    func testEqualDatesAndNamesStayStableAcrossTheFocusCutoff() {
        let projects = (0..<9).map { index in
            project("same-\(index)", name: "同名", starred: false, sessions: [session("chat", age: 30)])
        }
        let paths: Set<String> = [projects[7].path, projects[8].path]
        let expected = [projects[7].path, projects[0].path, projects[1].path]
        for order in [projects, Array(projects.reversed())] {
            XCTAssertEqual(ranked(order, active: paths).map(\.id), expected)
        }
    }

    func testResumeSkipsNewerInvalidRecordsAndUsesStableIDForTimeTies() throws {
        let records = [
            session("older", age: 100), session("workspace", age: 0, kind: .workspaceSummary),
            session("read-only", tool: "opencode", age: 0), session("", age: 0),
            session("  ", age: 0), session("--help", age: 0), session("two words", age: 0),
            session("b", tool: "claude", age: 20), session("a", tool: "claude", age: 20),
            session("new", age: 20),
        ]
        for order in [records, Array(records.reversed())] {
            let row = try XCTUnwrap(ranked([project("app", sessions: order)]).first)
            XCTAssertEqual(row.resumableSession?.stableID, "claude:a")
        }
    }

    func testNoValidSessionKeepsTheFocusedProjectWithoutAResumeTarget() throws {
        let records = [session("cursor", tool: "cursor", age: 0), session("", age: 0),
                       session("summary", age: 0, kind: .workspaceSummary)]
        for sessions in [[], records] {
            let item = project("focus", sessions: sessions)
            let row = try XCTUnwrap(ranked([item], active: [item.path]).first)
            XCTAssertEqual(row.id, item.path)
            XCTAssertNil(row.resumableSession)
        }
        XCTAssertTrue(ranked([project("idle", starred: false)]).isEmpty)
    }

    @MainActor
    func testThreeCopyActionsWriteDistinctRedactedCardsWithoutAWindow() throws {
        let value = ["private", "menu", "fixture"].joined(separator: "-")
        let assignment = "TEST_API_KEY=\(value)"
        var conversation = session("goal", age: 30)
        conversation.lastUser = "修复导入 \(assignment)"
        conversation.touchedFiles = ["Import.swift"]
        conversation.lastError = "旧的会话报错"
        conversation.endedWithError = true
        var app = project("app", sessions: [conversation])
        app.intro = ProjectIntro(text: "离线索引工具", source: "README.md")
        app.note = "交接人备注 \(assignment)"
        app.run = RunConfig(command: "swift run", port: 0, previewURL: nil)
        app.test = TestCommand(label: "测试", command: "swift test")
        let actions = ProjectActions()
        actions.testRuns[app.path] = TestRunState(path: app.path, status: .failed, output: "索引失败 \(assignment)",
                                                  startedAt: now, duration: 1, exitCode: 7, command: "swift test", logPath: "")
        let handoff = MenuBarHandoff()
        var cards: [HandoffCardScenario: String] = [:]
        handoff.copy(app, copyMode: .plain, actions: actions) { text in
            cards[.resume] = text
            return true
        }
        XCTAssertEqual(handoff.feedback.current?.title, "接力卡已复制")
        for scenario in [HandoffCardScenario.fixError, .notes] {
            handoff.copy(app, scenario: scenario, copyMode: .plain, actions: actions) { text in
                XCTAssertNil(cards.updateValue(text, forKey: scenario))
                return true
            }
            XCTAssertEqual(handoff.feedback.current?.title, "接力卡已复制")
            XCTAssertNil(handoff.feedback.current?.subtitle)
        }

        let resume = try XCTUnwrap(cards[.resume])
        let repair = try XCTUnwrap(cards[.fixError])
        let notes = try XCTUnwrap(cards[.notes])
        for text in [resume, repair, notes] {
            XCTAssertTrue(text.contains("TEST_API_KEY=[已脱敏]"))
            XCTAssertFalse(text.contains(value))
        }
        XCTAssertTrue(resume.hasPrefix("# 项目接力：app"))
        XCTAssertTrue(resume.contains("当前目标（最近对话）：修复导入"))
        XCTAssertTrue(resume.contains("Import.swift"))
        XCTAssertFalse(resume.contains("索引失败"))
        XCTAssertTrue(repair.hasPrefix("# 报错求助：app"))
        XCTAssertTrue(repair.contains("退出码 7"))
        XCTAssertTrue(repair.contains("索引失败"))
        XCTAssertFalse(repair.contains("旧的会话报错"))
        XCTAssertTrue(notes.hasPrefix("# 交接说明：app"))
        XCTAssertTrue(notes.contains("离线索引工具"))
        XCTAssertTrue(notes.contains("启动命令：`swift run`"))
        XCTAssertTrue(notes.contains("测试命令：`swift test`"))
        XCTAssertFalse(notes.contains("修复导入"))
        XCTAssertFalse(notes.contains("索引失败"))
    }

    @MainActor
    func testRepairUsesOnlySelectedProjectEvidenceAndReportsARejectedWrite() {
        var record = session("error", age: 30)
        record.lastError = "本项目对话报错"
        record.endedWithError = true
        let app = project("app", sessions: [record])
        let other = project("other")
        let actions = ProjectActions()
        let script = ProjectScript(id: "build", name: "build", command: "make build", source: .make)
        actions.testRuns[app.path] = TestRunState(path: other.path, status: .failed, output: "其他项目私有测试",
                                                  startedAt: now, duration: 1, exitCode: 1, command: "swift test", logPath: "")
        actions.scriptRuns["other"] = ScriptRunState(key: "other", projectPath: other.path, script: script, status: .failed,
                                                    output: "其他项目私有日志", startedAt: now, duration: 1, exitCode: 1, logPath: "")
        actions.messages[app.path] = "启动失败：不能确认归属的日志"
        let handoff = MenuBarHandoff()
        for accepted in [true, false] {
            handoff.copy(app, scenario: .fixError, copyMode: .plain, actions: actions) { text in
                XCTAssertTrue(text.contains("本项目对话报错"))
                XCTAssertFalse(text.contains("其他项目私有日志"))
                XCTAssertFalse(text.contains("其他项目私有测试"))
                XCTAssertFalse(text.contains("不能确认归属的日志"))
                return accepted
            }
            XCTAssertEqual(handoff.feedback.messages.map(\.title), [accepted ? "接力卡已复制" : "复制失败"])
        }
    }

    private func ranked(_ projects: [RepoProject], active: Set<String> = []) -> [MenuBarRemoteProject] {
        MenuBarRemoteProject.top(in: ProjectFocusPolicy.partition(projects: projects, now: now), activeAIPaths: active)
    }

    private func session(_ id: String, tool: String = "codex", age: TimeInterval,
                         kind: SessionRecordKind = .conversation) -> SessionRecord {
        SessionRecord(tool: tool, id: id, cwd: nil, startedAt: nil, modified: now.addingTimeInterval(-age), kind: kind)
    }

    private func project(_ id: String, name: String? = nil, starred: Bool = true, sessions: [SessionRecord] = []) -> RepoProject {
        var summary = SessionSummary.empty
        summary.recentSessions = sessions
        summary.lastSessionAt = sessions.map(\.modified).max()
        return RepoProject(path: "/menu-fixtures/\(id)", name: id, displayName: name ?? id, group: "", recent: nil,
                           branch: nil, lastCommit: nil, dirtyCount: 0, changes: .zero, ahead: 0, behind: 0, weekly: [:],
                           stacks: [], size: .empty, cleanup: .empty, run: nil, sessions: summary, intro: .empty, artwork: nil,
                           test: nil, starred: starred, color: nil, note: "", port: .noPreview)
    }
}
