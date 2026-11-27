import XCTest
@testable import FizzDeck

final class QuietGitFetchTests: XCTestCase {
    @MainActor func testAttemptWindowPersistsPerProjectIncludingAcrossMidnight() async throws {
        try await QuietFetchTestProcess.run(self, phases: ["reserve", "reopen"]) { home, phase in
            let fm = FileManager.default, suite = "quiet-window." + home.lastPathComponent
            let real = home.appendingPathComponent("project"), alias = home.appendingPathComponent("shortcut"), other = home.appendingPathComponent("other")
            let window = QuietGitFetch.AttemptWindow(suiteName: suite)
            let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 23, minute: 59, second: 59)))
            if phase == "reserve" {
                let missing = await window.reserve(path: real.path, now: now)
                XCTAssertFalse(missing.allowed)
                try fm.createDirectory(at: real, withIntermediateDirectories: false)
                try fm.createDirectory(at: other, withIntermediateDirectories: false)
                try fm.createSymbolicLink(at: alias, withDestinationURL: real)
                let first = await window.reserve(path: real.path, now: now)
                XCTAssertTrue(first.allowed)
                return // Exit before the second process opens this suite. No synchronize() or copied prefs.
            }
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: alias.path), real.path)
            XCTAssertEqual(PathTools.canonical(real.path), PathTools.canonical(alias.path))
            let midnight = await window.reserve(path: alias.path, now: now.addingTimeInterval(2))
            let independent = await window.reserve(path: other.path, now: now.addingTimeInterval(2))
            let early = await window.reserve(path: real.path, now: now.addingTimeInterval(86_399))
            let due = await window.reserve(path: alias.path, now: now.addingTimeInterval(86_400))
            XCTAssertEqual([midnight.allowed, independent.allowed, early.allowed, due.allowed], [false, true, false, true])
            XCTAssertEqual(midnight.next, now.addingTimeInterval(86_400)); XCTAssertEqual(early.next, midnight.next)
        }
    }

    func testOnlyStandardHTTPSOrPinnedForgeSSHAndInertConfigAreEligible() {
        let url = "https://github.com/example/project.git"
        let base = ["core.repositoryformatversion\n0", "core.bare\nfalse", "remote.origin.url\n\(url)",
                    "remote.origin.fetch\n+refs/heads/*:refs/remotes/origin/*", "branch.local.remote\norigin", "branch.local.merge\nrefs/heads/trunk"].joined(separator: "\0") + "\0"
        func target(_ config: String) -> QuietGitFetch.Target? { QuietGitFetch.target(config: config, head: "ref: refs/heads/local") }
        XCTAssertEqual(target(base)?.tracking, "refs/remotes/origin/trunk")
        for host in ["github.com", "gitlab.com", "bitbucket.org"] {
            let ssh = "ssh://git@\(host)/org/project.git"
            for form in ["git@\(host):org/project.git", ssh, "ssh://git@\(host):22/org/project.git"] {
                XCTAssertEqual(target(base.replacingOccurrences(of: url, with: form))?.url, ssh)
            }
        }
        for key in ["include.path", "core.hookspath", "core.fsmonitor", "core.sshcommand", "remote.origin.uploadpack", "remote.origin.vcs", "filter.demo.clean", "credential.helper", "url.other.insteadof", "http.extraheader"] {
            XCTAssertNil(target(base + "\(key)\nunused\0"))
        }
        for other in ["file:///tmp/repo", "ssh://github.com/example/project", "custom::example", "https://user@github.com/example/project", "https://localhost/a/b", url + "?q=1", "https://github.com/a/../b",
                      "git@github-alias:a/b", "other@github.com:a/b", "git@github.com.invalid:a/b", "ssh://git@github.com:443/a/b", "ssh://git@github.com@invalid/a/b", "git@github.com:a/b%20c", "git@github.com:a/../b", "git@github.com:a/b?ref=v2"] {
            XCTAssertNil(target(base.replacingOccurrences(of: url, with: other)))
        }
        XCTAssertNil(target(base + "remote.origin.url\n\(url)\0"))
        XCTAssertNil(target(base.replacingOccurrences(of: "refs/remotes/origin/*", with: "refs/heads/*")))
        XCTAssertNil(QuietGitFetch.target(config: base, head: String(repeating: "a", count: 40)))
    }

    func testRealFetchAdvancesOnlyTrackingRefWhilePreservingIndexAndDirtyFiles() async throws {
        let git = try XCTUnwrap(DoctorCommand.git)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-git-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let upstream = root.appendingPathComponent("publisher"), clone = root.appendingPathComponent("checkout")
        func run(_ args: [String], in dir: URL) async throws -> String {
            let result = await DoctorCommand.run(git, ["-c", "core.hooksPath=/dev/null", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid"] + args,
                                                 cwd: dir, environment: ["GIT_ALLOW_PROTOCOL": "file"])
            return try XCTUnwrap(result, "fixture git \(args.first ?? "")").trimmingCharacters(in: .newlines)
        }
        _ = try await run(["init", "--template=", "-b", "main", upstream.path], in: root)
        try "one".write(to: upstream.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        _ = try await run(["add", "file"], in: upstream)
        _ = try await run(["commit", "-m", "first"], in: upstream)
        _ = try await run(["clone", "--no-local", "--template=", upstream.path, clone.path], in: root)
        _ = try await run(["remote", "set-url", "origin", "https://github.com/example/project.git"], in: clone)
        try "local edit".write(to: clone.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        let original = try await run(["rev-parse", "HEAD"], in: clone)
        let index = try Data(contentsOf: clone.appendingPathComponent(".git/index"))
        try "two".write(to: upstream.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        _ = try await run(["commit", "-am", "second"], in: upstream)
        let expected = try await run(["rev-parse", "HEAD"], in: upstream)
        // Only the test transport uses a local fixture. Target validation, isolated Git dirs and publication are real.
        let result = await QuietGitFetch.check(in: clone) { git, bare, target in
            let args = QuietGitFetch.fetchArguments(for: target).map { $0 == target.url ? upstream.path : $0 }
            let ok = await DoctorCommand.run(git, args, cwd: bare, environment: ["GIT_ALLOW_PROTOCOL": "file"])
            return ok != nil
        }
        XCTAssertEqual(result?.head, original)
        XCTAssertEqual(result?.counts, GitTrackingCounts(behind: 1, ahead: 0))
        let nextUpstream = try await run(["rev-parse", "@{u}"], in: clone)
        let nextHead = try await run(["rev-parse", "HEAD"], in: clone)
        XCTAssertEqual(nextUpstream, expected)
        XCTAssertEqual(nextHead, original)
        XCTAssertEqual(try Data(contentsOf: clone.appendingPathComponent(".git/index")), index)
        XCTAssertEqual(try String(contentsOf: clone.appendingPathComponent("file"), encoding: .utf8), "local edit")
        XCTAssertFalse(FileTools.exists(clone.appendingPathComponent(".git/FETCH_HEAD")))

        _ = try await run(["config", "core.hooksPath", "unused-fixture-path"], in: clone)
        let rejected = await QuietGitFetch.check(in: clone) { _, _, _ in XCTFail("no transport for unsupported config"); return false }
        XCTAssertNil(rejected)
    }

    func testTimeoutOnOwnedChildIsBounded() async {
        let clock = ContinuousClock(), started = clock.now
        let value = await DoctorCommand.run("/bin/sleep", ["5"], cwd: URL(fileURLWithPath: "/"), timeout: 0.12)
        XCTAssertNil(value)
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(2))
    }
}
