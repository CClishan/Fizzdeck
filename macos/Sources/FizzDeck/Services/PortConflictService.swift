import Darwin
import Foundation
import os

/// A retry toast may hold an old snapshot. It cannot reuse the destructive button's consent.
fileprivate final class PortStopConsent: Sendable, Equatable {
    private let unused = OSAllocatedUnfairLock(initialState: true)
    func consume() -> Bool {
        unused.withLock { value in
            defer { value = false }
            return value
        }
    }
    static func == (lhs: PortStopConsent, rhs: PortStopConsent) -> Bool { lhs === rhs }
}

struct PortOccupant: Identifiable, Sendable, Hashable {
    let pid: Int32
    let name: String
    var uid: uid_t?
    var identity: ListenerIdentity?
    var command: String?
    var addresses: Set<String> = []
    var previewHosts: Set<String> = []

    var id: Int32 { pid }
    var canStop: Bool {
        guard let identity, let uid, let command, !command.isEmpty else { return false }
        return identity.pid == pid && identity.uid == uid && uid != 0 && uid == getuid() && uid == geteuid()
    }
    var displayCommand: String { SecretRedactor.redact(command ?? name).text }
    var details: String { "PID \(pid) · UID \(uid.map(String.init) ?? "未知")\n\(displayCommand)" }
}

struct PortConflict: Identifiable, Sendable, Equatable {
    let port: Int
    let occupants: [PortOccupant]
    let note: String?
    fileprivate var consent: PortStopConsent?

    init(port: Int, occupants: [PortOccupant], note: String?) {
        self.port = port
        self.occupants = occupants
        self.note = note
    }

    var id: Int { port }
    var occupantSummary: String {
        guard !occupants.isEmpty else { return note ?? "占用进程未知" }
        return occupants.map { "\($0.name) · PID \($0.pid)" }.joined(separator: "，")
    }
    var canStop: Bool { occupants.count == 1 && occupants.first?.canStop == true }
    var details: String { occupants.map(\.details).joined(separator: "\n\n") }

    // Only the destructive button inside a confirmation dialog creates this copy.
    func confirmedByUser() -> Self {
        var copy = self
        copy.consent = PortStopConsent()
        return copy
    }
}

struct PortTerminationResult: Sendable, Equatable {
    let succeeded: Bool
    let message: String
    var portReleased = false
    static func refused(_ message: String) -> Self { Self(succeeded: false, message: message) }
}

enum PortConflictService {
    static let commonPorts: Set<Int> = Set(3000...3010).union(4173...4175).union(4321...4329)
        .union(5173...5183).union(8000...8010).union([4000, 4200, 5000, 5001, 5500, 6006, 8080, 8081, 8088, 8787, 8788, 8888, 9000])

    enum ScanError: LocalizedError {
        case unavailable
        case hiddenListener(Int)
        var errorDescription: String? {
            switch self {
            case .unavailable: "无法核对 TCP 监听进程，请刷新后重试"
            case .hiddenListener(let port): "端口 \(port) 有响应，但无法读取监听 PID"
            }
        }
    }

    /// One lsof per global topology refresh; no port-by-port polling or background timer.
    static func snapshot(ports: Set<Int>) async throws -> [PortConflict] {
        let ports = ports.filter { (1...65535).contains($0) }
        guard let firstPort = ports.first else { return [] }
        let selector = ports.count == 1 ? "-iTCP:\(firstPort)" : "-iTCP"
        let result = await Shell.run("/usr/sbin/lsof", ["-nP", selector, "-sTCP:LISTEN", "-F0pcuftn"], timeout: 5)
        guard let result, !result.timedOut else { throw ScanError.unavailable }
        if result.status == 1, result.text.isEmpty {
            // A listener that lsof cannot see is not evidence that a particular project's port is free.
            if ports.count == 1, PortProbe.isOpen(firstPort) { throw ScanError.hiddenListener(firstPort) }
            return []
        }
        guard result.succeeded, result.text.contains("\0") else { throw ScanError.unavailable }
        let listeners = parseListeners(result.text, ports: ports)
        guard ports.count != 1 || !listeners.isEmpty else { throw ScanError.unavailable }
        return listeners.map { conflict in
            let occupants = conflict.occupants.map { original in
                var item = original
                if item.uid == getuid() {
                    item.identity = ListenerIdentity.read(item.pid)
                    item.command = ListenerIdentity.command(for: item.pid)
                }
                return item
            }
            return PortConflict(port: conflict.port, occupants: occupants, note: nil)
        }
    }

    static func inspect(port: Int) async -> PortConflict? {
        do { return try await snapshot(ports: [port]).first }
        catch { return PortConflict(port: port, occupants: [], note: error.localizedDescription) }
    }

