import XCTest
@testable import FizzDeck

final class SessionIndexTests: XCTestCase {
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
