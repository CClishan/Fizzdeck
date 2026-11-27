import Darwin
import Foundation

/// An exec or PID reuse changes the kernel's pidversion. A PID alone is never a stop handle.
struct ListenerIdentity: Hashable, Sendable {
    let pid: Int32
    let uid: uid_t
    let version: UInt32
    let executable: String

    private static func token(for pid: Int32) -> audit_token_t? {
        guard pid > 1, pid != getpid() else { return nil }
        var port: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &port) == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, port) }
        var token = audit_token_t()
        let words = MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(words)
        let result = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: words) {
                task_info(port, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        // Darwin audit token: effective UID, real UID, PID and pidversion.
        guard result == KERN_SUCCESS, count == words, token.val.5 == UInt32(pid),
              token.val.1 == geteuid(), token.val.3 == getuid(), token.val.1 == token.val.3
        else { return nil }
        return token
    }

    static func read(_ pid: Int32) -> Self? {
        guard var token = token(for: pid) else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath_audittoken(&token, &path, UInt32(path.count)) > 0 else { return nil }
        return Self(pid: pid, uid: token.val.1, version: token.val.7, executable: String(cString: path))
    }

    func sendTERM() -> Bool {
        guard var token = Self.token(for: pid), token.val.1 == uid, token.val.7 == version else { return false }
        return proc_signal_with_audittoken(&token, SIGTERM) == 0
    }
}

/// `ProjectActions.launch` gives its direct child the project cwd and the dev log as stdout/stderr.
/// Tests, arbitrary scripts, other apps, and an unrelated copy of FizzDeck do not share that launch proof.
struct PreviewProject: Equatable, Sendable {
    let path: String
    let title: String
    let port: Int
    let logPath: String

    @MainActor static func from(_ project: RepoProject, actions: ProjectActions) -> Self? {
        guard let port = project.run?.port, (1...65535).contains(port) else { return nil }
        return Self(path: project.path, title: project.displayName, port: port, logPath: actions.logPath(for: project))
    }

    func owns(listener pid: Int32, launchedBy rootPID: Int32? = nil) -> Bool {
        Self.owner(of: pid, among: [self], launchedBy: rootPID) != nil
    }

    static func owner(of pid: Int32, among projects: [Self], launchedBy rootPID: Int32? = nil) -> Self? {
        guard !projects.isEmpty else { return nil }
        var current = pid
        var seen = Set<Int32>()
        while current > 1, current != getpid(), seen.insert(current).inserted {
            guard let info = ListenerIdentity.bsdInfo(current), info.pbi_uid == geteuid(), info.pbi_ruid == getuid()
            else { return nil }
            if info.pbi_ppid == UInt32(getpid()) {
                if let rootPID, current != rootPID { return nil }
                var cwd = proc_vnodepathinfo()
                let bytes = Int32(MemoryLayout.size(ofValue: cwd))
                guard proc_pidinfo(current, PROC_PIDVNODEPATHINFO, 0, &cwd, bytes) == bytes else { return nil }
                let outputs = [STDOUT_FILENO, STDERR_FILENO].compactMap { fd -> vinfo_stat? in
                    var file = vnode_fdinfowithpath()
                    let bytes = Int32(MemoryLayout.size(ofValue: file))
                    guard proc_pidfdinfo(current, fd, PROC_PIDFDVNODEPATHINFO, &file, bytes) == bytes else { return nil }
                    return file.pvip.vip_vi.vi_stat
                }
                guard outputs.count == 2 else { return nil }
                let matches = projects.filter { project in
                    sameFile(cwd.pvi_cdir.vip_vi.vi_stat, path: project.path)
                        && outputs.allSatisfy { sameFile($0, path: project.logPath) }
                }
                return matches.count == 1 ? matches[0] : nil
            }
            current = Int32(info.pbi_ppid)
        }
        return nil
    }

    private static func sameFile(_ actual: vinfo_stat, path: String) -> Bool {
        var expected = stat()
        return stat(path, &expected) == 0 && actual.vst_ino == expected.st_ino
            && actual.vst_dev == UInt32(bitPattern: expected.st_dev)
    }

}

extension ListenerIdentity {
    static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_pid == UInt32(pid) else { return nil }
        return info
    }

    /// KERN_PROCARGS2 also contains the environment; consume exactly argc arguments, never display it.
    static func command(for pid: Int32) -> String? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4, size <= 2 * 1024 * 1024 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        let data = bytes.prefix(size)
        guard argc > 0, let end = data.dropFirst(4).firstIndex(of: 0),
              let start = data[end...].firstIndex(where: { $0 != 0 }) else { return nil }
        var args: [String] = []
        var offset = start
        for _ in 0..<argc {
            guard offset < size, let end = data[offset...].firstIndex(of: 0) else { return nil }
            args.append(String(decoding: data[offset..<end], as: UTF8.self))
            offset = end + 1
        }
        return args.joined(separator: " ")
    }
}
