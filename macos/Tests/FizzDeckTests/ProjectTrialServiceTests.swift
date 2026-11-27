import Darwin
import XCTest
@testable import FizzDeck

final class ProjectTrialServiceTests: XCTestCase {
    func testDiscoveryDoesNotExecuteAndOnlyOffersDeclaredOneShotScripts() throws {
        let dir = try directory()
        let marker = dir.appendingPathComponent("executed")
        let package = dir.appendingPathComponent("package.json")
        try #"{"scripts":{"dev":"vite","build":"touch executed","type-check":"tsc --noEmit","test":"vitest --watch","lint":"eslint ."}}"#.write(to: package, atomically: true, encoding: .utf8)
        let found = TrialCommand.available(in: dir)
        XCTAssertEqual(found.map(\.kind), [.build, .typecheck])
        XCTAssertEqual(found.map(\.command), ["npm run 'build'", "npm run 'type-check'"])
        XCTAssertFalse(FileTools.exists(marker))
        try #"{"scripts":{"test":"echo no test specified && exit 1","test:unit":"vitest run"}}"#.write(to: package, atomically: true, encoding: .utf8)
        XCTAssertEqual(TrialCommand.available(in: dir).map(\.command), ["npm run 'test:unit'"])
        try #"{"scripts":{"check":"tsc --noEmit"}}"#.write(to: package, atomically: true, encoding: .utf8)
        try Data().write(to: dir.appendingPathComponent("yarn.lock"))
        XCTAssertEqual(TrialCommand.available(in: dir), [TrialCommand(kind: .typecheck, command: "yarn run 'check'")])
        try #"{"scripts":{"check":"eslint ."}}"#.write(to: package, atomically: true, encoding: .utf8)
        XCTAssertTrue(TrialCommand.available(in: dir).isEmpty)
        try FileManager.default.removeItem(at: package)
        XCTAssertTrue(TrialCommand.available(in: dir).isEmpty)
        try Data().write(to: dir.appendingPathComponent("Package.swift"))
        XCTAssertEqual(TrialCommand.available(in: dir).map(\.command), ["swift build", "swift test"])
    }

    @MainActor
    func testManualRunRetainsFinalStdoutStderrExitStatusAndRefusesUnmanagedProject() async throws {
        let dir = try directory()
        let (project, store, trials) = setup(dir)
        try "build:\n\t@echo STDOUT-fixture\n\t@echo STDERR-fixture >&2\n\t@echo CI=$(CI)\n\t@exit 3\n".write(to: dir.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
        let choice = try XCTUnwrap(TrialCommand.available(in: dir).first)
        trials.start(choice, for: project, store: store)
        XCTAssertNil(trials.runs[project.path])
        store.projects = [project]
        trials.start(choice, for: project, store: store)
        try await eventually { trials.runs[project.path]?.status == .failed }
        let run = try XCTUnwrap(trials.runs[project.path])
        XCTAssertNotEqual(run.exitCode, 0)
        let tail = LogTailReader.read(path: run.logURL.path)
        for expected in ["STDOUT-fixture", "STDERR-fixture", "CI=1"] { XCTAssertTrue(tail.contains(expected), tail) }
    }

    @MainActor
    func testSecondClickDoesNotStartAnotherRunAndStopReachesMakeChild() async throws {
        let dir = try directory()
        let (project, store, trials) = setup(dir)
        let worker = dir.appendingPathComponent("worker.py")
        try """
        import pathlib, signal, time
        def stop(*args):
            pathlib.Path('worker-terminated').touch()
            raise SystemExit(0)
        signal.signal(signal.SIGTERM, stop)
        print('visible-before-stop', flush=True)
        pathlib.Path('ready').touch()
        time.sleep(10)
        """.write(to: worker, atomically: true, encoding: .utf8)
        try "test:\n\t@/usr/bin/python3 -I worker.py\nbuild:\n\t@touch duplicate\n".write(to: dir.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
        let choices = TrialCommand.available(in: dir)
        let test = try XCTUnwrap(choices.first { $0.kind == .test })
        let build = try XCTUnwrap(choices.first { $0.kind == .build })
        store.projects = [project]
        trials.start(test, for: project, store: store)
        let first = try XCTUnwrap(trials.runs[project.path])
        defer { trials.stop(project.path) }
        try await eventually { FileTools.exists(dir.appendingPathComponent("ready")) }
        XCTAssertTrue(LogTailReader.read(path: first.logURL.path).contains("visible-before-stop"))
        trials.start(build, for: project, store: store)
        XCTAssertEqual(trials.runs[project.path]?.id, first.id)
        trials.stop(project.path)
        try await eventually { trials.runs[project.path]?.status == .stopped && FileTools.exists(dir.appendingPathComponent("worker-terminated")) }
        XCTAssertFalse(FileTools.exists(dir.appendingPathComponent("duplicate")))
        trials.start(build, for: project, store: store)
        try await eventually { trials.runs[project.path]?.status == .succeeded }
        XCTAssertTrue(FileTools.exists(dir.appendingPathComponent("duplicate")))
        XCTAssertNotEqual(trials.runs[project.path]?.id, first.id)
    }

    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trial-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    @MainActor private func setup(_ dir: URL) -> (RepoProject, RepositoryStore, ProjectTrialService) {
        let project = RepoProject(path: dir.path, name: "fixture", displayName: "fixture", group: "", recent: nil,
                                  branch: nil, lastCommit: nil, dirtyCount: 0, changes: .zero, ahead: 0, behind: 0,
                                  weekly: [:], stacks: [], size: .empty, cleanup: .empty, run: nil, sessions: .empty,
                                  intro: .empty, artwork: nil, test: nil, starred: false, color: nil, note: "", port: .noPreview)
        return (project, RepositoryStore(), ProjectTrialService(logs: dir.appendingPathComponent("logs")))
    }

    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "TrialFixtureTimeout", code: 1)
    }
}
