import XCTest
@testable import FizzDeck

final class TerminalLauncherTests: XCTestCase {
    func testLaunchScriptQuotesCwdAndCleansUpScript() {
        let script = TerminalLauncher.launchScriptContents(
            cwd: "/tmp/my 'quoted' dir",
            command: "codex resume abc",
            scriptPath: "/tmp/run 'one'.command"
        )

        XCTAssertTrue(script.contains("cd '/tmp/my '\\''quoted'\\'' dir'"))
        XCTAssertTrue(script.contains("rm -f '/tmp/run '\\''one'\\''.command'"))
        XCTAssertTrue(script.contains("codex resume abc"))
        XCTAssertTrue(script.contains("if [ $status -ne 0 ]; then"))
        XCTAssertTrue(script.contains("exec \"${SHELL:-/bin/zsh}\" -l"))
    }

    func testLaunchScriptEscapesCommandEcho() {
        let script = TerminalLauncher.launchScriptContents(
            cwd: "/tmp/work",
            command: "echo \"$HOME\" `whoami`"
        )

        XCTAssertTrue(
            script.contains("echo \"→ echo \\\"\\$HOME\\\" \\`whoami\\`\"")
        )
        XCTAssertTrue(script.contains("\necho \"$HOME\" `whoami`\n"))
    }

