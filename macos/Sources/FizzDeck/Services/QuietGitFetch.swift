import CryptoKit
import Foundation

enum QuietGitFetch {
    struct Target: Equatable, Sendable {
        let url: String, branch: String, source: String, tracking: String
        var usesSSH: Bool { url.hasPrefix("ssh://") }
    }

    struct Result: Sendable {
        let branch: String, head: String, counts: GitTrackingCounts
    }

    actor AttemptWindow {
        static let shared = AttemptWindow()
        private let suiteName: String?
        private lazy var defaults = suiteName == nil ? UserDefaults.standard : UserDefaults(suiteName: suiteName)

        init(suiteName: String? = nil) { self.suiteName = suiteName }

        // Resolve aliases and reserve on this actor, only when the worker reaches the project.
        func reserve(path: String, now: Date) -> (allowed: Bool, next: Date) {
            guard FileTools.isDirectory(URL(fileURLWithPath: path)) else { return (false, now) }
            let next = now.addingTimeInterval(86_400)
            guard let defaults else { return (false, next) }
            let digest = SHA256.hash(data: Data(PathTools.canonical(path).utf8)).map { String(format: "%02x", $0) }.joined()
            let key = "fizzdeck.quietFetch.attempt." + digest
            if let last = defaults.object(forKey: key) as? Date, now.timeIntervalSince(last) < 86_400 {
                return (false, last.addingTimeInterval(86_400))
            }
            defaults.set(now, forKey: key)
            return (true, next)
        }
    }

    private static func matches(_ string: String, _ regex: String) -> Bool {
        string.range(of: "\\A(?:" + regex + ")\\z", options: .regularExpression) != nil
    }