    static func parseListeners(_ output: String, ports: Set<Int>) -> [PortConflict] {
        var listeners: [Int: [Int32: PortOccupant]] = [:]
        var pid: Int32?, uid: uid_t?
        var name = "", family = ""
        for part in output.split(separator: "\0") {
            let field = part.drop(while: { $0 == "\n" }) // lsof starts each process/file record on a new line
            let value = field.dropFirst()
            switch field.first {
            case "p": pid = Int32(value); uid = nil; name = ""; family = ""
            case "c": name = String(value)
            case "u": uid = uid_t(value)
            case "f": family = ""
            case "t": family = String(value)
            case "n":
                guard let pid, pid > 0, let colon = value.lastIndex(of: ":"),
                      let port = Int(value.suffix(from: value.index(after: colon))), ports.contains(port) else { continue }
                var item = listeners[port]?[pid] ?? PortOccupant(pid: pid, name: name.isEmpty ? "未知进程" : name, uid: uid)
                item.addresses.insert(String(value))
                switch (family, value[..<colon]) {
                case ("IPv4", "*"), ("IPv4", "0.0.0.0"), ("IPv4", "127.0.0.1"): item.previewHosts.insert("127.0.0.1")
                case ("IPv6", "*"), ("IPv6", "[::]"), ("IPv6", "[::1]"): item.previewHosts.insert("[::1]")
                default: break
                }
                listeners[port, default: [:]][pid] = item
            default: break
            }
        }
        return listeners.map { port, byPID in
            PortConflict(port: port, occupants: byPID.values.sorted { $0.pid < $1.pid }, note: nil)
        }.sorted { $0.port < $1.port }
    }

    static func previewURL(port: Int, occupant: PortOccupant, project: PreviewProject) async -> String? {
        guard let current = try? await snapshot(ports: [port]).first, current.occupants == [occupant],
              occupant.canStop, project.owns(listener: occupant.pid), let host = occupant.previewHosts.sorted().first
        else { return nil }
        return "http://\(host):\(port)"
    }

    @MainActor static func terminateConfirmed(
        _ conflict: PortConflict, only target: PortOccupant? = nil, managedBy project: PreviewProject? = nil,
        stillAuthorized: () -> Bool = { true }
    ) async -> PortTerminationResult {
        guard !conflict.occupants.isEmpty else { return .refused("没有可结束的 PID，请刷新后重试") }
        guard conflict.consent?.consume() == true else { return .refused("请在运行页核对 PID 和命令，再确认停止") }
        guard let selected = target ?? (conflict.occupants.count == 1 ? conflict.occupants.first : nil) else {
            return .refused("多个进程共用此端口，请选择要停止的 PID")
        }
        guard selected.canStop, conflict.occupants.contains(selected), let identity = selected.identity else {
            return .refused("无法核实当前用户的进程身份，不发送信号")
        }
        do {
            guard let current = try await snapshot(ports: [conflict.port]).first,
                  (target != nil || current.occupants.count == 1), current.occupants.contains(selected),
                  project?.owns(listener: selected.pid) != false, !Task.isCancelled, stillAuthorized()
            else { return .refused("端口、属主或进程身份已变化，请重新确认") }
            guard identity.sendTERM() else {
                return .refused("无法向 PID \(selected.pid) 发送 SIGTERM，请刷新核对")
            }
            for delay in [150, 350, 700, 1400] {
                try await Task.sleep(for: .milliseconds(delay))
                let remaining = try await snapshot(ports: [conflict.port]).first?.occupants ?? []
                if remaining.isEmpty { return .init(succeeded: true, message: "端口 \(conflict.port) 已释放", portReleased: true) }
                if !remaining.contains(where: { $0.pid == selected.pid && ($0.identity == nil || $0.identity == identity) }) {
                    return .init(succeeded: target != nil, message: "所选 PID 已停止监听，端口 \(conflict.port) 仍有其他监听")
                }
            }
            return .refused("已发送 SIGTERM，所选 PID 仍在监听；未强制停止")
        } catch { return .refused(error.localizedDescription) }
    }
}

struct DeveloperListener: Identifiable, Sendable {
    let conflict: PortConflict
    let process: PortOccupant
    let owner: PreviewProject?
    let possibleOrphan: Bool
    var id: String { "\(conflict.port):\(process.pid)" }
    var label: String { owner.map { "受管 · \($0.title)" } ?? (possibleOrphan ? "未受管 · 疑似孤儿" : "未受管") }

    static func scan(ports: Set<Int>, projects: [PreviewProject]) async throws -> [Self] {
        try await PortConflictService.snapshot(ports: ports).flatMap { conflict in
            conflict.occupants.map { item in
                let owner = item.canStop ? PreviewProject.owner(of: item.pid, among: projects) : nil
                // launchd is also the legitimate parent of many agents; never call PPID 1 alone an orphan.
                let runtime = item.identity.map { URL(fileURLWithPath: $0.executable).lastPathComponent.lowercased() } ?? ""
                let devRuntime = ["node", "bun", "deno", "ruby", "java", "php"].contains(runtime) || runtime.hasPrefix("python")
                let orphan = owner == nil && devRuntime && ListenerIdentity.bsdInfo(item.pid)?.pbi_ppid == 1
                return Self(conflict: conflict, process: item, owner: owner, possibleOrphan: orphan)
            }
        }
    }
}
