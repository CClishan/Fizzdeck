import Darwin
import XCTest
@testable import FizzDeck

final class QuietGitSSHTests: XCTestCase {
    func testSystemSSHResolvesEffectivePolicyWithoutConnecting() async throws {
        let target = QuietGitFetch.Target(url: "ssh://git@github.com/org/repo.git", branch: "main", source: "refs/heads/main", tracking: "refs/remotes/origin/main")
        let env = QuietGitFetch.transportEnvironment(git: try XCTUnwrap(DoctorCommand.git), target: target)
        XCTAssertEqual(env["GIT_ALLOW_PROTOCOL"], "ssh"); XCTAssertNil(env["SSH_AUTH_SOCK"]); XCTAssertNil(env["https_proxy"])
        XCTAssertEqual(env["SSH_ASKPASS_REQUIRE"], "never")
        let words = try XCTUnwrap(env["GIT_SSH_COMMAND"]).split(separator: " ").map(String.init)
        XCTAssertEqual(words.first, "/usr/bin/ssh"); XCTAssertTrue(words.contains("/dev/null"))
        let dump = await DoctorCommand.run("/usr/bin/ssh", ["-G"] + words.dropFirst() + ["git@github.com"], cwd: URL(fileURLWithPath: "/"))
        let lines = Set(try XCTUnwrap(dump).split(separator: "\n").map(String.init))
        for line in ["user git", "hostname github.com", "port 22", "batchmode yes", "passwordauthentication no", "kbdinteractiveauthentication no",
                     "preferredauthentications publickey", "forwardagent no", "identityagent none", "permitlocalcommand no", "clearallforwardings yes", "connecttimeout 4"] {
            XCTAssertTrue(lines.contains(line), line)
        }
        XCTAssertFalse(lines.isDisjoint(with: ["stricthostkeychecking true", "stricthostkeychecking yes"]))
        XCTAssertFalse(lines.isDisjoint(with: ["updatehostkeys false", "updatehostkeys no"]))
    }

    func testAuthenticatedFetchRejectsUnknownChangedHostsAndMissingAuthorization() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd"), "requires system OpenSSH")
        let root = URL(fileURLWithPath: "/tmp/fizz-ssh-" + UUID().uuidString), git = try XCTUnwrap(DoctorCommand.git)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        func write(_ text: String, _ name: String) throws { try Data(text.utf8).write(to: root.appendingPathComponent(name)) }
        for key in ["host", "client"] {
            let result = await DoctorCommand.run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", root.appendingPathComponent(key).path], cwd: root)
            _ = try XCTUnwrap(result)
        }
        let host = try String(contentsOf: root.appendingPathComponent("host.pub"), encoding: .utf8)
        let client = try String(contentsOf: root.appendingPathComponent("client.pub"), encoding: .utf8)
        let trust = "github.com " + host, known = root.appendingPathComponent("known_hosts")
        let repo = root.appendingPathComponent("publisher"), bare = root.appendingPathComponent("client.git")
        func fixtureGit(_ args: [String], _ cwd: URL) async throws -> String {
            let result = await DoctorCommand.run(git, ["-c", "core.hooksPath=/dev/null", "-c", "user.name=Fixture", "-c", "user.email=test@example.invalid"] + args,
                                                 cwd: cwd, environment: ["GIT_ALLOW_PROTOCOL": "file"])
            return try XCTUnwrap(result).trimmingCharacters(in: .newlines)
        }
        _ = try await fixtureGit(["init", "--template=", "-b", "main", repo.path], root)
        _ = try await fixtureGit(["commit", "--allow-empty", "-m", "one"], repo)
        _ = try await fixtureGit(["clone", "--bare", "--no-local", "--template=", repo.path, bare.path], root)
        _ = try await fixtureGit(["update-ref", "refs/heads/base", "HEAD"], bare)
        _ = try await fixtureGit(["commit", "--allow-empty", "-m", "two"], repo)
        let expected = try await fixtureGit(["rev-parse", "HEAD"], repo)
        try write(client, "authorized_keys")
        try write("""
        HostKey \(root.path)/host
        AuthorizedKeysFile \(root.path)/authorized_keys
        AllowUsers \(NSUserName())
        StrictModes no
        UsePAM no
        AuthenticationMethods publickey
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        DisableForwarding yes
        PermitTTY no
        PermitUserRC no
        PrintMotd no
        PrintLastLog no
        UseDNS no
        ForceCommand \(git) upload-pack \(repo.path)
        """, "sshd.conf")

