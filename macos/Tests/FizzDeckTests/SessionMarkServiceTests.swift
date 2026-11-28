import XCTest
@testable import FizzDeck

final class SessionMarkServiceTests: XCTestCase {
    func testLocalizedCheckpointLabelKeepsStoredBaselineAndCustomNotes() throws {
        let baseline = SessionMark(projectPath: "/fixture", kind: .gitSnapshot, label: SessionMarkService.baselineLabel)
        var custom = baseline
        custom.label = "保留自定义说明"
        let original = try JSONEncoder().encode(baseline)
        try FizzL10n.$languageOverride.withValue(.english) {
            let decoded = try JSONDecoder().decode(SessionMark.self, from: original)
            XCTAssertTrue(decoded.isProtectionBaseline)
            XCTAssertEqual(decoded.displayLabel, "Version protection baseline")
            XCTAssertEqual(decoded.label, "开启版本保护时的基线")
            XCTAssertEqual(custom.displayLabel, "保留自定义说明")
        }
    }
    private func makeTempDir(prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runGit(_ args: [String], in dir: URL, extraEnv: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        extraEnv.forEach { env[$0.key] = $0.value }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            XCTFail("git \(args.joined(separator: " ")) failed (\(process.terminationStatus)): \(text)")
        }
        return text
    }

    func testCreateMarkPreservesRepoStateAndDiffsAndRestoresCleanly() async throws {
        let root = try makeTempDir(prefix: "FizzDeckMarkRepo")
        let tmpDir = root.appendingPathComponent("tmp", isDirectory: true)
        let marksFile = root.appendingPathComponent("marks.json")
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try runGit(["init"], in: repo)
        _ = try runGit(["config", "user.name", "Tester"], in: repo)
        _ = try runGit(["config", "user.email", "tester@example.com"], in: repo)

        try "v1\n".write(to: repo.appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
        try "keep\n".write(to: repo.appendingPathComponent("delete-me.txt"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "."], in: repo)
        _ = try runGit(["commit", "-m", "initial"], in: repo)

        // Create staged change + untracked file + excluded node_modules before mark
        try "v1-staged\n".write(to: repo.appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "app.txt"], in: repo)
        try "untracked-before\n".write(to: repo.appendingPathComponent("draft.txt"), atomically: true, encoding: .utf8)
        let nodeModules = repo.appendingPathComponent("node_modules/pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try "ignored-module\n".write(to: nodeModules.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)

        let statusBefore = try runGit(["status", "--porcelain"], in: repo)
        let logBefore = try runGit(["log", "--oneline"], in: repo)
        let stagedDiffBefore = try runGit(["diff", "--cached"], in: repo)

        let mark = await SessionMarkService.createMark(
            for: repo,
            sessionID: "sess-1",
            sessionStableID: "claude:sess-1",
            tool: "claude",
            allowGitSnapshot: true,
            tmpDir: tmpDir
        )

        XCTAssertEqual(mark.kind, .gitSnapshot)
        XCTAssertNotNil(mark.snapshotSHA)
        XCTAssertNotNil(mark.headSHA)
        XCTAssertEqual(try runGit(["status", "--porcelain"], in: repo), statusBefore)
        XCTAssertEqual(try runGit(["log", "--oneline"], in: repo), logBefore)
        XCTAssertEqual(try runGit(["diff", "--cached"], in: repo), stagedDiffBefore)

        // Verify tmpDir left 0 leftover .index files
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path)) ?? []
        XCTAssertEqual(leftovers, [])

        MarkStore.upsert(mark, in: marksFile)
        let loaded = MarkStore.load(from: marksFile)
        XCTAssertEqual(loaded.count, 1)

        let available = await SessionMarkService.isAvailable(mark, in: repo)
        XCTAssertTrue(available)

        // Pin & unpin
        let pinnedOK = await SessionMarkService.setPinned(true, mark: mark, in: repo)
        XCTAssertTrue(pinnedOK)
        let refsText = try runGit(["show-ref"], in: repo)
        XCTAssertTrue(refsText.contains("refs/fizzdeck/marks/\(mark.id)"))
        let unpinnedOK = await SessionMarkService.setPinned(false, mark: mark, in: repo)
        XCTAssertTrue(unpinnedOK)

