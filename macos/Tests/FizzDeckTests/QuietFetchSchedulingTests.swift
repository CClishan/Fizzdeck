import AppKit
import XCTest
@testable import FizzDeck

final class QuietFetchSchedulingTests: XCTestCase {
    private actor Transfers {
        private(set) var paths: [String] = []
        private(set) var peak = 0
        private(set) var cancellations = 0
        private var running = 0
        private var first: CheckedContinuation<Void, Never>?

        func check(_ directory: URL, upstream: URL) async -> QuietGitFetch.Result? {
            paths.append(directory.path)
            running += 1
            peak = max(peak, running)
            defer { running -= 1; if Task.isCancelled { cancellations += 1 } }
            if paths.count == 1 { await withCheckedContinuation { first = $0 } }
            return await QuietGitFetch.check(in: directory) { git, bare, target in
                let args = QuietGitFetch.fetchArguments(for: target).map { $0 == target.url ? upstream.path : $0 }
                return await DoctorCommand.run(git, args, cwd: bare, environment: ["GIT_ALLOW_PROTOCOL": "file"]) != nil
            }
        }

        func releaseFirst() { first?.resume(); first = nil }
    }

    @MainActor func testOpeningAppOnDashboardChecksAllFocusedProjectsAndReschedulesOnActivation() async throws {
        try await QuietFetchTestProcess.run(self) { home, _ in
            try await self.checkDashboard(in: home)
        }
    }

    @MainActor private func checkDashboard(in home: URL) async throws {
        guard !RootStore.hasSavedRootsFile else { return XCTFail("Expected a fresh workspace") }
        let fm = FileManager.default, publisher = home.appendingPathComponent("publisher"), seed = home.appendingPathComponent("seed")
        let git = try XCTUnwrap(DoctorCommand.git)
        func run(_ args: [String], in dir: URL) async throws {
            let result = await DoctorCommand.run(git, ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "core.hooksPath=/dev/null"] + args,
                                                 cwd: dir, environment: ["GIT_ALLOW_PROTOCOL": "file"])
            _ = try XCTUnwrap(result, "fixture: \(args[0])")
        }
        try await run(["init", "--template=", "-b", "main", publisher.path], in: home)
        try await run(["commit", "--allow-empty", "-m", "initial"], in: publisher)
        try await run(["clone", "--template=", "--no-local", publisher.path, seed.path], in: home)
        try await run(["remote", "set-url", "origin", "git@github.com:fixture/quiet.git"], in: seed)
        let paths = try (0..<12).map { i in
            let repo = home.appendingPathComponent("project-\(i)")
            try fm.copyItem(at: seed, to: repo)
            return PathTools.normalize(repo.path)
        }
        let focused = Set(paths.prefix(10)), later = paths[10]
        try RootStore.save(paths)
        try MetaStore.save(Dictionary(uniqueKeysWithValues: focused.map { ($0, ProjectMeta(starred: true)) }))
        try await run(["commit", "--allow-empty", "-m", "second"], in: publisher)
        try await run(["commit", "--allow-empty", "-m", "third"], in: publisher)

