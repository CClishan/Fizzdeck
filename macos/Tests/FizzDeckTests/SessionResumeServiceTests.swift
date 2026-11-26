import XCTest
@testable import FizzDeck

final class SessionResumeServiceTests: XCTestCase {
    func testFallbackCommandEscapesSpacesAndQuotes() {
        let session = SessionRecord(
            tool: "codex",
            id: "abc-123",
            cwd: "/tmp/my 'project' dir",
            startedAt: nil,
            modified: Date(),
            lastUser: nil
        )

        let fallback = SessionResumeService.fallbackCommand(for: session, projectPath: "/tmp/fallback")
        XCTAssertEqual(fallback, "cd '/tmp/my '\\''project'\\'' dir' && codex resume abc-123")
    }

    func testLaunchScriptKeepsShellOpenOnFailure() {
        let script = TerminalLauncher.launchScriptContents(
            cwd: "/tmp/work dir",
            command: "claude --resume sess-9",
            scriptPath: "/tmp/run.command"
        )

        XCTAssertTrue(script.contains("cd '/tmp/work dir'"))
        XCTAssertTrue(script.contains("claude --resume sess-9"))
        XCTAssertTrue(script.contains("if [ $status -ne 0 ]; then"))
        XCTAssertTrue(script.contains("exec \"${SHELL:-/bin/zsh}\" -l"))
        XCTAssertTrue(script.contains("rm -f '/tmp/run.command'"))
    }
}
