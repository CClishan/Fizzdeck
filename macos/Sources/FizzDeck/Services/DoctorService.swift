import Foundation

enum DoctorPreferences {
    static let confirmedFirstInstallKey = "fizzdeck.doctor.confirmedFirstInstall"

    static func hasConfirmedFirstInstall(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: confirmedFirstInstallKey)
    }

    static func setConfirmedFirstInstall(_ confirmed: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(confirmed, forKey: confirmedFirstInstallKey)
    }
}

enum DoctorSeverity: Int, Codable, Sendable, Comparable {
    case critical = 0
    case warning = 1
    case healthy = 2

    static func < (lhs: DoctorSeverity, rhs: DoctorSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum DoctorIssueKind: String, Codable, Sendable, Hashable {
    case missingDependencies
    case staleDependencies
    case missingEnvFile
    case unignoredEnvFile
    case trackedSecrets
    case portConflict
    case runtimeVersionMismatch
    case notAGitRepo
    case cloudBehind

    // An old, edited, or future state.json must never hide a critical finding.
    var canExempt: Bool {
        switch self {
        case .staleDependencies, .missingEnvFile, .runtimeVersionMismatch, .notAGitRepo, .cloudBehind: true
        case .missingDependencies, .unignoredEnvFile, .trackedSecrets, .portConflict: false
        }
    }

    var exemptionTitle: String {
        switch self {
        case .staleDependencies: FizzL10n.text("依赖过期", "Outdated dependencies")
        case .missingEnvFile: FizzL10n.text("缺少环境配置", "Missing environment file")
        case .runtimeVersionMismatch: FizzL10n.text("运行时版本不匹配", "Runtime version mismatch")
        case .notAGitRepo: FizzL10n.text("未开启版本保护", "Version protection off")
        case .cloudBehind: FizzL10n.text("云端领先", "Remote ahead")
        default: rawValue
        }
    }
}

enum DoctorFixAction: Equatable, Sendable {
    case installDependencies(command: String)
    case createEnvFromExample
    case addEnvToGitignore
    case resolvePortConflict(PortConflict)
    case initGitRepository
    case inspectTrackedSecrets(files: [String])
    case copyShellCommand(command: String)
}

struct DoctorIssue: Identifiable, Equatable, Sendable {
    let id: String
    let projectPath: String
    let kind: DoctorIssueKind
    let severity: DoctorSeverity
    let fixAction: DoctorFixAction?
    private let finding: Finding

    // Store facts, not rendered sentences. A language change never needs another scan.
    fileprivate enum Finding: Equatable, Sendable {
        case verbatim(title: String, detail: String)
        case lightweight(LightweightProjectIssue)
        case cloudBehind(Int)
        case missingEnvironment(CopyMode)
        case unprotected(CopyMode)
        case runtime(RuntimeVersionMismatch)
        case secrets(files: [String], total: Int, CopyMode)
        case port(PortConflict, CopyMode, DoctorListenerFailure?)
    }

    var title: String { title(for: nil) }

    func title(for mode: CopyMode?) -> String {
        switch finding {
        case .verbatim(let title, _): title
        case .lightweight(let issue): issue.title(for: mode)
        case .cloudBehind(let count):
            FizzL10n.text("云端领先 \(count) 个提交", mode == .plain
                ? "\(count) new \(count == 1 ? "version" : "versions") online"
                : "Remote ahead by \(count) \(count == 1 ? "commit" : "commits")")
        case .missingEnvironment(let scannedMode):
            (mode ?? scannedMode) == .plain
                ? FizzL10n.text("缺少项目配置文件 .env（已有模板）", "The project needs a .env file (template available)")
                : FizzL10n.text("缺少环境变量文件 .env", "Missing .env file")
        case .unprotected(let scannedMode):
            (mode ?? scannedMode) == .plain
                ? FizzL10n.text("还没有开启版本保护", "Version protection is off")
                : FizzL10n.text("未初始化 Git 仓库", "Git repository not initialized")
        case .runtime(let mismatch): mismatch.title
        case .secrets(_, _, let scannedMode):
            (mode ?? scannedMode) == .plain
                ? FizzL10n.text("已保存的代码里疑似包含密钥", "Saved code may contain secrets")
                : FizzL10n.text("跟踪文件命中疑似密钥", "Possible secrets in tracked files")
        case .port(let conflict, let scannedMode, _):
            (mode ?? scannedMode) == .plain
                ? FizzL10n.text("端口 \(conflict.port) 被其他程序占着", "Another program is using port \(conflict.port)")
                : FizzL10n.text("端口 \(conflict.port) 已被占用", "Port \(conflict.port) is in use")
        }
    }

    var detail: String {
        switch finding {
        case .verbatim(_, let detail): return detail
        case .lightweight(let issue): return issue.detail
        case .cloudBehind:
            return FizzL10n.text("可在版本页查看并决定是否拉取", "Review the changes on the version tab before pulling.")
        case .missingEnvironment:
            return FizzL10n.text("根目录已有 .env.example 模板，可复制成 .env 后填入所需配置", "Copy .env.example from the project root to .env, then fill in the required values.")
        case .unprotected:
            return FizzL10n.text("开启后，每次 AI 对话前都能自动记下状态，随时可还原", "Turn it on to save the project state before each AI conversation and restore it later.")
        case .runtime(let mismatch): return mismatch.detail
        case .secrets(let files, let total, _):
            let sample = files.joined(separator: FizzL10n.text("、", ", "))
            let more = total > files.count ? FizzL10n.text(" 等 \(total) 个文件", " (\(total) files in total)") : ""
            return FizzL10n.text("命中文件：\(sample)\(more)，建议移入 .env 后再上传到云端", "Files: \(sample)\(more). Move the secrets into .env before uploading.")
        case .port(let conflict, _, let failure): return failure?.message ?? conflict.occupantSummary
        }
    }

    init(projectPath: String, kind: DoctorIssueKind, severity: DoctorSeverity, title: String, detail: String,
         fixAction: DoctorFixAction?, identity: String? = nil) {
        self.init(projectPath: projectPath, kind: kind, severity: severity, finding: .verbatim(title: title, detail: detail),
                  fixAction: fixAction, identity: identity)
    }

    fileprivate init(projectPath: String, kind: DoctorIssueKind, severity: DoctorSeverity, finding: Finding,
                     fixAction: DoctorFixAction?, identity: String? = nil) {
        let baseID = "\(projectPath)::\(kind.rawValue)"
        if let identity, !identity.isEmpty {
            self.id = "\(baseID)::\(identity)"
        } else {
            self.id = baseID
        }
        self.projectPath = projectPath
        self.kind = kind
        self.severity = severity
        self.finding = finding
        self.fixAction = fixAction
    }
}

// Keep app-generated probe errors typed; external error messages pass through unchanged.
enum DoctorListenerFailure: Equatable, Sendable {
    case unavailable, hidden(Int), other(String)

    init(_ error: Error) {
        switch error as? PortConflictService.ScanError {
        case .unavailable: self = .unavailable
        case .hiddenListener(let port): self = .hidden(port)
        case nil: self = .other(error.localizedDescription)
        }
    }

    var message: String {
        switch self {
        case .unavailable: PortConflictService.ScanError.unavailable.localizedDescription
        case .hidden(let port): PortConflictService.ScanError.hiddenListener(port).localizedDescription
        case .other(let message): message
        }
    }
}

enum DoctorCheckScope: Sendable {
    case focused
    case idle
}

struct DoctorProjectReport: Identifiable, Equatable, Sendable {
    let projectPath: String
    let checkedAt: Date
    let issues: [DoctorIssue]

    var id: String { projectPath }

    var severity: DoctorSeverity {
        if issues.contains(where: { $0.severity == .critical }) {
            return .critical
        }
        if issues.contains(where: { $0.severity == .warning }) {
            return .warning
        }
        return .healthy
    }

    var actionableCount: Int {
        issues.filter { $0.severity != .healthy }.count
    }

    func applying(_ exemptions: Set<DoctorIssueKind>) -> Self {
        Self(projectPath: projectPath, checkedAt: checkedAt, issues: issues.filter {
            $0.severity == .critical || !$0.kind.canExempt || !exemptions.contains($0.kind)
        })
    }
}

struct MachineToolStatus: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let path: String?
    var available: Bool { path != nil }
    var detail: String { path ?? FizzL10n.text("未安装", "Not installed") }
}

struct MachineDiskStatus: Equatable, Sendable {
    let free: Int64
    let total: Int64
}

struct MachineEnvironmentReport: Equatable, Sendable {
    let checkedAt: Date
    let gitInstalled: Bool
    let gitUserName: String?
    let gitUserEmail: String?
    let nodeVersion: String?
    let pythonVersion: String?
    let cliTools: [MachineToolStatus]
    let disk: MachineDiskStatus?