        let suite = "quiet-launch-" + UUID().uuidString, prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 86_399), transfers = Transfers()
        var now = start
        let store = RepositoryStore(preferences: prefs, quietFetchAttempts: .init(suiteName: suite), quietFetchNow: { now }) {
            await transfers.check($0, upstream: publisher)
        }
        func until(line: UInt = #line, _ condition: () async -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(12)
            while !(await condition()) {
                if ContinuousClock.now >= deadline { throw FixtureError.timedOut(line: line) }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        func activate() { NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil) }
        await store.prepare()
        try await until { await !transfers.paths.isEmpty }
        XCTAssertEqual(store.destination, .dashboard)
        activate()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        await store.scan()
        let pending = try XCTUnwrap(store.projects.first { $0.path == later })
        store.setStarred(true, for: [pending]); store.setStarred(false, for: [pending])
        let reservations = prefs.persistentDomain(forName: suite)?.keys.filter { $0.hasPrefix("fizzdeck.quietFetch.attempt.") }
        XCTAssertEqual(reservations?.count, 1, "Waiting projects must not spend their daily attempt")
        await transfers.releaseFirst() // Finish the whole queue while the window is inactive.
        try await until { store.projects.filter { $0.behind == 2 }.count == focused.count }
        let firstPass = await transfers.paths
        XCTAssertEqual(firstPass.count, 10); XCTAssertEqual(Set(firstPass), focused)
        for path in focused {
            XCTAssertEqual(store.doctorReports[path]?.issues.first { $0.kind == .cloudBehind }?.title, "云端领先 2 个提交")
        }

        now = start.addingTimeInterval(86_399)
        activate(); await store.scan()
        store.setStarred(true, for: [pending])
        try await until { store.projects.first { $0.path == later }?.behind == 2 }
        let withinDay = await transfers.paths
        XCTAssertEqual(withinDay, firstPass + [later])

        try await run(["commit", "--allow-empty", "-m", "fourth"], in: publisher)
        now = start.addingTimeInterval(86_400)
        activate() // No intervening resign, scan, or navigation.
        try await until { store.projects.filter { $0.behind == 3 }.count == focused.count }
        let calls = await transfers.paths, peak = await transfers.peak, cancelled = await transfers.cancellations
        XCTAssertEqual(calls.count, 21); XCTAssertEqual(Set(calls.dropFirst(11)), focused)
        XCTAssertEqual(peak, 1); XCTAssertEqual(cancelled, 0)
        XCTAssertEqual(store.projects.first { $0.path == later }?.behind, 2)
        XCTAssertEqual(store.destination, .dashboard)
    }

    private enum FixtureError: Error { case timedOut(line: UInt) }
}

// Each phase is a fresh XCTest process. Only the temporary home (including preferences) survives a restart.
@MainActor enum QuietFetchTestProcess {
    static func run(_ test: XCTestCase, phases: [String] = ["run"], method: String = #function,
                    body: (URL, String) async throws -> Void) async throws {
        let fm = FileManager.default, env = ProcessInfo.processInfo.environment, marker = "FIZZDECK_QUIET_FETCH_TEST_PHASE"
        if let phase = env[marker] {
            let home = AppPaths.home
            guard phases.contains(phase), let fixed = env["CFFIXED_USER_HOME"],
                  PathTools.canonical(home.path) == PathTools.canonical(fixed), home.lastPathComponent.hasPrefix("fizz-quiet-launch-") else {
                return XCTFail("Refusing to use a non-fixture home")
            }
            try await body(home, phase)
            try Data().write(to: home.appendingPathComponent("completed-" + phase))
            return
        }
        let home = fm.temporaryDirectory.appendingPathComponent("fizz-quiet-launch-" + UUID().uuidString)
        try fm.createDirectory(at: home, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: home) }
        for phase in phases {
            let log = home.appendingPathComponent(phase + ".log")
            fm.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log), child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            child.arguments = ["xctest", "-XCTest", "\(NSStringFromClass(type(of: test)))/\(method.dropLast(2))", Bundle(for: type(of: test)).bundlePath]
            child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "CFFIXED_USER_HOME": home.path,
                                 "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", marker: phase]
            child.standardOutput = output; child.standardError = output
            try child.run()
            let deadline = ContinuousClock.now + .seconds(70)
            while child.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
            if child.isRunning { child.terminate(); return XCTFail("Isolated test timed out: " + phase) }
            try output.close()
            guard child.terminationStatus == 0, fm.fileExists(atPath: home.appendingPathComponent("completed-" + phase).path) else {
                let failure = try String(contentsOf: log, encoding: .utf8)
                return XCTFail(failure)
            }
        }
    }
}
