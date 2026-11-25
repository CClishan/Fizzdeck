import Foundation
import XCTest
@testable import FizzDeck

final class GitSyncServiceTests: XCTestCase {
    func testPushWithoutUpstreamReturnsActionableMessage() async throws {
        let directory = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await GitSyncService.run(.push, in: directory)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message.contains("没有 upstream"), result.message)
    }

    func testFetchWithHTTP401ReportsCredentialFailure() async throws {
        let directory = try makeRepository()
        let server = try LocalAuthServer()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try git(["config", "http.proxy", ""], in: directory)
        try git(["remote", "add", "origin", "http://127.0.0.1:\(server.port)/repo.git"], in: directory)

        let started = Date()
        let result = await GitSyncService.run(.fetch, in: directory)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message.contains("Git 凭据不可用"), result.message)
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
    }

    func testFetchWithSSHPublicKeyFailureReportsKeyFailure() async throws {
        let directory = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ssh = directory.appendingPathComponent("fake-ssh")
        try "#!/bin/sh\necho 'Permission denied (publickey).' >&2\nexit 255\n"
            .write(to: ssh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ssh.path)

        try git(["remote", "add", "origin", "ssh://git@127.0.0.1/repo.git"], in: directory)
        try git(["config", "core.sshCommand", ssh.path], in: directory)

        let started = Date()
        let result = await GitSyncService.run(.fetch, in: directory)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message.contains("SSH 密钥不可用"), result.message)
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
    }

    func testFailureMapsNetworkAndFastForwardErrors() {
        let network = GitSyncService.failure(
            .fetch,
            result: ShellOutput(
                status: 128,
                text: "fatal: unable to access 'https://example.invalid/repo.git': Could not resolve host"
            )
        )
        XCTAssertEqual(network.status, .failed)
        XCTAssertTrue(network.message.contains("无法访问远端"), network.message)

        let diverged = GitSyncService.failure(
            .pull,
            result: ShellOutput(
                status: 128,
                text: "fatal: Not possible to fast-forward, aborting."
            )
        )
        XCTAssertEqual(diverged.status, .failed)
        XCTAssertTrue(diverged.message.contains("无法 fast-forward"), diverged.message)
    }

    func testFetchToClosedLocalPortReportsNetworkFailure() async throws {
        let directory = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        try git(["config", "http.proxy", ""], in: directory)
        try git(["remote", "add", "origin", "http://127.0.0.1:9/repo.git"], in: directory)

        let started = Date()
        let result = await GitSyncService.run(.fetch, in: directory)

        XCTAssertTrue(result.status == .failed, result.message)
        XCTAssertTrue(result.message.contains("无法访问远端"), result.message)
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
    }

    func testPullWithUncommittedFileIsBlockedBeforeNetwork() async throws {
        let directory = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        try "changed".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = await GitSyncService.run(.pull, in: directory)

        XCTAssertTrue(result.status == .blocked, result.message)
        XCTAssertTrue(result.message.contains("1 个文件未提交"), result.message)
    }

    func testShellTimeoutTerminatesHungCommand() async {
        let started = Date()
        let result = await Shell.run("sh", ["-c", "exec sleep 5"], timeout: 0.2)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertTrue(result?.timedOut == true)
        XCTAssertLessThan(elapsed, 3)
    }

    private func makeRepository() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckGitSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try git(["init"], in: directory)
        try git(["config", "user.email", "test@example.com"], in: directory)
        try git(["config", "user.name", "FizzDeck Test"], in: directory)
        try "initial".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try git(["add", "README.md"], in: directory)
        try git(["commit", "-m", "initial"], in: directory)
        return directory
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            XCTFail(
                "git \(arguments.joined(separator: " ")) failed: "
                    + (String(data: data, encoding: .utf8) ?? "unknown error")
            )
            throw GitTestError.commandFailed
        }
    }
}

private enum GitTestError: Error {
    case commandFailed
    case serverStartupFailed
}

private final class LocalAuthServer {
    let port: Int
    private let process: Process
    private let directory: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FizzDeckAuthServer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory

        let script = directory.appendingPathComponent("server.py")
        let portFile = directory.appendingPathComponent("port")
        try """
        import http.server
        import socketserver
        import sys

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="FizzDeckTest"')
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, *args):
                pass

        with socketserver.TCPServer(("127.0.0.1", 0), Handler) as server:
            with open(sys.argv[1], "w") as file:
                file.write(str(server.server_address[1]))
            server.serve_forever()
        """.write(to: script, atomically: true, encoding: .utf8)

        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", script.path, portFile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let text = try? String(contentsOf: portFile, encoding: .utf8),
               let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.port = port
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        process.terminate()
        try? FileManager.default.removeItem(at: directory)
        throw GitTestError.serverStartupFailed
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
