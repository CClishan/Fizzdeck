import Foundation

struct GitActionResult: Sendable, Equatable {
    let succeeded: Bool
    let message: String
    var didMutate: Bool = false
}

struct GitChange: Identifiable, Sendable, Hashable {
    let path: String
    let originalPath: String?
    let indexStatus: Character
    let worktreeStatus: Character
    let untracked: Bool
    let conflicted: Bool

    var id: String { path }

    var statusCode: String {
        untracked ? "??" : "\(indexStatus)\(worktreeStatus)"
    }

    var displayCode: String {
        let value = statusCode.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? "·" : value
    }

    var hasStagedChanges: Bool {
        !untracked && indexStatus != " " && indexStatus != "?"
    }

    var hasUnstagedChanges: Bool {
        untracked || conflicted || worktreeStatus != " "
    }

    var isDeleted: Bool {
        indexStatus == "D" || worktreeStatus == "D"
    }
}

enum GitDiffLineKind: Sendable, Equatable {
    case header
    case hunk
    case addition
    case deletion
    case context
    case meta
}

struct GitDiffLine: Identifiable, Sendable, Equatable {
    let id: Int
    let kind: GitDiffLineKind
    let text: String
    let oldLine: Int?
    let newLine: Int?
}

struct GitDiffSection: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let lines: [GitDiffLine]
}

struct GitFileDiff: Sendable, Equatable {
    let path: String
    let sections: [GitDiffSection]
    let additions: Int
    let deletions: Int
    let truncated: Bool
    let binary: Bool
    let note: String?

    var isEmpty: Bool { sections.allSatisfy(\.lines.isEmpty) }
}

struct GitParsedDiff: Sendable, Equatable {
    let lines: [GitDiffLine]
    let additions: Int
    let deletions: Int
    let truncated: Bool
}

struct GitRemote: Sendable, Hashable {
    let raw: String

    init?(raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.raw = value
    }

    var webURL: URL? {
        guard let hostAndPath = hostAndPath else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = hostAndPath.host
        components.port = hostAndPath.port
        var path = hostAndPath.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasSuffix(".git") {
            path.removeLast(4)
        }
        guard !path.isEmpty else { return nil }
        components.path = "/" + path
        return components.url
    }

    private var hostAndPath: (host: String, path: String, port: Int?)? {
        if let components = URLComponents(string: raw),
           let scheme = components.scheme?.lowercased() {
            guard scheme != "file" else { return nil }
            guard let host = components.host, !host.isEmpty else { return nil }
            let port = scheme == "http" || scheme == "https" ? components.port : nil
            return (host, components.path, port)
        }

        guard let separator = raw.firstIndex(of: ":") else { return nil }
        let prefix = String(raw[..<separator])
        let path = String(raw[raw.index(after: separator)...])
        guard !prefix.contains("/"), !path.hasPrefix("//") else { return nil }

        let host = prefix.split(separator: "@").last.map(String.init) ?? prefix
        guard host.contains("."), host != "localhost" else { return nil }
        return (host, path, nil)
    }
}

struct GitTrackingCounts: Equatable, Sendable {
    var behind = 0
    var ahead = 0
}

enum GitService {
    private static let fieldSeparator = "\u{1f}"
    private static let recordSeparator = "\u{1e}"
    private static let maxDiffBytes = 256 * 1_024
    private static let maxDiffLines = 1_200
    private static let maxPreviewBytes = 256 * 1_024
    private static let maxPreviewLines = 800

    static func hasGit(_ directory: URL) -> Bool {
        FileTools.exists(directory.appendingPathComponent(".git"))
    }

    static func remote(_ directory: URL) async -> GitRemote? {
        guard hasGit(directory) else { return nil }
        guard let value = await Shell.output(
            "git",
            ["config", "--get", "remote.origin.url"],
            cwd: directory,
            timeout: 10
        ) else { return nil }
        return GitRemote(raw: value)
    }

