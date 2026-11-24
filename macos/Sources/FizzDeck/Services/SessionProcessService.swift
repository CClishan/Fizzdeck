import Darwin
import Foundation

struct SessionEndResult: Sendable {
    let success: Bool
    let message: String
}

enum SessionProcessService {
    static func liveProcesses(for sessions: [SessionRecord]) async -> [String: [Int32]] {
        guard !sessions.isEmpty else { return [:] }
        guard let output = await Shell.output(
            "/bin/ps",
            ["-axo", "pid=,command="],
            timeout: 5
        ) else {
            return [:]
        }
        return parse(processList: output, sessions: sessions)
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

    static func end(_ session: SessionRecord) async -> SessionEndResult {
        let processes = await liveProcesses(for: [session])[session.stableID] ?? []
        guard !processes.isEmpty else {
            return SessionEndResult(
                success: false,
                message: "没有找到这个会话对应的 CLI 进程；Codex Desktop 请在客户端内结束。"
            )
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let targets = processes.filter { $0 != currentPID }
        let signalled = targets.filter { Darwin.kill($0, SIGTERM) == 0 }
        guard !signalled.isEmpty else {
            return SessionEndResult(success: false, message: "无法向会话进程发送结束信号。")
        }

        try? await Task.sleep(for: .milliseconds(700))
        let remaining = await liveProcesses(for: [session])[session.stableID] ?? []
        let pids = signalled.map(String.init).joined(separator: ", ")
        if remaining.isEmpty {
            return SessionEndResult(success: true, message: "已结束会话进程 \(pids)")
        }
        return SessionEndResult(
            success: false,
            message: "已发送结束信号 \(pids)，进程仍在退出。"
        )
    }

    static func matches(_ command: String, session: SessionRecord) -> Bool {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let toolIndex = tokens.firstIndex(where: { token in
            let name = URL(fileURLWithPath: token).lastPathComponent.lowercased()
            return name == session.tool
        }) else { return false }
        guard toolIndex <= 1 else { return false }
        if toolIndex == 1 {
            let launcher = URL(fileURLWithPath: tokens[0]).lastPathComponent.lowercased()
            guard ["env", "node", "bun", "deno"].contains(launcher) else { return false }
        }

        if session.tool == "codex", command.contains("app-server") {
            return false
        }

        let arguments = Array(tokens.dropFirst(toolIndex + 1))
        switch session.tool {
        case "codex":
            return arguments.count >= 2
                && arguments[0] == "resume"
                && arguments[1] == session.id
        case "claude":
            guard arguments.count >= 2 else { return false }
            return (arguments[0] == "--resume" || arguments[0] == "-r")
                && arguments[1] == session.id
        default:
            return false
        }
    }
}
