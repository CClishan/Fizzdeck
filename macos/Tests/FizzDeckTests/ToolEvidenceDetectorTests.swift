import XCTest
@testable import FizzDeck

final class ToolEvidenceDetectorTests: XCTestCase {
    func testDetectsWorkspaceMarkersAndCwdEvidenceWithSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckToolEvidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let realProject = root.appendingPathComponent("real-project", isDirectory: true)
        try FileManager.default.createDirectory(at: realProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: realProject.appendingPathComponent(".cursor", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "rules".write(
            to: realProject.appendingPathComponent(".windsurfrules"),
            atomically: true,
            encoding: .utf8
        )
        try "# Gemini".write(
            to: realProject.appendingPathComponent("GEMINI.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: realProject.appendingPathComponent(".trae", isDirectory: true),
            withIntermediateDirectories: true
        )

        let symlinkProject = root.appendingPathComponent("link-project", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkProject, withDestinationURL: realProject)

        let index = ToolEvidenceIndex(toolCwds: [
            .codex: [PathTools.canonical(symlinkProject.path)],
            .grok: [PathTools.canonical(realProject.path)],
        ])

        let detected = ToolEvidenceDetector.detect(directory: realProject, index: index)
        XCTAssertTrue(detected.contains(.codex))
        XCTAssertTrue(detected.contains(.grok))
        XCTAssertTrue(detected.contains(.cursor))
        XCTAssertTrue(detected.contains(.trae))
        XCTAssertTrue(detected.contains(.windsurf))
        XCTAssertTrue(detected.contains(.gemini))
        XCTAssertFalse(detected.contains(.claude))
    }

    func testBuildsGrokCwdIndexFromNestedSessionDirectory() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckGrokEvidence-\(UUID().uuidString)")
        let project = home.appendingPathComponent("Projects/beta", isDirectory: true)
        let encodedCwd = project.path.replacingOccurrences(of: "/", with: "%2F")
        let session = home
            .appendingPathComponent(".grok/sessions", isDirectory: true)
            .appendingPathComponent(encodedCwd, isDirectory: true)
            .appendingPathComponent("019b0000-grok-acceptance", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try "{}".write(
            to: session.appendingPathComponent("chat_history.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let index = ToolEvidenceIndex.build(homeDirectory: home)
        let detected = ToolEvidenceDetector.detect(
            directory: project,
            entryNames: [],
            index: index
        )

        XCTAssertTrue(detected.contains(.grok))
    }

    func testBuildsGeminiCwdIndexFromProjectRoot() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckGeminiEvidence-\(UUID().uuidString)")
        let project = home.appendingPathComponent("Projects/gamma", isDirectory: true)
        let projectRoot = home
            .appendingPathComponent(".gemini/tmp/gamma-slug", isDirectory: true)
        let chats = projectRoot.appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try project.path.write(
            to: projectRoot.appendingPathComponent(".project_root"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"sessionId":"gamma-session","kind":"main"}
        {"type":"user","content":"检查项目"}
        """.write(
            to: chats.appendingPathComponent("session-gamma.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let index = ToolEvidenceIndex.build(homeDirectory: home)
        let detected = ToolEvidenceDetector.detect(
            directory: project,
            entryNames: [],
            index: index
        )

        XCTAssertTrue(detected.contains(.gemini))
    }
}