    static func summary(_ directory: URL) async -> GitSummary? {
        guard hasGit(directory) else { return nil }

        async let branchTask = Shell.output("git", ["rev-parse", "--abbrev-ref", "HEAD"], cwd: directory)
        async let logTask = Shell.output(
            "git",
            ["log", "-1", "--format=%H%n%ad%n%s%n%an", "--date=iso-strict"],
            cwd: directory
        )
        async let statusTask = statusOutput(directory)
        async let trackingTask = Shell.output(
            "git",
            ["rev-list", "--count", "--left-right", "@{upstream}...HEAD"],
            cwd: directory
        )

        let (branch, log, status, tracking) = await (branchTask, logTask, statusTask, trackingTask)
        let lines = statusLines(status)
        let untracked = lines.filter { $0.hasPrefix("??") }.count
        let changes = ChangeStats(tracked: lines.count - untracked, untracked: untracked, total: lines.count)
        let counts = trackingCounts(tracking)

        return GitSummary(
            branch: branch ?? "HEAD",
            lastCommit: parseLastCommit(log),
            changes: changes,
            ahead: counts.ahead,
            behind: counts.behind
        )
    }

    static func weekly(_ directory: URL) async -> [String: Int]? {
        await dailyCommitCounts(directory, days: 7)
    }

