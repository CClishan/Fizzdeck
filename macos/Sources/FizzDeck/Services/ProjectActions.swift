import Darwin
import Foundation
import Observation

enum ProjectAction: String, Sendable {
    case launching
    case stopping
}

enum TestStatus: String, Sendable {
    case running
    case passed
    case failed
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
    var messages: [String: String] = [:]

    @ObservationIgnored private var devProcesses: [String: Process] = [:]
    @ObservationIgnored private var devLogs: [String: FileHandle] = [:]
    @ObservationIgnored private var testProcesses: [String: Process] = [:]
    @ObservationIgnored private var testLogs: [String: FileHandle] = [:]
    @ObservationIgnored private var cancelledTestPaths: Set<String> = []

    func isBusy(_ path: String) -> Bool {
        busy[path] != nil
    }

    func message(for path: String) -> String? {
        messages[path]
    }

    func testRun(for path: String) -> TestRunState? {
        testRuns[path]
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
            store.setPort(.running, for: project.path)
            messages[project.path] = "端口 \(run.port) 已在运行"
            return
        }

        busy[project.path] = .launching
        defer { busy[project.path] = nil }

        let logURL = URL(fileURLWithPath: logPath(for: project))
        let header = "\n--- \(Date().ISO8601Format()) \(run.command)\n"
        guard let log = openLog(logURL, header: header) else {
            messages[project.path] = "无法写入 \(PathTools.displayPath(logURL.path))"
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
                        body: "\(project.displayName) · localhost:\(run.port)"
                    )
                }
                return
            }
            if !process.isRunning { break }
            try? await Task.sleep(for: .milliseconds(350))
        }

        if process.isRunning {
            messages[project.path] = "进程已启动（PID \(process.processIdentifier)），端口 \(run.port) 尚未就绪"
        } else {
            store.setPort(.stopped, for: project.path)
            let tail = FileTools.tail(logURL, bytes: 800).trimmingCharacters(in: .whitespacesAndNewlines)
            messages[project.path] = tail.isEmpty ? "启动失败，进程已退出" : "启动失败：\(tail)"
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
            store.setPort(.stopped, for: project.path)
            messages[project.path] = "已停止端口 \(port)"
        }
    }

    func runTests(_ project: RepoProject, store: RepositoryStore) {
        guard isManaged(project, in: store) else {
            messages[project.path] = "不在受管项目内，拒绝执行测试"
            return
        }
        guard let test = project.test else {
            messages[project.path] = "没有识别到测试命令"
            return
        }
        guard testRuns[project.path]?.status != .running else { return }
        cancelledTestPaths.remove(project.path)

        let logURL = URL(fileURLWithPath: logPath(for: project, prefix: "test-"))
        let header = "\n--- \(Date().ISO8601Format()) \(test.command)\n"
        guard let log = openLog(logURL, header: header) else {
            messages[project.path] = "无法写入测试日志"
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

    func openLog(for project: RepoProject, test: Bool = false) {
        let path = logPath(for: project, prefix: test ? "test-" : "")
        guard FileTools.exists(path) else {
            messages[project.path] = "还没有日志文件"
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
                    body: "\(project.displayName) · \(state.command)"
                )
            }
        }
    }
}
