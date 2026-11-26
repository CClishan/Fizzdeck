import XCTest
@testable import FizzDeck

@MainActor
final class WorkspaceWatcherTests: XCTestCase {
    func testDebounceCoalescesBurstIntoOneCallback() async {
        var changes: [WorkspaceChange] = []
        let debouncer = WorkspaceDebouncer(interval: 0.15) { changes.append($0) }

        for _ in 0..<8 {
            debouncer.schedule(.sessions)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(debouncer.scheduledCount, 8)
        XCTAssertEqual(changes, [])

        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(changes, [.sessions])
    }

    func testDebounceMergesSessionAndGitChanges() async {
        var changes: [WorkspaceChange] = []
        let debouncer = WorkspaceDebouncer(interval: 0.1) { changes.append($0) }

        debouncer.schedule(.sessions)
        debouncer.schedule(.git)
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(changes, [.sessions, .git])
    }

    func testCancelDropsPendingCallback() async {
        var changes: [WorkspaceChange] = []
        let debouncer = WorkspaceDebouncer(interval: 0.1) { changes.append($0) }

        debouncer.schedule(.sessions)
        debouncer.cancel()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(changes, [])
    }

    func testWatcherLifecyclePauseResumeAndStop() async {
        var changes: [WorkspaceChange] = []
        let watcher = WorkspaceWatcher(debounceInterval: 0.05) { changes.append($0) }

        XCTAssertFalse(watcher.isStarted)
        watcher.start()
        XCTAssertTrue(watcher.isStarted)
        XCTAssertFalse(watcher.isPaused)

        watcher.pause()
        XCTAssertTrue(watcher.isPaused)
        changes.removeAll()

        watcher.resume()
        XCTAssertFalse(watcher.isPaused)
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(changes.contains(.sessions))

        watcher.stop()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(watcher.isStarted)
        XCTAssertNil(watcher.gitPath)
        changes.removeAll()
        watcher.resume()
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(changes, [])
    }

    func testWatcherObservesGitHeadChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckWatchGit-\(UUID().uuidString)", isDirectory: true)
        let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "ref: refs/heads/main\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        var gitEvents = 0
        let watcher = WorkspaceWatcher(debounceInterval: 0.2) { change in
            if change == .git { gitEvents += 1 }
        }
        watcher.start()
        watcher.setGitPath(root.path)
        defer { watcher.stop() }

        try? await Task.sleep(for: .milliseconds(600))
        try "ref: refs/heads/feature\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        let changed = await waitUntil(timeout: 4) { gitEvents > 0 }
        XCTAssertTrue(changed)
        XCTAssertGreaterThanOrEqual(gitEvents, 1)
    }

    func testWatcherObservesSessionRootWrites() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckWatchSessions-\(UUID().uuidString)", isDirectory: true)
        let root = home.appendingPathComponent(".gemini/tmp/slug/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        var sessionEvents = 0
        let watcher = WorkspaceWatcher(
            homeDirectory: home,
            sessionRoots: [".gemini/tmp"],
            debounceInterval: 0.2
        ) { change in
            if change == .sessions { sessionEvents += 1 }
        }
        watcher.start()
        defer { watcher.stop() }

        try? await Task.sleep(for: .milliseconds(600))
        try """
        {"sessionId":"watch-catch","kind":"main"}
        {"type":"user","content":"监听"}
        """.write(
            to: root.appendingPathComponent("session-watch.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let changed = await waitUntil(timeout: 4) { sessionEvents > 0 }
        XCTAssertTrue(changed)
    }

    func testWatcherIgnoresGitFilesOutsideHeadAndIndex() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckWatchGitFilter-\(UUID().uuidString)", isDirectory: true)
        let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "ref: refs/heads/main\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        var gitEvents = 0
        let watcher = WorkspaceWatcher(debounceInterval: 0.2) { change in
            if change == .git { gitEvents += 1 }
        }
        watcher.start()
        watcher.setGitPath(root.path)
        defer { watcher.stop() }

        try? await Task.sleep(for: .milliseconds(700))
        try "[core]\n\tbare = false\n".write(
            to: gitDirectory.appendingPathComponent("config"),
            atomically: true,
            encoding: .utf8
        )
        try? await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(gitEvents, 0)

        try Data([0x44, 0x49, 0x52, 0x43]).write(
            to: gitDirectory.appendingPathComponent("index"),
            options: .atomic
        )
        let changed = await waitUntil(timeout: 4) { gitEvents > 0 }
        XCTAssertTrue(changed, "Writing .git/index should still trigger a refresh")
    }

    func testGitPathMatching() {
        let project = "/tmp/example"
        XCTAssertTrue(WorkspaceWatchPaths.touchesGit(path: "/tmp/example/.git/HEAD", gitPath: project))
        XCTAssertTrue(WorkspaceWatchPaths.touchesGit(path: "/tmp/example/.git/index", gitPath: project))
        XCTAssertFalse(WorkspaceWatchPaths.touchesGit(path: "/tmp/example/.git/config", gitPath: project))
        XCTAssertFalse(WorkspaceWatchPaths.touchesGit(path: "/tmp/other/.git/HEAD", gitPath: project))
        XCTAssertFalse(WorkspaceWatchPaths.touchesGit(path: "/tmp/example/.git/HEAD", gitPath: nil))
    }

    func testGitPathMatchingResolvesSymlinkedWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckWatchSymlink-\(UUID().uuidString)", isDirectory: true)
        let realRepo = root.appendingPathComponent("real-repo", isDirectory: true)
        let gitDir = realRepo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let symlinkRepo = root.appendingPathComponent("link-repo", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkRepo, withDestinationURL: realRepo)

        let realHead = gitDir.appendingPathComponent("HEAD").path
        XCTAssertTrue(WorkspaceWatchPaths.touchesGit(path: realHead, gitPath: symlinkRepo.path))
        XCTAssertFalse(WorkspaceWatchPaths.touchesGit(
            path: gitDir.appendingPathComponent("config").path,
            gitPath: symlinkRepo.path
        ))
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
