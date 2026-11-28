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
        let repository = try await makeRepository()
        _ = try await addFeature(in: repository)

        let worktrees = await GitWorktreeService.list(in: repository)

        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(URL(fileURLWithPath: worktrees.first?.path ?? "").lastPathComponent, "main")
        XCTAssertTrue(worktrees.first?.isMain == true)
        XCTAssertTrue(worktrees.contains { $0.branch == "feature" && !$0.isDetached })
    }

    func testCreateAtControlledSibling() async throws {
        let repository = try await makeRepository()
        let branch = "feature/layout"
        let expected = container(beside: repository).appendingPathComponent("feature-layout", isDirectory: true)
        let start = try await git(["rev-parse", "HEAD"], in: repository)

        XCTAssertEqual(GitWorktreeService.destination(for: branch, beside: repository)?.path, expected.path)
        let created = try await GitWorktreeService.create(branch, in: repository)

        XCTAssertEqual(created.path, expected.path)
        XCTAssertEqual(created.branch, branch)
        XCTAssertEqual(created.head, String(start.prefix(12)))
        XCTAssertFalse(created.isMain)
        let checkout = try await checkoutState(in: expected)
        XCTAssertEqual(checkout.branch, "refs/heads/\(branch)")
        XCTAssertEqual(checkout.head, start)
        XCTAssertEqual(checkout.status, "")
        XCTAssertEqual(try read("README.md", in: expected), "initial\n")
    }

    func testCreateRejectsInvalidOrExistingBranch() async throws {
        let repository = try await makeRepository()
        try await git(["branch", "existing"], in: repository)
        let refs = try await git(["show-ref", "--heads"], in: repository)

        for branch in ["", "--force", "feature/../escape", "feature//layout", "bad name", "HEAD"] {
            XCTAssertNil(GitWorktreeService.destination(for: branch, beside: repository), branch)
            try await assertBlocked { _ = try await GitWorktreeService.create(branch, in: repository) }
        }
        try await assertBlocked { _ = try await GitWorktreeService.create("existing", in: repository) }

        let refsAfter = try await git(["show-ref", "--heads"], in: repository)
        let worktrees = await GitWorktreeService.list(in: repository)
        XCTAssertEqual(refsAfter, refs)
        XCTAssertEqual(worktrees.map(\.branch), ["main"])
    }

    func testCreateRejectsOccupiedPathAndSlugCollision() async throws {
        let repository = try await makeRepository()
        let occupied = container(beside: repository).appendingPathComponent("occupied", isDirectory: true)
        let existing = try await GitWorktreeService.create("feature/layout", in: repository)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: false)
        let refs = try await git(["show-ref", "--heads"], in: repository)

        try await assertBlocked { _ = try await GitWorktreeService.create("occupied", in: repository) }
        try await assertBlocked { _ = try await GitWorktreeService.create("feature-layout", in: repository) }

        let refsAfter = try await git(["show-ref", "--heads"], in: repository)
        XCTAssertEqual(refsAfter, refs)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: occupied.path), [])
        XCTAssertEqual(try read("README.md", in: URL(fileURLWithPath: existing.path)), "initial\n")
    }

    func testCreateRejectsSymlinkContainerAndDestination() async throws {
        let repository = try await makeRepository()
        let fm = FileManager.default
        let parent = container(beside: repository)
        let outside = repository.deletingLastPathComponent().appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: false)
        try write("keep\n", to: "keep.txt", in: outside)
        try fm.createSymbolicLink(at: parent, withDestinationURL: outside)

        try await assertBlocked { _ = try await GitWorktreeService.create("feature", in: repository) }
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: parent.path), outside.path)

        try fm.removeItem(at: parent)
        try fm.createDirectory(at: parent, withIntermediateDirectories: false)
        let target = parent.appendingPathComponent("feature")
        let missing = outside.appendingPathComponent("missing")
        try fm.createSymbolicLink(at: target, withDestinationURL: missing)
        try await assertBlocked { _ = try await GitWorktreeService.create("feature", in: repository) }

        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: target.path), missing.path)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path), ["keep.txt"])
        XCTAssertEqual(try read("keep.txt", in: outside), "keep\n")
        let refs = try await git(["for-each-ref", "--format=%(refname)", "refs/heads"], in: repository)
        XCTAssertEqual(refs, "refs/heads/main")
    }

    func testStatusCountsDivergenceAndChanges() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        try await commitFile("main\n", named: "main.txt", in: repository)
        try await commitFile("first\n", named: "feature.txt", in: linked)
        try await commitFile("second\n", named: "feature.txt", in: linked)
        try write("edited\n", to: "README.md", in: linked)
        let drafts = linked.appendingPathComponent("drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: false)
        try write("one\n", to: "one.txt", in: drafts)
        try write("two\n", to: "two.txt", in: drafts)
        try write("ignored\n", to: "ignored.log", in: linked)

        let overview = try await GitWorktreeService.status(in: repository)
        let main = try XCTUnwrap(overview.rows.first { $0.worktree.isMain })
        let feature = try XCTUnwrap(overview.rows.first { $0.worktree.branch == "feature" })

        XCTAssertEqual(overview.mainBranch, "main")
        XCTAssertEqual(main.changedCount, 0)
        XCTAssertEqual(main.ahead, 0)
        XCTAssertEqual(main.behind, 0)
        XCTAssertFalse(main.canManage)
        XCTAssertEqual(feature.changedCount, 3)
        XCTAssertEqual(feature.ahead, 2)
        XCTAssertEqual(feature.behind, 1)
        XCTAssertTrue(feature.canManage)
    }

    func testStatusSelectsSupportedDefaultBranch() async throws {
        let repository = try await makeRepository()
        try await git(["branch", "-m", "unrelated"], in: repository)
        let noDefault = try await GitWorktreeService.status(in: repository)
        XCTAssertNil(noDefault.mainBranch)

        try await git(["branch", "-m", "master"], in: repository)
        let fallback = try await GitWorktreeService.status(in: repository)
        XCTAssertEqual(fallback.mainBranch, "master")

        try await git(["branch", "trunk"], in: repository)
        try await git(["update-ref", "refs/remotes/origin/trunk", "refs/heads/trunk"], in: repository)
        try await git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk"], in: repository)
        let knownDefault = try await GitWorktreeService.status(in: repository)
        XCTAssertEqual(knownDefault.mainBranch, "trunk")
    }

    func testMergeFastForwardsWithoutRemoving() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        try await commitFile("feature\n", named: "feature.txt", in: linked)
        let source = try await checkoutState(in: linked)
        let worktree = try await featureSnapshot(in: repository)

        _ = try await GitWorktreeService.mergeIntoMain(worktree, in: repository)

        let primary = try await checkoutState(in: repository)
        let sourceAfter = try await checkoutState(in: linked)
        let worktreesAfter = await GitWorktreeService.list(in: repository)
        XCTAssertEqual(primary.head, source.head)
        XCTAssertEqual(primary.branch, "refs/heads/main")
        XCTAssertEqual(primary.status, "")
        XCTAssertEqual(try read("feature.txt", in: repository), "feature\n")
        XCTAssertEqual(sourceAfter, source)
        XCTAssertTrue(worktreesAfter.contains { $0.path == linked.path && $0.branch == "feature" })
    }

    func testMergeRefusesDirtyPrimary() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        try await commitFile("feature\n", named: "feature.txt", in: linked)
        let worktree = try await featureSnapshot(in: repository)
        try write("staged edit\n", to: "README.md", in: repository)
        try await git(["add", "README.md"], in: repository)
        try write("working edit\n", to: "README.md", in: repository)
        try write("local draft\n", to: "draft.txt", in: repository)
        let before = try await checkoutState(in: repository)

        try await assertBlocked { _ = try await GitWorktreeService.mergeIntoMain(worktree, in: repository) }

        let after = try await checkoutState(in: repository)
        XCTAssertEqual(after, before)
        XCTAssertEqual(try read("README.md", in: repository), "working edit\n")
        XCTAssertEqual(try read("draft.txt", in: repository), "local draft\n")
    }

    func testMergeDoesNotOverwriteIgnoredPrimaryFile() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let localFile = repository.appendingPathComponent("ignored.log")
        let localBytes = Data([0x00, 0xff, 0x0d, 0x0a])
        try localBytes.write(to: localFile)
        try write("tracked by feature\n", to: "ignored.log", in: linked)
        try await git(["add", "-f", "--", "ignored.log"], in: linked)
        try await git(["commit", "-m", "track ignored path"], in: linked)
        let worktree = try await featureSnapshot(in: repository)
        let primary = try await checkoutState(in: repository)
        XCTAssertEqual(primary.status, "")

        do {
            _ = try await GitWorktreeService.mergeIntoMain(worktree, in: repository)
            XCTFail("Expected the merge to refuse overwriting ignored.log")
        } catch GitWorktreeService.Failure.git {
            // Git refuses the overwrite before starting a merge.
        }

        let primaryAfter = try await checkoutState(in: repository)
        XCTAssertEqual(primaryAfter, primary)
        XCTAssertEqual(try Data(contentsOf: localFile), localBytes)
    }

    func testMergeRequiresDefaultCheckout() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        try await commitFile("feature\n", named: "feature.txt", in: linked)
        let worktree = try await featureSnapshot(in: repository)
        try await git(["switch", "-c", "scratch"], in: repository)
        let refs = try await git(["show-ref", "--heads"], in: repository)

        try await assertBlocked { _ = try await GitWorktreeService.mergeIntoMain(worktree, in: repository) }

        let branch = try await git(["symbolic-ref", "HEAD"], in: repository)
        let refsAfter = try await git(["show-ref", "--heads"], in: repository)
        XCTAssertEqual(branch, "refs/heads/scratch")
        XCTAssertEqual(refsAfter, refs)
    }

    func testMergeRequiresFreshCleanSource() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let stale = try await featureSnapshot(in: repository)
        let primary = try await checkoutState(in: repository)
        try await commitFile("feature\n", named: "feature.txt", in: linked)

        try await assertBlocked { _ = try await GitWorktreeService.mergeIntoMain(stale, in: repository) }

        let current = try await featureSnapshot(in: repository)
        try write("source draft\n", to: "draft.txt", in: linked)
        try await assertBlocked { _ = try await GitWorktreeService.mergeIntoMain(current, in: repository) }

        let primaryAfter = try await checkoutState(in: repository)
        XCTAssertEqual(primaryAfter, primary)
        XCTAssertEqual(try read("draft.txt", in: linked), "source draft\n")
    }

    func testMergeConflictRestoresRefsIndexAndBothCheckouts() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        try await commitFile("main conflict\n", named: "README.md", in: repository)
        try await commitFile("feature conflict\n", named: "README.md", in: linked)
        try await commitFile("feature only\n", named: "feature.txt", in: linked)
        let worktree = try await featureSnapshot(in: repository)
        let refs = try await git(["show-ref", "--heads"], in: repository)
        let primary = try await checkoutState(in: repository)
        let source = try await checkoutState(in: linked)

        do {
            _ = try await GitWorktreeService.mergeIntoMain(worktree, in: repository)
            return XCTFail("Expected a merge conflict")
        } catch let GitWorktreeService.Failure.mergeConflict(mainPath, rollbackSucceeded) {
            XCTAssertEqual(mainPath, repository.path)
            XCTAssertTrue(rollbackSucceeded)
        }

        let refsAfter = try await git(["show-ref", "--heads"], in: repository)
        let primaryAfter = try await checkoutState(in: repository)
        let sourceAfter = try await checkoutState(in: linked)
        XCTAssertEqual(refsAfter, refs)
        XCTAssertEqual(primaryAfter, primary)
        XCTAssertEqual(sourceAfter, source)
        XCTAssertEqual(try read("README.md", in: repository), "main conflict\n")
        XCTAssertEqual(try read("README.md", in: linked), "feature conflict\n")
        XCTAssertEqual(try read("feature.txt", in: linked), "feature only\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent("feature.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent(".git/MERGE_HEAD").path))
    }

    func testDirtyRemovalRequiresConfirmation() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let worktree = try await featureSnapshot(in: repository)
        try write("ignored\n", to: "ignored.log", in: linked)
        let ignoredOnly = try await requireDiscardConfirmation(for: worktree, in: repository)
        XCTAssertEqual(ignoredOnly.changedCount, 0)
        XCTAssertEqual(ignoredOnly.ignoredCount, 1)

        try write("edited\n", to: "README.md", in: linked)
        try write("draft\n", to: "draft.txt", in: linked)
        let token = try await requireDiscardConfirmation(for: worktree, in: repository)

        XCTAssertEqual(token.changedCount, 2)
        XCTAssertEqual(token.ignoredCount, 1)
        XCTAssertEqual(try read("README.md", in: linked), "edited\n")
        XCTAssertEqual(try read("draft.txt", in: linked), "draft\n")
        XCTAssertEqual(try read("ignored.log", in: linked), "ignored\n")
    }

    func testDirtyRemovalRequiresCurrentConfirmation() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let worktree = try await featureSnapshot(in: repository)
        try write("edited\n", to: "README.md", in: linked)
        let original = try await requireDiscardConfirmation(for: worktree, in: repository)
        XCTAssertEqual(original.changedCount, 1)

        try write("added after review\n", to: "draft.txt", in: linked)
        let afterAddition = try await requireDiscardConfirmation(for: worktree, in: repository, reviewing: original)
        XCTAssertEqual(afterAddition.changedCount, 2)
        XCTAssertEqual(try read("draft.txt", in: linked), "added after review\n")

        let status = try await git(["status", "--porcelain=v1"], in: linked)
        try write("different contents after review\n", to: "README.md", in: linked)
        let statusAfter = try await git(["status", "--porcelain=v1"], in: linked)
        XCTAssertEqual(statusAfter, status)
        let current = try await requireDiscardConfirmation(for: worktree, in: repository, reviewing: afterAddition)
        XCTAssertEqual(current.changedCount, 2)
        XCTAssertEqual(try read("README.md", in: linked), "different contents after review\n")

        try await GitWorktreeService.remove(worktree, in: repository, confirmingDiscardOf: current)

        let remaining = await GitWorktreeService.list(in: repository)
        XCTAssertFalse(FileManager.default.fileExists(atPath: linked.path))
        XCTAssertEqual(remaining.map(\.branch), ["main"])
    }

    func testDirtyRemovalConfirmationExpiresAfterEditInsideIgnoredDirectory() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let worktree = try await featureSnapshot(in: repository)
        let ignored = linked.appendingPathComponent("ignored-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: false)
        try write("cache\n", to: "entry.txt", in: ignored)
        let statusArguments = ["status", "--porcelain=v1", "--untracked-files=all", "--ignored"]
        let status = try await git(statusArguments, in: linked)
        XCTAssertEqual(status, "!! ignored-cache/entry.txt")
        let reviewed = try await requireDiscardConfirmation(for: worktree, in: repository)
        XCTAssertEqual(reviewed.changedCount, 0)
        XCTAssertEqual(reviewed.ignoredCount, 1)

        let edited = "cache edited in place\n"
        do {
            // Change the existing file without replacing its directory entry.
            let file = try FileHandle(forWritingTo: ignored.appendingPathComponent("entry.txt"))
            defer { try? file.close() }
            try file.write(contentsOf: Data(edited.utf8))
        }
        let statusAfter = try await git(statusArguments, in: linked)
        XCTAssertEqual(statusAfter, status)

        let refreshed = try await requireDiscardConfirmation(for: worktree, in: repository, reviewing: reviewed)
        XCTAssertEqual(refreshed.changedCount, 0)
        XCTAssertEqual(refreshed.ignoredCount, 1)
        XCTAssertEqual(try read("entry.txt", in: ignored), edited)
    }

    func testCleanRemovalKeepsBranch() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        try await commitFile("unmerged\n", named: "feature.txt", in: linked)
        let worktree = try await featureSnapshot(in: repository)
        let refs = try await git(["show-ref", "--heads"], in: repository)

        try await GitWorktreeService.remove(worktree, in: repository)

        let refsAfter = try await git(["show-ref", "--heads"], in: repository)
        let remaining = await GitWorktreeService.list(in: repository)
        XCTAssertEqual(refsAfter, refs)
        XCTAssertFalse(FileManager.default.fileExists(atPath: linked.path))
        XCTAssertEqual(remaining.map(\.branch), ["main"])
    }

    func testRemovalRefusesReplacementRepositoryAtRegisteredPath() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let worktree = try await featureSnapshot(in: repository)
        let listArguments = ["worktree", "list", "--porcelain"]
        let registrations = try await git(listArguments, in: repository)

        // A filesystem move leaves the old Git registration pointing at the same path.
        let saved = linked.deletingLastPathComponent().appendingPathComponent("saved-feature", isDirectory: true)
        try FileManager.default.moveItem(at: linked, to: saved)
        try await initializeRepository(at: linked)
        try await commitFile("replacement repository\n", named: "keep.txt", in: linked)
        let replacement = try await checkoutState(in: linked)
        let staleRegistrations = try await git(listArguments, in: repository)
        XCTAssertEqual(staleRegistrations, registrations)
        XCTAssertEqual(replacement.status, "")

        try await assertBlocked { try await GitWorktreeService.remove(worktree, in: repository) }

        let replacementAfter = try await checkoutState(in: linked)
        let registrationsAfter = try await git(listArguments, in: repository)
        XCTAssertEqual(replacementAfter, replacement)
        XCTAssertEqual(registrationsAfter, registrations)
        XCTAssertEqual(try read("keep.txt", in: linked), "replacement repository\n")
        XCTAssertEqual(try read("README.md", in: saved), "initial\n")
    }

    func testRemovalBlocksManagedActivity() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let worktree = try await featureSnapshot(in: repository)

        try await assertBlocked {
            try await GitWorktreeService.remove(worktree, in: repository, managedActivity: { $0 == linked.path })
        }

        XCTAssertEqual(try read("README.md", in: linked), "initial\n")
    }

    func testRemovalBlocksProcessInNestedCheckoutDirectory() async throws {
        let repository = try await makeRepository()
        let linked = try await addFeature(in: repository)
        let worktree = try await featureSnapshot(in: repository)
        let nested = linked.appendingPathComponent("dev", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        process.currentDirectoryURL = nested
        process.environment = [:]
        let exited = expectation(description: "temporary process exits")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        try await assertBlocked { try await GitWorktreeService.remove(worktree, in: repository) }
        XCTAssertTrue(process.isRunning)
        XCTAssertEqual(try read("README.md", in: linked), "initial\n")
        if process.isRunning { process.terminate() }
        await fulfillment(of: [exited], timeout: 5)

        try await GitWorktreeService.remove(worktree, in: repository)
        XCTAssertFalse(FileManager.default.fileExists(atPath: linked.path))
    }

    private func makeRepository() async throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FizzDeck Worktree Tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let repository = root.appendingPathComponent("main", isDirectory: true)

        try await initializeRepository(at: repository)
        try write("initial\n", to: "README.md", in: repository)
        try write("ignored.log\n/ignored-cache/\n", to: ".gitignore", in: repository)
        try await git(["add", "README.md", ".gitignore"], in: repository)
        try await git(["commit", "-m", "initial"], in: repository)
        return repository
    }

    private func initializeRepository(at directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try await git(["init", "-b", "main", "--template="], in: directory)
        try await git(["config", "--local", "user.email", "test@example.com"], in: directory)
        try await git(["config", "--local", "user.name", "FizzDeck Test"], in: directory)
    }

    private func container(beside repository: URL) -> URL {
        repository.deletingLastPathComponent().appendingPathComponent("main-wt", isDirectory: true)
    }

    private func addFeature(in repository: URL) async throws -> URL {
        let linked = container(beside: repository).appendingPathComponent("feature", isDirectory: true)
        try await git(["worktree", "add", "-b", "feature", "--", linked.path], in: repository)
        return linked
    }

    private func featureSnapshot(in repository: URL) async throws -> GitWorktree {
        let worktrees = await GitWorktreeService.list(in: repository)
        return try XCTUnwrap(worktrees.first { $0.branch == "feature" })
    }

    private func commitFile(_ contents: String, named name: String, in directory: URL) async throws {
        try write(contents, to: name, in: directory)
        try await git(["add", "--", name], in: directory)
        try await git(["commit", "-m", contents.trimmingCharacters(in: .newlines)], in: directory)
    }

    private func write(_ contents: String, to name: String, in directory: URL) throws {
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func read(_ name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    private struct CheckoutState: Equatable {
        let head: String
        let branch: String
        let index: String
        let status: String
    }

    private func checkoutState(in directory: URL) async throws -> CheckoutState {
        try await CheckoutState(
            head: git(["rev-parse", "HEAD"], in: directory),
            branch: git(["symbolic-ref", "HEAD"], in: directory),
            index: git(["ls-files", "--stage"], in: directory),
            status: git(["status", "--porcelain=v1", "--untracked-files=all"], in: directory)
        )
    }

    private func assertBlocked(file: StaticString = #filePath, line: UInt = #line, _ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch GitWorktreeService.Failure.blocked {
            return
        }
        XCTFail("Expected GitWorktreeService.Failure.blocked", file: file, line: line)
    }

    private func requireDiscardConfirmation(
        for worktree: GitWorktree, in repository: URL, reviewing token: GitWorktreeService.DiscardConfirmation? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws -> GitWorktreeService.DiscardConfirmation {
        do {
            try await GitWorktreeService.remove(worktree, in: repository, confirmingDiscardOf: token)
        } catch let GitWorktreeService.Failure.dirtyRemoval(confirmation) {
            return confirmation
        }
        return try XCTUnwrap(nil, "Expected a discard confirmation", file: file, line: line)
    }

    private struct GitCommandFailure: Error, CustomStringConvertible {
        let description: String
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) async throws -> String {
        let unset = ProcessInfo.processInfo.environment.keys.filter { $0.hasPrefix("GIT_") }.sorted()
            .flatMap { ["-u", $0] }
        let result = await Shell.run("/usr/bin/env", unset + [
            "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_NOSYSTEM=1", "GIT_ATTR_NOSYSTEM=1",
            "GIT_OPTIONAL_LOCKS=0", "GIT_TERMINAL_PROMPT=0", "GIT_ALLOW_PROTOCOL=", "LC_ALL=C",
            "/usr/bin/git", "-c", "core.hooksPath=/dev/null",
        ] + arguments, cwd: directory, timeout: 20)
        guard let result, result.succeeded, !result.timedOut else {
            throw GitCommandFailure(description: "git \(arguments) in \(directory.path) failed: \(String(describing: result))")
        }
        return result.text.trimmingCharacters(in: .newlines)
    }
}
