import XCTest
@testable import FizzDeck

final class LightweightProjectCheckTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckL0-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runGit(_ args: [String], in dir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testDetectsMissingStaleDependenciesAndUnignoredEnv() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try runGit(["init"], in: dir)
        try "{\"name\":\"demo\"}\n".write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "API_KEY=secret123456\n".write(to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let first = await LightweightProjectCheckService.check(directory: dir, copyMode: .plain)
        XCTAssertEqual(Set(first.map(\.kind)), Set([.missingDependencies, .unignoredEnvFile]))

        // Add node_modules older than package.json, and ignore .env
        let nm = dir.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        let oldDate = Date(timeIntervalSinceNow: -120)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: nm.path)
        try ".env\n".write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let second = await LightweightProjectCheckService.check(directory: dir, copyMode: .plain)
        XCTAssertEqual(second.map(\.kind), [.staleDependencies])

        // Update node_modules timestamp -> all clean
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: nm.path)
        let third = await LightweightProjectCheckService.check(directory: dir, copyMode: .plain)
        XCTAssertTrue(third.isEmpty)
    }

    func testRuleBasedCommitMessageUsesRecentIntentOrFilesAndRedactsSecrets() {
        let now = Date()
        let recent = SessionRecord(
            tool: "claude",
            id: "s1",
            cwd: "/tmp/demo",
            startedAt: nil,
            modified: now.addingTimeInterval(-300),
            lastUser: "fallback",
            firstUser: "加上拖拽排序 sk-proj-1234567890abcdefghij"
        )
        let projectWithSession = makeProject(sessions: [recent])
        let msg1 = CommitMessageGenerator.ruleBased(
            project: projectWithSession,
            changedFiles: ["src/App.tsx"],
            now: now
        )
        XCTAssertTrue(msg1.hasPrefix("更新：加上拖拽排序"))
        XCTAssertFalse(msg1.contains("sk-proj-"))

        let projectNoSession = makeProject(sessions: [])
        let msg2 = CommitMessageGenerator.ruleBased(
            project: projectNoSession,
            changedFiles: ["src/A.swift", "src/B.swift", "src/C.swift", "src/D.swift"],
            now: now
        )
        XCTAssertEqual(msg2, "更新 4 个文件：A.swift, B.swift, C.swift 等")

        let msg3 = CommitMessageGenerator.ruleBased(
            project: projectNoSession,
            changedFiles: [],
            copyMode: .plain,
            now: now
        )
        XCTAssertEqual(msg3, "保存当前进度")
    }

    private func makeProject(sessions: [SessionRecord]) -> RepoProject {
        RepoProject(
            path: "/tmp/demo",
            name: "demo",
            displayName: "demo",
            group: "网页",
            recent: Date(),
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
                detected: [],
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
