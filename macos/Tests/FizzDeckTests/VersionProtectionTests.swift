import Foundation
import XCTest
@testable import FizzDeck

final class VersionProtectionTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var project: URL { root.appendingPathComponent("project") }
    private var marks: URL { root.appendingPathComponent("state/marks.json") }
    private var scratch: URL { root.appendingPathComponent("scratch") }

    override func setUpWithError() throws { try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func write(_ path: String, _ text: String) throws {
        let url = project.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func enable(_ url: URL? = nil) async -> (succeeded: Bool, message: String) {
        await DoctorService.initGitRepository(in: url ?? project, marksFile: marks, tmpDir: scratch)
    }

    @discardableResult
    private func git(_ args: [String]) async throws -> String {
        let result = await Shell.run("git", args, cwd: project)
        let output = try XCTUnwrap(result)
        XCTAssertTrue(output.succeeded, "\(args): \(output.text)")
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testRulesAreSpecificToEachStackAndCombineForMixedProjects() {
        let manifests = ["package.json", "pyproject.toml", "Package.swift", "Cargo.toml", "go.mod"]
        let expected = ["node_modules/", "__pycache__/", ".build/", "target/", "*.test"]
        for (idx, manifest) in manifests.enumerated() {
            let rules = ProtectionFiles.ignoreRules(rootEntries: [manifest])
            XCTAssertEqual(Set(expected).intersection(rules), [expected[idx]], manifest)
        }
        let mixed = ProtectionFiles.ignoreRules(rootEntries: manifests)
        XCTAssertTrue(Set(expected).isSubset(of: Set(mixed)))
        XCTAssertEqual(Set(mixed).count, mixed.count)
        XCTAssertTrue(Set(expected).isDisjoint(with: ProtectionFiles.ignoreRules(rootEntries: ["notes.txt"])))
    }

    func testFirstMarkSurvivesGCAndRestoresOnlySelectedSafeFilesWithoutChangingIndex() async throws {
        let original = "custom.data\r\n# my rules\r\n!.env.local\r\n!coverage.out"
        try write(".gitignore", "\u{FEFF}" + original)
        let source = "src/name [1].go"
        let initial = "package main\n"
        for (path, text) in [(source, initial), ("go.mod", "module fixture"), ("go.sum", "keep"), ("coverage.out", "my exception"),
                             (".env.example", "MODE=demo"), (".env.local", "private value"), ("cert.p8", "private bytes"),
                             ("custom.data", "not tracked"), ("bin/built", "artifact"), ("node_modules/lib/index.js", "generated"),
                             ("notes.txt", "ghp_" + String(repeating: "a", count: 26))] {
            try write(path, text)
        }
        let external = root.appendingPathComponent("outside.txt")
        try Data("external".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("link"), withDestinationURL: external)
        let big = project.appendingPathComponent("large.dat")
        try Data().write(to: big)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(SessionMarkService.maxFileBytes + 1))
        try handle.close()
        // More than the legacy index's 200 exclusions; sparse hard links keep the fixture small.
        for i in 0..<201 { try FileManager.default.linkItem(at: big, to: project.appendingPathComponent("large-\(i).dat")) }

        let result = await enable()
        XCTAssertTrue(result.succeeded, result.message)
        let restoredMarks = MarkStore.marks(for: project.path, in: MarkStore.load(from: marks))
        XCTAssertEqual(restoredMarks.count, 1)
        let mark = try XCTUnwrap(restoredMarks.first)
        XCTAssertTrue(mark.isProtectionBaseline && mark.pinned)
        XCTAssertNil(mark.sessionID)
        XCTAssertNil(mark.headSHA)
        let sha = try XCTUnwrap(mark.snapshotSHA)
        let tree = try await git(["ls-tree", "-rz", "--name-only", sha])
        XCTAssertEqual(Set(tree.split(separator: "\0").map(String.init)), [source, "go.mod", "go.sum", ".gitignore", ".env.example", "coverage.out"])
        let ignoreData = try Data(contentsOf: project.appendingPathComponent(".gitignore"))
        XCTAssertTrue(ignoreData.starts(with: [0xef, 0xbb, 0xbf]))
        XCTAssertTrue(ignoreData.suffix(original.utf8.count).elementsEqual(original.utf8))
        let ignoreText = String(decoding: ignoreData, as: UTF8.self)
        XCTAssertTrue(ignoreText.contains("/bin/"))
        XCTAssertFalse(ignoreText.contains("node_modules/"))
        let matchedRule = try await git(["check-ignore", "--no-index", "-v", "--", "custom.data"])
        XCTAssertTrue(matchedRule.hasSuffix(":custom.data\tcustom.data"), matchedRule)
        let realIndex = project.appendingPathComponent(".git/index")
        XCTAssertFalse(FileManager.default.fileExists(atPath: realIndex.path))
        let head = await Shell.run("git", ["rev-parse", "--verify", "HEAD"], cwd: project)
        XCTAssertFalse(head?.succeeded ?? true)
        try await git(["gc", "--prune=now"])
        let available = await SessionMarkService.isAvailable(mark, in: project)
        XCTAssertTrue(available)

        try write(source, "staged\n")
        try await git(["--literal-pathspecs", "add", "--", source])
        let indexBefore = try Data(contentsOf: realIndex)
        try write(source, "later worktree edit\n")
        try write("new.go", "new work\n")
        let diff = await SessionMarkService.diffSummary(for: mark, in: project, tmpDir: scratch)
        XCTAssertEqual(diff.modifiedOrDeleted.map(\.path), [source])
        XCTAssertEqual(diff.createdAfterMark.map(\.path), ["new.go"])
        let restore = await SessionMarkService.restore(mark: mark, filesToRestore: [source], in: project, marksFile: marks, tmpDir: scratch)
        XCTAssertTrue(restore.succeeded, restore.message)
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(source)), Data(initial.utf8))
        XCTAssertEqual(try Data(contentsOf: realIndex), indexBefore)
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("new.go")), Data("new work\n".utf8))
        let repeated = await enable()
        XCTAssertFalse(repeated.succeeded)
        XCTAssertEqual(MarkStore.load(from: marks).filter(\.isProtectionBaseline).count, 1)
        XCTAssertEqual(try Data(contentsOf: realIndex), indexBefore)

        // A file may become sensitive between preview and the user's click. Do not overwrite an unbacked-up version.
        let sensitive = "API_KEY=" + String(repeating: "x", count: 30)
        try write(source, sensitive)
        let unsafeRestore = await SessionMarkService.restore(mark: mark, filesToRestore: [source], in: project, marksFile: marks, tmpDir: scratch)
        XCTAssertFalse(unsafeRestore.succeeded)
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(source)), Data(sensitive.utf8))
    }

    func testExistingRepositoryAndNestedFolderKeepUserIndexConfigAndIgnoreBytes() async throws {
        try await git(["init", "-q"])
        try await git(["config", "user.name", "My settings"])
        try write(".gitignore", "keep-only-this\n")
        try write("nested/file", "staged value")
        try await git(["add", "nested/file"])
        try write("nested/file", "different in working tree")
        let urls = [".git/config", ".git/index", ".git/HEAD", ".gitignore", "nested/file"].map { project.appendingPathComponent($0) }
        let before = try urls.map { try Data(contentsOf: $0) }
        let existing = await enable()
        let nested = await enable(project.appendingPathComponent("nested"))
        XCTAssertFalse(existing.succeeded || nested.succeeded)
        XCTAssertFalse(GitService.hasGit(project.appendingPathComponent("nested")))
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marks.path))
    }

    func testMixedStackBaselineKeepsManifestsAndLockfilesButSkipsEachToolchainOutput() async throws {
        let keep = ["package.json", "pnpm-lock.yaml", "pyproject.toml", "uv.lock", "Package.swift", "Package.resolved", "Cargo.toml", "Cargo.lock", "go.mod", "go.sum"]
        let artifacts = ["dist/index.js", "__pycache__/m.pyc", ".build/debug/bin", "target/debug/generated", "worker.test"]
        for path in keep + artifacts { try write(path, "fixture") }
        let result = await enable()
        XCTAssertTrue(result.succeeded, result.message)
        let sha = try XCTUnwrap(MarkStore.load(from: marks).first?.snapshotSHA)
        let tree = try await git(["ls-tree", "-rz", "--name-only", sha])
        XCTAssertEqual(Set(tree.split(separator: "\0").map(String.init)), Set(keep + [".gitignore"]))
        let ignored = try await git(["check-ignore", "--"] + artifacts + keep)
        XCTAssertEqual(Set(ignored.split(separator: "\n").map(String.init)), Set(artifacts))
    }

    func testCannotPublishPartialProtectionOrClobberAnExternalIgnoreOrMarkStore() async throws {
        let outside = root.appendingPathComponent("outside")
        try Data("keep\n".utf8).write(to: outside)
        let ignore = project.appendingPathComponent(".gitignore")
        try FileManager.default.createSymbolicLink(at: ignore, withDestinationURL: outside)
        let symlink = await enable()
        XCTAssertFalse(symlink.succeeded)
        XCTAssertFalse(GitService.hasGit(project))
        XCTAssertEqual(try Data(contentsOf: outside), Data("keep\n".utf8))
        try FileManager.default.removeItem(at: ignore)
        try FileManager.default.createDirectory(at: marks.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = Data("malformed existing data".utf8)
        try damaged.write(to: marks)
        let failed = await enable()
        XCTAssertFalse(failed.succeeded)
        XCTAssertFalse(GitService.hasGit(project))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ignore.path))
        XCTAssertEqual(try Data(contentsOf: marks), damaged)
    }

    func testConcurrentEntryPointsPublishExactlyOneBaseline() async throws {
        try write("Package.swift", "// fixture\n")
        let directory = project, file = marks, tmp = scratch
        async let a = DoctorService.initGitRepository(in: directory, marksFile: file, tmpDir: tmp)
        async let b = DoctorService.initGitRepository(in: directory, marksFile: file, tmpDir: tmp)
        let results = await [a, b]
        XCTAssertEqual(results.filter(\.succeeded).count, 1)
        let all = MarkStore.load(from: marks)
        XCTAssertEqual(all.count, 1)
        let first = try XCTUnwrap(all.first)
        let available = await SessionMarkService.isAvailable(first, in: project)
        XCTAssertTrue(available)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent(".git/index").path))
    }
}
