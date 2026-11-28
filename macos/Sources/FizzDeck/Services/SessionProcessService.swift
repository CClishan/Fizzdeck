import Darwin
import Foundation

struct SessionEndResult: Sendable {
    let success: Bool
    let message: String
}

struct LiveSessionProcess: Sendable, Hashable {
    let pid: Int32
    let tty: String?
    let tool: String
    let sessionID: String?
    let cwd: String?
    let exactMatch: Bool
}

struct LaunchedSessionInfo: Sendable, Hashable {
    let stableID: String
    let tty: String?
    let windowID: Int?
    let terminal: String?
    let launchedAt: Date
}

actor LaunchedSessionStore {
    static let shared = LaunchedSessionStore()
    private var records: [String: LaunchedSessionInfo] = [:]

    func record(stableID: String, tty: String?, windowID: Int?, terminal: String? = nil) {
        records[stableID] = LaunchedSessionInfo(
            stableID: stableID,
            tty: tty,
            windowID: windowID,
            terminal: terminal,
            launchedAt: Date()
        )
    }

    func info(for stableID: String) -> LaunchedSessionInfo? {
        records[stableID]
    }
}

enum SessionProcessService {
    static func liveProcesses(for sessions: [SessionRecord]) async -> [String: [Int32]] {
        let detailed = await liveProcessesDetailed(for: sessions, projectPath: nil)
        return detailed.mapValues { list in
            list.filter(\.exactMatch).map(\.pid)
        }.filter { !$0.value.isEmpty }
    }

    static func liveProcessesDetailed(
        for sessions: [SessionRecord],
        projectPath: String?
    ) async -> [String: [LiveSessionProcess]] {
        guard !sessions.isEmpty else { return [:] }
        guard let output = await Shell.output(
            "/bin/ps",
            ["-axo", "pid=,tty=,command="],
            timeout: 5
        ) else {
            return [:]
        }

        let entries = parseProcessRows(output)
        var cwdByPID: [Int32: String] = [:]
        if projectPath != nil {
            let candidatePIDs = entries
                .filter { isInspectableToolCommand($0.command) }
                .map(\.pid)
            if !candidatePIDs.isEmpty {
                cwdByPID = await fetchProcessCwds(pids: candidatePIDs)
            }
        }

        return parseDetailed(
            processRows: entries,
            sessions: sessions,
            cwdByPID: cwdByPID,
            projectPath: projectPath
        )
    }

    static func parse(
        processList: String,
        sessions: [SessionRecord]
    ) -> [String: [Int32]] {
        guard !sessions.isEmpty else { return [:] }
        var result: [String: [Int32]] = [:]

        for line in processList.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(where: \.isWhitespace),
                  let pid = Int32(trimmed[..<separator])
            else { continue }

            let command = String(trimmed[trimmed.index(after: separator)...])
            for session in sessions where matches(command, session: session) {
                result[session.stableID, default: []].append(pid)
            }
        }

