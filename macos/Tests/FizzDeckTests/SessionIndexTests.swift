import XCTest
@testable import FizzDeck

final class SessionIndexTests: ChineseInterfaceTestCase {
    func testSummarySortsAndGroupsSessions() {
        let target = URL(fileURLWithPath: "/tmp/fizzdeck-session")
        let start = Date(timeIntervalSince1970: 1_000)
        let index = [
            record(
                tool: "codex",
                id: "codex-old",
                cwd: target.path,
                modified: start,
                lastUser: "old request"
            ),
            record(
                tool: "claude",
                id: "claude-new",
                cwd: target.path,
                modified: start.addingTimeInterval(30),
                lastUser: "claude request"
            ),
            record(
                tool: "codex",
                id: "codex-new",
                cwd: target.path,
                modified: start.addingTimeInterval(20),
                lastUser: "new request"
            ),
            record(
                tool: "codex",
                id: "other-project",
                cwd: "/tmp/elsewhere",
                modified: start.addingTimeInterval(60),
                lastUser: "other request"
            ),
        ]

        let summary = SessionIndex.summary(for: target, in: index)

        XCTAssertEqual(summary.sessionCount, 3)
        XCTAssertEqual(
            summary.recentSessions.map(\.stableID),
            ["claude:claude-new", "codex:codex-new", "codex:codex-old"]
        )
        XCTAssertEqual(summary.detected, ["claude", "codex"])
        XCTAssertEqual(summary.byTool.map(\.tool), ["claude", "codex"])

        let codex = summary.byTool.first { $0.tool == "codex" }
        XCTAssertEqual(codex?.sessionCount, 2)
        XCTAssertEqual(codex?.lastSessionID, "codex-new")
        XCTAssertEqual(codex?.lastUserMessage, "new request")

        XCTAssertEqual(summary.lastTool, "claude")
        XCTAssertEqual(summary.lastSessionID, "claude-new")
        XCTAssertEqual(summary.lastUserMessage, "claude request")
    }

