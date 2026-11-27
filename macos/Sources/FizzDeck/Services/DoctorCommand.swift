import Darwin
import Foundation

// For automatic diagnostics only. No login shell, inherited credentials, project PATH or terminal.
enum DoctorCommand {
    static let developerBins = [
        "/Applications/Xcode.app/Contents/Developer/usr/bin", "/Library/Developer/CommandLineTools/usr/bin",
    ]
    static var git: String? { executable("git", in: developerBins) }

    static func executable(_ name: String, in directories: [String]) -> String? {
        directories.lazy.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ executable: String, _ arguments: [String], cwd: URL, environment: [String: String] = [:],
                    timeout: TimeInterval = 3, outputLimit: Int = 16 * 1024, inputFile: URL? = nil,
                    acceptedStatuses: Set<Int32> = [0]) async -> String? {
        guard !Task.isCancelled else { return nil }
        let worker = Task.detached(priority: .utility) { () -> String? in
            var env = ["PATH": "/usr/bin:/bin", "HOME": "/var/empty", "LC_ALL": "C", "XDG_CONFIG_HOME": "/var/empty",
                       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_ATTR_NOSYSTEM": "1",
                       "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/usr/bin/false", "SSH_ASKPASS": "/usr/bin/false",
                       "GIT_ALLOW_PROTOCOL": "", "GIT_NO_LAZY_FETCH": "1", "GIT_NO_REPLACE_OBJECTS": "1", "GIT_OPTIONAL_LOCKS": "0"]
            env.merge(environment) { _, new in new }
            var fds = [Int32](repeating: -1, count: 2)
            guard pipe(&fds) == 0 else { return nil }
            defer { close(fds[0]) }
            var actions: posix_spawn_file_actions_t?
            var attr: posix_spawnattr_t?
            posix_spawn_file_actions_init(&actions)
            posix_spawnattr_init(&attr)
            defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr) }
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, inputFile?.path ?? "/dev/null", O_RDONLY | O_NOFOLLOW, 0)
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
            posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
            posix_spawn_file_actions_addchdir(&actions, cwd.path)
            posix_spawnattr_setpgroup(&attr, 0)
            posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
            let argv = ([executable] + arguments).map { strdup($0) } + [nil]
            let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
            var pid: pid_t = 0
            let spawned = posix_spawn(&pid, executable, &actions, &attr, argv, envp)
            close(fds[1])
            guard spawned == 0 else { return nil }
            _ = fcntl(fds[0], F_SETFL, O_NONBLOCK)
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            var buffer = [UInt8](repeating: 0, count: 4096), output = Data(), status: Int32 = 0
            while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
                let count = read(fds[0], &buffer, buffer.count)
                if count > 0 {
                    guard output.count + count <= outputLimit else { break }
                    output.append(contentsOf: buffer.prefix(count))
                } else if count == 0, waitpid(pid, &status, WNOHANG) == pid {
                    return status & 0x7f == 0 && acceptedStatuses.contains((status >> 8) & 0xff) ? String(data: output, encoding: .utf8) : nil
                } else {
                    var reader = pollfd(fd: fds[0], events: Int16(POLLIN), revents: 0)
                    if count == 0 { usleep(5_000) } else { _ = poll(&reader, 1, 50) }
                }
            }
            // This process group is created above and its leader has not yet been reaped.
            _ = kill(-pid, SIGKILL)
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            return nil
        }
        return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }
}
