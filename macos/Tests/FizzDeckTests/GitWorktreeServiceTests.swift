import Foundation
import XCTest
@testable import FizzDeck

final class GitWorktreeServiceTests: XCTestCase {
    func testParsePorcelainIdentifiesMainDetachedLockedAndPrunable() {
        let output = """
        worktree /tmp/Fizz Deck/main
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /tmp/Fizz Deck/feature
        HEAD 2222222222222222222222222222222222222222
        detached
        locked in use
        prunable gitdir file points to non-existent location
        """

        let worktrees = GitWorktreeService.parsePorcelain(output)

        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees[0].path, "/tmp/Fizz Deck/main")
        XCTAssertEqual(worktrees[0].branch, "main")
        XCTAssertTrue(worktrees[0].isMain)
        XCTAssertFalse(worktrees[0].isDetached)

        XCTAssertEqual(worktrees[1].path, "/tmp/Fizz Deck/feature")
        XCTAssertEqual(worktrees[1].head, "222222222222")
        XCTAssertNil(worktrees[1].branch)
        XCTAssertTrue(worktrees[1].isDetached)
        XCTAssertTrue(worktrees[1].isLocked)
        XCTAssertTrue(worktrees[1].isPrunable)
        XCTAssertFalse(worktrees[1].isMain)
    }

    func testListReadsRealGitWorktree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckWorktreeTests-\(UUID().uuidString)")
        let repository = root.appendingPathComponent("main")
        let linked = root.appendingPathComponent("feature")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try await git(["init"], in: repository)
        try await git(["config", "user.email", "test@example.com"], in: repository)
        try await git(["config", "user.name", "FizzDeck Test"], in: repository)
        try "initial".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try await git(["add", "README.md"], in: repository)
        try await git(["commit", "-m", "initial"], in: repository)
        try await git(["worktree", "add", "-b", "feature", linked.path], in: repository)

        let worktrees = await GitWorktreeService.list(in: repository)

        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(URL(fileURLWithPath: worktrees.first?.path ?? "").lastPathComponent, "main")
        XCTAssertTrue(worktrees.first?.isMain == true)
        XCTAssertTrue(worktrees.contains { $0.branch == "feature" && !$0.isDetached })
    }

    private func git(_ arguments: [String], in directory: URL) async throws {
        let result = await Shell.run("git", arguments, cwd: directory, timeout: 20)
        XCTAssertEqual(result?.status, 0, result?.text ?? "git failed")
    }
}