    func testSummaryNormalizesWorkingDirectory() {
        let target = URL(fileURLWithPath: "/tmp/fizzdeck-session")
        let index = [
            record(
                tool: "codex",
                id: "normalized",
                cwd: "/tmp/fizzdeck-session/./nested/..",
                modified: Date(timeIntervalSince1970: 1_000)
            ),
            record(
                tool: "claude",
                id: "missing-cwd",
                cwd: nil,
                modified: Date(timeIntervalSince1970: 1_100)
            ),
            record(
                tool: "claude",
                id: "different",
                cwd: "/tmp/fizzdeck-session-other",
                modified: Date(timeIntervalSince1970: 1_200)
            ),
        ]

        let summary = SessionIndex.summary(for: target, in: index)

        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.recentSessions.map(\.stableID), ["codex:normalized"])
    }

    func testResumeCommands() {
        let date = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            record(tool: "codex", id: "abc", cwd: nil, modified: date).resumeCommand,
            "codex resume abc"
        )
        XCTAssertEqual(
            record(tool: "claude", id: "def", cwd: nil, modified: date).resumeCommand,
            "claude --resume def"
        )
        XCTAssertEqual(
            record(tool: "grok", id: "xyz", cwd: nil, modified: date).resumeCommand,
            "grok -r xyz"
        )
        XCTAssertEqual(
            record(tool: "gemini", id: "gem-1", cwd: nil, modified: date).resumeCommand,
            "gemini --resume gem-1"
        )
        XCTAssertNil(
            record(tool: "other", id: "ghi", cwd: nil, modified: date).resumeCommand
        )
    }

    func testScanLinesFromEndHandlesChunkBoundaries() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "one\ntwo\nthree\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var visited: [String] = []
        let found = FileTools.scanLinesFromEnd(in: url, chunkBytes: 5, maxBytes: 100) { line in
            visited.append(line)
            return line == "two"
        }

        XCTAssertTrue(found)
        XCTAssertEqual(visited, ["three", "two"])
    }

    func testIncrementalCacheHitAndInvalidationOnEdit() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckSessionCache-\(UUID().uuidString)")
        let sessionsDir = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let cacheFile = home.appendingPathComponent("session-cache.json")
        let rollout = sessionsDir.appendingPathComponent("rollout-test.jsonl")
        let initial = """
        {"timestamp":"2026-11-25T10:00:00Z","type":"session_meta","payload":{"id":"sess-1","cwd":"/tmp/demo"}}
        {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"text":"first prompt"}]}}}
        """
        try initial.write(to: rollout, atomically: true, encoding: .utf8)

        let first = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.lastUser, "first prompt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))

        // Cache hit keeps parsed data; lightweight cwd map reads it fast
        let cwdMap = SessionIndex.buildLightweightCwdMap(homeDirectory: home, cacheFile: cacheFile)
        XCTAssertEqual(cwdMap["codex"], [PathTools.canonical("/tmp/demo")])

        // Modify file size & mtime -> invalidates cache
        let updated = initial + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"item\":{\"type\":\"UserMessage\",\"content\":[{\"text\":\"second prompt\"}]}}}\n"
        try updated.write(to: rollout, atomically: true, encoding: .utf8)
        let second = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        XCTAssertEqual(second.first?.lastUser, "second prompt")
    }

    func testCodexUsageAndModelParsing() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckCodexUsage-\(UUID().uuidString)")
        let sessionsDir = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let rollout = sessionsDir.appendingPathComponent("rollout-usage.jsonl")
        let content = """
        {"timestamp":"2026-11-25T10:00:00Z","type":"session_meta","payload":{"id":"codex-usage","cwd":"/tmp/demo"}}
        {"timestamp":"2026-11-25T10:00:01Z","type":"turn_context","payload":{"model":"gpt-5.1"}}
        {"timestamp":"2026-11-25T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":200,"output_tokens":300,"reasoning_output_tokens":50,"total_tokens":1500}}}}
        """
        try content.write(to: rollout, atomically: true, encoding: .utf8)

        let records = SessionIndex.build(
            homeDirectory: home,
            cacheFile: home.appendingPathComponent("session-cache.json")
        )
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.model, "gpt-5.1")
        XCTAssertEqual(record.usage?.totalTokens, 1500)
        XCTAssertEqual(record.usage?.cachedInputTokens, 200)
        XCTAssertNotNil(record.costUSD)
        XCTAssertEqual(record.costIsEstimate, true)
    }

    func testClaudeCostStateParsing() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckClaudeUsage-\(UUID().uuidString)")
        let project = home.appendingPathComponent(".claude/projects/-tmp-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let file = project.appendingPathComponent("claude-usage.jsonl")
        let content = """
        {"type":"user","cwd":"/tmp/demo","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}
        {"type":"assistant","message":{"model":"claude-opus-4-1","usage":{"input_tokens":100,"output_tokens":40,"cache_read_input_tokens":20,"cache_creation_input_tokens":10,"output_tokens_details":{"thinking_tokens":5}}}}
        {"type":"cost-state","totalCostUSD":0.42,"hasUnknownModelCost":false,"modelUsage":{"claude-opus-4-1":{"inputTokens":100,"outputTokens":40,"thinkingTokens":5,"cacheReadInputTokens":20,"cacheCreationInputTokens":10}}}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let records = SessionIndex.build(
            homeDirectory: home,
            cacheFile: home.appendingPathComponent("session-cache.json")
        )
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.tool, "claude")
        XCTAssertEqual(record.usage?.totalTokens, 170)
        XCTAssertEqual(record.costUSD, 0.42)
        XCTAssertEqual(record.costIsEstimate, false)
        XCTAssertEqual(record.model, "claude-opus-4-1")
    }

    func testGrokSessionParsing() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckGrokUsage-\(UUID().uuidString)")
        let encoded = "%2Ftmp%2Fdemo"
        let session = home
            .appendingPathComponent(".grok/sessions/\(encoded)/grok-session", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let chat = """
        {"type":"system","content":"system"}
        {"type":"user","content":[{"type":"text","text":"实际需求"}]}
        """
        try chat.write(
            to: session.appendingPathComponent("chat_history.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let updates = """
        {"method":"session/update","params":{"_meta":{"totalTokens":2345}}}
        """
        try updates.write(
            to: session.appendingPathComponent("updates.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let events = """
        {"type":"turn_started","model_id":"grok-4.6"}
        """
        try events.write(
            to: session.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let records = SessionIndex.build(
            homeDirectory: home,
            cacheFile: home.appendingPathComponent("session-cache.json")
        )
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.tool, "grok")
        XCTAssertEqual(record.id, "grok-session")
        XCTAssertEqual(record.cwd, "/tmp/demo")
        XCTAssertEqual(record.lastUser, "实际需求")
        XCTAssertEqual(record.usage?.totalTokens, 2345)
        XCTAssertEqual(record.model, "grok-4.6")
        XCTAssertEqual(record.resumeCommand, "grok -r grok-session")
    }

    func testPricingCatalogOnlyEstimatesKnownModels() {
        let usage = TokenUsage(
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            outputTokens: 100_000,
            totalTokens: 1_100_000
        )
        XCTAssertEqual(
            PricingCatalog.estimate(model: "gpt-5.1", usage: usage) ?? 0,
            2.25,
            accuracy: 0.001
        )
        XCTAssertNil(PricingCatalog.estimate(model: "router/custom-model", usage: usage))
    }

    func testGeminiSessionParsingAndIncrementalCache() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckGemini-\(UUID().uuidString)")
        let projectPath = home.appendingPathComponent("Projects/gemini-app", isDirectory: true)
        let projectRoot = home
            .appendingPathComponent(".gemini/tmp/gemini-app-slug", isDirectory: true)
        let chats = projectRoot.appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try """
        {"projects":{"\(projectPath.path)":"gemini-app-slug"}}
        """.write(
            to: home.appendingPathComponent(".gemini/projects.json"),
            atomically: true,
            encoding: .utf8
        )
        try projectPath.path.write(
            to: projectRoot.appendingPathComponent(".project_root"),
            atomically: true,
            encoding: .utf8
        )

        let chat = chats.appendingPathComponent("session-2026-11-26T10-00-00.jsonl")
        let initial = """
        {"sessionId":"gemini-session-1","projectHash":"hash","startTime":"2026-11-26T10:00:00.000Z","lastUpdated":"2026-11-26T10:05:00.000Z","summary":"Gemini summary","kind":"main"}
        {"id":"m1","timestamp":"2026-11-26T10:00:01Z","type":"user","content":"帮我检查构建"}
        {"id":"m2","timestamp":"2026-11-26T10:00:02Z","type":"gemini","content":[{"text":"好的"}],"model":"gemini-2.5-pro","tokens":{"input":100,"output":50,"cached":10,"thoughts":5,"tool":0,"total":165}}
        """
        try initial.write(to: chat, atomically: true, encoding: .utf8)

        let cacheFile = home.appendingPathComponent("session-cache.json")
        let first = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        let gemini = try XCTUnwrap(first.first { $0.tool == "gemini" })

        XCTAssertEqual(gemini.id, "gemini-session-1")
        XCTAssertEqual(gemini.cwd, projectPath.path)
        XCTAssertEqual(gemini.lastUser, "帮我检查构建")
        XCTAssertEqual(gemini.model, "gemini-2.5-pro")
        XCTAssertEqual(gemini.usage?.totalTokens, 165)
        XCTAssertEqual(gemini.usage?.reasoningOutputTokens, 5)
        XCTAssertEqual(gemini.resumeCommand, "gemini --resume gemini-session-1")
        XCTAssertNil(gemini.costUSD)

        let cwdMap = SessionIndex.buildLightweightCwdMap(homeDirectory: home, cacheFile: cacheFile)
        XCTAssertTrue(cwdMap["gemini"]?.contains(PathTools.canonical(projectPath.path)) == true)

        let updated = initial + """

        {"id":"m3","timestamp":"2026-11-26T10:06:00Z","type":"user","content":"继续补测试"}
        """
        try updated.write(to: chat, atomically: true, encoding: .utf8)
        let second = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        let refreshed = try XCTUnwrap(second.first { $0.tool == "gemini" })
        XCTAssertEqual(refreshed.lastUser, "继续补测试")
    }

    func testIDEWorkspaceSessionIsReadOnlyAndHasNoResumeCommand() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckIDE-\(UUID().uuidString)")
        let projectPath = "/tmp/fizzdeck-ide-demo-\(UUID().uuidString)"
        let workspaceDir = home.appendingPathComponent(
            "Library/Application Support/Cursor/User/workspaceStorage/abc123",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try """
        {"folder":"file://\(projectPath)"}
        """.write(
            to: workspaceDir.appendingPathComponent("workspace.json"),
            atomically: true,
            encoding: .utf8
        )
        let database = workspaceDir.appendingPathComponent("state.vscdb")
        try runSQLite([
            "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB);",
            "INSERT INTO ItemTable (key, value) VALUES ('workbench.panel.aichat.view.aichat.chatdata', '{\"tabs\":[{\"chatTitle\":\"实现会话恢复\"}]}');",
        ], database: database)

        let cacheFile = home.appendingPathComponent("session-cache.json")
        let records = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        let cursor = try XCTUnwrap(records.first { $0.tool == "cursor" })

        XCTAssertEqual(cursor.id, "abc123")
        XCTAssertEqual(cursor.cwd, projectPath)
        XCTAssertTrue(cursor.isWorkspaceSummary)
        XCTAssertEqual(cursor.lastUser, "实现会话恢复")
        XCTAssertNil(cursor.resumeCommand)

        let map = SessionIndex.buildLightweightCwdMap(homeDirectory: home, cacheFile: cacheFile)
        XCTAssertTrue(map["cursor"]?.contains(PathTools.canonical(projectPath)) == true)

        let evidence = ToolEvidenceIndex.build(homeDirectory: home)
        XCTAssertTrue(evidence.toolCwds[.cursor]?.contains(PathTools.canonical(projectPath)) == true)
    }

    func testIDEWorkspaceSurvivesCorruptDatabase() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckIDECorrupt-\(UUID().uuidString)")
        let workspaceDir = home.appendingPathComponent(
            "Library/Application Support/Windsurf/User/workspaceStorage/broken",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try """
        {"folder":"file:///tmp/fizzdeck-windsurf-demo"}
        """.write(
            to: workspaceDir.appendingPathComponent("workspace.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data("not a sqlite database".utf8).write(
            to: workspaceDir.appendingPathComponent("state.vscdb")
        )

        let records = SessionIndex.build(
            homeDirectory: home,
            cacheFile: home.appendingPathComponent("session-cache.json")
        )
        let windsurf = try XCTUnwrap(records.first { $0.tool == "windsurf" })

        XCTAssertEqual(windsurf.lastUser, "Windsurf 工作区活动")
        XCTAssertNil(windsurf.resumeCommand)
    }

    func testBuildsAndParsesDeepSeekHarnessSession() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-dsh-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let sessionsDir = home.appendingPathComponent(".dsh/storages/session_projcache/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let payload: [String: Any] = [
            "version": 7,
            "record": [
                "identity": [
                    "createdAt": 1_795_592_198_000,
                    "cwd": "/tmp/fizzdeck-dsh-demo",
                ],
                "rows": [
                    "title": ["val": "整合 DeepSeek Harness 用量"],
                    "modelSelection": [
                        "val": [
                            "lastUsed": [
                                "provider": "magpie",
                                "model": "tokeplus-ds/deepseek/deepseek-v4.1-flash-1017",
                            ]
                        ]
                    ],
                    "tokenUsage": [
                        "val": [
                            "totals": [
                                "uncachedInputTokens": 20_000,
                                "cacheReadTokens": 100_000,
                                "cacheWriteTokens": 0,
                                "outputTokens": 5_000,
                            ]
                        ]
                    ],
                    "timeContext": [
                        "val": [
                            "lastMessageTime": 1_795_593_000_000
                        ]
                    ],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: sessionsDir.appendingPathComponent("session-dsh-1.json"))

        let cacheFile = home.appendingPathComponent("session-cache.json")
        let records = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        let dsh = try XCTUnwrap(records.first { $0.tool == "deepseek" })

        XCTAssertEqual(dsh.id, "session-dsh-1")
        XCTAssertEqual(dsh.cwd, "/tmp/fizzdeck-dsh-demo")
        XCTAssertEqual(dsh.lastUser, "整合 DeepSeek Harness 用量")
        XCTAssertEqual(dsh.model, "tokeplus-ds/deepseek/deepseek-v4.1-flash-1017")
        XCTAssertEqual(dsh.usage?.inputTokens, 120_000)
        XCTAssertEqual(dsh.usage?.cachedInputTokens, 100_000)
        XCTAssertEqual(dsh.usage?.outputTokens, 5_000)
        XCTAssertEqual(dsh.usage?.totalTokens, 125_000)
        XCTAssertEqual(dsh.costIsEstimate, true)
        XCTAssertGreaterThan(dsh.costUSD ?? 0, 0)

        let cwdMap = SessionIndex.buildLightweightCwdMap(homeDirectory: home, cacheFile: cacheFile)
        XCTAssertTrue(cwdMap["deepseek"]?.contains(PathTools.canonical("/tmp/fizzdeck-dsh-demo")) == true)
    }

    func testBuildsAndParsesAgyConversationWithChildTokenRollup() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("fizzdeck-agy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let agyRoot = home.appendingPathComponent(".gemini/antigravity", isDirectory: true)
        let parentLogDir = agyRoot.appendingPathComponent("brain/agy-parent-1/.system_generated/logs", isDirectory: true)
        let childLogDir = agyRoot.appendingPathComponent("brain/agy-child-1/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: parentLogDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childLogDir, withIntermediateDirectories: true)

        let dbURL = agyRoot.appendingPathComponent("conversation_summaries.db")
        try runSQLite([
            """
            CREATE TABLE conversation_summaries (
                conversation_id text PRIMARY KEY,
                title text NOT NULL DEFAULT "",
                last_modified_time datetime NOT NULL,
                workspace_uris text NOT NULL,
                parent_conversation_id text NOT NULL DEFAULT ""
            );
            """,
            """
            INSERT INTO conversation_summaries VALUES (
                'agy-parent-1',
                'Optimize FizzDeck UI',
                '2026-11-26 09:00:00+00:00',
                '["file:///tmp/fizzdeck-agy-demo"]',
                ''
            );
            """,
            """
            INSERT INTO conversation_summaries VALUES (
                'agy-child-1',
                '',
                '2026-11-26 08:55:00+00:00',
                '["file:///tmp/fizzdeck-agy-demo"]',
                'agy-parent-1'
            );
            """,
        ], database: dbURL)

        let parentTranscript = """
        {"type":"USER_INPUT","created_at":"2026-11-26T08:40:00Z","content":"check UI"}
        {"type":"PLANNER_RESPONSE","created_at":"2026-11-26T08:41:00Z","model":"claude-opus-5-5-medium","input_tokens":10000,"cache_read_tokens":20000,"output_tokens":500}
        """
        let childTranscript = """
        {"type":"PLANNER_RESPONSE","created_at":"2026-11-26T08:50:00Z","model":"gemini-4-hydrogen-tiered-high","input_tokens":5000,"cache_read_tokens":10000,"output_tokens":250}
        """
        try parentTranscript.write(to: parentLogDir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
        try childTranscript.write(to: childLogDir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let cacheFile = home.appendingPathComponent("session-cache.json")
        let records = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        let agyRecords = records.filter { $0.tool == "agy" }

        XCTAssertEqual(agyRecords.count, 1)
        let agy = try XCTUnwrap(agyRecords.first)
        XCTAssertEqual(agy.id, "agy-parent-1")
        XCTAssertEqual(agy.cwd, "/tmp/fizzdeck-agy-demo")
        XCTAssertEqual(agy.lastUser, "Optimize FizzDeck UI")
        XCTAssertEqual(agy.usage?.inputTokens, 45_000)
        XCTAssertEqual(agy.usage?.cachedInputTokens, 30_000)
        XCTAssertEqual(agy.usage?.outputTokens, 750)
        XCTAssertEqual(agy.usage?.totalTokens, 45_750)
        XCTAssertEqual(agy.costIsEstimate, true)
        XCTAssertGreaterThan(agy.costUSD ?? 0, 0)
        XCTAssertNil(agy.resumeCommand)

        let cwdMap = SessionIndex.buildLightweightCwdMap(homeDirectory: home, cacheFile: cacheFile)
        XCTAssertTrue(cwdMap["agy"]?.contains(PathTools.canonical("/tmp/fizzdeck-agy-demo")) == true)
    }

    func testCodexRichSessionExtractionAndErrorRecovery() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckCodexRich-\(UUID().uuidString)")
        let sessionsDir = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let failingRollout = sessionsDir.appendingPathComponent("rollout-fail.jsonl")
        let failingContent = """
        {"timestamp":"2026-11-26T10:00:00Z","type":"session_meta","payload":{"id":"codex-fail","cwd":"/tmp/demo-app"}}
        {"timestamp":"2026-11-26T10:00:10Z","type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"text":"加上拖拽排序"}]}}}
        {"timestamp":"2026-11-26T10:01:00Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\\n*** Update File: /tmp/demo-app/src/App.jsx\\n*** Add File: src/TodoList.jsx\\n*** Update File: /tmp/demo-app/src/App.jsx\\n*** End Patch"}}
        {"timestamp":"2026-11-26T10:02:00Z","type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"text":"顺便跑一下测试"}]}}}
        {"timestamp":"2026-11-26T10:03:00Z","type":"response_item","payload":{"type":"function_call","name":"write_file","arguments":"{\\"file_path\\":\\"/tmp/demo-app/src/Helper.js\\"}"}}
        {"timestamp":"2026-11-26T10:05:00Z","type":"response_item","payload":{"type":"function_call_output","output":"{\\"output\\":\\"Error: Missing script test sk-proj-1234567890abcdefghij\\",\\"metadata\\":{\\"exit_code\\":1}}"}}
        """
        try failingContent.write(to: failingRollout, atomically: true, encoding: .utf8)

        let recoveredRollout = sessionsDir.appendingPathComponent("rollout-recovered.jsonl")
        let recoveredContent = """
        {"timestamp":"2026-11-26T11:00:00Z","type":"session_meta","payload":{"id":"codex-ok","cwd":"/tmp/demo-app"}}
        {"timestamp":"2026-11-26T11:00:05Z","type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"text":"修复构建"}]}}}
        {"timestamp":"2026-11-26T11:01:00Z","type":"response_item","payload":{"type":"function_call_output","output":"{\\"output\\":\\"Error: build failed\\",\\"metadata\\":{\\"exit_code\\":1}}"}}
        {"timestamp":"2026-11-26T11:02:00Z","type":"response_item","payload":{"type":"function_call_output","output":"{\\"output\\":\\"Build succeeded\\",\\"metadata\\":{\\"exit_code\\":0}}"}}
        """
        try recoveredContent.write(to: recoveredRollout, atomically: true, encoding: .utf8)

        let records = SessionIndex.build(
            homeDirectory: home,
            cacheFile: home.appendingPathComponent("session-cache.json")
        )
        let failed = try XCTUnwrap(records.first { $0.id == "codex-fail" })
        XCTAssertEqual(failed.firstUser, "加上拖拽排序")
        XCTAssertEqual(failed.lastUser, "顺便跑一下测试")
        XCTAssertEqual(failed.primaryIntent, "加上拖拽排序")
        XCTAssertEqual(failed.turnCount, 2)
        XCTAssertEqual(failed.touchedFiles, ["src/App.jsx", "src/TodoList.jsx", "src/Helper.js"])
        XCTAssertEqual(failed.endedWithError, true)
        XCTAssertTrue(failed.lastError?.contains("Missing script test") == true)
        XCTAssertFalse(failed.lastError?.contains("sk-proj-") == true)
        XCTAssertEqual(failed.durationMinutes, 5)

        let recovered = try XCTUnwrap(records.first { $0.id == "codex-ok" })
        XCTAssertNotNil(recovered.lastError)
        XCTAssertEqual(recovered.endedWithError, false)
    }

    func testClaudeRichSessionExtractionAndLegacyDecode() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckClaudeRich-\(UUID().uuidString)")
        let project = home.appendingPathComponent(".claude/projects/-tmp-claude-app", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let file = project.appendingPathComponent("claude-rich.jsonl")
        let content = """
        {"timestamp":"2026-11-26T09:00:00Z","type":"user","cwd":"/tmp/claude-app","message":{"role":"user","content":[{"type":"text","text":"创建登录页"}]}}
        {"timestamp":"2026-11-26T09:01:00Z","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/claude-app/src/Login.tsx"}}]}}
        {"timestamp":"2026-11-26T09:02:00Z","type":"user","cwd":"/tmp/claude-app","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"1","is_error":false,"content":"ok"}]}}
        {"timestamp":"2026-11-26T09:03:00Z","type":"user","cwd":"/tmp/claude-app","message":{"role":"user","content":[{"type":"text","text":"运行构建检查"}]}}
        {"timestamp":"2026-11-26T09:04:00Z","type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/App.tsx"}}]}}
        {"timestamp":"2026-11-26T09:05:00Z","type":"user","cwd":"/tmp/claude-app","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"2","is_error":true,"content":"TypeScript compile error in Login.tsx"}]}}
        {"timestamp":"2026-11-26T09:06:00Z","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"构建失败了，请检查类型。"}]}}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let cacheFile = home.appendingPathComponent("session-cache.json")
        // Seed a stale v4 cache to verify v5 invalidation rebuilds rich fields
        let staleV4 = """
        {"version":4,"entries":{"stale":{"mtime":0,"fileSize":0,"record":{"tool":"claude","id":"claude-rich","cwd":"/tmp/claude-app","modified":0}}}}
        """
        try staleV4.write(to: cacheFile, atomically: true, encoding: .utf8)

        let records = SessionIndex.build(homeDirectory: home, cacheFile: cacheFile)
        let claude = try XCTUnwrap(records.first { $0.id == "claude-rich" })
        XCTAssertNotNil(claude.startedAt)
        XCTAssertEqual(claude.firstUser, "创建登录页")
        XCTAssertEqual(claude.lastUser, "运行构建检查")
        XCTAssertEqual(claude.turnCount, 2)
        XCTAssertEqual(claude.touchedFiles, ["src/Login.tsx", "src/App.tsx"])
        XCTAssertEqual(claude.lastError, "TypeScript compile error in Login.tsx")
        XCTAssertEqual(claude.endedWithError, true)
        XCTAssertEqual(claude.durationMinutes, 6)

        // Legacy JSON missing the 6 new fields decodes cleanly
        let legacyJSON = """
        {"tool":"codex","id":"legacy-1","cwd":"/tmp/a","modified":1700000000,"lastUser":"old"}
        """
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.firstUser)
        XCTAssertEqual(decoded.touchedFiles, [])
        XCTAssertNil(decoded.lastError)
        XCTAssertFalse(decoded.endedWithError)
        XCTAssertNil(decoded.turnCount)
        XCTAssertNil(decoded.durationMinutes)
        XCTAssertNil(decoded.agentTimeSeconds)
        XCTAssertNil(decoded.testResult)
        XCTAssertEqual(decoded.primaryIntent, "old")
    }

    func testCodexUsesPairedTurnEventsAndLinksPTYTestExit() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".codex/sessions/rollout-metrics.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let first = #"""
        {"timestamp":"2026-11-26T10:00:00Z","type":"session_meta","payload":{"id":"metrics","cwd":"/tmp/app"}}
        {"timestamp":"2026-11-26T10:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"one"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"回归验证"}]}}
        {"type":"event_msg","payload":{"type":"user_message","message":"回归验证"}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"swift","arguments":"{\"cmd\":\"swift test --filter Panel\"}"}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"swift","output":"Chunk ID: abcd\nWall time: 0.10 seconds\nProcess exited with code 1\nFinal output:\nProcess exited with code 0"}}
        {"timestamp":"2026-11-26T10:00:04Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"one","duration_ms":2500}}
        """#
        try first.write(to: file, atomically: true, encoding: .utf8)
        func read() throws -> SessionRecord { try XCTUnwrap(SessionIndex.build(homeDirectory: home, cacheFile: nil).first) }
        let failed = try read()
        XCTAssertEqual(failed.agentTimeSeconds, 2)
        XCTAssertEqual(failed.turnCount, 1)
        XCTAssertEqual(failed.testResult, .failed)

        let second = #"""
        {"timestamp":"2026-11-26T11:00:00Z","type":"event_msg","payload":{"type":"turn_started","turn_id":"two"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"继续"}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"node","arguments":"{\"cmd\":\"npx --yes vitest run\"}"}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"node","output":"Chunk ID: abcd\nWall time: 0.1 seconds\nProcess running with session ID 17\nOutput:\nProcess exited with code 1"}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"unrelated","output":{"exit_code":1}}}
        {"type":"response_item","payload":{"type":"function_call","name":"write_stdin","call_id":"poll","arguments":"{\"session_id\":17,\"chars\":\"\"}"}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"poll","output":{"chunk_id":"abcd","exit_code":0,"output":"passed"}}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"other","arguments":{"cmd":"echo 'vitest run'"}}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"other","output":{"chunk_id":"efgh","session_id":17}}}
        {"type":"response_item","payload":{"type":"function_call","name":"write_stdin","call_id":"other-poll","arguments":{"session_id":17}}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"other-poll","output":{"chunk_id":"efgh","exit_code":1}}}
        {"timestamp":"2026-11-26T11:00:07Z","type":"event_msg","payload":{"type":"turn_complete","turn_id":"two"}}
        """#
        try (first + "\n" + second).write(to: file, atomically: true, encoding: .utf8)
        let passed = try read()
        XCTAssertEqual(passed.agentTimeSeconds, 9)
        XCTAssertEqual(passed.durationMinutes, 60)
        XCTAssertEqual(passed.turnCount, 2)
        XCTAssertEqual(passed.testResult, .passed)
    }

    func testCodexNoTestRequiresCompleteLogAndReparsesWave4CacheOnce() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".codex/sessions/rollout-old-cache.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let transcript = #"""
        {"type":"session_meta","payload":{"id":"old-cache","cwd":"/tmp/app"}}
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"one"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"写下 swift test 这几个字"}}
        {"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"echo","arguments":{"cmd":"echo 'swift test; npm test'"}}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"echo","output":{"exit_code":0,"output":"swift test; npm test"}}}
        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"one","duration_ms":4200}}
        """#
        try transcript.write(to: file, atomically: true, encoding: .utf8)
        let cache = home.appendingPathComponent("cache.json")
        let stamp = try FileManager.default.attributesOfItem(atPath: file.path)
        let date = try XCTUnwrap(stamp[.modificationDate] as? Date)
        try FileTools.writeJSON(["version": 5, "entries": [PathTools.normalize(file.path): [
            "mtime": date.timeIntervalSince1970, "fileSize": transcript.utf8.count,
            "record": ["tool": "codex", "id": "old-cache", "cwd": "/tmp/app", "modified": 0, "lastUser": "old cache"],
        ]]], to: cache)

        let rebuilt = try XCTUnwrap(SessionIndex.build(homeDirectory: home, cacheFile: cache).first)
        XCTAssertEqual(rebuilt.lastUser, "写下 swift test 这几个字")
        XCTAssertEqual(rebuilt.agentTimeSeconds, 4)
        XCTAssertEqual(rebuilt.testResult, .notRun)
        let upgradedCache = try Data(contentsOf: cache)
        XCTAssertEqual(SessionIndex.build(homeDirectory: home, cacheFile: cache), [rebuilt])
        XCTAssertEqual(try Data(contentsOf: cache), upgradedCache)

        let active = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"two"}}"#
        try (transcript + "\n" + active).write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(SessionIndex.build(homeDirectory: home, cacheFile: cache).first?.testResult)
        try (transcript + "\n{" ).write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(SessionIndex.build(homeDirectory: home, cacheFile: nil).first?.testResult)
    }

    func testClaudeUsesDurationMarkersAndBashResultForTheMatchingCall() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/-tmp-app/metrics.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let first = #"""
        {"type":"user","cwd":"/tmp/app","message":{"role":"user","content":"运行 pytest"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"bash-1","input":{"command":"python3 -m pytest"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"mismatched","content":"Exit code 0"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"bash-1","is_error":true,"content":"Exit code 1\nFAILED example.py"}]},"toolUseResult":"Error: Exit code 1\nFAILED example.py"}
        {"timestamp":"2026-11-26T10:00:03Z","type":"system","subtype":"turn_duration","uuid":"duration-one","durationMs":3200}
        {"timestamp":"2026-11-26T10:00:03Z","type":"system","subtype":"turn_duration","uuid":"duration-one","durationMs":3200}
        """#
        try first.write(to: file, atomically: true, encoding: .utf8)
        func read() throws -> SessionRecord { try XCTUnwrap(SessionIndex.build(homeDirectory: home, cacheFile: nil).first) }
        let failed = try read()
        XCTAssertEqual(failed.agentTimeSeconds, 3)
        XCTAssertEqual(failed.turnCount, 1)
        XCTAssertEqual(failed.testResult, .failed)

        let second = #"""
        {"type":"user","cwd":"/tmp/app","message":{"role":"user","content":"再试一次"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"bash-2","input":{"command":"go test ./..."}}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"bash-2","input":{"command":"go test ./..."}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"bash-2","content":"ok"}]},"toolUseResult":{"stdout":"ok","stderr":"","interrupted":false,"isImage":false}}
        {"timestamp":"2026-11-26T12:00:02Z","type":"system","subtype":"turn_duration","uuid":"duration-two","durationMs":2400}
        """#
        let full = first + "\n" + second
        try full.write(to: file, atomically: true, encoding: .utf8)
        let passed = try read()
        XCTAssertEqual(passed.agentTimeSeconds, 5)
        XCTAssertEqual(passed.turnCount, 2)
        XCTAssertEqual(passed.testResult, .passed)

        let rejected = #"""
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"bash-3","input":{"command":"npm test"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"bash-3","is_error":true,"content":"The user denied this tool call"}]}}
        """#
        try (full + "\n" + rejected).write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(try read().testResult)
    }

    func testTestCommandMatcherAcceptsCommonWrappersAndRejectsAmbiguousExit() throws {
        for command: Any in ["swift test", "pytest -q", "jest", "vitest run", "cargo +stable test", "go test ./...",
                             "npm test", "make -C fixtures test", "npm exec -- jest", "pnpm exec vitest run",
                             "CI=true npx --yes vitest run", ["/bin/zsh", "-lc", "uv run pytest"]] {
            var tests = SessionLogMetrics.Tests()
            let attempt = try XCTUnwrap(tests.start(command), "\(command)")
            tests.finish(attempt, exitCode: 0)
            XCTAssertEqual(tests.result(complete: true), .passed, "\(command)")
        }
        for command in ["echo 'swift test'", "printf 'npm test'", "grep 'cargo test' README", "jest --listTests",
                        "npm -v", "pytest --collect-only", "make -n test", "git diff > output.txt", "echo hi # ; go test"] {
            var tests = SessionLogMetrics.Tests()
            XCTAssertNil(tests.start(command), command)
            XCTAssertEqual(tests.result(complete: true), .notRun, command)
        }
        for (command, code) in [("swift test | tail -5", 0), ("false && pytest", 1), ("cd missing && npm test", 1), ("jest", 127)] {
            var tests = SessionLogMetrics.Tests()
            let attempt = try XCTUnwrap(tests.start(command), command)
            tests.finish(attempt, exitCode: code)
            XCTAssertNil(tests.result(complete: true), command)
        }
    }

    private func runSQLite(_ statements: [String], database: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path] + statements
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func record(
        tool: String,
        id: String,
        cwd: String?,
        modified: Date,
        lastUser: String? = nil
    ) -> SessionRecord {
        SessionRecord(
            tool: tool,
            id: id,
            cwd: cwd,
            startedAt: nil,
            modified: modified,
            lastUser: lastUser
        )
    }
}
