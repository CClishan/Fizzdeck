import CryptoKit
import Darwin
import Foundation
import Observation

enum TrialKind: String, CaseIterable, Identifiable, Sendable {
    case build, typecheck, test
    var id: Self { self }
}

struct TrialCommand: Identifiable, Equatable, Sendable {
    let kind: TrialKind
    let command: String
    var id: TrialKind { kind }

    static func checksTypes(_ script: String?) -> Bool {
        script?.range(of: #"(?:^|\s)(?:tsc|vue-tsc|svelte-check|astro\s+check)(?:\s|$)"#, options: .regularExpression) != nil
    }

    /// Discovery is file-only. Never use a package manager (even for listing scripts) during Doctor scans.
    static func available(in dir: URL) -> [Self] {
        let scripts = RunDetector.scripts(dir)
        let definitions = FileTools.json(dir.appendingPathComponent("package.json"))?["scripts"] as? [String: String] ?? [:]
        let names: [TrialKind: [String]] = [
            .build: ["build"], .typecheck: ["typecheck", "type-check", "check:types", "types:check", "check"],
            .test: ["test:ci", "test:run", "test", "test:unit", "vitest"],
        ]
        func exists(_ file: String) -> Bool { FileTools.exists(dir.appendingPathComponent(file)) }
        var native: [TrialKind: String] = [:]
        if exists("Package.swift") { native = [.build: "swift build", .test: "swift test"] }
        else if exists("Cargo.toml") { native = [.build: "cargo build", .typecheck: "cargo check", .test: "cargo test"] }
        else if exists("go.mod") { native = [.build: "go build ./...", .test: "go test ./..."] }
        else if exists("pom.xml") { native = [.build: "mvn -q -DskipTests package", .test: "mvn -q test"] }
        else if exists("build.gradle") || exists("build.gradle.kts") {
            let tool = exists("gradlew") ? "./gradlew" : "gradle"
            native = [.build: "\(tool) assemble", .test: "\(tool) test"]
        }
        return TrialKind.allCases.compactMap { kind in
            for name in names[kind] ?? [] {
                for script in scripts where script.name == name {
                    if script.source == .npm {
                        guard let body = definitions[name], !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !body.contains("no test specified"), body.range(of: #"(?:^|\s)(?:--watch(?:All)?(?:=true)?|-w|vitest\s+watch)(?:\s|$)"#, options: .regularExpression) == nil
                        else { continue }
                    }
                    if name == "check", !(script.source == .npm && checksTypes(definitions[name])) { continue }
                    return Self(kind: kind, command: script.command)
                }
            }
            return native[kind].map { Self(kind: kind, command: $0) }
        }
    }
}

struct TrialRun: Identifiable, Equatable {
    let id = UUID()
    let choice: TrialCommand
    let logURL: URL
    var status: ScriptRunStatus = .running
    var stopRequested = false
    var exitCode: Int32?
    var error: String?

    var summary: String {
        switch status {
        case .running: stopRequested ? "等待退出" : "运行中"
        case .succeeded: "通过"
        case .failed: exitCode.map { "失败 · 退出码 \($0)" } ?? "启动失败"
        case .stopped: "已停止"
        }
    }
}

/// Shared by the Run and Doctor views. Trial output goes straight to disk (including the last bytes before exit).
@MainActor @Observable
final class ProjectTrialService {
    static let shared = ProjectTrialService()
    private(set) var runs: [String: TrialRun] = [:]
    @ObservationIgnored private var children: [String: Process] = [:]
    private let logs: URL

    init(logs: URL = AppPaths.logsDir) { self.logs = logs }

    func start(_ choice: TrialCommand, for project: RepoProject, store: RepositoryStore) {
        let path = project.path
        guard store.projects.contains(where: { $0.path == path }), runs[path]?.status != .running else { return }
        let key = SHA256.hash(data: Data(path.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let url = logs.appendingPathComponent("trial-\(key).log")
        var run = TrialRun(choice: choice, logURL: url)
        do {
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            try Data("$ \(choice.command)\n".utf8).write(to: url, options: .atomic)
            let log = try FileHandle(forWritingTo: url)
            defer { try? log.close() }
            try log.seekToEnd()
            let process = Process()
            process.currentDirectoryURL = URL(fileURLWithPath: path)
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "exec " + choice.command]
            var env = ProcessInfo.processInfo.environment
            let userBins = [".cargo/bin", ".bun/bin", ".local/bin", ".npm-global/bin"].map { AppPaths.home.appendingPathComponent($0).path }
            env["PATH"] = ([env["PATH"] ?? "", "/opt/homebrew/bin", "/usr/local/bin"] + userBins)
                .filter { !$0.isEmpty }.joined(separator: ":")
            env["CI"] = "1"
            env["NO_COLOR"] = "1"
            process.environment = env
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = log
            process.standardError = log
            process.terminationHandler = { [weak self] finished in
                Task { @MainActor in
                    guard let self, self.children[path] === finished, var state = self.runs[path] else { return }
                    state.exitCode = finished.terminationStatus
                    state.status = state.stopRequested ? .stopped : (finished.terminationStatus == 0 ? .succeeded : .failed)
                    self.runs[path] = state
                    self.children[path] = nil
                }
            }
            try process.run()
            children[path] = process
        } catch {
            run.status = .failed
            run.error = error.localizedDescription
        }
        runs[path] = run
    }

    func stop(_ path: String) {
        guard var run = runs[path], !run.stopRequested, let process = children[path], process.isRunning else { return }
        let pid = process.processIdentifier
        // Foundation launches a new process group on Darwin. Include npm/make workers, never the app's group.
        guard pid > 1, getpgid(pid) == pid, pid != getpgrp(), Darwin.kill(-pid, SIGTERM) == 0 else {
            run.error = "无法核对本次试跑的进程组或发送 SIGTERM"
            runs[path] = run
            return
        }
        run.stopRequested = true
        runs[path] = run
    }
}