        // Mutate after mark: modify tracked & untracked-at-mark, delete a file, create a new file
        try "v2-broken\n".write(to: repo.appendingPathComponent("app.txt"), atomically: true, encoding: .utf8)
        try "draft-edited\n".write(to: repo.appendingPathComponent("draft.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: repo.appendingPathComponent("delete-me.txt"))
        try "brand-new\n".write(to: repo.appendingPathComponent("new-after.txt"), atomically: true, encoding: .utf8)

        let summary = await SessionMarkService.diffSummary(for: mark, in: repo, tmpDir: tmpDir)
        XCTAssertTrue(summary.available)
        XCTAssertEqual(
            Set(summary.modifiedOrDeleted.map(\.path)),
            Set(["app.txt", "draft.txt", "delete-me.txt"])
        )
        XCTAssertEqual(
            summary.createdAfterMark.map(\.path),
            ["new-after.txt"]
        )

        // File diff for modified & createdAfterMark
        let appDiff = await SessionMarkService.fileDiff(
            for: mark,
            change: MarkFileChange(path: "app.txt", status: .modified),
            in: repo,
            tmpDir: tmpDir
        )
        XCTAssertFalse(appDiff.isEmpty)
        XCTAssertGreaterThan(appDiff.additions, 0)

        let newDiff = await SessionMarkService.fileDiff(
            for: mark,
            change: MarkFileChange(path: "new-after.txt", status: .createdAfterMark),
            in: repo,
            tmpDir: tmpDir
        )
        XCTAssertEqual(newDiff.additions, 1)

        // Restore modified & deleted files (do NOT touch new-after.txt)
        let restoreResult = await SessionMarkService.restore(
            mark: mark,
            filesToRestore: ["app.txt", "draft.txt", "delete-me.txt"],
            newlyCreatedToTrash: [],
            in: repo,
            marksFile: marksFile,
            tmpDir: tmpDir
        )
        XCTAssertTrue(restoreResult.succeeded)
        XCTAssertEqual(restoreResult.restoredCount, 3)
        XCTAssertEqual(restoreResult.trashedCount, 0)
        XCTAssertNotNil(restoreResult.preRestoreMark)

        XCTAssertEqual(
            try String(contentsOf: repo.appendingPathComponent("app.txt"), encoding: .utf8),
            "v1-staged\n"
        )
        XCTAssertEqual(
            try String(contentsOf: repo.appendingPathComponent("draft.txt"), encoding: .utf8),
            "untracked-before\n"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("delete-me.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("new-after.txt").path))

        // Undo restore using automatic preRestoreMark!
        let backup = try XCTUnwrap(restoreResult.preRestoreMark)
        let undoResult = await SessionMarkService.restore(
            mark: backup,
            filesToRestore: ["app.txt", "draft.txt", "delete-me.txt"],
            in: repo,
            marksFile: marksFile,
            tmpDir: tmpDir
        )
        XCTAssertTrue(undoResult.succeeded)
        XCTAssertEqual(
            try String(contentsOf: repo.appendingPathComponent("app.txt"), encoding: .utf8),
            "v2-broken\n"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("delete-me.txt").path))
    }

    func testUnbornRepoAndMissingGitConfigStillCreatesMarkAndNonGitFallsBackToPureMark() async throws {
        let root = try makeTempDir(prefix: "FizzDeckMarkEdge")
        let tmpDir = root.appendingPathComponent("tmp", isDirectory: true)
        let unbornRepo = root.appendingPathComponent("unborn", isDirectory: true)
        let plainFolder = root.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: unbornRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plainFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Plain non-Git folder -> pureMark
        let pureMark = await SessionMarkService.createMark(for: plainFolder, tmpDir: tmpDir)
        XCTAssertEqual(pureMark.kind, .pureMark)
        XCTAssertNil(pureMark.snapshotSHA)
        XCTAssertNil(pureMark.headSHA)

        // Unborn git repo with NO user.name/email configured
        _ = try runGit(["init"], in: unbornRepo)
        try "hello\n".write(to: unbornRepo.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let unbornMark = await SessionMarkService.createMark(for: unbornRepo, tmpDir: tmpDir)
        XCTAssertEqual(unbornMark.kind, .gitSnapshot)
        XCTAssertNil(unbornMark.headSHA)
        XCTAssertNotNil(unbornMark.snapshotSHA)

        try "changed\n".write(to: unbornRepo.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let diff = await SessionMarkService.diffSummary(for: unbornMark, in: unbornRepo, tmpDir: tmpDir)
        XCTAssertTrue(diff.available)
        XCTAssertEqual(diff.modifiedOrDeleted.map(\.path), ["main.swift"])
    }

    func testOversizedFileIsExcludedAndPreferencesDefaultCorrectly() async throws {
        let root = try makeTempDir(prefix: "FizzDeckMarkLarge")
        let tmpDir = root.appendingPathComponent("tmp", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try runGit(["init"], in: repo)
        try "small\n".write(to: repo.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        let bigData = Data(repeating: 0x41, count: 6 * 1024 * 1024)
        try bigData.write(to: repo.appendingPathComponent("big.bin"))

        let mark = await SessionMarkService.createMark(for: repo, tmpDir: tmpDir)
        XCTAssertEqual(mark.kind, .gitSnapshot)
        let treeFiles = try runGit(["ls-tree", "-r", "--name-only", XCTUnwrap(mark.snapshotSHA)], in: repo)
        XCTAssertTrue(treeFiles.contains("small.txt"))
        XCTAssertFalse(treeFiles.contains("big.bin"))

        let suiteName = "fizzdeck.tests.marks.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(MarkPreferences.implicitMarksEnabled(in: defaults))
        MarkPreferences.setImplicitMarksEnabled(false, in: defaults)
        XCTAssertFalse(MarkPreferences.implicitMarksEnabled(in: defaults))
        XCTAssertFalse(MarkPreferences.firstMarkToastShown(in: defaults))
        MarkPreferences.setFirstMarkToastShown(true, in: defaults)
        XCTAssertTrue(MarkPreferences.firstMarkToastShown(in: defaults))
    }
}
