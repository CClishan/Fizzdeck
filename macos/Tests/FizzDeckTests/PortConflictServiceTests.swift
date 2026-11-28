import Darwin
import XCTest
@testable import FizzDeck

final class PortConflictServiceTests: ChineseInterfaceTestCase {
    func testCachedListenerCanLocalizeAMissingNameAndPreserveARealName() throws {
        let inputs = ["p12\0f5\0tIPv4\0n127.0.0.1:3000\0", "p12\0c未知进程\0f5\0tIPv4\0n127.0.0.1:3000\0"]
        let captured = try FizzL10n.$languageOverride.withValue(.chinese) {
            try inputs.map { try XCTUnwrap(PortConflictService.parseListeners($0, ports: [3000]).first) }
        }
        FizzL10n.$languageOverride.withValue(.english) {
            XCTAssertTrue(captured[0].occupantSummary.contains("Unknown process"), "Unnamed process: \(captured[0].occupantSummary)")
            XCTAssertTrue(captured[1].occupantSummary.contains("未知进程"), "Real process name: \(captured[1].occupantSummary)")
        }
    }

    func testFieldRecordsKeepPortPIDAndFamilyTogetherWithoutDuplicateListeners() throws {
        let fields = ["p101", "cnode", "u501", "\nf4", "tIPv6", "n[::1]:5173", "\nf5", "tIPv4", "n*:5173",
                      "\nf6", "tIPv4", "n127.0.0.1:9100", "\np202", "cpython", "u502", "\nf7", "tIPv4", "n*:3000"]
        let rows = PortConflictService.parseListeners(fields.joined(separator: "\0"), ports: [3000, 5173])
        XCTAssertEqual(rows.map(\.port), [3000, 5173])
        XCTAssertEqual(rows.map(\.occupantSummary), ["python · PID 202", "node · PID 101"])
        let ipv46 = try XCTUnwrap(rows.last?.occupants.first)
        XCTAssertEqual(ipv46.previewHosts, ["127.0.0.1", "[::1]"])
        XCTAssertEqual(ipv46.addresses, ["*:5173", "[::1]:5173"])
        XCTAssertEqual(ipv46.uid, 501)
        XCTAssertFalse(ipv46.canStop) // lsof's PID and UID alone are not a stop handle
    }

    func testMalformedPIDAndNewlinesInNamesCannotInventListeners() throws {
        let fields = ["p404", "u501", "\nf4", "tIPv4", "n*:3000", "\np505", "cworker\np777", "u501", "\nf4", "tIPv4", "n*:3000", "\npABC", "\nf4", "tIPv4", "n*:3000"]
        let row = try XCTUnwrap(PortConflictService.parseListeners(fields.joined(separator: "\0"), ports: [3000]).first)
        XCTAssertEqual(row.occupants.map(\.pid), [404, 505])
        XCTAssertEqual(row.occupants.map(\.displayName), ["未知进程", "worker\np777"])
        XCTAssertNil(ListenerIdentity.read(getpid()))
        XCTAssertNil(ListenerIdentity.read(1))
    }

