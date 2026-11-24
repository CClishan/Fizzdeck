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

    func testIgnoresCodexDesktopAppServer() {
        let command = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/codex app-server --listen stdio://"
        XCTAssertFalse(SessionProcessService.matches(command, session: codex))
    }

    func testIgnoresArgumentsThatOnlyMentionResume() {
        let command = "grep codex resume 01a20cb9-cfa6-7e42-be3a-5f1072992852"
        XCTAssertFalse(SessionProcessService.matches(command, session: codex))
    }

    func testEndsDedicatedCLIProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(
            at: executable,
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/yes")
        )

        let process = Process()
        process.executableURL = executable
        process.arguments = ["resume", codex.id]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let result = await SessionProcessService.end(codex)

        XCTAssertTrue(result.success, result.message)
        XCTAssertFalse(process.isRunning)
    }
}
