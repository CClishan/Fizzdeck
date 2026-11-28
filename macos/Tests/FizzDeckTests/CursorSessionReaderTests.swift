import Foundation
import XCTest
@testable import FizzDeck

final class CursorSessionReaderTests: XCTestCase {
    private let sessionID = "65d3d59d-8dc0-4b18-8763-59f890e8fe7c"

    func testNestedTranscriptFeedsProjectChineseSearchAndFileHistory() async throws {
        let home = try makeHome()
        let projectURL = home.appendingPathComponent("projects/工作台 Demo")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let alias = home.appendingPathComponent("project-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: projectURL)
        try FileManager.default.createSymbolicLink(at: projectURL.appendingPathComponent("external"), withDestinationURL: home)
        let source = transcript(in: home, slug: "trusted-workspace", nested: true)
        try writeMetadata(["workspacePath": alias.absoluteString], to: marker(in: home, slug: "trusted-workspace"))

        let diagnostic = "fixture_diagnostic_token_123"
        try writeLines([
            user("<user_query>修复侧栏滚动</user_query>"),
            "{invalid,",
            assistant([
                tool("StrReplace", path: alias.appendingPathComponent("Sources/Panel.swift").absoluteString),
                tool("Write", path: "./Docs/../说明.md"),
                tool("Edit", path: "../other/outside.swift"),
                tool("Write", path: "external/nonexistent.swift"),
                tool("Edit", path: projectURL.absoluteString + "/Sources/Invalid%00.swift"),
                tool("Read", path: "ReadOnly.swift"),
            ]),
            user("<user_query>补上滚动回归测试</user_query>"),
            json(["type": "turn_ended", "status": "error", "error": ["message": "运行失败 API_TOKEN=\(diagnostic)"]]),
        ], to: source)
        let cache = home.appendingPathComponent("fizzdeck-cache.json")
        let records = SessionIndex.build(homeDirectory: home, cacheFile: cache)
        let record = try XCTUnwrap(records.first)
        let projectPath = PathTools.canonical(projectURL.path)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.stableID, "cursor:\(sessionID)")
        XCTAssertEqual(record.kind, .conversation)
        XCTAssertEqual(record.cwd, projectPath)
        XCTAssertEqual(record.primaryIntent, "修复侧栏滚动")
        XCTAssertEqual(record.lastUser, "补上滚动回归测试")
        XCTAssertEqual(record.turnCount, 2)
        XCTAssertNil(record.agentTimeSeconds)
        XCTAssertNil(record.testResult)
        XCTAssertEqual(record.touchedFiles, ["Sources/Panel.swift", "说明.md"])
        XCTAssertTrue(record.endedWithError)
        XCTAssertTrue(record.lastError?.contains("运行失败") == true)
        XCTAssertFalse(record.lastError?.contains(diagnostic) == true)
        XCTAssertNil(record.usage)
        XCTAssertNil(record.resumeCommand)

        let evidence = ToolEvidenceIndex.build(homeDirectory: home, sessionCwdMap: ["cursor": [projectPath]])
        let projects = await RepositoryScanner.scanFast(paths: [projectPath], meta: [:], evidenceIndex: evidence)
        var project = try XCTUnwrap(projects.first)
        XCTAssertTrue(project.detectedTools.contains(.cursor))
        project.sessions = SessionIndex.summary(for: projectURL, in: records)
        XCTAssertEqual(project.sessions.sessionCount, 1)
        let search = SessionSearchIndex(databaseURL: home.appendingPathComponent("search.sqlite"))
        await search.rebuild(from: [project])
        let chinese = await search.search(query: "侧栏滚动", toolFilter: "cursor", errorOnly: true)
        let byFile = await search.sessions(touchingFile: "Sources/Panel.swift", projectPath: project.path)
        XCTAssertEqual(chinese.map(\.sessionStableID), [record.stableID])
        XCTAssertEqual(byFile.map(\.sessionStableID), [record.stableID])
    }

    func testEmptyDamagedAndAssistantOnlyLogsAreIgnoredUntilAUserMessageArrives() throws {
        let home = try makeHome()
        let slug = "trusted"
        let source = transcript(in: home, slug: slug, nested: false)
        try writeMetadata(["workspacePath": home.path], to: marker(in: home, slug: slug))
        let cache = home.appendingPathComponent("cache.json")

        try writeLines([], to: source)
        XCTAssertTrue(SessionIndex.build(homeDirectory: home, cacheFile: cache).isEmpty)
        try writeLines(["{truncated", assistant([tool("Write", path: "x.swift")]), user("<system_reminder>通知")], to: source)
        XCTAssertTrue(SessionIndex.build(homeDirectory: home, cacheFile: cache).isEmpty)
        try writeLines(["{truncated", user("恢复导入")], to: source)
        XCTAssertEqual(SessionIndex.build(homeDirectory: home, cacheFile: cache).map(\.lastUser), ["恢复导入"])
    }

    func testWorkspaceFolderMatchMustBeUniqueAndDoesNotDuplicateSummary() throws {
        let home = try makeHome()
        let first = home.appendingPathComponent("Team-Repo/Client")
        let second = home.appendingPathComponent("Team/Repo-Client")
        let slug = first.path.dropFirst().replacingOccurrences(of: "/", with: "-")
        let source = transcript(in: home, slug: slug, nested: false)
        let cache = home.appendingPathComponent("cache.json")
        try writeLines([user("接上本地对话")], to: source)

        func register(_ folder: URL, id: String) throws {
            let metadata = home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage/\(id)/workspace.json")
            try writeMetadata(["folder": folder.absoluteString], to: metadata)
        }
        try register(first, id: "first")

        let imported = SessionIndex.build(homeDirectory: home, cacheFile: cache)
        XCTAssertEqual(imported.map(\.kind), [.conversation])
        XCTAssertEqual(imported.first?.cwd, PathTools.canonical(first.path))
        let oldStamp = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldStamp], ofItemAtPath: cache.path)
        XCTAssertEqual(SessionIndex.build(homeDirectory: home, cacheFile: cache), imported)
        XCTAssertEqual(FileTools.modificationDate(cache), oldStamp)

        try register(second, id: "second")
        let ambiguous = SessionIndex.build(homeDirectory: home, cacheFile: cache)
        XCTAssertEqual(ambiguous.filter(\.isWorkspaceSummary).count, 2)
        XCTAssertFalse(ambiguous.contains { $0.kind == .conversation })
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("fizzdeck-cursor-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        return home
    }

    private func transcript(in home: URL, slug: String, nested: Bool) -> URL {
        let directory = home.appendingPathComponent(".cursor/projects/\(slug)/agent-transcripts")
        return (nested ? directory.appendingPathComponent(sessionID) : directory).appendingPathComponent("\(sessionID).jsonl")
    }

    private func marker(in home: URL, slug: String) -> URL {
        home.appendingPathComponent(".cursor/projects/\(slug)/.workspace-trusted")
    }

    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func user(_ text: String) throws -> String {
        try json(["role": "user", "message": ["content": [["type": "text", "text": text]]]])
    }

    private func assistant(_ content: [[String: Any]]) throws -> String {
        try json(["role": "assistant", "message": ["content": content]])
    }

    private func tool(_ name: String, path: String) -> [String: Any] {
        ["type": "tool_use", "name": name, "input": ["path": path]]
    }

    private func writeMetadata(_ object: [String: Any], to url: URL) throws {
        try writeLines([json(object)], to: url)
    }

    private func writeLines(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