    func testTerminateRejectsEmptyConfirmedTargets() async {
        let conflict = PortConflict(port: 5173, occupants: [], note: "unknown")
        let result = await PortConflictService.terminateConfirmed(conflict)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("没有可结束的 PID"))
    }

    @MainActor
    func testSharedStopRoutesUntrackedListenerToDoctorAndOnlyStopsTheRecordedLaunch() async throws {
        let dir = try directory()
        let (external, port) = try await startListener(in: dir, log: "dev.log").waitUntilReady()
        let project = RepoProject(path: dir.path, name: "fixture", displayName: "Fixture", group: "", recent: nil,
                                  branch: nil, lastCommit: nil, dirtyCount: 0, changes: .zero, ahead: 0, behind: 0,
                                  weekly: [:], stacks: [], size: .empty, cleanup: .empty,
                                  run: RunConfig(command: "fixture", port: port, previewURL: nil), sessions: .empty,
                                  intro: .empty, artwork: nil, test: nil, starred: false, color: nil, note: "", port: .running)
        let store = RepositoryStore()
        let actions = ProjectActions()
        store.projects = [project]
        var presented = false
        await actions.stop(project, store: store) { presented = true }
        XCTAssertTrue(presented)
        XCTAssertTrue(actions.message(for: dir.path)?.contains("逐个核对 PID") == true)
        let notice = try XCTUnwrap(ToastCenter.shared.current)
        defer { ToastCenter.shared.dismiss(id: notice.id) }
        let next = try XCTUnwrap(notice.action)
        XCTAssertEqual(next.title, "去体检")
        next.handler()
        XCTAssertEqual(store.destination, .cleanup)
        XCTAssertTrue(external.isRunning)

        // Even a sibling with the same UID, cwd, dev log and port is not descended from this launch.
        let (launch, _) = try await startListener(in: dir, port: port, log: "dev.log", throughParent: true).waitUntilReady()
        let owner = PreviewProject(path: dir.path, title: "Fixture", port: port, logPath: dir.appendingPathComponent("dev.log").path)
        XCTAssertTrue(owner.owns(listener: external.processIdentifier))
        XCTAssertFalse(owner.owns(listener: external.processIdentifier, launchedBy: launch.processIdentifier))
        let before = try await PortConflictService.snapshot(ports: [port])
        let target = try XCTUnwrap(before.first?.occupants.first {
            $0.pid != external.processIdentifier && $0.command?.contains(dir.appendingPathComponent("listen-fixture.py").path) == true
        })
        var prompts = 0
        let outcome = await ManagedPreviewStop.request(project: owner, launch: launch, isCurrent: { true }) { shown, selected in
            prompts += 1
            return shown == owner && selected == target
        }
        XCTAssertEqual(prompts, 1)
        guard case .reviewInDoctor(let reason) = outcome else { return XCTFail("External listener still holds the port") }
        XCTAssertTrue(reason.contains("仍有其他监听"), reason)
        let after = try await PortConflictService.snapshot(ports: [port])
        XCTAssertEqual(after.first?.occupants.map(\.pid), [external.processIdentifier])
    }

    @MainActor
    func testSharedStopCancellationOrRevokedRegistrationDuringConfirmationSendsNoSignal() async throws {
        let dir = try directory()
        let (launch, port) = try await startListener(in: dir, log: "dev.log", declineTERM: true).waitUntilReady()
        let owner = PreviewProject(path: dir.path, title: "Fixture", port: port, logPath: dir.appendingPathComponent("dev.log").path)
        let cancelled = await ManagedPreviewStop.request(project: owner, launch: launch, isCurrent: { true }) { _, _ in false }
        XCTAssertEqual(cancelled, .cancelled)
        var registered = true
        let revoked = await ManagedPreviewStop.request(project: owner, launch: launch, isCurrent: { registered }) { _, target in
            XCTAssertEqual(target.pid, launch.processIdentifier)
            registered = false
            return true
        }
        guard case .reviewInDoctor = revoked else { return XCTFail("Revoked registration permitted a stop") }
        XCTAssertFalse(registered)
        XCTAssertTrue(launch.isRunning)
        XCTAssertFalse(FileTools.exists(dir.appendingPathComponent("signals")))
    }

    func testManagedPreviewRequiresAppAncestryCwdAndDevLogAndStopOnlySignalsSelectedListener() async throws {
        let dir = try directory()
        let (first, port) = try await startListener(in: dir, log: "dev.log", throughParent: true).waitUntilReady()
        let project = PreviewProject(path: dir.path, title: "Fixture", port: port, logPath: dir.appendingPathComponent("dev.log").path)
        let samePort = PreviewProject(path: dir.path, title: "Other", port: port, logPath: dir.appendingPathComponent("other.log").path)
        let rows = try await DeveloperListener.scan(ports: [port], projects: [samePort, project])
        let row = try XCTUnwrap(rows.first)
        XCTAssertNotEqual(first.processIdentifier, row.process.pid) // listener is a grandchild, as with npm
        XCTAssertEqual(row.owner, project)
        XCTAssertTrue(row.process.displayCommand.contains("listen-fixture.py"))
        XCTAssertEqual(row.process.uid, getuid())
        let preview = await PortConflictService.previewURL(port: port, occupant: row.process, project: project)
        XCTAssertEqual(preview, "http://127.0.0.1:\(port)")
        let impostorPreview = await PortConflictService.previewURL(port: port, occupant: row.process, project: samePort)
        XCTAssertNil(impostorPreview)
        let (second, _) = try await startListener(in: dir, port: port, log: "external.log").waitUntilReady()
        let shared = try await DeveloperListener.scan(ports: [port], projects: [project])
        XCTAssertEqual(shared.count, 2)
        XCTAssertNil(shared.first(where: { $0.process.pid == second.processIdentifier })?.owner)
        let both = try XCTUnwrap(shared.first?.conflict)
        let noSelection = await PortConflictService.terminateConfirmed(both.confirmedByUser())
        XCTAssertFalse(noSelection.succeeded)
        XCTAssertTrue(second.isRunning)
        let ambiguous = await PortConflictService.previewURL(port: port, occupant: row.process, project: project)
        XCTAssertNil(ambiguous)
        let result = await PortConflictService.terminateConfirmed(row.conflict.confirmedByUser(), only: row.process, managedBy: project)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(second.isRunning)
        let remaining = try await PortConflictService.snapshot(ports: [port])
        XCTAssertEqual(remaining.first?.occupants.map(\.pid), [second.processIdentifier])
    }

    func testStalePIDOwnerCommandGenerationOrManagedProofNeverSignalsTheFixture() async throws {
        let dir = try directory()
        let (child, port) = try await startListener(in: dir, log: "dev.log").waitUntilReady()
        let scanned = try await PortConflictService.snapshot(ports: [port])
        let original = try XCTUnwrap(scanned.first)
        let proc = try XCTUnwrap(original.occupants.first)
        let identity = try XCTUnwrap(proc.identity)
        let implicit = await PortConflictService.terminateConfirmed(original)
        XCTAssertFalse(implicit.succeeded)
        var wrongUID = proc; wrongUID.uid = identity.uid &+ 1
        var wrongCommand = proc; wrongCommand.command = "different"
        var recycledPID = proc
        recycledPID.identity = ListenerIdentity(pid: proc.pid, uid: identity.uid, version: identity.version &+ 1, executable: identity.executable)
        for stale in [wrongUID, wrongCommand, recycledPID] {
            let request = PortConflict(port: port, occupants: [stale], note: nil).confirmedByUser()
            let result = await PortConflictService.terminateConfirmed(request)
            XCTAssertFalse(result.succeeded)
            XCTAssertTrue(child.isRunning)
        }
        let renamedLog = PreviewProject(path: dir.path, title: "wrong", port: port, logPath: dir.appendingPathComponent("renamed").path)
        let consent = original.confirmedByUser()
        let unmanaged = await PortConflictService.terminateConfirmed(consent, only: proc, managedBy: renamedLog)
        XCTAssertFalse(unmanaged.succeeded)
        let retry = await PortConflictService.terminateConfirmed(consent, only: proc)
        XCTAssertFalse(retry.succeeded)
        XCTAssertTrue(child.isRunning)
        guard identity.pid == child.processIdentifier, identity.sendTERM() else { return XCTFail("Fixture identity changed") }
        try await Self.waitForExit(child)
        let (replacement, _) = try await startListener(in: dir, port: port, log: "dev.log").waitUntilReady()
        let result = await PortConflictService.terminateConfirmed(original.confirmedByUser())
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(replacement.isRunning)
    }

    func testDetachedDevFixtureIsOnlyAPossibleOrphanAndCanBeStoppedAfterConfirmation() async throws {
        let dir = try directory()
        let pidFile = dir.appendingPathComponent("orphan-pid")
        let (parent, port) = try await startListener(in: dir, log: "orphan.log", orphanPID: pidFile).waitUntilReady()
        try await Self.waitForExit(parent)
        let pid = try XCTUnwrap(Int32(FileTools.readFileIfExists(pidFile)))
        let configured = PreviewProject(path: dir.path, title: "Fixture", port: port, logPath: dir.appendingPathComponent("orphan.log").path)
        let rows = try await DeveloperListener.scan(ports: [port], projects: [configured])
        // Refuse to exercise the positive stop path unless both PID and the unique fixture script match.
        let row = try XCTUnwrap(rows.first { $0.process.pid == pid && $0.process.command?.contains(dir.appendingPathComponent("listen-fixture.py").path) == true })
        XCTAssertNil(row.owner)
        XCTAssertTrue(row.possibleOrphan)
        let result = await PortConflictService.terminateConfirmed(row.conflict.confirmedByUser(), only: row.process)
        XCTAssertTrue(result.succeeded, result.message)
    }

    func testListenerThatDeclinesTERMIsLeftAliveWithoutAnotherSignal() async throws {
        let dir = try directory()
        let (child, port) = try await startListener(in: dir, log: "stubborn.log", declineTERM: true).waitUntilReady()
        defer { try? Data().write(to: dir.appendingPathComponent("finish")) }
        let scanned = try await PortConflictService.snapshot(ports: [port])
        let conflict = try XCTUnwrap(scanned.first)
        let target = try XCTUnwrap(conflict.occupants.first { $0.pid == child.processIdentifier && $0.command?.contains(dir.appendingPathComponent("listen-fixture.py").path) == true })
        let result = await PortConflictService.terminateConfirmed(conflict.confirmedByUser(), only: target)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("仍在监听"), result.message)
        XCTAssertTrue(child.isRunning)
        XCTAssertEqual(FileTools.readFileIfExists(dir.appendingPathComponent("signals")), "TERM\n")
    }

    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ports-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private static func waitForExit(_ process: Process) async throws {
        for _ in 0..<150 {
            guard process.isRunning, let info = ListenerIdentity.bsdInfo(process.processIdentifier), info.pbi_status != SZOMB else { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "PortFixtureExitTimeout", code: 1)
    }

    /// Only loopback sockets, OS-assigned first port, no discovery of or signals to existing listeners.
    private func startListener(in dir: URL, port: Int = 0, log: String, throughParent: Bool = false, orphanPID: URL? = nil, declineTERM: Bool = false) throws -> PendingListener {
        let script = dir.appendingPathComponent("listen-fixture.py")
        if !FileTools.exists(script) {
            try """
            import socket, sys, time, pathlib, signal
            if sys.argv[3] == 'decline':
                def decline(*args):
                    with open('signals', 'a') as log:
                        print('TERM', file=log)
                signal.signal(signal.SIGTERM, decline)
            with socket.socket() as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
                s.bind(('127.0.0.1', int(sys.argv[2])))
                s.listen()
                pathlib.Path(sys.argv[1]).write_text(str(s.getsockname()[1]))
                deadline = time.monotonic() + 12
                folder = pathlib.Path(sys.argv[1]).parent
                done = pathlib.Path(sys.argv[1] + '.finish')
                while time.monotonic() < deadline and folder.exists() and not (done.exists() or pathlib.Path('finish').exists()):
                    time.sleep(.04)
            """.write(to: script, atomically: true, encoding: .utf8)
        }
        let ready = dir.appendingPathComponent(UUID().uuidString)
        let logURL = dir.appendingPathComponent(log)
        if !FileTools.exists(logURL) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        let out = try FileHandle(forWritingTo: logURL)
        defer { try? out.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let args = ["-I", script.path, ready.path, String(port), declineTERM ? "decline" : "accept"]
        if let orphanPID {
            process.arguments = ["-I", "-c", "import pathlib,subprocess,sys; child=subprocess.Popen([sys.executable] + sys.argv[2:]); pathlib.Path(sys.argv[1]).write_text(str(child.pid))", orphanPID.path] + args
        } else {
            process.arguments = throughParent ? ["-I", "-c", "import subprocess,sys; sys.exit(subprocess.call([sys.executable] + sys.argv[1:]))"] + args : args
        }
        process.currentDirectoryURL = dir
        process.standardOutput = out; process.standardError = out
        try process.run()
        addTeardownBlock {
            try Data().write(to: ready.appendingPathExtension("finish"))
            try await Self.waitForExit(process)
        }
        return PendingListener(process: process, ready: ready, log: logURL, parentMayExit: orphanPID != nil)
    }

    private struct PendingListener: Sendable {
        let process: Process
        let ready: URL
        let log: URL
        let parentMayExit: Bool

        func waitUntilReady() async throws -> (Process, Int) {
            for _ in 0..<200 {
                if let port = Int(FileTools.readFileIfExists(ready)), port > 0 { return (process, port) }
                if !parentMayExit, !process.isRunning { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw NSError(domain: "PortFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: FileTools.readFileIfExists(log)])
        }
    }
}