    func testTerminalAppleScriptLaunchesByScriptPath() {
        let source = TerminalAppleScript.launch(
            terminal: .terminal,
            scriptPath: "/tmp/a \"b\" \\c.command",
            cwd: "/tmp/work"
        )

        let script = source ?? ""
        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("do script \"exec '/tmp/a \\\"b\\\" \\\\c.command'\""))
        XCTAssertTrue(script.contains("set tabTTY to tty of newTab"))
        XCTAssertTrue(script.contains("return tabTTY & \"|\" & (winID as string)"))
    }

    func testITermAppleScriptWritesLaunchCommand() {
        let source = TerminalAppleScript.launch(
            terminal: .iterm2,
            scriptPath: "/tmp/work/run.command",
            cwd: "/tmp/work"
        )

        let script = source ?? ""
        XCTAssertTrue(script.contains("tell application id \"com.googlecode.iterm2\""))
        XCTAssertTrue(script.contains("create window with default profile"))
        XCTAssertTrue(script.contains("create tab with default profile"))
        XCTAssertTrue(script.contains("write text \"exec '/tmp/work/run.command'\""))
        XCTAssertTrue(script.contains("return tty"))
    }

    func testGhosttyAppleScriptUsesWorkingDirectoryAndCommand() {
        let source = TerminalAppleScript.launch(
            terminal: .ghostty,
            scriptPath: "/tmp/my work/run.command",
            cwd: "/tmp/my \"work\""
        )

        let script = source ?? ""
        XCTAssertTrue(script.contains("tell application id \"com.mitchellh.ghostty\""))
        XCTAssertTrue(script.contains("new surface configuration"))
        XCTAssertTrue(script.contains("initial working directory of surfaceConfig to \"/tmp/my \\\"work\\\"\""))
        XCTAssertTrue(script.contains("command of surfaceConfig to \"/bin/zsh '/tmp/my work/run.command'\""))
        XCTAssertTrue(script.contains("new window with configuration surfaceConfig"))
        XCTAssertTrue(script.contains("try\n"))
        XCTAssertTrue(script.contains("on error\n"))
    }

    func testWarpURLPercentEncodesProjectPath() throws {
        let url = try XCTUnwrap(TerminalLauncher.warpURL(path: "/tmp/my work/项目"))
        XCTAssertEqual(url.scheme, "warp")
        XCTAssertEqual(url.host, "action")
        XCTAssertEqual(url.path, "/new_tab")
        XCTAssertEqual(url.query, "path=/tmp/my%20work/%E9%A1%B9%E7%9B%AE")
        XCTAssertNil(
            TerminalAppleScript.launch(
                terminal: .warp,
                scriptPath: "/tmp/run.command",
                cwd: "/tmp"
            )
        )
    }

    func testInstalledTerminalDetectionUsesBundleLookupThenFallbackPaths() {
        let installed = TerminalLauncher.installedTerminals(
            bundleLookup: { bundleIdentifier in
                switch bundleIdentifier {
                case "com.googlecode.iterm2":
                    return URL(fileURLWithPath: "/Applications/iTerm.app")
                case "com.mitchellh.ghostty":
                    return URL(fileURLWithPath: "/Applications/Ghostty.app")
                default:
                    return nil
                }
            },
            fileExists: { path in
                path == "/System/Applications/Utilities/Terminal.app"
            }
        )

        XCTAssertEqual(installed, [.terminal, .iterm2, .ghostty])
    }

    func testPreferredTerminalFallsBackToTerminalWhenMissing() {
        XCTAssertEqual(
            TerminalLauncher.resolve(preferred: .warp, installed: [.terminal, .ghostty]),
            .terminal
        )
        XCTAssertEqual(
            TerminalLauncher.resolve(preferred: .ghostty, installed: [.terminal, .ghostty]),
            .ghostty
        )
    }

    func testCleanupRemovesOnlyStaleResumeScripts() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(
            "fizzdeck-launcher-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }

        let now = Date()
        let stale = directory.appendingPathComponent("resume-codex-old.command")
        let fresh = directory.appendingPathComponent("resume-codex-fresh.command")
        let unrelated = directory.appendingPathComponent("notes.txt")

        for url in [stale, fresh, unrelated] {
            try Data("#!/bin/zsh\n".utf8).write(to: url)
        }
        try manager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 60 * 60)],
            ofItemAtPath: stale.path
        )
        try manager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fresh.path
        )
        try manager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-48 * 60 * 60)],
            ofItemAtPath: unrelated.path
        )

        let removed = TerminalLauncher.cleanupLaunchers(in: directory, now: now)

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(manager.fileExists(atPath: stale.path))
        XCTAssertTrue(manager.fileExists(atPath: fresh.path))
        XCTAssertTrue(manager.fileExists(atPath: unrelated.path))
    }

    func testCleanupMissingDirectoryIsNoOp() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fizzdeck-missing-\(UUID().uuidString)",
            isDirectory: true
        )

        XCTAssertEqual(TerminalLauncher.cleanupLaunchers(in: directory), 0)
    }

    func testPreferencesRoundTripInIsolatedDefaults() throws {
        let suiteName = "fizzdeck.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(TerminalPreferences.preferredTerminal(defaults: defaults), .terminal)
        TerminalPreferences.setPreferredTerminal(.ghostty, defaults: defaults)
        XCTAssertEqual(TerminalPreferences.preferredTerminal(defaults: defaults), .ghostty)

        XCTAssertEqual(SessionResumePreferences.codexTarget(defaults: defaults), .auto)
        SessionResumePreferences.setCodexTarget(.desktop, defaults: defaults)
        XCTAssertEqual(SessionResumePreferences.codexTarget(defaults: defaults), .desktop)
    }

    func testFocusAppleScriptCoversAllTerminalVariants() {
        let terminalScript = TerminalAppleScript.focus(terminal: .terminal, tty: "/dev/ttys003") ?? ""
        XCTAssertTrue(terminalScript.contains("tell application \"Terminal\""))
        XCTAssertTrue(terminalScript.contains("set targetTTY to \"/dev/ttys003\""))
        XCTAssertTrue(terminalScript.contains("return \"FOCUSED\""))

        let itermScript = TerminalAppleScript.focus(terminal: .iterm2, tty: "/dev/ttys004") ?? ""
        XCTAssertTrue(itermScript.contains("tell application id \"com.googlecode.iterm2\""))
        XCTAssertTrue(itermScript.contains("if tty of s is targetTTY then"))
        XCTAssertTrue(itermScript.contains("select s"))

        XCTAssertNil(TerminalAppleScript.focus(terminal: .ghostty, tty: "/dev/ttys005"))
        XCTAssertNil(TerminalAppleScript.focus(terminal: .warp, tty: "/dev/ttys006"))
    }

    func testAutomationPermissionStoreRoundTripsPerTerminal() throws {
        let suiteName = "fizzdeck.automation.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AutomationPermissionStore.state(for: .terminal, defaults: defaults), .unknown)
        AutomationPermissionStore.record(.granted, for: .terminal, defaults: defaults)
        AutomationPermissionStore.record(.denied, for: .ghostty, defaults: defaults)

        XCTAssertEqual(AutomationPermissionStore.state(for: .terminal, defaults: defaults), .granted)
        XCTAssertEqual(AutomationPermissionStore.state(for: .ghostty, defaults: defaults), .denied)
        XCTAssertEqual(AutomationPermissionStore.state(for: .iterm2, defaults: defaults), .unknown)
    }
}
