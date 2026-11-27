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

        // Replay the pre-existing HEAD creation after attaching, as FSEvents can do when coalescing writes.
        watcher.handleEventPaths([gitDirectory.appendingPathComponent("HEAD").path], change: .git)
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

    func testManifestEventsAreShallowTargetedAndFollowFocusChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fizz-watch-inputs-" + UUID().uuidString)
        let first = root.appendingPathComponent("one"), second = root.appendingPathComponent("two")
        let nested = first.appendingPathComponent("node_modules/pkg")
        for dir in [nested, second] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ name: String, _ dir: URL) throws { try UUID().uuidString.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        try write("package.json", first)
        var changes: [WorkspaceChange] = []
        let watcher = WorkspaceWatcher(homeDirectory: root, sessionRoots: [], debounceInterval: 0.12) { changes.append($0) }
        watcher.setFocusedPaths([first.path]); watcher.start()
        defer { watcher.stop() }
        let attached = await waitUntil(timeout: 3) { changes == [.manifest(first.path)] }
        XCTAssertTrue(attached); changes.removeAll()
        try write("package.json", nested); try write("src.swift", first); try write("pnpm-lock.yaml", second)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(changes, [])
        try write("package.json", first)
        let modified = await waitUntil(timeout: 3) { changes == [.manifest(first.path)] }
        XCTAssertTrue(modified)
        changes.removeAll()
        try "in-place".write(to: first.appendingPathComponent("package.json"), atomically: false, encoding: .utf8)
        let inPlace = await waitUntil(timeout: 3) { changes.contains(.manifest(first.path)) }
        XCTAssertTrue(inPlace)
        changes.removeAll()
        try write(".env.preview", first)
        let created = await waitUntil(timeout: 3) { changes.contains(.manifest(first.path)) }
        XCTAssertTrue(created)
        try FileManager.default.removeItem(at: first.appendingPathComponent(".env.preview"))
        let deleted = await waitUntil(timeout: 3) { changes.count >= 2 }
        XCTAssertTrue(deleted)
        changes.removeAll(); watcher.setFocusedPaths([second.path]); try write(".env.old", first)
        let attachedSecond = await waitUntil(timeout: 3) { changes == [.manifest(second.path)] }
        XCTAssertTrue(attachedSecond); changes.removeAll()
        try write("Gemfile.lock", second)
        let switched = await waitUntil(timeout: 3) { changes.contains(.manifest(second.path)) }
        XCTAssertTrue(switched)
        XCTAssertFalse(changes.contains(.manifest(first.path)))
        watcher.pause(); changes.removeAll(); try write("go.mod", second)
        try await Task.sleep(for: .milliseconds(500)); XCTAssertTrue(changes.isEmpty)
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
