import Darwin
import Foundation

struct PortOccupant: Identifiable, Sendable, Hashable {
    let pid: Int32
    let name: String

    var id: Int32 { pid }
}

struct PortConflict: Identifiable, Sendable, Equatable {
    let port: Int
    let occupants: [PortOccupant]
    let note: String?

    var id: Int { port }

    var occupantSummary: String {
        guard !occupants.isEmpty else { return note ?? "占用进程未知" }
        return occupants
            .map { "\($0.name) · PID \($0.pid)" }
            .joined(separator: "，")
    }
}

struct PortTerminationResult: Sendable, Equatable {
    let succeeded: Bool
    let message: String
}

enum PortConflictService {
    static func inspect(port: Int) async -> PortConflict? {
        guard (1...65_535).contains(port), PortProbe.isOpen(port) else { return nil }

        guard let result = await Shell.run(
            "lsof",
            ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"],
            timeout: 5
        ) else {
            return PortConflict(port: port, occupants: [], note: "lsof 不可用，无法读取 PID")
        }

        let occupants = parseOccupants(result.text)
        if occupants.isEmpty {
            return PortConflict(
                port: port,
                occupants: [],
                note: result.succeeded ? "端口有监听，但未解析到进程" : "lsof 读取失败"
            )
        }
        return PortConflict(port: port, occupants: occupants, note: nil)
    }

    static func parseOccupants(_ output: String) -> [PortOccupant] {
        var results: [PortOccupant] = []
        var seen = Set<Int32>()
        var pendingPID: Int32?

        func append(pid: Int32, name: String) {
            guard pid > 1, seen.insert(pid).inserted else { return }
            results.append(PortOccupant(pid: pid, name: name.isEmpty ? "未知进程" : name))
        }

        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            if rawLine.hasPrefix("p"), let pid = Int32(rawLine.dropFirst()) {
                if let pendingPID, !seen.contains(pendingPID) {
                    append(pid: pendingPID, name: "")
                }
                pendingPID = pid
            } else if rawLine.hasPrefix("c"), let pid = pendingPID {
                append(pid: pid, name: String(rawLine.dropFirst()))
                pendingPID = nil
            }
        }
        if let pendingPID {
            append(pid: pendingPID, name: "")
        }
        return results
    }

    static func terminateConfirmed(_ conflict: PortConflict) async -> PortTerminationResult {
        guard !conflict.occupants.isEmpty else {
            return PortTerminationResult(succeeded: false, message: "没有可结束的 PID，请刷新后重试")
        }
        guard let current = await inspect(port: conflict.port) else {
            return PortTerminationResult(succeeded: true, message: "端口 \(conflict.port) 已释放")
        }

        let confirmed = Set(conflict.occupants.map(\.pid))
        let targets = current.occupants.filter {
            confirmed.contains($0.pid)
                && $0.pid > 1
                && $0.pid != getpid()
        }
        guard !targets.isEmpty else {
            return PortTerminationResult(
                succeeded: false,
                message: "占用进程已变化，请刷新后重新确认"
            )
        }

        var signaled = 0
        var signaledTargets: [PortOccupant] = []
        var failures: [String] = []
        for occupant in targets {
            if Darwin.kill(occupant.pid, SIGTERM) == 0 {
                signaled += 1
                signaledTargets.append(occupant)
            } else {
                failures.append("\(occupant.name) (\(occupant.pid)) errno \(errno)")
            }
        }
        guard signaled > 0 else {
            return PortTerminationResult(
                succeeded: false,
                message: "SIGTERM 发送失败：\(failures.joined(separator: "、"))"
            )
        }

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if !PortProbe.isOpen(conflict.port) {
                let names = signaledTargets.map { "\($0.name) (\($0.pid))" }.joined(separator: "、")
                let suffix = failures.isEmpty
                    ? ""
                    : "；部分失败：\(failures.joined(separator: "、"))"
                return PortTerminationResult(
                    succeeded: true,
                    message: "已结束 \(names)，端口 \(conflict.port) 已释放\(suffix)"
                )
            }
            try? await Task.sleep(for: .milliseconds(150))
        }

        return PortTerminationResult(
            succeeded: false,
            message: "已发送 SIGTERM，但端口 \(conflict.port) 仍在监听；未强制结束进程"
        )
    }
}
