import XCTest
@testable import FizzDeck

final class GitServiceTests: XCTestCase {
    func testTrackingCountsUseBehindThenAhead() {
        XCTAssertEqual(
            GitService.trackingCounts("3\t5\n"),
            GitTrackingCounts(behind: 3, ahead: 5)
        )
    }

    func testTrackingCountsHandleZero() {
        XCTAssertEqual(
            GitService.trackingCounts("0 0"),
            GitTrackingCounts(behind: 0, ahead: 0)
        )
    }

    func testTrackingCountsDefaultWhenUpstreamIsMissing() {
        XCTAssertEqual(GitService.trackingCounts(nil), GitTrackingCounts())
        XCTAssertEqual(GitService.trackingCounts(""), GitTrackingCounts())
    }

    func testTrackingCountsRejectMalformedOutput() {
        XCTAssertEqual(GitService.trackingCounts("4"), GitTrackingCounts())
        XCTAssertEqual(GitService.trackingCounts("4\tfive"), GitTrackingCounts())
        XCTAssertEqual(GitService.trackingCounts("1\t2\t3"), GitTrackingCounts())
    }

    func testSSHRemoteConvertsToBrowserURL() {
        let remote = GitRemote(raw: "git@github.com:CClishan/Fizzdeck.git")

        XCTAssertEqual(
            remote?.webURL?.absoluteString,
            "https://github.com/CClishan/Fizzdeck"
        )
    }

    func testDetailKeepsFirstCharacterForTrackedChange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckGitServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try await git(["init"], in: directory)
        try await git(["config", "user.email", "test@example.com"], in: directory)
        try await git(["config", "user.name", "FizzDeck Test"], in: directory)

        let file = directory.appendingPathComponent("HANDOFF.md")
        try "initial".write(to: file, atomically: true, encoding: .utf8)
        try await git(["add", "HANDOFF.md"], in: directory)
        try await git(["commit", "-m", "initial"], in: directory)
        try "changed".write(to: file, atomically: true, encoding: .utf8)

        let (detail, _) = await GitService.detail(directory)

        XCTAssertEqual(detail?.files.first?.code, "M")
        XCTAssertEqual(detail?.files.first?.path, "HANDOFF.md")
    }

    private func git(_ arguments: [String], in directory: URL) async throws {
        let result = await Shell.run("git", arguments, cwd: directory, timeout: 10)
        XCTAssertEqual(result?.status, 0, result?.text ?? "git failed")
    }
}