    private static func endpoint(_ raw: String) -> String? {
        guard raw.utf8.count <= 512, !raw.contains("..") else { return nil }
        for host in ["github.com", "gitlab.com", "bitbucket.org"] {
            let https = "https://\(host)/", ssh = "ssh://git@\(host)/"
            for prefix in [https, ssh, "ssh://git@\(host):22/", "git@\(host):"] where raw.hasPrefix(prefix) {
                let path = String(raw.dropFirst(prefix.count))
                guard matches(path, #"[A-Za-z0-9_-][A-Za-z0-9._-]*(?:/[A-Za-z0-9_-][A-Za-z0-9._-]*)+/?"#) else { return nil }
                return (prefix == https ? https : ssh) + path
            }
        }
        return nil
    }

    static func target(config: String, head: String) -> Target? {
        func validRef(_ value: String) -> Bool {
            matches(value, #"[A-Za-z0-9_][A-Za-z0-9._/-]{0,180}"#) && !value.contains("..") && value != "HEAD"
                && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                    !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(".") && !$0.lowercased().hasSuffix(".lock")
                }
        }
        let prefix = "ref: refs/heads/"
        guard head.hasPrefix(prefix) else { return nil }
        let branch = String(head.dropFirst(prefix.count))
        guard validRef(branch) else { return nil }
        var values: [String: [String]] = [:]
        for record in config.split(separator: "\0") {
            let parts = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let key = String(parts[0]), value = String(parts[1])
            // Unknown configuration stays on the explicit, manual Git path.
            guard matches(key, #"core\.(repositoryformatversion|filemode|bare|logallrefupdates|ignorecase|precomposeunicode)|remote\.[A-Za-z0-9_-]+\.(url|fetch)|branch\..+\.(remote|merge|vscode-merge-base)|user\.(name|email)"#)
            else { return nil }
            values[key, default: []].append(value)
        }
        func only(_ key: String) -> String? { values[key]?.count == 1 ? values[key]?.first : nil }
        guard only("core.repositoryformatversion") == "0", only("core.bare") == "false",
              let remote = only("branch.\(branch).remote"), matches(remote, #"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}"#),
              let source = only("branch.\(branch).merge"), source.hasPrefix("refs/heads/"),
              let rawURL = only("remote.\(remote).url"), let url = endpoint(rawURL) else { return nil }
        let trackedBranch = String(source.dropFirst("refs/heads/".count)), tracking = "refs/remotes/\(remote)/\(trackedBranch)"
        guard validRef(trackedBranch), let mapping = only("remote.\(remote).fetch"),
              ["+refs/heads/*:refs/remotes/\(remote)/*", "+\(source):\(tracking)", "\(source):\(tracking)"].contains(mapping) else { return nil }
        return Target(url: url, branch: branch, source: source, tracking: tracking)
    }

    private static let safeOptions = ["--git-dir=.", "--no-pager", "-c", "core.bare=true", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
                                      "-c", "core.logAllRefUpdates=false", "-c", "gc.auto=0", "-c", "maintenance.auto=false"]
    private static let packBudget: Int64 = 32 * 1024 * 1024

    static func fetchArguments(for target: Target) -> [String] {
        let options = safeOptions + ["-c", "credential.helper=", "-c", "credential.interactive=false", "-c", "http.followRedirects=false",
                                     "-c", "protocol.version=0", "-c", "core.alternateRefsCommand=/usr/bin/true", "-c", "pack.threads=1",
                                     "-c", "fetch.unpackLimit=1", "-c", "fetch.fsckObjects=true"]
        let args = ["fetch", "--quiet", "--no-tags", "--no-recurse-submodules", "--no-auto-maintenance", "--no-write-fetch-head",
                    "--no-write-commit-graph", "--negotiation-tip=refs/heads/base", "--", target.url, "+\(target.source):refs/heads/received"]
        return options + args
    }

    // Every word is controlled by the app. Git passes the validated destination separately as argv.
    // A signing agent or a security key can prompt outside ssh even in BatchMode; don't enlist either.
    static let sshArguments = [
        "-F", "/dev/null", "-T", "-p", "22", "-oBatchMode=yes", "-oPreferredAuthentications=publickey",
        "-oPasswordAuthentication=no", "-oKbdInteractiveAuthentication=no", "-oNumberOfPasswordPrompts=0",
        "-oStrictHostKeyChecking=yes", "-oUpdateHostKeys=no", "-oCheckHostIP=no", "-oVerifyHostKeyDNS=no",
        "-oUserKnownHostsFile=%d/.ssh/known_hosts", "-oGlobalKnownHostsFile=/etc/ssh/ssh_known_hosts",
        "-oIdentityAgent=none", "-oIdentitiesOnly=yes", "-oAddKeysToAgent=no", "-oUseKeychain=no",
        "-oIdentityFile=%d/.ssh/id_ed25519", "-oIdentityFile=%d/.ssh/id_ecdsa", "-oIdentityFile=%d/.ssh/id_rsa",
        "-oPubkeyAcceptedAlgorithms=ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256",
        "-oForwardAgent=no", "-oClearAllForwardings=yes", "-oForwardX11=no", "-oPermitLocalCommand=no",
        "-oCanonicalizeHostname=no", "-oProxyCommand=none", "-oProxyJump=none", "-oControlMaster=no", "-oControlPath=none",
        "-oConnectTimeout=4", "-oConnectionAttempts=1", "-oLogLevel=ERROR",
    ]

    static func transportEnvironment(git: String, target: Target) -> [String: String] {
        let libexec = URL(fileURLWithPath: git).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("libexec/git-core").path
        var env = ["GIT_ALLOW_PROTOCOL": target.usesSSH ? "ssh" : "https", "GIT_PROTOCOL_FROM_USER": "0", "GIT_EXEC_PATH": libexec]
        if target.usesSSH {
            env["GIT_SSH_COMMAND"] = (["/usr/bin/ssh"] + sshArguments).joined(separator: " ")
            env["GIT_SSH_VARIANT"] = "ssh"
            env["SSH_ASKPASS_REQUIRE"] = "never"
            return env
        }
        // Proxy settings are app/user input, never project input. Do not forward credentials or other ambient environment.
        let processEnv = ProcessInfo.processInfo.environment
        if let proxy = processEnv["HTTPS_PROXY"] ?? processEnv["https_proxy"] ?? processEnv["HTTP_PROXY"],
           let parts = URLComponents(string: proxy), ["http", "https"].contains(parts.scheme), parts.host != nil,
           parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil { env["https_proxy"] = proxy }
        return env
    }

    private static func transfer(git: String, in bare: URL, target: Target) async -> Bool {
        let packDir = bare.appendingPathComponent("objects/pack"), environment = transportEnvironment(git: git, target: target)
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await DoctorCommand.run(git, fetchArguments(for: target), cwd: bare, environment: environment, timeout: 8, outputLimit: 1024) != nil }
            group.addTask {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                    if FileTools.childEntries(of: packDir).reduce(Int64(0), { $0 + FileTools.fileSize($1) }) > packBudget { break }
                }
                return false
            }
            let ok = await group.next() ?? false
            group.cancelAll()
            return ok
        }
    }

    typealias Transfer = @Sendable (String, URL, Target) async -> Bool

