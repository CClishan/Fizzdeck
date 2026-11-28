import Darwin
import Foundation
import Observation
import SwiftUI

enum ProjectAction: String, Sendable {
    case launching
    case stopping
}

struct DevServerFailure: Sendable, Equatable {
    enum Reason: Equatable, Sendable { case launchFailed, exited(Int32) }
    let reason: Reason
    let recordedAt: Date
    let logHeader: String?

    var exitCode: Int32? {
        if case .exited(let code) = reason { return code }
        return nil
    }
}

enum TestStatus: String, Sendable {
    case running
    case passed
    case failed
}

enum ScriptRunStatus: String, Sendable {
    case running
    case succeeded
    case failed
    case stopped
}

struct ScriptRunState: Identifiable, Sendable {
    let key: String
    let projectPath: String
    let script: ProjectScript
    var status: ScriptRunStatus
    var output: String
    let startedAt: Date
    var duration: TimeInterval?
    var exitCode: Int32?
    let logPath: String

    var id: String { key }
}

struct TestRunState: Identifiable, Sendable {
    let path: String
    var status: TestStatus
    var output: String
    let startedAt: Date
    var duration: TimeInterval?
    var exitCode: Int32?
    let command: String
    let logPath: String

    var id: String { path }
}

@MainActor
@Observable
final class ProjectActions {
    var busy: [String: ProjectAction] = [:]
    var devFailures: [String: DevServerFailure] = [:]
    var testRuns: [String: TestRunState] = [:]
    var scriptRuns: [String: ScriptRunState] = [:]
    var portConflicts: [String: PortConflict] = [:]
    var messages: [String: String] = [:]
    var testMessages: [String: String] = [:]

    private let logs: URL
    init(logs: URL = AppPaths.logsDir) { self.logs = logs }

    @ObservationIgnored private var devProcesses: [String: Process] = [:]
    @ObservationIgnored private var devLogs: [String: FileHandle] = [:]
    @ObservationIgnored private var testProcesses: [String: Process] = [:]
    @ObservationIgnored private var testLogs: [String: FileHandle] = [:]
    @ObservationIgnored private var cancelledTestPaths: Set<String> = []
    @ObservationIgnored private var scriptProcesses: [String: Process] = [:]
    @ObservationIgnored private var scriptLogs: [String: FileHandle] = [:]
    @ObservationIgnored private var cancelledScriptKeys: Set<String> = []
    @ObservationIgnored private var serviceToastIDs: [String: UUID] = [:]

    func isBusy(_ path: String) -> Bool {
        busy[path] != nil
    }

    func hasRunningWorktreeActivity(at path: String) -> Bool {
        func contains(_ candidate: String) -> Bool {
            let candidate = PathTools.canonical(candidate)
            return candidate == path || candidate.hasPrefix(path + "/")
        }
        return busy.keys.contains(where: contains)
            || devProcesses.contains { $0.value.isRunning && contains($0.key) }
            || testRuns.values.contains { $0.status == .running && contains($0.path) }
            || scriptRuns.values.contains { $0.status == .running && contains($0.projectPath) }
            || ProjectTrialService.shared.runs.contains { $0.value.status == .running && contains($0.key) }
    }

    func message(for path: String) -> String? {
        messages[path]
    }

    func testMessage(for path: String) -> String? {
        testMessages[path]
    }

    var testRunsSnapshot: [String: TestRunState] {
        testRuns
    }

    func testRun(for path: String) -> TestRunState? {
        testRuns[path]
    }

    func portConflict(for path: String) -> PortConflict? {
        portConflicts[path]
    }

    func scriptKey(for project: RepoProject, script: ProjectScript) -> String {
        "\(project.path)|\(script.id)"
    }

    func scriptRun(for project: RepoProject, script: ProjectScript) -> ScriptRunState? {
        scriptRuns[scriptKey(for: project, script: script)]
    }