        return result
    }

    static func parseDetailed(
        processList: String,
        sessions: [SessionRecord],
        cwdByPID: [Int32: String] = [:],
        projectPath: String? = nil
    ) -> [String: [LiveSessionProcess]] {
        let rows = parseProcessRows(processList)
        return parseDetailed(
            processRows: rows,
            sessions: sessions,
            cwdByPID: cwdByPID,
            projectPath: projectPath
        )
    }

    static func end(_ session: SessionRecord) async -> SessionEndResult {
        let processes = await liveProcesses(for: [session])[session.stableID] ?? []
        guard !processes.isEmpty else {
            return SessionEndResult(
                success: false,
                message: FizzL10n.text("没有找到这个会话对应的 CLI 进程；Codex Desktop 请在客户端内结束。", "No CLI process was found for this session. End Codex Desktop sessions in the app.")
            )
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let targets = processes.filter { $0 != currentPID }
        let signalled = targets.filter { Darwin.kill($0, SIGTERM) == 0 }
        guard !signalled.isEmpty else {
            return SessionEndResult(success: false, message: FizzL10n.text("无法向会话进程发送结束信号。", "Couldn’t send a stop signal to the session process."))
        }

        try? await Task.sleep(for: .milliseconds(700))
        let remaining = await liveProcesses(for: [session])[session.stableID] ?? []
        let pids = signalled.map(String.init).joined(separator: ", ")
        if remaining.isEmpty {
            return SessionEndResult(success: true, message: FizzL10n.text("已结束会话进程 \(pids)", "Stopped session process \(pids)"))
        }
        return SessionEndResult(
            success: false,
            message: FizzL10n.text("已发送结束信号 \(pids)，进程仍在退出。", "Stop signal sent to \(pids). The process is still exiting.")
        )
    }

    static func matches(_ command: String, session: SessionRecord) -> Bool {
        guard let parsed = parseToolInvocation(command),
              parsed.tool == session.tool
        else { return false }

        let arguments = parsed.arguments
        switch session.tool {
        case "codex":
            return arguments.count >= 2
                && arguments[0] == "resume"
                && arguments[1] == session.id
        case "claude":
            guard arguments.count >= 2 else { return false }
            return (arguments[0] == "--resume" || arguments[0] == "-r")
                && arguments[1] == session.id
        case "grok":
            guard let first = arguments.first else { return false }
            if first.hasPrefix("--resume=") {
                return String(first.dropFirst("--resume=".count)) == session.id
            }
            guard arguments.count >= 2 else { return false }
            return (first == "--resume" || first == "-r")
                && arguments[1] == session.id
        case "gemini":
            guard let first = arguments.first else { return false }
            if first.hasPrefix("--resume=") {
                return String(first.dropFirst("--resume=".count)) == session.id
            }
            guard arguments.count >= 2 else { return false }
            return (first == "--resume" || first == "-r")
                && arguments[1] == session.id
        default:
            return false
        }
    }

    private struct ProcessRow {
        let pid: Int32
        let tty: String?
        let command: String
    }

    private static func parseDetailed(
        processRows: [ProcessRow],
        sessions: [SessionRecord],
        cwdByPID: [Int32: String],
        projectPath: String?
    ) -> [String: [LiveSessionProcess]] {
        guard !sessions.isEmpty else { return [:] }
        var result: [String: [LiveSessionProcess]] = [:]
        var matchedPIDs = Set<Int32>()

        // 1. Exact resume <id> matches
        for row in processRows {
            for session in sessions where matches(row.command, session: session) {
                matchedPIDs.insert(row.pid)
                result[session.stableID, default: []].append(LiveSessionProcess(
                    pid: row.pid,
                    tty: row.tty,
                    tool: session.tool,
                    sessionID: session.id,
                    cwd: cwdByPID[row.pid],
                    exactMatch: true
                ))
            }
        }

        // 2. Non-exact live CLI processes in the same project cwd (new session / --continue)
        if let projectPath {
            let targetNorm = PathTools.normalize(projectPath)
            let targetCanon = PathTools.canonical(projectPath)
            let latestByTool = Dictionary(
                grouping: sessions.sorted { $0.modified > $1.modified },
                by: \.tool
            ).compactMapValues(\.first)

            for row in processRows where !matchedPIDs.contains(row.pid) {
                guard let parsed = parseToolInvocation(row.command),
                      let latestSession = latestByTool[parsed.tool],
                      let cwd = cwdByPID[row.pid],
                      PathTools.normalize(cwd) == targetNorm || PathTools.canonical(cwd) == targetCanon
                else { continue }

                result[latestSession.stableID, default: []].append(LiveSessionProcess(
                    pid: row.pid,
                    tty: row.tty,
                    tool: parsed.tool,
                    sessionID: latestSession.id,
                    cwd: cwd,
                    exactMatch: false
                ))
            }
        }

        return result
    }

    private static func parseProcessRows(_ output: String) -> [ProcessRow] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(where: \.isWhitespace),
                  let pid = Int32(trimmed[..<firstSpace])
            else { return nil }

            let afterPID = trimmed[trimmed.index(after: firstSpace)...]
                .drop(while: \.isWhitespace)
            guard let secondSpace = afterPID.firstIndex(where: \.isWhitespace) else { return nil }
            let rawTTY = String(afterPID[..<secondSpace])
            let tty: String? = (rawTTY == "??" || rawTTY == "-")
                ? nil
                : (rawTTY.hasPrefix("/dev/") ? rawTTY : "/dev/\(rawTTY)")
            let command = String(afterPID[afterPID.index(after: secondSpace)...]
                .drop(while: \.isWhitespace))
            guard !command.isEmpty else { return nil }
            return ProcessRow(pid: pid, tty: tty, command: command)
        }
    }

    private static func isInspectableToolCommand(_ command: String) -> Bool {
        parseToolInvocation(command) != nil
    }

    private static func parseToolInvocation(_ command: String) -> (tool: String, arguments: [String])? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let toolIndex = tokens.firstIndex(where: { token in
            let name = URL(fileURLWithPath: token).lastPathComponent.lowercased()
            return name == "codex" || name == "claude" || name == "grok" || name == "gemini"
        }) else { return nil }
        guard toolIndex <= 1 else { return nil }
        if toolIndex == 1 {
            let launcher = URL(fileURLWithPath: tokens[0]).lastPathComponent.lowercased()
            guard ["env", "node", "bun", "deno"].contains(launcher) else { return nil }
        }
        let tool = URL(fileURLWithPath: tokens[toolIndex]).lastPathComponent.lowercased()
        if tool == "codex", command.contains("app-server") {
            return nil
        }
        return (tool, Array(tokens.dropFirst(toolIndex + 1)))
    }

    private static func fetchProcessCwds(pids: [Int32]) async -> [Int32: String] {
        let pidArg = pids.map(String.init).joined(separator: ",")
        guard let output = await Shell.output(
            "/usr/sbin/lsof",
            ["-a", "-p", pidArg, "-d", "cwd", "-Fn"],
            timeout: 4
        ) else {
            return [:]
        }
        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentPID = pid
            } else if line.hasPrefix("n"), let pid = currentPID {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }
}