        let target = QuietGitFetch.Target(url: "ssh://git@github.com/org/project.git", branch: "main", source: "refs/heads/main", tracking: "refs/remotes/origin/main")
        func fetch() async throws -> Bool {
            try await withLoopbackSSHD(root) { port in
                // Only our socket, temporary identities and host database differ from the production client policy.
                var policy = QuietGitFetch.sshArguments.filter { !$0.hasPrefix("-oIdentityFile=") && !$0.hasPrefix("-oUserKnownHostsFile=") && !$0.hasPrefix("-oGlobalKnownHostsFile=") }
                let p = try XCTUnwrap(policy.firstIndex(of: "-p")); policy[p + 1] = String(port)
                policy += ["-oHostName=127.0.0.1", "-oHostKeyAlias=github.com", "-oUserKnownHostsFile=\(known.path)",
                           "-oGlobalKnownHostsFile=/dev/null", "-oIdentityFile=\(root.path)/client"]
                var env = QuietGitFetch.transportEnvironment(git: git, target: target)
                env["GIT_SSH_COMMAND"] = (["/usr/bin/ssh"] + policy).joined(separator: " ")
                let args = QuietGitFetch.fetchArguments(for: target).map { $0 == target.url ? "ssh://\(NSUserName())@github.com/org/project.git" : $0 }
                return await DoctorCommand.run(git, args, cwd: bare, environment: env, timeout: 5) != nil
            }
        }

        try write(trust, "known_hosts")
        let fetched = try await fetch(); XCTAssertTrue(fetched)
        let received = try await fixtureGit(["rev-parse", "refs/heads/received"], bare); XCTAssertEqual(received, expected)
        for untrusted in ["", "github.com " + client] {
            try write(untrusted, "known_hosts")
            let accepted = try await fetch(); XCTAssertFalse(accepted)
            XCTAssertEqual(try Data(contentsOf: known), Data(untrusted.utf8))
        }
        try write(trust, "known_hosts"); try write("", "authorized_keys")
        let unauthorized = try await fetch(); XCTAssertFalse(unauthorized)
        XCTAssertEqual(try Data(contentsOf: known), Data(trust.utf8))
    }

    // One connection to an ephemeral loopback socket. No Remote Login setting, user keys or existing process involved.
    private func withLoopbackSSHD(_ dir: URL, client: (UInt16) async throws -> Bool) async throws -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0); guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(address.sin_len)
        let ready = withUnsafeMutablePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, length) == 0 && listen(fd, 1) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        guard ready else { throw POSIXError(.EADDRNOTAVAIL) }
        let server = Task.detached {
            var reader = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&reader, 1, 6000) > 0 else { return false }
            let socket = accept(fd, nil, nil); guard socket >= 0 else { return false }
            let io = FileHandle(fileDescriptor: socket, closeOnDealloc: true), process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd"); process.arguments = ["-i", "-f", dir.appendingPathComponent("sshd.conf").path]
            process.standardInput = io; process.standardOutput = io; process.standardError = FileHandle.nullDevice
            process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
            do { try process.run(); try io.close(); process.waitUntilExit(); return true } catch { return false }
        }
        let result = try await client(UInt16(bigEndian: address.sin_port))
        let connected = await server.value; XCTAssertTrue(connected)
        return result
    }
}