    func logPath(for project: RepoProject, prefix: String = "") -> String {
        logs
            .appendingPathComponent(prefix + URL(fileURLWithPath: project.path).lastPathComponent + ".log")
            .path
    }

    func launch(_ project: RepoProject, store: RepositoryStore) async {
        guard !isBusy(project.path) else { return }
        devFailures[project.path] = nil
        guard isManaged(project, in: store) else {
            messages[project.path] = FizzL10n.text("不在受管项目内，拒绝启动", "This project is not managed by FizzDeck and cannot be started here")
            return
        }
        guard let run = project.run else {
            messages[project.path] = FizzL10n.text("没有识别到可运行的 dev 脚本", "No development command found")
            return
        }
        guard run.port > 0 else {
            messages[project.path] = FizzL10n.text("没有可探测的预览端口", "No preview port to check")
            return
        }

        if PortProbe.isOpen(run.port) {
            let conflict = await PortConflictService.inspect(port: run.port)
            let resolvedConflict = conflict ?? PortConflict(
                port: run.port,
                occupants: [],
                note: FizzL10n.text("端口已有监听进程", "A process is already listening on this port")
            )
            portConflicts[project.path] = resolvedConflict
            store.setPort(.stopped, for: project.path)
            messages[project.path] = FizzL10n.text("端口 \(run.port) 被占用：\(resolvedConflict.occupantSummary)", "Port \(run.port) is in use: \(resolvedConflict.occupantSummary)")
            showPortConflictToast(
                project: project,
                conflict: resolvedConflict,
                store: store
            )
            return
        }

        portConflicts[project.path] = nil
        messages[project.path] = nil
        updateServiceToast(
            path: project.path,
            title: FizzL10n.text("正在启动 \(project.displayName)", "Starting \(project.displayName)"),
            subtitle: run.command,
            step: 0,
            state: .running,
            tint: .secondary,
            action: nil
        )
        busy[project.path] = .launching
        defer { busy[project.path] = nil }

        let logURL = URL(fileURLWithPath: logPath(for: project))
        let header = "--- \(Date().ISO8601Format(.init(includingFractionalSeconds: true))) \(run.command)"
        guard let log = openLog(logURL, header: "\n\(header)\n") else {
            devFailures[project.path] = DevServerFailure(reason: .launchFailed, recordedAt: Date(), logHeader: nil)
            messages[project.path] = FizzL10n.text("无法写入 \(PathTools.displayPath(logURL.path))", "Couldn’t write to \(PathTools.displayPath(logURL.path))")
            updateServiceToast(
                path: project.path,
                title: FizzL10n.text("无法启动服务", "Couldn’t start the service"),
                subtitle: FizzL10n.text("日志目录不可写", "The log folder is read-only"),
                step: 0,
                state: .failed,
                tint: FizzTheme.statusWarning,
                action: retryAction(for: project, store: store)
            )
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", run.command]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        var environment = shellEnvironment
        environment["BROWSER"] = "none"
        process.environment = environment
        process.standardOutput = log
        process.standardError = log

        do {
            try process.run()
        } catch {
            try? log.close()
            devFailures[project.path] = DevServerFailure(reason: .launchFailed, recordedAt: Date(), logHeader: header)
            messages[project.path] = FizzL10n.text("启动失败：\(error.localizedDescription)", "Couldn’t start: \(error.localizedDescription)")
            updateServiceToast(
                path: project.path,
                title: FizzL10n.text("启动失败", "Couldn’t start"),
                subtitle: error.localizedDescription,
                step: 0,
                state: .failed,
                tint: FizzTheme.statusDanger,
                action: retryAction(for: project, store: store)
            )
            return
        }

        devProcesses[project.path] = process
        devLogs[project.path] = log
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.handleDevTermination(
                    path: project.path,
                    port: run.port,
                    logHeader: header,
                    process: finished,
                    store: store
                )
            }
        }

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if PortProbe.isOpen(run.port) {
                store.setPort(.running, for: project.path)
                messages[project.path] = FizzL10n.text("已启动 \(run.command) · localhost:\(run.port)", "Started \(run.command) · localhost:\(run.port)")
                Task {
                    await LocalNotifications.send(
                        title: FizzL10n.text("开发服务已就绪", "Development service ready"),
                        body: "\(project.displayName) · localhost:\(run.port)",
                        projectPath: project.path,
                        tab: .progress
                    )
                }
                updateServiceToast(
                    path: project.path,
                    title: FizzL10n.text("服务已启动", "Service started"),
                    subtitle: "localhost:\(run.port)",
                    step: 4,
                    state: .live,
                    tint: FizzTheme.statusSuccess,
                    action: ToastAction(
                        title: FizzL10n.text("打开预览", "Open Preview"),
                        symbol: "arrow.up.forward.square"
                    ) {
                        SystemActions.openURL("http://127.0.0.1:\(run.port)")
                    }
                )
                return
            }
            if !process.isRunning { break }
            try? await Task.sleep(for: .milliseconds(350))
        }

        if process.isRunning {
            messages[project.path] = FizzL10n.text("进程已启动（PID \(process.processIdentifier)），端口 \(run.port) 尚未就绪", "Process started (PID \(process.processIdentifier)); port \(run.port) is not ready yet")
            updateServiceToast(
                path: project.path,
                title: FizzL10n.text("服务启动中", "Starting service"),
                subtitle: FizzL10n.text("PID \(process.processIdentifier) · 等待 localhost:\(run.port)", "PID \(process.processIdentifier) · Waiting for localhost:\(run.port)"),
                step: 2,
                state: .running,
                tint: .secondary,
                action: nil
            )
        } else {
            store.setPort(.stopped, for: project.path)
            devFailures[project.path] = DevServerFailure(reason: .exited(process.terminationStatus), recordedAt: Date(), logHeader: header)
            let tail = FileTools.tail(logURL, bytes: 800).trimmingCharacters(in: .whitespacesAndNewlines)
            messages[project.path] = tail.isEmpty ? FizzL10n.text("启动失败，进程已退出", "Startup failed; the process exited") : FizzL10n.text("启动失败：\(tail)", "Couldn’t start: \(tail)")
            updateServiceToast(
                path: project.path,
                title: FizzL10n.text("启动失败", "Couldn’t start"),
                subtitle: tail.isEmpty ? FizzL10n.text("进程已退出", "Process exited") : String(tail.prefix(100)),
                step: 0,
                state: .failed,
                tint: FizzTheme.statusDanger,
                action: retryAction(for: project, store: store)
            )
        }
    }

    func stop(_ project: RepoProject, store: RepositoryStore, presentNotice: () -> Void = {}) async {
        let path = project.path
        guard !isBusy(path) else { return }
        func review(_ reason: String) {
            let hint = FizzL10n.text("请到体检的「开发监听端口」逐个核对 PID。", "Check each PID under Development Ports in Doctor.")
            messages[path] = "\(reason)。\(hint)"
            presentNotice()
            ToastCenter.shared.show(reason, symbol: "info.circle", tint: FizzTheme.statusWarning, duration: 8, subtitle: hint,
                                    action: ToastAction(title: FizzL10n.text("去体检", "Open Doctor"), symbol: "stethoscope") { store.openCleanup() })
        }
        func registered() -> Bool { store.projects.contains { $0.path == path && $0.run == project.run } }
        guard registered(), let owner = PreviewProject.from(project, actions: self) else {
            review(FizzL10n.text("项目或预览端口已变化", "The project or preview port changed"))
            return
        }
        busy[path] = .stopping
        defer { busy[path] = nil }
        let launch = devProcesses[path]
        let outcome = await ManagedPreviewStop.request(project: owner, launch: launch, isCurrent: {
            registered() && self.devProcesses[path] === launch
        }, confirm: ManagedPreviewStop.confirm)
        switch outcome {
        case .cancelled: break
        case .portFree(let message):
            guard registered() else { return }
            devFailures[path] = nil
            portConflicts[path] = nil
            store.setPort(.stopped, for: path)
            messages[path] = message
        case .reviewInDoctor(let reason): review(reason)
        }
    }

    func resolvePortConflictAndLaunch(
        _ project: RepoProject,
        conflict: PortConflict,
        store: RepositoryStore
    ) async {
        guard !isBusy(project.path) else { return }
        guard isManaged(project, in: store) else {
            messages[project.path] = FizzL10n.text("不在受管项目内，拒绝结束占用进程", "Cannot stop a process for an unmanaged project")
            return
        }

        updateServiceToast(
            path: project.path,
            title: FizzL10n.text("正在释放端口", "Freeing port"),
            subtitle: conflict.occupants.map { "PID \($0.pid)" }.joined(separator: " · "),
            step: 0,
            state: .running,
            tint: .secondary,
            action: nil
        )
        busy[project.path] = .launching
        let result = await PortConflictService.terminateConfirmed(conflict)
        if result.succeeded {
            portConflicts[project.path] = nil
        } else if let refreshed = await PortConflictService.inspect(port: conflict.port) {
            portConflicts[project.path] = refreshed
        }
        messages[project.path] = result.message
        busy[project.path] = nil

        guard result.succeeded else {
            updateServiceToast(
                path: project.path,
                title: FizzL10n.text("释放端口失败", "Couldn’t free the port"),
                subtitle: result.message,
                step: 0,
                state: .failed,
                tint: FizzTheme.statusWarning,
                action: ToastAction(
                    title: FizzL10n.text("再次尝试", "Try Again"),
                    symbol: "arrow.clockwise"
                ) { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.resolvePortConflictAndLaunch(
                            project,
                            conflict: conflict,
                            store: store
                        )
                    }
                }
            )
            return
        }
        await launch(project, store: store)
    }

    func runTests(_ project: RepoProject, store: RepositoryStore) {
        guard isManaged(project, in: store) else {
            testMessages[project.path] = FizzL10n.text("不在受管项目内，拒绝执行测试", "Cannot run tests for an unmanaged project")
            return
        }
        guard let test = project.test else {
            testMessages[project.path] = FizzL10n.text("没有识别到测试命令", "No test command found")
            return
        }
        guard testRuns[project.path]?.status != .running else { return }
        cancelledTestPaths.remove(project.path)
        testMessages[project.path] = nil

        let logURL = URL(fileURLWithPath: logPath(for: project, prefix: "test-"))
        let header = "\n--- \(Date().ISO8601Format()) \(test.command)\n"
        guard let log = openLog(logURL, header: header) else {
            testMessages[project.path] = FizzL10n.text("无法写入测试日志", "Couldn’t write the test log")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", test.command]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        var environment = shellEnvironment
        environment["CI"] = "1"
        environment["FORCE_COLOR"] = "0"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        testRuns[project.path] = TestRunState(
            path: project.path,
            status: .running,
            output: "",
            startedAt: Date(),
            duration: nil,
            exitCode: nil,
            command: test.command,
            logPath: logURL.path
        )

        do {
            try process.run()
        } catch {
            try? log.close()
            if var state = testRuns[project.path] {
                state.status = .failed
                state.output = error.localizedDescription
                state.duration = Date().timeIntervalSince(state.startedAt)
                testRuns[project.path] = state
            }
            return
        }

        testProcesses[project.path] = process
        testLogs[project.path] = log
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.appendTestOutput(project.path, text: text)
            }
        }
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.finishTest(project, exitCode: finished.terminationStatus)
            }
        }
    }

    func stopTests(_ project: RepoProject) {
        cancelledTestPaths.insert(project.path)
        testProcesses[project.path]?.interrupt()
    }

    func runScript(_ script: ProjectScript, project: RepoProject, store: RepositoryStore) {
        guard isManaged(project, in: store) else {
            messages[project.path] = FizzL10n.text("不在受管项目内，拒绝执行脚本", "Cannot run scripts for an unmanaged project")
            return
        }

        let key = scriptKey(for: project, script: script)
        guard scriptRuns[key]?.status != .running else { return }
        cancelledScriptKeys.remove(key)

        let logURL = scriptLogURL(for: project, script: script)
        let header = "\n--- \(Date().ISO8601Format()) \(script.command)\n"
        guard let log = openLog(logURL, header: header) else {
            messages[project.path] = FizzL10n.text("无法写入脚本日志", "Couldn’t write the script log")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script.command]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        var environment = shellEnvironment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        scriptRuns[key] = ScriptRunState(
            key: key,
            projectPath: project.path,
            script: script,
            status: .running,
            output: "",
            startedAt: Date(),
            duration: nil,
            exitCode: nil,
            logPath: logURL.path
        )
        scriptProcesses[key] = process
        scriptLogs[key] = log
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.appendScriptOutput(key, text: text)
            }
        }
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.finishScript(key, exitCode: finished.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            scriptProcesses[key] = nil
            scriptLogs[key] = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            try? log.close()
            if var state = scriptRuns[key] {
                state.status = .failed
                state.output = error.localizedDescription
                state.duration = Date().timeIntervalSince(state.startedAt)
                scriptRuns[key] = state
            }
            messages[project.path] = FizzL10n.text("脚本启动失败：\(error.localizedDescription)", "Couldn’t start the script: \(error.localizedDescription)")
            return
        }
    }

    func stopScript(_ script: ProjectScript, project: RepoProject) {
        let key = scriptKey(for: project, script: script)
        guard scriptProcesses[key]?.isRunning == true else { return }
        cancelledScriptKeys.insert(key)
        scriptProcesses[key]?.terminate()
    }

    func openScriptLog(_ script: ProjectScript, project: RepoProject) {
        let path = scriptLogPath(for: project, script: script)
        guard FileTools.exists(path) else {
            messages[project.path] = FizzL10n.text("还没有脚本日志", "No script log yet")
            return
        }
        SystemActions.open(path)
    }

    func scriptLogPath(for project: RepoProject, script: ProjectScript) -> String {
        scriptLogURL(for: project, script: script).path
    }

    static func installDependenciesScript(command: String) -> ProjectScript {
        ProjectScript(
            id: "doctor-install-deps",
            name: FizzL10n.text("安装依赖", "Install dependencies"),
            command: command,
            source: .npm
        )
    }

    func installRun(for project: RepoProject, command: String) -> ScriptRunState? {
        scriptRun(for: project, script: Self.installDependenciesScript(command: command))
    }

    func runInstallDependencies(command: String, for project: RepoProject, store: RepositoryStore) {
        runScript(Self.installDependenciesScript(command: command), project: project, store: store)
    }

    func stopInstallDependencies(command: String, for project: RepoProject) {
        stopScript(Self.installDependenciesScript(command: command), project: project)
    }

    func openLog(for project: RepoProject, test: Bool = false) {
        let path = logPath(for: project, prefix: test ? "test-" : "")
        if test {
            testMessages[project.path] = nil
        } else {
            messages[project.path] = nil
        }
        guard FileTools.exists(path) else {
            if test {
                testMessages[project.path] = FizzL10n.text("还没有测试日志", "No test log yet")
            } else {
                messages[project.path] = FizzL10n.text("还没有启动日志", "No launch log yet")
            }
            return
        }
        SystemActions.open(path)
    }

    private func isManaged(_ project: RepoProject, in store: RepositoryStore) -> Bool {
        store.projects.contains { $0.path == project.path }
    }

    private var shellEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var paths = [
            AppPaths.home.appendingPathComponent(".npm-global/bin").path,
            AppPaths.home.appendingPathComponent(".bun/bin").path,
            AppPaths.home.appendingPathComponent(".local/bin").path,
            AppPaths.home.appendingPathComponent("bin").path,
            AppPaths.home.appendingPathComponent(".cargo/bin").path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        if let current = environment["PATH"], !current.isEmpty {
            paths.append(current)
        }
        environment["PATH"] = paths.joined(separator: ":")
        return environment
    }

    private func openLog(_ url: URL, header: String) -> FileHandle? {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            try handle.write(contentsOf: Data(header.utf8))
            return handle
        } catch {
            return nil
        }
    }

    private func scriptLogURL(for project: RepoProject, script: ProjectScript) -> URL {
        let projectSlug = URL(fileURLWithPath: project.path).lastPathComponent
        let scriptSlug = script.id.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return logs
            .appendingPathComponent("script-\(projectSlug)-\(String(scriptSlug)).log")
    }

    private func handleDevTermination(
        path: String,
        port: Int,
        logHeader: String,
        process: Process,
        store: RepositoryStore
    ) {
        guard devProcesses[path] === process else { return }
        devProcesses[path] = nil
        if let log = devLogs[path] {
            try? log.close()
            devLogs[path] = nil
        }
        store.setPort(PortProbe.isOpen(port) ? .running : .stopped, for: path)
        if process.terminationStatus != 0, busy[path] != .stopping {
            devFailures[path] = DevServerFailure(reason: .exited(process.terminationStatus), recordedAt: Date(), logHeader: logHeader)
        }
        messages[path] = process.terminationStatus == 0
            ? FizzL10n.text("开发服务器已退出", "Development server exited")
            : FizzL10n.text("开发服务器已退出（状态 \(process.terminationStatus)）", "Development server exited (status \(process.terminationStatus))")
    }

    private func appendTestOutput(_ path: String, text: String) {
        guard var state = testRuns[path] else { return }
        state.output = String((state.output + text).suffix(16_000))
        testRuns[path] = state
        if let log = testLogs[path] {
            try? log.write(contentsOf: Data(text.utf8))
        }
    }

    private func appendScriptOutput(_ key: String, text: String) {
        guard var state = scriptRuns[key] else { return }
        state.output = String((state.output + text).suffix(16_000))
        scriptRuns[key] = state
        if let log = scriptLogs[key] {
            try? log.write(contentsOf: Data(text.utf8))
        }
    }

    private func finishScript(_ key: String, exitCode: Int32) {
        guard var state = scriptRuns[key] else { return }
        let wasStopped = cancelledScriptKeys.remove(key) != nil
        state.status = wasStopped ? .stopped : (exitCode == 0 ? .succeeded : .failed)
        state.exitCode = exitCode
        state.duration = Date().timeIntervalSince(state.startedAt)
        scriptRuns[key] = state
        scriptProcesses[key] = nil
        if let log = scriptLogs[key] {
            try? log.close()
            scriptLogs[key] = nil
        }
        if !wasStopped {
            let succeeded = state.status == .succeeded
            ToastCenter.shared.show(
                succeeded ? FizzL10n.text("脚本完成", "Script completed") : FizzL10n.text("脚本失败", "Script failed"),
                symbol: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill",
                tint: succeeded ? FizzTheme.statusSuccess : FizzTheme.statusDanger,
                subtitle: state.script.name,
                microViz: .bars(
                    values: [max(0, state.duration ?? 0)],
                    improved: succeeded
                )
            )
        }
    }

    private func finishTest(_ project: RepoProject, exitCode: Int32) {
        guard var state = testRuns[project.path] else { return }
        let wasStopped = cancelledTestPaths.remove(project.path) != nil
        state.status = exitCode == 0 ? .passed : .failed
        state.exitCode = exitCode
        state.duration = Date().timeIntervalSince(state.startedAt)
        testRuns[project.path] = state
        testProcesses[project.path] = nil
        if let log = testLogs[project.path] {
            try? log.close()
            testLogs[project.path] = nil
        }
        if state.status == .failed, !wasStopped {
            Task {
                await LocalNotifications.send(
                    title: FizzL10n.text("测试失败", "Tests failed"),
                    body: "\(project.displayName) · \(state.command)",
                    projectPath: project.path,
                    tab: .run
                )
            }
        }
        if wasStopped {
            ToastCenter.shared.show(
                FizzL10n.text("测试已停止", "Tests stopped"),
                symbol: "stop.circle.fill",
                tint: .secondary,
                subtitle: project.displayName,
                microViz: .compact(state: .warning)
            )
        } else {
            let summary = TestOutcomeSummary.parse(state.output, status: state.status)
            let passed = state.status == .passed
            ToastCenter.shared.show(
                passed ? FizzL10n.text("测试通过", "Tests passed") : FizzL10n.text("测试失败", "Tests failed"),
                symbol: passed ? "checkmark.seal.fill" : "xmark.octagon.fill",
                tint: passed ? FizzTheme.statusSuccess : FizzTheme.statusDanger,
                subtitle: FizzL10n.text("\(summary.passed) 通过 · \(summary.failed) 失败 · \(durationLabel(state.duration))", "\(summary.passed) passed · \(summary.failed) failed · \(durationLabel(state.duration))"),
                microViz: .tests(passed: summary.passed, failed: summary.failed),
                action: ToastAction(
                    title: FizzL10n.text("查看日志", "View Log"),
                    symbol: "doc.text"
                ) { [weak self] in
                    self?.openLog(for: project, test: true)
                }
            )
        }
    }

    private func retryAction(
        for project: RepoProject,
        store: RepositoryStore
    ) -> ToastAction {
        ToastAction(title: FizzL10n.text("重试", "Retry"), symbol: "arrow.clockwise") { [weak self] in
            guard let self else { return }
            Task { await self.launch(project, store: store) }
        }
    }

    private func showPortConflictToast(
        project: RepoProject,
        conflict: PortConflict,
        store: RepositoryStore
    ) {
        updateServiceToast(
            path: project.path,
            title: FizzL10n.text("端口 :\(conflict.port) 被占用", "Port :\(conflict.port) is in use"),
            subtitle: conflict.occupantSummary,
            step: 0,
            state: .failed,
            tint: FizzTheme.statusWarning,
            action: ToastAction(
                title: FizzL10n.text("释放并重试", "Free Port and Retry"),
                symbol: "arrow.clockwise"
            ) { [weak self] in
                guard let self else { return }
                Task {
                    await self.resolvePortConflictAndLaunch(
                        project,
                        conflict: conflict,
                        store: store
                    )
                }
            }
        )
    }

    private func updateServiceToast(
        path: String,
        title: @autoclosure () -> String,
        subtitle: @autoclosure () -> String?,
        step: Int,
        state: ToastPipelineState,
        tint: Color,
        action: ToastAction?
    ) {
        let microViz = ToastMicroViz.pipeline(step: step, state: state)
        if let id = serviceToastIDs[path],
           ToastCenter.shared.update(id, mutate: { message in
               message.setText(title, subtitle: subtitle)
               message.tint = tint
               message.microViz = microViz
               message.action = action
               message.duration = nil
           }) {
            return
        }

        serviceToastIDs[path] = ToastCenter.shared.show(
            title(),
            symbol: "bolt.horizontal.fill",
            tint: tint,
            duration: nil,
            subtitle: subtitle(),
            microViz: microViz,
            action: action
        )
    }

    private func durationLabel(_ duration: TimeInterval?) -> String {
        String(format: "%.1fs", duration ?? 0)
    }
}