    var needsGitIdentity: Bool {
        gitInstalled && ((gitUserName ?? "").isEmpty || (gitUserEmail ?? "").isEmpty)
    }

}

enum DoctorService {
    private static let secretPattern =
        #"(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,})"#

    static func detectInstallCommand(in directory: URL) -> String {
        if FileTools.exists(directory.appendingPathComponent("pnpm-lock.yaml")) {
            return "pnpm install"
        }
        if FileTools.exists(directory.appendingPathComponent("yarn.lock")) {
            return "yarn install"
        }
        if FileTools.exists(directory.appendingPathComponent("bun.lock"))
            || FileTools.exists(directory.appendingPathComponent("bun.lockb")) {
            return "bun install"
        }
        return "npm install"
    }

    static let l0Kinds: Set<DoctorIssueKind> = [
        .missingDependencies, .staleDependencies, .unignoredEnvFile, .missingEnvFile, .notAGitRepo,
    ]

    static func cloudIssue(for project: RepoProject) -> DoctorIssue? {
        guard project.behind > 0 else { return nil }
        return DoctorIssue(projectPath: project.path, kind: .cloudBehind, severity: .warning,
                           finding: .cloudBehind(project.behind), fixAction: nil)
    }

    static func inspectL0(
        _ project: RepoProject, copyMode: CopyMode = .plain, exemptions: Set<DoctorIssueKind> = []
    ) async -> DoctorProjectReport {
        let directory = URL(fileURLWithPath: project.path)
        var issues: [DoctorIssue] = []

        let l0Issues = LightweightProjectCheckService.staticIssues(in: directory, copyMode: copyMode)
        for item in l0Issues {
            switch item.kind {
            case .missingDependencies:
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .missingDependencies,
                    severity: .critical,
                    finding: .lightweight(item),
                    fixAction: .installDependencies(command: detectInstallCommand(in: directory))
                ))
            case .staleDependencies:
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .staleDependencies,
                    severity: .warning,
                    finding: .lightweight(item),
                    fixAction: .installDependencies(command: detectInstallCommand(in: directory))
                ))
            case .unignoredEnvFile:
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .unignoredEnvFile,
                    severity: .critical,
                    finding: .lightweight(item),
                    fixAction: .addEnvToGitignore
                ))
            }
        }

        let hasExample = FileTools.exists(directory.appendingPathComponent(".env.example"))
        let hasEnv = FileTools.exists(directory.appendingPathComponent(".env"))
            || FileTools.exists(directory.appendingPathComponent(".env.local"))
        if hasExample && !hasEnv {
            issues.append(DoctorIssue(
                projectPath: project.path,
                kind: .missingEnvFile,
                severity: .warning,
                finding: .missingEnvironment(copyMode),
                fixAction: .createEnvFromExample
            ))
        }

        if !GitService.hasGit(directory) {
            issues.append(DoctorIssue(
                projectPath: project.path, kind: .notAGitRepo, severity: .warning,
                finding: .unprotected(copyMode),
                fixAction: .initGitRepository
            ))
        }
        return report(for: project.path, issues: issues).applying(exemptions)
    }

    static func inspectProject(
        _ project: RepoProject,
        scope: DoctorCheckScope,
        copyMode: CopyMode = .plain,
        runtimeEnvironment: RuntimeVersionEnvironment? = nil,
        exemptions: Set<DoctorIssueKind> = []
    ) async -> DoctorProjectReport {
        let directory = URL(fileURLWithPath: project.path)
        let l0 = await inspectL0(project, copyMode: copyMode, exemptions: exemptions)
        var issues = l0.issues.filter { scope == .focused || [.unignoredEnvFile, .notAGitRepo].contains($0.kind) }
        if scope == .focused && !exemptions.contains(.runtimeVersionMismatch) {
            let runtimeMismatches = await RuntimeVersionChecker.inspectProject(
                in: directory,
                environment: runtimeEnvironment
            )
            for mismatch in runtimeMismatches {
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .runtimeVersionMismatch,
                    severity: .warning,
                    finding: .runtime(mismatch),
                    fixAction: .copyShellCommand(command: mismatch.fixCommand),
                    identity: mismatch.id
                ))
            }
        }

        if GitService.hasGit(directory) {
            let secretFiles = await findTrackedSecretFiles(in: directory)
            if !secretFiles.isEmpty {
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .trackedSecrets,
                    severity: .critical,
                    finding: .secrets(files: Array(secretFiles.prefix(3)), total: secretFiles.count, copyMode),
                    fixAction: .inspectTrackedSecrets(files: Array(secretFiles.prefix(10)))
                ))
            }
        }

        if scope == .focused, let port = project.run?.port, project.port != .running,
           let issue = await portIssue(port, projectPath: project.path, copyMode: copyMode) {
            issues.append(issue)
        }
        return report(for: project.path, issues: issues).applying(exemptions)
    }

    private static func portIssue(_ port: Int, projectPath: String, copyMode: CopyMode) async -> DoctorIssue? {
        let conflict: PortConflict
        let failure: DoctorListenerFailure?
        do {
            guard let listener = try await PortConflictService.snapshot(ports: [port]).first else { return nil }
            conflict = listener
            failure = nil
        } catch {
            conflict = PortConflict(port: port, occupants: [], note: nil)
            failure = DoctorListenerFailure(error)
        }
        return DoctorIssue(projectPath: projectPath, kind: .portConflict, severity: .critical,
                           finding: .port(conflict, copyMode, failure), fixAction: .resolvePortConflict(conflict))
    }

    static func report(for path: String, issues: [DoctorIssue]) -> DoctorProjectReport {
        let sorted = issues.sorted {
            if $0.severity != $1.severity {
                return $0.severity < $1.severity
            }
            if $0.kind != $1.kind {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.id < $1.id
        }

        return DoctorProjectReport(
            projectPath: path,
            checkedAt: Date(),
            issues: sorted
        )
    }

    static func inspectMachineEnvironment() async -> MachineEnvironmentReport {
        async let gitVersionTask = Shell.output("git", ["--version"], timeout: 3)
        async let gitNameTask = Shell.output("git", ["config", "--global", "user.name"], timeout: 3)
        async let gitEmailTask = Shell.output("git", ["config", "--global", "user.email"], timeout: 3)
        async let runtimeTask = RuntimeVersionChecker.detectEnvironment(for: [.node, .python])
        async let claudePathTask = AgentCLISummaryProvider.defaultLocateExecutable("claude")
        async let codexPathTask = AgentCLISummaryProvider.defaultLocateExecutable("codex")
        async let geminiPathTask = AgentCLISummaryProvider.defaultLocateExecutable("gemini")

        let (gitVer, gitName, gitEmail, runtimes, claudePath, codexPath, geminiPath) = await (
            gitVersionTask,
            gitNameTask,
            gitEmailTask,
            runtimeTask,
            claudePathTask,
            codexPathTask,
            geminiPathTask
        )

        let cleanName = gitName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = gitEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNode = runtimes.node
        let cleanPython = runtimes.python

        let cliTools = [
            MachineToolStatus(
                id: "claude",
                title: "Claude Code",
                path: claudePath
            ),
            MachineToolStatus(
                id: "codex",
                title: "Codex CLI",
                path: codexPath
            ),
            MachineToolStatus(
                id: "gemini",
                title: "Gemini CLI",
                path: geminiPath
            ),
        ]

        return MachineEnvironmentReport(
            checkedAt: Date(),
            gitInstalled: !(gitVer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            gitUserName: (cleanName?.isEmpty ?? true) ? nil : cleanName,
            gitUserEmail: (cleanEmail?.isEmpty ?? true) ? nil : cleanEmail,
            nodeVersion: (cleanNode?.isEmpty ?? true) ? nil : cleanNode,
            pythonVersion: (cleanPython?.isEmpty ?? true)
                ? nil
                : RuntimeVersionChecker.installedVersion(from: cleanPython ?? ""),
            cliTools: cliTools,
            disk: probeDisk()
        )
    }

    static func probeDisk() -> MachineDiskStatus? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]),
        let free = values.volumeAvailableCapacityForImportantUsage,
        let total = values.volumeTotalCapacity else {
            return nil
        }
        return MachineDiskStatus(free: free, total: Int64(total))
    }

    static func findTrackedSecretFiles(in directory: URL) async -> [String] {
        guard let git = DoctorCommand.git else { return [] }
        let args = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "submodule.recurse=false"]
        // Keep checking tracked working files before a save; an ignored but already tracked .env is still a risk.
        let matches = await DoctorCommand.run(git, args + ["grep", "--no-textconv", "--threads=1", "-z", "-l", "-I", "-E", "-e", secretPattern, "--", "."],
                                              cwd: directory, timeout: 3, outputLimit: 128 * 1024, acceptedStatuses: [0, 1])
        let tracked = await DoctorCommand.run(git, args + ["ls-files", "--cached", "-z", "--", ".env", ":(top,glob).env.*"], cwd: directory)
        let env = (tracked ?? "").split(separator: "\0").map(String.init).filter(DoctorInputs.isPrivateEnv)
        return Set((matches ?? "").split(separator: "\0").map(String.init)).union(env).sorted()
    }

    static func createEnvFromExample(in directory: URL) -> URL? {
        let example = directory.appendingPathComponent(".env.example")
        let destination = directory.appendingPathComponent(".env")
        guard FileTools.exists(example), !FileTools.exists(destination) else {
            return nil
        }
        do {
            try FileTools.manager.copyItem(at: example, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    static func initGitRepository(in directory: URL, marksFile: URL = AppPaths.marksFile, tmpDir: URL = AppPaths.tmpDir) async -> (succeeded: Bool, message: String) {
        await VersionProtectionService.enable(in: directory, marksFile: marksFile, tmpDir: tmpDir)
    }

    static func configureGitIdentity(name: String, email: String) async -> (succeeded: Bool, message: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanEmail.isEmpty else {
            return (false, FizzL10n.text("请填写名字和邮箱", "Enter your name and email."))
        }

        let nameResult = await Shell.run("git", ["config", "--global", "user.name", cleanName], timeout: 5)
        let emailResult = await Shell.run("git", ["config", "--global", "user.email", cleanEmail], timeout: 5)
        guard nameResult?.succeeded == true && emailResult?.succeeded == true else {
            return (false, FizzL10n.text("写入 Git 全局设置失败", "Couldn’t save global Git settings."))
        }
        return (true, FizzL10n.text("已保存 Git 作者名与邮箱", "Saved Git author name and email"))
    }

    static func trashCleanupItems(
        _ items: [CleanupItem],
        in projectDirectory: URL,
        trashHandler: @Sendable (URL) throws -> Void = { url in
            try FileTools.manager.trashItem(at: url, resultingItemURL: nil)
        }
    ) -> (trashedCount: Int, freedBytes: Int64, error: String?) {
        let rootURL = projectDirectory.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

        var trashedCount = 0
        var freedBytes: Int64 = 0

        for item in items {
            let rawURL = URL(fileURLWithPath: item.path)
            let candidate = rawURL.resolvingSymlinksInPath().standardizedFileURL
            guard candidate.path.hasPrefix(rootPrefix), candidate.path != rootURL.path else {
                return (trashedCount, freedBytes, FizzL10n.text("已阻止越界路径清理：\(item.label)", "Blocked cleanup outside the project: \(item.label)"))
            }
            guard FileTools.exists(candidate) else { continue }
            do {
                try trashHandler(candidate)
                trashedCount += 1
                freedBytes += max(0, item.bytes)
            } catch {
                return (trashedCount, freedBytes, FizzL10n.text("移入废纸篓失败：\(item.label)", "Couldn’t move to Trash: \(item.label)"))
            }
        }

        return (trashedCount, freedBytes, nil)
    }
}
