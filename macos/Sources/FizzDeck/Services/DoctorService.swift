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
    case notAGitRepo
}

enum DoctorFixAction: Equatable, Sendable {
    case installDependencies(command: String)
    case createEnvFromExample
    case addEnvToGitignore
    case resolvePortConflict(PortConflict)
    case initGitRepository
    case inspectTrackedSecrets(files: [String])
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
        fixAction: DoctorFixAction?
    ) {
        self.id = "\(projectPath)::\(kind.rawValue)"
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

    static func inspectProject(
        _ project: RepoProject,
        scope: DoctorCheckScope,
        copyMode: CopyMode = .plain
    ) async -> DoctorProjectReport {
        let directory = URL(fileURLWithPath: project.path)
        var issues: [DoctorIssue] = []

        let l0Issues = await LightweightProjectCheckService.check(directory: directory, copyMode: copyMode)
        for item in l0Issues {
            switch item.kind {
            case .missingDependencies:
                guard scope == .focused else { continue }
                issues.append(DoctorIssue(
                    projectPath: project.path,
                    kind: .missingDependencies,
                    severity: .critical,
                    title: item.title,
                    detail: item.detail,
                    fixAction: .installDependencies(command: detectInstallCommand(in: directory))
                ))
            case .staleDependencies:
                guard scope == .focused else { continue }
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

        if scope == .focused {
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
        }

        if !GitService.hasGit(directory) {
            issues.append(DoctorIssue(
                projectPath: project.path,
                kind: .notAGitRepo,
                severity: .warning,
                title: copyMode == .plain ? "还没有开启版本保护" : "未初始化 Git 仓库",
                detail: "开启后，每次 AI 对话前都能自动记下状态，随时可还原",
                fixAction: .initGitRepository
            ))
        } else {
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

        issues.sort {
            if $0.severity != $1.severity {
                return $0.severity < $1.severity
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }

        return DoctorProjectReport(
            projectPath: project.path,
            checkedAt: Date(),
            issues: issues
        )
    }

    static func inspectMachineEnvironment() async -> MachineEnvironmentReport {
        async let gitVersionTask = Shell.output("git", ["--version"], timeout: 3)
        async let gitNameTask = Shell.output("git", ["config", "--global", "user.name"], timeout: 3)
        async let gitEmailTask = Shell.output("git", ["config", "--global", "user.email"], timeout: 3)
        async let nodeTask = Shell.output("node", ["-v"], timeout: 3)
        async let claudePathTask = AgentCLISummaryProvider.defaultLocateExecutable("claude")
        async let codexPathTask = AgentCLISummaryProvider.defaultLocateExecutable("codex")
        async let geminiPathTask = AgentCLISummaryProvider.defaultLocateExecutable("gemini")

        let (gitVer, gitName, gitEmail, nodeVer, claudePath, codexPath, geminiPath) = await (
            gitVersionTask,
            gitNameTask,
            gitEmailTask,
            nodeTask,
            claudePathTask,
            codexPathTask,
            geminiPathTask
        )

        let cleanName = gitName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = gitEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNode = nodeVer?.trimmingCharacters(in: .whitespacesAndNewlines)

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
        guard let result = await Shell.run(
            "git",
            ["grep", "-l", "-I", "-E", secretPattern],
            cwd: directory,
            timeout: 6
        ), result.succeeded else {
            return []
        }

        return result.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    static func initGitRepository(in directory: URL) async -> (succeeded: Bool, message: String) {
        guard let result = await Shell.run(
            "git",
            ["init"],
            cwd: directory,
            timeout: 10
        ), result.succeeded else {
            return (false, "初始化版本保护失败，请确认本机已安装 Git")
        }

        let gitignore = directory.appendingPathComponent(".gitignore")
        let existing = FileTools.readFileIfExists(gitignore, maxBytes: 256 * 1024)
        let lines = Set(
            existing
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        let defaults = [".env", ".env.local", ".DS_Store", "node_modules/"]
        let missing = defaults.filter { !lines.contains($0) }
        if !missing.isEmpty {
            var next = existing
            if !next.isEmpty && !next.hasSuffix("\n") {
                next += "\n"
            }
            next += missing.joined(separator: "\n") + "\n"
            try? next.write(to: gitignore, atomically: true, encoding: .utf8)
        }

        return (true, "已开启版本保护并自动生成默认忽略规则")
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
