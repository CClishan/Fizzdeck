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

    func testParseChangesHandlesStagedUnstagedUntrackedAndRename() {
        let output = " M Sources/App.swift\0"
            + "?? Notes/new file.md\0"
            + "R  Sources/Renamed.swift\0Sources/Old.swift\0"

        let changes = GitService.parseChanges(output)

        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes[0].path, "Sources/App.swift")
        XCTAssertTrue(changes[0].hasUnstagedChanges)
        XCTAssertFalse(changes[0].hasStagedChanges)

        XCTAssertEqual(changes[1].path, "Notes/new file.md")
        XCTAssertTrue(changes[1].untracked)
        XCTAssertEqual(changes[1].statusCode, "??")

        XCTAssertEqual(changes[2].path, "Sources/Renamed.swift")
        XCTAssertEqual(changes[2].originalPath, "Sources/Old.swift")
        XCTAssertTrue(changes[2].hasStagedChanges)
        XCTAssertFalse(changes[2].hasUnstagedChanges)
    }

    func testParseUnifiedDiffTracksLineNumbersAndCounts() {
        let input = """
        diff --git a/a.swift b/a.swift
        index 1111111..2222222 100644
        --- a/a.swift
        +++ b/a.swift
        @@ -1,3 +1,4 @@
         let a = 1
        -let b = 2
        +let b = 3
        +let c = 4
         let d = 5
        """

        let parsed = GitService.parseUnifiedDiff(input)

        XCTAssertEqual(parsed.additions, 2)
        XCTAssertEqual(parsed.deletions, 1)
        XCTAssertFalse(parsed.truncated)
        XCTAssertEqual(parsed.lines.first(where: { $0.kind == .deletion })?.oldLine, 2)
        XCTAssertEqual(parsed.lines.first(where: { $0.kind == .addition })?.newLine, 2)
    }

    func testParseUnifiedDiffTruncatesAtLineLimit() {
        let input = """
        @@ -1,4 +1,4 @@
         one
         two
         three
         four
        """

        let parsed = GitService.parseUnifiedDiff(input, maxLines: 3)

        XCTAssertEqual(parsed.lines.count, 3)
        XCTAssertTrue(parsed.truncated)
    }

    func testStageUnstageAndCommit() async throws {
        let directory = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        try "changed".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let staged = await GitService.stage(["README.md"], in: directory)
        XCTAssertTrue(staged.succeeded, staged.message)
        var changes = await GitService.changes(directory)
        XCTAssertTrue(changes.first?.hasStagedChanges == true)
        if let change = changes.first {
            let diff = await GitService.fileDiff(for: change, in: directory)
            XCTAssertEqual(diff.sections.first?.title, "已暂存")
            XCTAssertEqual(diff.additions, 1)
            XCTAssertEqual(diff.deletions, 1)
        } else {
            XCTFail("missing staged change")
        }

        let unstaged = await GitService.unstage(["README.md"], in: directory)
        XCTAssertTrue(unstaged.succeeded, unstaged.message)
        changes = await GitService.changes(directory)
        XCTAssertTrue(changes.first?.hasUnstagedChanges == true)
        XCTAssertFalse(changes.first?.hasStagedChanges == true)

        let stagedAgain = await GitService.stage(["README.md"], in: directory)
        XCTAssertTrue(stagedAgain.succeeded, stagedAgain.message)
        let committed = await GitService.commit("update readme", in: directory)
        XCTAssertTrue(committed.succeeded, committed.message)
        let subject = await Shell.output(
            "git",
            ["log", "-1", "--format=%s"],
            cwd: directory
        )
        XCTAssertEqual(subject, "update readme")
    }

    func testCommitRejectsEmptyMessage() async throws {
        let directory = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await GitService.commit("   ", in: directory)

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("提交信息"), result.message)
    }

    func testStageAllUnstageAllAndSwitchBranch() async throws {
        let directory = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await git(["branch", "feature"], in: directory)
        try "one".write(
            to: directory.appendingPathComponent("one.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "two".write(
            to: directory.appendingPathComponent("two.txt"),
            atomically: true,
            encoding: .utf8
        )

        let staged = await GitService.stageAll(in: directory)
        XCTAssertTrue(staged.succeeded, staged.message)
        var changes = await GitService.changes(directory)
        XCTAssertEqual(changes.filter(\.hasStagedChanges).count, 2)

        let unstaged = await GitService.unstageAll(in: directory)
        XCTAssertTrue(unstaged.succeeded, unstaged.message)
        changes = await GitService.changes(directory)
        XCTAssertTrue(changes.allSatisfy { !$0.hasStagedChanges })

        let switched = await GitService.switchBranch("feature", in: directory)
        XCTAssertTrue(switched.succeeded, switched.message)
        let branch = await Shell.output(
            "git",
            ["rev-parse", "--abbrev-ref", "HEAD"],
            cwd: directory
        )
        XCTAssertEqual(branch, "feature")

        let invalid = await GitService.switchBranch("bad branch", in: directory)
        XCTAssertFalse(invalid.succeeded)
    }

    func testStashPushAndPopRestoresTrackedChange() async throws {
        let directory = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let readme = directory.appendingPathComponent("README.md")
        try "local change".write(to: readme, atomically: true, encoding: .utf8)

        let pushed = await GitService.stashPush(in: directory)
        XCTAssertTrue(pushed.succeeded, pushed.message)
        let clean = await Shell.output(
            "git",
            ["status", "--porcelain=v1"],
            cwd: directory
        )
        XCTAssertEqual(clean, "")

        let popped = await GitService.stashPop(in: directory)
        XCTAssertTrue(popped.succeeded, popped.message)
        XCTAssertEqual(try String(contentsOf: readme, encoding: .utf8), "local change")
    }

    func testCommitAndPushUpdatesLocalRemote() async throws {
        let root = temporaryDirectory()
        let remote = root.appendingPathComponent("remote.git")
        let directory = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let remoteInit = await Shell.run("git", ["init", "--bare", remote.path], timeout: 10)
        XCTAssertEqual(remoteInit?.status, 0, remoteInit?.text ?? "bare init failed")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await git(["init", "-b", "main"], in: directory)
        try await git(["config", "user.email", "test@example.com"], in: directory)
        try await git(["config", "user.name", "FizzDeck Test"], in: directory)
        try "initial".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try await git(["add", "README.md"], in: directory)
        try await git(["commit", "-m", "initial"], in: directory)
        try await git(["remote", "add", "origin", remote.path], in: directory)
        try await git(["push", "-u", "origin", "main"], in: directory)

        try "second".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let staged = await GitService.stage(["README.md"], in: directory)
        XCTAssertTrue(staged.succeeded, staged.message)

        let result = await GitService.commitAndPush("second commit", in: directory)
        XCTAssertTrue(result.succeeded, result.message)

        let remoteSubject = await Shell.output(
            "git",
            ["--git-dir", remote.path, "log", "-1", "--format=%s", "main"],
            timeout: 10
        )
        XCTAssertEqual(remoteSubject, "second commit")
    }

    func testCommitAndPushKeepsCommitWhenPushFails() async throws {
        let directory = try await makeRepository()
        let root = directory.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingRemote = root.appendingPathComponent("missing-\(UUID().uuidString).git")
        try await git(["remote", "add", "origin", missingRemote.path], in: directory)
        try "second".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let staged = await GitService.stage(["README.md"], in: directory)
        XCTAssertTrue(staged.succeeded, staged.message)

        let result = await GitService.commitAndPush("local commit", in: directory)

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.didMutate)
        XCTAssertTrue(result.message.contains("已提交"), result.message)
        let subject = await Shell.output(
            "git",
            ["log", "-1", "--format=%s"],
            cwd: directory
        )
        XCTAssertEqual(subject, "local commit")
    }

    func testUntrackedFilePreviewIsInlineDiff() async throws {
        let directory = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        try "line one\nline two\n".write(
            to: directory.appendingPathComponent("notes.md"),
            atomically: true,
            encoding: .utf8
        )
        let changes = await GitService.changes(directory)
        guard let change = changes.first(where: { $0.path == "notes.md" }) else {
            return XCTFail("missing untracked change")
        }

        let diff = await GitService.fileDiff(for: change, in: directory)

        XCTAssertEqual(diff.additions, 2)
        XCTAssertEqual(diff.sections.first?.title, "未跟踪文件")
        XCTAssertEqual(diff.sections.first?.lines.first?.kind, .addition)
    }

    func testUntrackedFilePreviewTruncatesLargeFile() async throws {
        let directory = try await makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let line = String(repeating: "大文件行X\n", count: 20_000)
        try line.write(
            to: directory.appendingPathComponent("large.txt"),
            atomically: true,
            encoding: .utf8
        )
        let changes = await GitService.changes(directory)
        guard let change = changes.first(where: { $0.path == "large.txt" }) else {
            return XCTFail("missing large untracked file")
        }

        let diff = await GitService.fileDiff(for: change, in: directory)

        XCTAssertTrue(diff.truncated)
        XCTAssertFalse(diff.binary)
        XCTAssertLessThanOrEqual(diff.sections.first?.lines.count ?? 0, 800)
    }

    private func makeRepository() async throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await git(["init"], in: directory)
        try await git(["config", "user.email", "test@example.com"], in: directory)
        try await git(["config", "user.name", "FizzDeck Test"], in: directory)
        try "initial".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try await git(["add", "README.md"], in: directory)
        try await git(["commit", "-m", "initial"], in: directory)
        return directory
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckGitServiceTests-\(UUID().uuidString)")
    }

    private func git(_ arguments: [String], in directory: URL) async throws {
        let result = await Shell.run("git", arguments, cwd: directory, timeout: 10)
        XCTAssertEqual(result?.status, 0, result?.text ?? "git failed")
    }
}
