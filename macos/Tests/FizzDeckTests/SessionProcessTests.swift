import XCTest
@testable import FizzDeck

final class SessionProcessTests: XCTestCase {
    private let codex = SessionRecord(
        tool: "codex",
        id: "01a20cb9-cfa6-7e42-be3a-5f1072992852",
        cwd: "/tmp/project",
        startedAt: nil,
        modified: Date(),
        lastUser: nil
    )

    private let claude = SessionRecord(
        tool: "claude",
        id: "7d8c1f0e-session",
        cwd: "/tmp/project",
        startedAt: nil,
        modified: Date(),
        lastUser: nil
    )

    private let grok = SessionRecord(
        tool: "grok",
        id: "019a9f2c-grok-session",
        cwd: "/tmp/project",
        startedAt: nil,
        modified: Date(),
        lastUser: nil
    )

    private let gemini = SessionRecord(
        tool: "gemini",
        id: "gemini-session-9",
        cwd: "/tmp/project",
        startedAt: nil,
        modified: Date(),
        lastUser: nil
    )

    func testMatchesOnlyExactResumeCommands() {
        let processes = """
          101 /usr/local/bin/codex resume 01a20cb9-cfa6-7e42-be3a-5f1072992852
          102 /usr/local/bin/codex resume 01a20cb9-cfa6-7e42-be3a-5f1072992852-extra
          103 /Applications/ChatGPT.app/Contents/Resources/codex-cli/codex app-server --listen stdio://
          104 node /usr/local/bin/claude --resume 7d8c1f0e-session
          105 node /usr/local/bin/claude --resume 7d8c1f0e-session-extra
        """

        let result = SessionProcessService.parse(
            processList: processes,
            sessions: [codex, claude]
        )

        XCTAssertEqual(result[codex.stableID], [101])
        XCTAssertEqual(result[claude.stableID], [104])
    }

    func testMatchesGrokResumeForms() {
        let processes = """
          106 /usr/local/bin/grok -r 019a9f2c-grok-session
          107 /usr/local/bin/grok --resume=019a9f2c-grok-session
          108 /usr/local/bin/grok --resume 019a9f2c-grok-session-extra
        """

        let result = SessionProcessService.parse(
            processList: processes,
            sessions: [grok]
        )

        XCTAssertEqual(result[grok.stableID], [106, 107])
    }

    func testIgnoresCodexDesktopAppServer() {
        let command = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/codex app-server --listen stdio://"
        XCTAssertFalse(SessionProcessService.matches(command, session: codex))
    }

    func testMatchesGeminiResumeForms() {
        let processes = """
          201 /opt/homebrew/bin/gemini --resume gemini-session-9
          202 /opt/homebrew/bin/gemini -r gemini-session-9
          203 /opt/homebrew/bin/gemini --resume=gemini-session-9
          204 /opt/homebrew/bin/gemini --resume gemini-session-9-extra
          205 /opt/homebrew/bin/gemini --session-id gemini-session-9
        """

        let result = SessionProcessService.parse(
            processList: processes,
            sessions: [gemini]
        )

        XCTAssertEqual(result[gemini.stableID], [201, 202, 203])
    }

    func testIgnoresArgumentsThatOnlyMentionResume() {
        let command = "grep codex resume 01a20cb9-cfa6-7e42-be3a-5f1072992852"
        XCTAssertFalse(SessionProcessService.matches(command, session: codex))
    }

    func testParseDetailedCapturesTTYAndCwdNonResumeProcesses() {
        let processes = """
          101 ttys003 /usr/local/bin/codex resume 01a20cb9-cfa6-7e42-be3a-5f1072992852
          202 ttys005 /usr/local/bin/claude --continue
          303 ??      /Applications/ChatGPT.app/Contents/Resources/codex-cli/codex app-server --listen stdio://
        """

        let result = SessionProcessService.parseDetailed(
            processList: processes,
            sessions: [codex, claude],
            cwdByPID: [202: "/tmp/project", 303: "/tmp/project"],
            projectPath: "/tmp/project"
        )

        XCTAssertEqual(result[codex.stableID]?.first?.pid, 101)
        XCTAssertEqual(result[codex.stableID]?.first?.tty, "/dev/ttys003")
        XCTAssertEqual(result[codex.stableID]?.first?.exactMatch, true)

        XCTAssertEqual(result[claude.stableID]?.first?.pid, 202)
        XCTAssertEqual(result[claude.stableID]?.first?.tty, "/dev/ttys005")
        XCTAssertEqual(result[claude.stableID]?.first?.exactMatch, false)
    }

    func testEndsDedicatedCLIProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = SessionRecord(tool: "codex", id: UUID().uuidString, cwd: directory.path,
                                    startedAt: nil, modified: Date(), lastUser: nil)
        let executable = directory.appendingPathComponent("codex")
        // ps must see the fixture's executable name, independent of symlink resolution.
        try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/yes")).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let process = Process()
        process.executableURL = executable
        process.arguments = ["resume", session.id]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let deadline = ContinuousClock.now + .seconds(3)
        var matches = await SessionProcessService.liveProcesses(for: [session])[session.stableID] ?? []
        while matches.isEmpty && process.isRunning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(80))
            matches = await SessionProcessService.liveProcesses(for: [session])[session.stableID] ?? []
        }
        guard matches == [process.processIdentifier] else {
            let row = await Shell.output("/bin/ps", ["-ww", "-p", String(process.processIdentifier), "-o", "command="])
            return XCTFail("Expected only the test child; matches: \(matches), fixture command: \(row ?? "missing")")
        }
        let result = await SessionProcessService.end(session)

        XCTAssertTrue(result.success, result.message)
        XCTAssertFalse(process.isRunning)
    }
}
