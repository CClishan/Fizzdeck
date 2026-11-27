import Foundation

enum LightweightIssueKind: String, Codable, Sendable, Hashable {
    case missingDependencies
    case staleDependencies
    case unignoredEnvFile
}

struct LightweightProjectIssue: Identifiable, Equatable, Sendable {
    let kind: LightweightIssueKind
    let title: String
    let detail: String

    var id: String { kind.rawValue }
}

enum LightweightProjectCheckService {
    private static let lockfileNames = [
        "package.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "bun.lock",
        "bun.lockb",
    ]

    private static let envCandidates = [
        ".env",
        ".env.local",
    ]

    static func check(directory: URL, copyMode: CopyMode = .plain) async -> [LightweightProjectIssue] {
        var issues: [LightweightProjectIssue] = []

        if let nodeIssue = checkNodeDependencies(in: directory, copyMode: copyMode) {
            issues.append(nodeIssue)
        }

        if let envIssue = await checkUnignoredEnv(in: directory, copyMode: copyMode) {
            issues.append(envIssue)
        }

        return issues
    }

    // L0 checks repository ignore rules, not the Git index. Authoritative tracked-secret checks remain in L1.
    static func staticIssues(in directory: URL, copyMode: CopyMode) -> [LightweightProjectIssue] {
        var issues = [checkNodeDependencies(in: directory, copyMode: copyMode)].compactMap { $0 }
        guard GitService.hasGit(directory) else { return issues }
        let candidates = DoctorInputs.envNames(in: directory).filter {
            DoctorInputs.isPrivateEnv($0) && FileTools.exists(directory.appendingPathComponent($0))
        }
        guard !candidates.isEmpty else { return issues }
        let rules = [".git/info/exclude", ".gitignore"].flatMap {
            DoctorInputs.text(directory.appendingPathComponent($0), limit: 128 * 1024)
                .split(whereSeparator: \.isNewline).map(String.init)
        }
        if let name = candidates.sorted().first(where: { name in
            var ignored = false
            for line in rules where !line.hasPrefix("#") {
                let negate = line.hasPrefix("!")
                var pattern = negate ? String(line.dropFirst()) : line
                if pattern.hasPrefix("/") { pattern.removeFirst() }
                if fnmatch(pattern, name, FNM_PATHNAME) == 0 { ignored = !negate }
            }
            return !ignored
        }) {
            issues.append(LightweightProjectIssue(kind: .unignoredEnvFile,
                title: "\(name) 没有仓库忽略规则", detail: "建议加入 .gitignore，避免配置随代码上传"))
        }
        return issues
    }

    @discardableResult
    static func addEnvFilesToGitignore(in directory: URL) -> Bool {
        let gitignore = directory.appendingPathComponent(".gitignore")
        let existing = FileTools.readFileIfExists(gitignore, maxBytes: 256 * 1024)
        let existingLines = Set(
            existing
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        let variants = DoctorInputs.envNames(in: directory).filter {
            DoctorInputs.isPrivateEnv($0) && FileTools.exists(directory.appendingPathComponent($0))
        }
        // Ignore literal names only; never turn a crafted filename into another rule.
        let safeVariants = variants.filter { $0.range(of: #"^[.A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }
        let missing = Set(envCandidates).union(safeVariants).sorted().filter { !existingLines.contains($0) }
        guard !missing.isEmpty else { return true }
        var updated = existing
        if !updated.isEmpty && !updated.hasSuffix("\n") {
            updated += "\n"
        }
        updated += missing.joined(separator: "\n") + "\n"
        do {
            try updated.write(to: gitignore, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private static func checkNodeDependencies(
        in directory: URL,
        copyMode: CopyMode
    ) -> LightweightProjectIssue? {
        let packageJSON = directory.appendingPathComponent("package.json")
        guard FileTools.exists(packageJSON) else { return nil }

        let nodeModules = directory.appendingPathComponent("node_modules", isDirectory: true)
        guard FileTools.isDirectory(nodeModules) else {
            return LightweightProjectIssue(
                kind: .missingDependencies,
                title: FizzCopy.missingDependencies(copyMode).text,
                detail: "检测到 package.json，但还没有安装依赖"
            )
        }

        let modulesStampCandidates = [
            nodeModules,
            nodeModules.appendingPathComponent(".package-lock.json"),
        ]
        guard let installedDate = modulesStampCandidates.compactMap(FileTools.modificationDate).max() else {
            return nil
        }

        for name in lockfileNames {
            let fileURL = directory.appendingPathComponent(name)
            guard let modified = FileTools.modificationDate(fileURL) else { continue }
            if modified.timeIntervalSince(installedDate) > 5.0 {
                return LightweightProjectIssue(
                    kind: .staleDependencies,
                    title: copyMode == .plain ? "AI 可能加了新零件，需要重新安装依赖" : "依赖清单已更新，建议重新安装",
                    detail: "\(name) 比 node_modules 更新"
                )
            }
        }

        return nil
    }

    private static func checkUnignoredEnv(
        in directory: URL,
        copyMode: CopyMode
    ) async -> LightweightProjectIssue? {
        guard GitService.hasGit(directory) else { return nil }

        for name in envCandidates {
            let fileURL = directory.appendingPathComponent(name)
            guard FileTools.exists(fileURL) else { continue }

            let result = await Shell.run(
                "git",
                ["check-ignore", "-q", name],
                cwd: directory,
                timeout: 5
            )
            if result?.succeeded != true {
                return LightweightProjectIssue(
                    kind: .unignoredEnvFile,
                    title: copyMode == .plain ? "密钥文件 \(name) 可能会被上传" : "\(name) 未被 .gitignore 忽略",
                    detail: "建议加入 .gitignore，避免 API Key 泄露"
                )
            }
        }

        return nil
    }
}