    static func check(in project: URL, transfer: Transfer = { await QuietGitFetch.transfer(git: $0, in: $1, target: $2) }) async -> Result? {
        let fm = FileManager.default
        let db = project.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(".git")
        func plainPath(_ relative: String) -> Bool {
            // Check each component, including dangling links that resolvingSymlinksInPath would miss.
            var current = db.deletingLastPathComponent()
            for part in ([".git"] + relative.split(separator: "/").map(String.init)) {
                current.appendPathComponent(part)
                var st = stat()
                if lstat(current.path, &st) == 0, st.st_mode & S_IFMT == S_IFLNK { return false }
            }
            return true
        }
        guard let git = DoctorCommand.git, !Task.isCancelled, !db.path.contains(where: \.isNewline),
              ["objects/pack", "objects/info", "refs", "HEAD", "packed-refs", "config"].allSatisfy(plainPath),
              FileTools.isDirectory(db.appendingPathComponent("objects/pack")),
              ["shallow", "commondir", "objects/info/alternates", "objects/info/http-alternates"].allSatisfy({
                  var st = stat(); return lstat(db.appendingPathComponent($0).path, &st) != 0 && errno == ENOENT
              }) else { return nil }
        let config = DoctorInputs.text(db.appendingPathComponent("config"), limit: 64 * 1024)
        func head() -> String { DoctorInputs.text(db.appendingPathComponent("HEAD"), limit: 256).trimmingCharacters(in: .newlines) }
        let originalHead = head()
        guard !config.isEmpty, !originalHead.isEmpty else { return nil }
        let temp = fm.temporaryDirectory.appendingPathComponent("fizz-fetch-" + UUID().uuidString)
        do { try fm.createDirectory(at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { return nil }
        defer { try? fm.removeItem(at: temp) }
        let copy = temp.appendingPathComponent("config.snapshot")
        guard (try? config.write(to: copy, atomically: true, encoding: .utf8)) != nil,
              let entries = await DoctorCommand.run(git, ["config", "--file", copy.path, "--no-includes", "--null", "--list"], cwd: temp, outputLimit: 96 * 1024),
              let target = target(config: entries, head: originalHead), plainPath(target.tracking), plainPath("refs/heads/" + target.branch)
        else { return nil }

        // Both Git directories are app-owned. The network process sees only a known upstream tip, never local heads,
        // index, reflogs, hooks or Git configuration. Only an offline compare-and-swap can publish a tracking ref.
        let local = temp.appendingPathComponent("local.git"), network = temp.appendingPathComponent("network.git")
        do {
            for bare in [local, network] {
                try fm.createDirectory(at: bare, withIntermediateDirectories: false)
                try "ref: refs/heads/unused\n".write(to: bare.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
            }
            try fm.createSymbolicLink(at: local.appendingPathComponent("objects"), withDestinationURL: db.appendingPathComponent("objects"))
            try fm.createDirectory(at: network.appendingPathComponent("objects/pack"), withIntermediateDirectories: true)
            try fm.createDirectory(at: network.appendingPathComponent("objects/info"), withIntermediateDirectories: true)
            try (db.appendingPathComponent("objects").path + "\n").write(to: network.appendingPathComponent("objects/info/alternates"), atomically: true, encoding: .utf8)
            try fm.createSymbolicLink(at: local.appendingPathComponent("refs"), withDestinationURL: db.appendingPathComponent("refs"))
            if FileTools.exists(db.appendingPathComponent("packed-refs")) {
                try fm.createSymbolicLink(at: local.appendingPathComponent("packed-refs"), withDestinationURL: db.appendingPathComponent("packed-refs"))
            }
            try fm.createDirectory(at: network.appendingPathComponent("refs/heads"), withIntermediateDirectories: true)
        } catch { return nil }
        func oid(_ ref: String, in bare: URL) async -> String? {
            guard let output = await DoctorCommand.run(git, safeOptions + ["rev-parse", "--verify", ref], cwd: bare) else { return nil }
            let hash = output.trimmingCharacters(in: .newlines)
            return matches(hash, "[0-9a-f]{40}") ? hash : nil
        }
        let localRef = "refs/heads/" + target.branch
        guard let before = await oid(target.tracking, in: local), let tip = await oid(localRef, in: local),
              (try? (before + "\n").write(to: network.appendingPathComponent("refs/heads/base"), atomically: true, encoding: .utf8)) != nil,
              await transfer(git, network, target), !Task.isCancelled,
              let fetched = await oid("refs/heads/received", in: network), head() == originalHead,
              config == DoctorInputs.text(db.appendingPathComponent("config"), limit: 64 * 1024),
              plainPath(target.tracking), plainPath("objects/pack"), await oid(localRef, in: local) == tip,
              let counts = await DoctorCommand.run(git, safeOptions + ["rev-list", "--count", "--left-right", "\(fetched)...\(tip)"], cwd: network),
              let artifacts = try? fm.contentsOfDirectory(at: network.appendingPathComponent("objects/pack"), includingPropertiesForKeys: nil),
              artifacts.reduce(Int64(0), { $0 + FileTools.fileSize($1) }) <= packBudget
        else { return nil }
        for pack in artifacts where pack.pathExtension == "pack" {
            guard matches(pack.lastPathComponent, #"pack-[0-9a-f]{40}\.pack"#),
                  await DoctorCommand.run(git, safeOptions + ["index-pack", "--stdin", "--threads=1", "--max-input-size=\(packBudget)"], cwd: local, inputFile: pack) != nil
            else { return nil }
        }
        guard !Task.isCancelled, head() == originalHead, plainPath(target.tracking),
              config == DoctorInputs.text(db.appendingPathComponent("config"), limit: 64 * 1024), await oid(localRef, in: local) == tip,
              await DoctorCommand.run(git, safeOptions + ["update-ref", "--no-deref", target.tracking, fetched, before], cwd: local) != nil else { return nil }
        return Result(branch: target.branch, head: tip, counts: GitService.trackingCounts(counts))
    }
}