    static func dailyCommitCounts(
        _ directory: URL, days: Int, now: Date = Date(), calendar: Calendar = .current
    ) async -> [String: Int]? {
        guard days > 0, hasGit(directory),
              let start = calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: now))
        else { return nil }
        guard let output = await Shell.output(
            "git",
            ["log", "--since=@\(Int(start.timeIntervalSince1970))", "--format=%ct"],
            cwd: directory
        ) else { return nil }

        var counts: [String: Int] = [:]
        for timestamp in output.split(separator: "\n").compactMap({ Int($0) }) {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            if (start...now).contains(date) {
                counts[WorkbenchMetrics.dayKey(date, calendar: calendar), default: 0] += 1
            }
        }
        return counts
    }

    static func detail(_ directory: URL) async -> (GitDetail?, [Commit]) {
        guard hasGit(directory) else { return (nil, []) }

        async let branchesTask = Shell.output(
            "git",
            ["branch", "--format=%(refname:short)|%(committerdate:iso-strict)|%(upstream:short)", "--sort=-committerdate"],
            cwd: directory
        )
        async let statusTask = statusOutput(directory)
        async let remoteTask = Shell.output("git", ["remote", "get-url", "origin"], cwd: directory)
        async let aheadTask = Shell.output("git", ["rev-list", "--count", "--left-right", "@{u}...HEAD"], cwd: directory)
        async let stashTask = Shell.output("git", ["stash", "list"], cwd: directory)
        async let tagTask = Shell.output("git", ["describe", "--tags", "--abbrev=0"], cwd: directory)
        async let commitsTask = recentCommits(directory, limit: 12)

        let (branches, status, remote, ahead, stash, tag, commits) =
            await (branchesTask, statusTask, remoteTask, aheadTask, stashTask, tagTask, commitsTask)

        let branchList = parseBranches(branches)
        let files = parseChangedFiles(status)
        let counts = trackingCounts(ahead)

        let summary = GitDetail(
            branches: Array(branchList.prefix(40)),
            files: Array(files.prefix(200)),
            remote: remote,
            ahead: counts.ahead,
            behind: counts.behind,
            stashCount: stash?.split(separator: "\n").filter { !$0.isEmpty }.count ?? 0,
            lastTag: tag,
            changedCount: files.count
        )
        return (summary, commits)
    }

    static func changes(_ directory: URL) async -> [GitChange] {
        guard hasGit(directory) else { return [] }
        guard let result = await Shell.run(
            "git",
            ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
            cwd: directory,
            timeout: 30
        ), result.succeeded else {
            return []
        }
        return parseChanges(result.text)
    }

    static func parseChanges(_ output: String) -> [GitChange] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var changes: [GitChange] = []
        var index = 0

        while index < fields.count {
            let record = fields[index]
            index += 1
            let characters = Array(record)
            guard characters.count >= 4 else { continue }

            let indexStatus = characters[0]
            let worktreeStatus = characters[1]
            let path = String(characters.dropFirst(3))
            var originalPath: String?
            if ["R", "C"].contains(indexStatus) || ["R", "C"].contains(worktreeStatus) {
                if index < fields.count {
                    originalPath = fields[index]
                    index += 1
                }
            }

            let untracked = indexStatus == "?" && worktreeStatus == "?"
            let conflicted = indexStatus == "U"
                || worktreeStatus == "U"
                || (indexStatus == "A" && worktreeStatus == "A")
                || (indexStatus == "D" && worktreeStatus == "D")

            changes.append(
                GitChange(
                    path: path,
                    originalPath: originalPath,
                    indexStatus: indexStatus,
                    worktreeStatus: worktreeStatus,
                    untracked: untracked,
                    conflicted: conflicted
                )
            )
        }
        return changes
    }

    static func stage(_ paths: [String], in directory: URL) async -> GitActionResult {
        guard !paths.isEmpty else {
            return GitActionResult(succeeded: false, message: "没有可暂存的文件")
        }
        return await runWrite(
            ["add", "--"] + paths,
            in: directory,
            successMessage: paths.count == 1 ? "已暂存 1 个文件" : "已暂存 \(paths.count) 个文件"
        )
    }

    static func stageAll(in directory: URL) async -> GitActionResult {
        await runWrite(["add", "-A", "--", "."], in: directory, successMessage: "已暂存全部改动")
    }

    static func unstage(_ paths: [String], in directory: URL) async -> GitActionResult {
        guard !paths.isEmpty else {
            return GitActionResult(succeeded: false, message: "没有可取消暂存的文件")
        }
        if await hasHead(in: directory) {
            return await runWrite(
                ["restore", "--staged", "--"] + paths,
                in: directory,
                successMessage: paths.count == 1 ? "已取消暂存 1 个文件" : "已取消暂存 \(paths.count) 个文件"
            )
        }
        return await runWrite(
            ["rm", "--cached", "-r", "--"] + paths,
            in: directory,
            successMessage: "已从初始索引移除暂存"
        )
    }

    static func unstageAll(in directory: URL) async -> GitActionResult {
        if await hasHead(in: directory) {
            return await runWrite(
                ["restore", "--staged", "--", "."],
                in: directory,
                successMessage: "已取消全部暂存"
            )
        }
        return await runWrite(
            ["rm", "--cached", "-r", "--", "."],
            in: directory,
            successMessage: "已清空初始索引"
        )
    }

    static func commit(_ message: String, in directory: URL) async -> GitActionResult {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return GitActionResult(succeeded: false, message: "先填写一行提交信息")
        }
        guard !value.contains(where: \.isNewline) else {
            return GitActionResult(succeeded: false, message: "提交信息只能是一行")
        }
        guard let result = await Shell.run(
            "git",
            ["commit", "-m", value],
            cwd: directory,
            timeout: 120,
            extraEnvironment: ["GIT_TERMINAL_PROMPT": "0"]
        ) else {
            return GitActionResult(succeeded: false, message: "提交失败：无法启动 git")
        }
        guard result.succeeded else {
            return GitActionResult(succeeded: false, message: failureMessage("提交", result))
        }
        return GitActionResult(succeeded: true, message: "已提交：\(value)", didMutate: true)
    }

    static func commitAndPush(_ message: String, in directory: URL) async -> GitActionResult {
        let commitResult = await commit(message, in: directory)
        guard commitResult.succeeded else { return commitResult }

        let pushResult = await GitSyncService.run(.push, in: directory)
        guard pushResult.succeeded else {
            return GitActionResult(
                succeeded: false,
                message: "已提交，但推送失败：\(pushResult.message)",
                didMutate: true
            )
        }
        return GitActionResult(
            succeeded: true,
            message: "已提交并推送：\(message)",
            didMutate: true
        )
    }

    static func stashPush(in directory: URL) async -> GitActionResult {
        let stamp = ISO8601DateFormatter().string(from: Date())
        return await runWrite(
            ["stash", "push", "--include-untracked", "-m", "FizzDeck \(stamp)"],
            in: directory,
            successMessage: "已暂存当前改动"
        )
    }

    static func stashPop(in directory: URL) async -> GitActionResult {
        await runWrite(
            ["stash", "pop"],
            in: directory,
            successMessage: "已恢复最近一次 Stash",
            timeout: 60
        )
    }

    static func switchBranch(_ name: String, in directory: URL) async -> GitActionResult {
        let branch = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            return GitActionResult(succeeded: false, message: "分支名为空")
        }
        guard !branch.hasPrefix("-") else {
            return GitActionResult(succeeded: false, message: "非法分支名")
        }
        guard let validation = await Shell.run(
            "git",
            ["check-ref-format", "--branch", branch],
            cwd: directory,
            timeout: 10
        ), validation.succeeded else {
            return GitActionResult(succeeded: false, message: "非法分支名：\(branch)")
        }
        return await runWrite(
            ["switch", branch],
            in: directory,
            successMessage: "已切换到 \(branch)"
        )
    }

    static func fileDiff(for change: GitChange, in directory: URL) async -> GitFileDiff {
        if change.untracked {
            return untrackedPreview(for: change, in: directory)
        }

        var sections: [GitDiffSection] = []
        var additions = 0
        var deletions = 0
        var truncated = false
        var binary = false

        if change.hasStagedChanges {
            let output = await cappedDiff(
                arguments: ["diff", "--cached", "--no-color", "--no-ext-diff", "--unified=3", "--", change.path],
                in: directory
            )
            if let output {
                let parsed = parseUnifiedDiff(output.text, maxLines: maxDiffLines)
                if !parsed.lines.isEmpty {
                    sections.append(
                        GitDiffSection(id: "staged", title: "已暂存", lines: parsed.lines)
                    )
                }
                additions += parsed.additions
                deletions += parsed.deletions
                truncated = truncated || parsed.truncated || output.truncated
                binary = binary || output.text.contains("Binary files")
                    || output.text.contains("GIT binary patch")
            }
        }

        if change.hasUnstagedChanges {
            let output = await cappedDiff(
                arguments: ["diff", "--no-color", "--no-ext-diff", "--unified=3", "--", change.path],
                in: directory
            )
            if let output {
                let parsed = parseUnifiedDiff(output.text, maxLines: maxDiffLines)
                if !parsed.lines.isEmpty {
                    sections.append(
                        GitDiffSection(id: "working", title: "工作区", lines: parsed.lines)
                    )
                }
                additions += parsed.additions
                deletions += parsed.deletions
                truncated = truncated || parsed.truncated || output.truncated
                binary = binary || output.text.contains("Binary files")
                    || output.text.contains("GIT binary patch")
            }
        }

        return GitFileDiff(
            path: change.path,
            sections: sections,
            additions: additions,
            deletions: deletions,
            truncated: truncated,
            binary: binary,
            note: binary ? "二进制文件仅显示状态，不展开内容。" : nil
        )
    }

    static func parseUnifiedDiff(_ text: String, maxLines: Int = 1_200) -> GitParsedDiff {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [GitDiffLine] = []
        var oldLine: Int?
        var newLine: Int?
        var additions = 0
        var deletions = 0
        var truncated = false

        for (position, rawLine) in rawLines.enumerated() {
            if result.count >= maxLines {
                truncated = true
                break
            }
            let line = String(rawLine)
            let kind: GitDiffLineKind
            var currentOld = oldLine
            var currentNew = newLine

            if line.hasPrefix("@@") {
                kind = .hunk
                if let parsed = hunkStart(line) {
                    oldLine = parsed.old
                    newLine = parsed.new
                    currentOld = oldLine
                    currentNew = newLine
                }
            } else if line.hasPrefix("+++") || line.hasPrefix("---") {
                kind = .header
            } else if line.hasPrefix("+") {
                kind = .addition
                additions += 1
                currentNew = newLine
                if newLine != nil { newLine = newLine! + 1 }
            } else if line.hasPrefix("-") {
                kind = .deletion
                deletions += 1
                currentOld = oldLine
                if oldLine != nil { oldLine = oldLine! + 1 }
            } else if line.hasPrefix("\\") {
                kind = .meta
            } else if line.hasPrefix("diff --git")
                || line.hasPrefix("index ")
                || line.hasPrefix("new file mode")
                || line.hasPrefix("deleted file mode")
                || line.hasPrefix("similarity index")
                || line.hasPrefix("rename from")
                || line.hasPrefix("rename to")
                || line.hasPrefix("old mode")
                || line.hasPrefix("new mode") {
                kind = .header
            } else if line == "" && position == rawLines.count - 1 {
                continue
            } else if oldLine != nil || newLine != nil {
                kind = .context
                currentOld = oldLine
                currentNew = newLine
                if oldLine != nil { oldLine = oldLine! + 1 }
                if newLine != nil { newLine = newLine! + 1 }
            } else {
                kind = .header
            }

            result.append(
                GitDiffLine(
                    id: position,
                    kind: kind,
                    text: line,
                    oldLine: currentOld,
                    newLine: currentNew
                )
            )
        }

        return GitParsedDiff(
            lines: result,
            additions: additions,
            deletions: deletions,
            truncated: truncated
        )
    }

    private static func untrackedPreview(for change: GitChange, in directory: URL) -> GitFileDiff {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root
            .appendingPathComponent(change.path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return GitFileDiff(
                path: change.path,
                sections: [],
                additions: 0,
                deletions: 0,
                truncated: false,
                binary: false,
                note: "未跟踪文件指向仓库外，已拒绝预览。"
            )
        }

        guard let handle = try? FileHandle(forReadingFrom: candidate) else {
            return GitFileDiff(
                path: change.path,
                sections: [],
                additions: 0,
                deletions: 0,
                truncated: false,
                binary: false,
                note: "无法读取未跟踪文件。"
            )
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: maxPreviewBytes + 1)) ?? Data()
        let totalSize = FileTools.fileSize(candidate)
        let truncated = data.count > maxPreviewBytes || totalSize > Int64(maxPreviewBytes)
        let prefix = data.prefix(maxPreviewBytes)

        guard !prefix.contains(0), let text = decodeUTF8Prefix(prefix) else {
            return GitFileDiff(
                path: change.path,
                sections: [],
                additions: 0,
                deletions: 0,
                truncated: truncated,
                binary: true,
                note: "二进制文件仅显示状态，不展开内容。"
            )
        }

        var allLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if text.hasSuffix("\n"), allLines.last?.isEmpty == true {
            allLines.removeLast()
        }
        let limited = Array(allLines.prefix(maxPreviewLines))
        let lines = limited.enumerated().map { offset, value in
            GitDiffLine(
                id: offset,
                kind: .addition,
                text: "+" + value,
                oldLine: nil,
                newLine: offset + 1
            )
        }
        return GitFileDiff(
            path: change.path,
            sections: [
                GitDiffSection(id: "untracked", title: "未跟踪文件", lines: lines),
            ],
            additions: limited.count,
            deletions: 0,
            truncated: truncated || allLines.count > maxPreviewLines,
            binary: false,
            note: nil
        )
    }

    private static func decodeUTF8Prefix(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        for count in 1...min(3, data.count) {
            let candidate = Data(data.dropLast(count))
            if let text = String(data: candidate, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    private static func cappedDiff(
        arguments: [String],
        in directory: URL
    ) async -> (text: String, truncated: Bool)? {
        let command = (["git", "--no-pager"] + arguments)
            .map(shellQuote)
            .joined(separator: " ")
        let script = "\(command) 2>&1 | head -c \(maxDiffBytes)"
        guard let result = await Shell.run(
            "/bin/zsh",
            ["-lc", script],
            cwd: directory,
            timeout: 15
        ) else { return nil }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (text, result.text.utf8.count >= maxDiffBytes)
    }

    private static func hunkStart(_ line: String) -> (old: Int, new: Int)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        ) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line),
              let old = Int(line[oldRange]),
              let new = Int(line[newRange])
        else { return nil }
        return (old, new)
    }

    private static func hasHead(in directory: URL) async -> Bool {
        guard let result = await Shell.run(
            "git",
            ["rev-parse", "--verify", "HEAD"],
            cwd: directory,
            timeout: 10
        ) else { return false }
        return result.succeeded
    }

    private static func runWrite(
        _ arguments: [String],
        in directory: URL,
        successMessage: String,
        timeout: TimeInterval = 30
    ) async -> GitActionResult {
        guard let result = await Shell.run(
            "git",
            arguments,
            cwd: directory,
            timeout: timeout,
            extraEnvironment: ["GIT_TERMINAL_PROMPT": "0"]
        ) else {
            return GitActionResult(succeeded: false, message: "无法启动 git")
        }
        guard result.succeeded else {
            return GitActionResult(succeeded: false, message: failureMessage("操作", result))
        }
        return GitActionResult(succeeded: true, message: successMessage, didMutate: true)
    }

    private static func failureMessage(_ action: String, _ result: ShellOutput) -> String {
        if result.timedOut {
            return "\(action)超时，检查网络、代理或 Git 凭据"
        }
        let lowercased = result.text.lowercased()
        if lowercased.contains("nothing to commit") {
            return "\(action)失败：没有可提交的暂存改动"
        }
        if lowercased.contains("no local changes") {
            return "\(action)失败：当前没有可暂存的改动"
        }
        if lowercased.contains("conflict") {
            return "\(action)失败：存在冲突，先在终端处理冲突文件"
        }
        if lowercased.contains("not a git repository") {
            return "\(action)失败：当前目录不是 Git 仓库"
        }
        let lines = result.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("hint:") }
        let detail = lines.first(where: { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") })
            ?? lines.last
            ?? "退出状态 \(result.status)"
        let cleaned = detail
            .replacingOccurrences(of: "fatal: ", with: "")
            .replacingOccurrences(of: "error: ", with: "")
        return "\(action)失败：\(String(cleaned.prefix(160)))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func recentCommits(_ directory: URL, limit: Int) async -> [Commit] {
        guard let output = await Shell.output(
            "git",
            [
                "log",
                "-\(limit)",
                "--format=%H\(fieldSeparator)%h\(fieldSeparator)%ad\(fieldSeparator)%an\(fieldSeparator)%s\(fieldSeparator)%D\(recordSeparator)",
                "--date=iso-strict",
            ],
            cwd: directory
        ) else { return [] }

        return output
            .split(separator: Character(recordSeparator))
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { record in
                let fields = record.split(
                    separator: Character(fieldSeparator),
                    maxSplits: 5,
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard fields.count >= 5 else { return nil }
                return Commit(
                    hash: fields[1],
                    date: Format.isoDate(fields[2]),
                    subject: fields[4],
                    author: fields[3]
                )
            }
    }

    private static func statusOutput(_ directory: URL) async -> String? {
        guard let result = await Shell.run(
            "git",
            ["status", "--porcelain=v1", "-uall"],
            cwd: directory,
            timeout: 30
        ), result.succeeded else {
            return nil
        }
        return result.text.trimmingCharacters(in: .newlines)
    }

    private static func parseLastCommit(_ output: String?) -> Commit? {
        guard let output else { return nil }
        let fields = output.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count >= 4 else { return nil }
        return Commit(
            hash: String(fields[0]).prefix(7).description,
            date: Format.isoDate(String(fields[1])),
            subject: String(fields[2]),
            author: String(fields[3])
        )
    }

    static func trackingCounts(_ output: String?) -> GitTrackingCounts {
        guard let output else { return GitTrackingCounts() }
        let parts = output.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard parts.count == 2 else { return GitTrackingCounts() }
        return GitTrackingCounts(behind: parts[0], ahead: parts[1])
    }

    private static func parseBranches(_ output: String?) -> [BranchInfo] {
        guard let output else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return BranchInfo(
                name: name,
                date: parts.count > 1 ? parts[1] : "",
                upstream: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
            )
        }
    }

    private static func parseChangedFiles(_ output: String?) -> [GitFileChange] {
        guard let output else { return [] }
        return output.split(separator: "\n").compactMap { line in
            guard line.count > 3 else { return nil }
            let code = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let path = String(line.dropFirst(3))
            return GitFileChange(code: code, path: path, untracked: line.hasPrefix("??"))
        }
    }

    private static func statusLines(_ output: String?) -> [String] {
        output?.split(separator: "\n").map(String.init).filter { !$0.isEmpty } ?? []
    }
}
