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
        case .staleDependencies: "依赖过期"
        case .missingEnvFile: "缺少环境配置"
        case .runtimeVersionMismatch: "运行时版本不匹配"
        case .notAGitRepo: "未开启版本保护"
        case .cloudBehind: "云端领先"
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
    let title: String
    let detail: String
    let fixAction: DoctorFixAction?

    init(
        projectPath: String,
        kind: DoctorIssueKind,
        severity: DoctorSeverity,
        title: String,
        detail: String,
        fixAction: DoctorFixAction?,
        identity: String? = nil
    ) {
        let baseID = "\(projectPath)::\(kind.rawValue)"
        if let identity, !identity.isEmpty {
            self.id = "\(baseID)::\(identity)"
        } else {
            self.id = baseID
        }
        self.projectPath = projectPath
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fixAction = fixAction
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
    let available: Bool
    let detail: String
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
                           title: "云端领先 \(project.behind) 个提交", detail: "可在版本页查看并决定是否拉取", fixAction: nil)
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
                    title: item.title,
                    detail: item.detail,
                    fixAction: .installDependencies(command: detectInstallCommand(in: directory))
                ))
            case .staleDependencies:
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .staleDependencies,
                    severity: .warning,
                    title: item.title,
                    detail: item.detail,
                    fixAction: .installDependencies(command: detectInstallCommand(in: directory))
                ))
            case .unignoredEnvFile:
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .unignoredEnvFile,
                    severity: .critical,
                    title: item.title,
                    detail: item.detail,
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
                title: copyMode == .plain ? "缺少项目配置文件 .env（已有模板）" : "缺少环境变量文件 .env",
                detail: "根目录已有 .env.example 模板，可复制成 .env 后填入所需配置",
                fixAction: .createEnvFromExample
            ))
        }

        if !GitService.hasGit(directory) {
            issues.append(DoctorIssue(
                projectPath: project.path, kind: .notAGitRepo, severity: .warning,
                title: copyMode == .plain ? "还没有开启版本保护" : "未初始化 Git 仓库",
                detail: "开启后，每次 AI 对话前都能自动记下状态，随时可还原", fixAction: .initGitRepository
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
                    title: mismatch.title,
                    detail: mismatch.detail,
                    fixAction: .copyShellCommand(command: mismatch.fixCommand),
                    identity: mismatch.id
                ))
            }
        }

        if GitService.hasGit(directory) {
            let secretFiles = await findTrackedSecretFiles(in: directory)
            if !secretFiles.isEmpty {
                let sample = secretFiles.prefix(3).joined(separator: "、")
                let more = secretFiles.count > 3 ? " 等 \(secretFiles.count) 个文件" : ""
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .trackedSecrets,
                    severity: .critical,
                    title: copyMode == .plain ? "已保存的代码里疑似包含密钥" : "跟踪文件命中疑似密钥",
                    detail: "命中文件：\(sample)\(more)，建议移入 .env 后再上传到云端",
                    fixAction: .inspectTrackedSecrets(files: Array(secretFiles.prefix(10)))
                ))
            }
        }

        if scope == .focused,
           let port = project.run?.port,
           project.port != .running,
           let conflict = await PortConflictService.inspect(port: port) {
            issues.append(DoctorIssue(
                projectPath: project.path,
                kind: .portConflict,
                severity: .critical,
                title: copyMode == .plain ? "端口 \(port) 被其他程序占着" : "端口 \(port) 已被占用",
                detail: conflict.occupantSummary,
                fixAction: .resolvePortConflict(conflict)
            ))
        }

        return report(for: project.path, issues: issues).applying(exemptions)
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
                available: claudePath != nil,
                detail: claudePath ?? "未安装"
            ),
            MachineToolStatus(
                id: "codex",
                title: "Codex CLI",
                available: codexPath != nil,
                detail: codexPath ?? "未安装"
            ),
            MachineToolStatus(
                id: "gemini",
                title: "Gemini CLI",
                available: geminiPath != nil,
                detail: geminiPath ?? "未安装"
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
            return (false, "请填写名字和邮箱")
        }

        let nameResult = await Shell.run("git", ["config", "--global", "user.name", cleanName], timeout: 5)
        let emailResult = await Shell.run("git", ["config", "--global", "user.email", cleanEmail], timeout: 5)
        guard nameResult?.succeeded == true && emailResult?.succeeded == true else {
            return (false, "写入 Git 全局设置失败")
        }
        return (true, "已保存 Git 作者名与邮箱")
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
                return (trashedCount, freedBytes, "已阻止越界路径清理：\(item.label)")
            }
            guard FileTools.exists(candidate) else { continue }
            do {
                try trashHandler(candidate)
                trashedCount += 1
                freedBytes += max(0, item.bytes)
            } catch {
                return (trashedCount, freedBytes, "移入废纸篓失败：\(item.label)")
            }
        }

        return (trashedCount, freedBytes, nil)
    }
}
