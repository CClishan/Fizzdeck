import Darwin
import Foundation
import Observation
import SwiftUI

enum ProjectAction: String, Sendable {
    case launching
    case stopping
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
    var testRuns: [String: TestRunState] = [:]
    var scriptRuns: [String: ScriptRunState] = [:]
    var portConflicts: [String: PortConflict] = [:]
    var messages: [String: String] = [:]
    var testMessages: [String: String] = [:]

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

    func message(for path: String) -> String? {
        messages[path]
    }

    func testMessage(for path: String) -> String? {
        testMessages[path]
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
        AppPaths.logsDir
            .appendingPathComponent(prefix + URL(fileURLWithPath: project.path).lastPathComponent + ".log")
            .path
    }

    func launch(_ project: RepoProject, store: RepositoryStore) async {
        guard !isBusy(project.path) else { return }
        guard isManaged(project, in: store) else {
            messages[project.path] = "不在受管项目内，拒绝启动"
            return
        }
        guard let run = project.run else {
            messages[project.path] = "没有识别到可运行的 dev 脚本"
            return
        }
        guard run.port > 0 else {
            messages[project.path] = "没有可探测的预览端口"
            return
        }

        if PortProbe.isOpen(run.port) {
            let conflict = await PortConflictService.inspect(port: run.port)
            let resolvedConflict = conflict ?? PortConflict(
                port: run.port,
                occupants: [],
                note: "端口已有监听进程"
            )
            portConflicts[project.path] = resolvedConflict
            store.setPort(.stopped, for: project.path)
            messages[project.path] = "端口 \(run.port) 被占用：\(resolvedConflict.occupantSummary)"
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
            title: "正在启动 \(project.displayName)",
            subtitle: run.command,
            step: 0,
            state: .running,
            tint: FizzTheme.accent,
            action: nil
        )
        busy[project.path] = .launching
        defer { busy[project.path] = nil }

        let logURL = URL(fileURLWithPath: logPath(for: project))
        let header = "\n--- \(Date().ISO8601Format()) \(run.command)\n"
        guard let log = openLog(logURL, header: header) else {
            messages[project.path] = "无法写入 \(PathTools.displayPath(logURL.path))"
            updateServiceToast(
                path: project.path,
                title: "无法启动服务",
                subtitle: "日志目录不可写",
                step: 0,
                state: .failed,
                tint: .orange,
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
            messages[project.path] = "启动失败：\(error.localizedDescription)"
            updateServiceToast(
                path: project.path,
                title: "启动失败",
                subtitle: error.localizedDescription,
                step: 0,
                state: .failed,
                tint: .red,
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
                    process: finished,
                    store: store
                )
            }
        }

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if PortProbe.isOpen(run.port) {
                store.setPort(.running, for: project.path)
                messages[project.path] = "已启动 \(run.command) · localhost:\(run.port)"
                Task {
                    await LocalNotifications.send(
                        title: "开发服务已就绪",
                        body: "\(project.displayName) · localhost:\(run.port)",
                        projectPath: project.path,
                        tab: .overview
                    )
                }
                updateServiceToast(
                    path: project.path,
                    title: "服务已启动",
                    subtitle: "localhost:\(run.port)",
                    step: 4,
                    state: .live,
                    tint: .green,
                    action: ToastAction(
                        title: "打开预览",
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
            messages[project.path] = "进程已启动（PID \(process.processIdentifier)），端口 \(run.port) 尚未就绪"
            updateServiceToast(
                path: project.path,
                title: "服务启动中",
                subtitle: "PID \(process.processIdentifier) · 等待 localhost:\(run.port)",
                step: 2,
                state: .running,
                tint: FizzTheme.accent,
                action: nil
            )
        } else {
            store.setPort(.stopped, for: project.path)
            let tail = FileTools.tail(logURL, bytes: 800).trimmingCharacters(in: .whitespacesAndNewlines)
            messages[project.path] = tail.isEmpty ? "启动失败，进程已退出" : "启动失败：\(tail)"
            updateServiceToast(
                path: project.path,
                title: "启动失败",
                subtitle: tail.isEmpty ? "进程已退出" : String(tail.prefix(100)),
                step: 0,
                state: .failed,
                tint: .red,
                action: retryAction(for: project, store: store)
            )
        }
    }

    func stop(_ project: RepoProject, store: RepositoryStore) async {
        guard !isBusy(project.path) else { return }
        guard isManaged(project, in: store) else {
            messages[project.path] = "不在受管项目内，拒绝停止"
            return
        }
        guard let port = project.run?.port, port > 0 else {
            messages[project.path] = "没有可停止的预览端口"
            return
        }

        messages[project.path] = nil
        busy[project.path] = .stopping
        defer { busy[project.path] = nil }

        let pids = await listeningPIDs(port)
        guard !pids.isEmpty else {
            store.setPort(PortProbe.isOpen(port) ? .running : .stopped, for: project.path)
            messages[project.path] = "端口 \(port) 没有监听进程"
            return
        }

        for pid in pids {
            _ = Darwin.kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !PortProbe.isOpen(port) { break }
            try? await Task.sleep(for: .milliseconds(200))
        }

        if PortProbe.isOpen(port) {
            store.setPort(.running, for: project.path)
            messages[project.path] = "已发送停止信号（PID \(pids.map(String.init).joined(separator: ", "))），端口 \(port) 仍在监听"
        } else {
            portConflicts[project.path] = nil
            store.setPort(.stopped, for: project.path)
            messages[project.path] = "已停止端口 \(port)"
        }
    }

    func resolvePortConflictAndLaunch(
        _ project: RepoProject,
        conflict: PortConflict,
        store: RepositoryStore
    ) async {
        guard !isBusy(project.path) else { return }
        guard isManaged(project, in: store) else {
            messages[project.path] = "不在受管项目内，拒绝结束占用进程"
            return
        }

        updateServiceToast(
            path: project.path,
            title: "正在释放端口",
            subtitle: conflict.occupants.map { "PID \($0.pid)" }.joined(separator: " · "),
            step: 0,
            state: .running,
            tint: FizzTheme.accent,
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
                title: "释放端口失败",
                subtitle: result.message,
                step: 0,
                state: .failed,
                tint: .orange,
                action: ToastAction(
                    title: "再次尝试",
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
            testMessages[project.path] = "不在受管项目内，拒绝执行测试"
            return
        }
        guard let test = project.test else {
            testMessages[project.path] = "没有识别到测试命令"
            return
        }
        guard testRuns[project.path]?.status != .running else { return }
        cancelledTestPaths.remove(project.path)
        testMessages[project.path] = nil

        let logURL = URL(fileURLWithPath: logPath(for: project, prefix: "test-"))
        let header = "\n--- \(Date().ISO8601Format()) \(test.command)\n"
        guard let log = openLog(logURL, header: header) else {
            testMessages[project.path] = "无法写入测试日志"
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
            messages[project.path] = "不在受管项目内，拒绝执行脚本"
            return
        }

        let key = scriptKey(for: project, script: script)
        guard scriptRuns[key]?.status != .running else { return }
        cancelledScriptKeys.remove(key)

        let logURL = scriptLogURL(for: project, script: script)
        let header = "\n--- \(Date().ISO8601Format()) \(script.command)\n"
        guard let log = openLog(logURL, header: header) else {
            messages[project.path] = "无法写入脚本日志"
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
            messages[project.path] = "脚本启动失败：\(error.localizedDescription)"
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
            messages[project.path] = "还没有脚本日志"
            return
        }
        SystemActions.open(path)
    }

    func scriptLogPath(for project: RepoProject, script: ProjectScript) -> String {
        scriptLogURL(for: project, script: script).path
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
                testMessages[project.path] = "还没有测试日志"
            } else {
                messages[project.path] = "还没有启动日志"
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
        return AppPaths.logsDir
            .appendingPathComponent("script-\(projectSlug)-\(String(scriptSlug)).log")
    }

    private func listeningPIDs(_ port: Int) async -> [Int32] {
        let result = await Shell.run(
            "lsof",
            ["-ti", "tcp:\(port)", "-sTCP:LISTEN"],
            timeout: 5
        )
        guard let text = result?.text else { return [] }
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func handleDevTermination(
        path: String,
        port: Int,
        process: Process,
        store: RepositoryStore
    ) {
        if devProcesses[path] === process {
            devProcesses[path] = nil
        }
        if let log = devLogs[path] {
            try? log.close()
            devLogs[path] = nil
        }
        store.setPort(PortProbe.isOpen(port) ? .running : .stopped, for: path)
        messages[path] = process.terminationStatus == 0
            ? "开发服务器已退出"
            : "开发服务器已退出（状态 \(process.terminationStatus)）"
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
                succeeded ? "脚本完成" : "脚本失败",
                symbol: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill",
                tint: succeeded ? .green : .red,
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
                    title: "测试失败",
                    body: "\(project.displayName) · \(state.command)",
                    projectPath: project.path,
                    tab: .tests
                )
            }
        }
        if wasStopped {
            ToastCenter.shared.show(
                "测试已停止",
                symbol: "stop.circle.fill",
                tint: .secondary,
                subtitle: project.displayName,
                microViz: .compact(state: .warning)
            )
        } else {
            let summary = TestOutcomeSummary.parse(state.output, status: state.status)
            let passed = state.status == .passed
            ToastCenter.shared.show(
                passed ? "测试通过" : "测试失败",
                symbol: passed ? "checkmark.seal.fill" : "xmark.octagon.fill",
                tint: passed ? .green : .red,
                subtitle: "\(summary.passed) 通过 · \(summary.failed) 失败 · \(durationLabel(state.duration))",
                microViz: .tests(passed: summary.passed, failed: summary.failed),
                action: ToastAction(
                    title: "查看日志",
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
        ToastAction(title: "重试", symbol: "arrow.clockwise") { [weak self] in
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
            title: "端口 :\(conflict.port) 被占用",
            subtitle: conflict.occupantSummary,
            step: 0,
            state: .failed,
            tint: .orange,
            action: ToastAction(
                title: "释放并重试",
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
        title: String,
        subtitle: String?,
        step: Int,
        state: ToastPipelineState,
        tint: Color,
        action: ToastAction?
    ) {
        let microViz = ToastMicroViz.pipeline(step: step, state: state)
        if let id = serviceToastIDs[path],
           ToastCenter.shared.update(id, mutate: { message in
               message.title = title
               message.subtitle = subtitle
               message.tint = tint
               message.microViz = microViz
               message.action = action
               message.duration = nil
           }) {
            return
        }

        serviceToastIDs[path] = ToastCenter.shared.show(
            title,
            symbol: "bolt.horizontal.fill",
            tint: tint,
            duration: nil,
            subtitle: subtitle,
            microViz: microViz,
            action: action
        )
    }

    private func durationLabel(_ duration: TimeInterval?) -> String {
        String(format: "%.1fs", duration ?? 0)
    }
}
