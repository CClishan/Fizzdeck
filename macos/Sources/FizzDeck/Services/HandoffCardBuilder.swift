import Foundation

struct HandoffCardResult: Equatable, Sendable {
    let markdown: String
    let characterCount: Int
    let redactedCount: Int
    let includedSessionCount: Int
}

enum HandoffCardScenario: CaseIterable, Hashable, Sendable {
    case resume, fixError, notes

    var title: String {
        switch self {
        case .resume: FizzL10n.text("换工具接着做", "Resume in Another Tool")
        case .fixError: FizzL10n.text("丢给 AI 修报错", "Troubleshoot an Error")
        case .notes: FizzL10n.text("写交接说明", "Handoff Notes")
        }
    }
}

struct HandoffFailure: Sendable {
    enum Source: Equatable, Sendable {
        case session(String), script(String), tests, trial, devServer

        var title: String {
            switch self {
            case .session(let tool): FizzL10n.text("\(tool) 对话", "\(tool) session")
            case .script(let name): FizzL10n.text("受管脚本：\(name)", "Managed script: \(name)")
            case .tests: FizzL10n.text("测试", "Tests")
            case .trial: FizzL10n.text("体检试跑", "Trial run")
            case .devServer: FizzL10n.text("开发服务", "Dev server")
            }
        }
    }

    let source: Source
    let timestamp: Date?
    let output: String
    var exitCode: Int32? = nil
    var files: [String] = []
}

enum HandoffCardBuilder {
    static func build(
        project: RepoProject,
        scenario: HandoffCardScenario = .resume,
        sessionLimit: Int = 3,
        copyMode: CopyMode = .plain,
        localFailure: HandoffFailure? = nil,
        maxCharacters: Int = 1_500,
        now: Date = Date()
    ) -> HandoffCardResult {
        let conversations = project.sessions.recentSessions
            .filter { $0.kind == .conversation }
            .sorted { $0.modified > $1.modified }
        let title = switch scenario {
        case .resume: FizzL10n.text("项目接力", "Project handoff")
        case .fixError: FizzL10n.text("报错求助", "Troubleshooting request")
        case .notes: FizzL10n.text("交接说明", "Handoff notes")
        }
        var lines = [FizzL10n.text("# \(title)：\(project.displayName)", "# \(title): \(project.displayName)"), FizzL10n.text("- 路径：`\(project.path)`", "- Path: `\(project.path)`")]
        let stackItems = flattenedStacks(project.stacks)
        if !stackItems.isEmpty {
            lines.append(FizzL10n.text("- 技术栈：\(stackItems.joined(separator: " / "))", "- Stack: \(stackItems.joined(separator: " / "))"))
        } else if scenario == .fixError {
            lines.append(FizzL10n.text("- 技术栈：未识别。", "- Stack: Unknown."))
        }

        var sessionCount = 0
        var redactedInExcerpt = 0
        switch scenario {
        case .resume:
            // The existing AI polish uses this default card; diagnostic output stays in .fixError.
            let selected = Array(conversations.prefix(max(1, sessionLimit)))
            sessionCount = selected.count
            lines += resumeLines(project: project, sessions: selected, copyMode: copyMode, now: now)
        case .fixError:
            let repair = repairLines(conversations: conversations, localFailure: localFailure, now: now)
            lines += repair.lines
            redactedInExcerpt = repair.redactedCount
        case .notes:
            lines += notesLines(project: project)
        }

        let redacted = SecretRedactor.redact(lines.joined(separator: "\n"))
        let suffix = FizzL10n.text("\n…（已截断）", "\n… (truncated)")
        let markdown = if redacted.text.count <= maxCharacters {
            redacted.text
        } else if maxCharacters > suffix.count {
            String(redacted.text.prefix(maxCharacters - suffix.count)) + suffix
        } else {
            String(redacted.text.prefix(max(0, maxCharacters)))
        }
        return HandoffCardResult(
            markdown: markdown,
            characterCount: markdown.count,
            redactedCount: redacted.redactedCount + redactedInExcerpt,
            includedSessionCount: sessionCount
        )
    }

    private static func resumeLines(
        project: RepoProject, sessions: [SessionRecord], copyMode: CopyMode, now: Date
    ) -> [String] {
        var lines: [String] = []
        if let run = nonEmpty(project.run?.command) {
            lines.append(FizzL10n.text("- 启动命令：`\(run)`", "- Run: `\(run)`"))
        }
        let hasGitStatus = project.gitLoadState == .ready && (project.branch != nil || project.changes.total > 0)
        let status = hasGitStatus
            ? FizzCopy.projectStatusSummary(dirtyCount: project.changes.total, ahead: project.ahead, behind: project.behind, mode: copyMode)
            : FizzL10n.text("未取得可确认的 Git 工作区状态。", "Git working tree status is unavailable.")
        lines.append(FizzL10n.text("- 当前状态：\(status)", "- Current status: \(status)"))

        let latest = sessions.first
        let goal = nonEmpty(latest?.lastUser) ?? latest?.primaryIntent
        lines.append(FizzL10n.text("- 当前目标（最近对话）：\(goal ?? "未记录，请先向交接方确认。")", "- Current goal (latest session): \(goal ?? "Not recorded. Confirm the goal before continuing.")"))
        if let commit = nonEmpty(project.lastCommit?.subject) {
            lines.append(FizzL10n.text("- 最近一次提交：\(commit)", "- Latest commit: \(commit)"))
        }

        let files = recentFiles(in: sessions)
        lines.append(FizzL10n.text("- 最近对话记录的改动：\(files.isEmpty ? "未记录改动文件。" : files.joined(separator: ", "))", "- Files changed in recent sessions: \(files.isEmpty ? "None recorded." : files.joined(separator: ", "))"))
        let nextStep: String
        if goal == nil {
            nextStep = FizzL10n.text("先确认要接着做的目标，再核对已有改动。", "Confirm the goal, then review the existing changes.")
        } else if latest?.endedWithError == true {
            nextStep = FizzL10n.text("先复查最近对话报告的失败，再继续当前目标。", "Review the failure from the last session before resuming the task.")
        } else if let test = nonEmpty(project.test?.command) {
            nextStep = FizzL10n.text("核对已有改动，继续当前目标，再用 `\(test)` 验证。", "Review the changes, continue the task, and verify with `\(test)`.")
        } else {
            nextStep = FizzL10n.text("先核对已有改动，再继续当前目标。", "Review the existing changes, then continue the task.")
        }
        lines.append(FizzL10n.text("- 建议下一步：\(nextStep)", "- Suggested next step: \(nextStep)"))

        if !sessions.isEmpty {
            lines.append("")
            lines.append(FizzL10n.text("## 最近对话", "## Recent sessions"))
            for session in sessions {
                let toolTitle = HomeDashboardModel.toolTitle(session.tool)
                let when = relativeTimeLabel(session.modified, relativeTo: now)
                let intent = session.primaryIntent ?? FizzL10n.text("未记录目标", "No goal recorded")
                let status = session.endedWithError ? FizzL10n.text(" · 报错结束", " · ended with an error") : ""
                lines.append("- [\(toolTitle) · \(when)\(status)] \(intent)")
            }
        }
        return lines
    }

    private static func repairLines(
        conversations: [SessionRecord], localFailure: HandoffFailure?, now: Date
    ) -> (lines: [String], redactedCount: Int) {
        // Once a conversation has moved on, its modified date no longer dates the recorded error.
        let sessionFailures: [HandoffFailure] = conversations.compactMap { session in
            let output = nonEmpty(session.lastError)
            guard session.endedWithError || output != nil else { return nil }
            return HandoffFailure(
                source: .session(HomeDashboardModel.toolTitle(session.tool)),
                timestamp: session.endedWithError ? session.modified : nil,
                output: output ?? "",
                files: session.touchedFiles
            )
        }
        let candidates = (localFailure.map { [$0] } ?? []) + sessionFailures
        let failure = latestFailure(in: candidates)
        let files = uniqueFiles(failure?.files ?? [])
        let contextFiles = recentFiles(in: Array(conversations.prefix(2)))
        var lines: [String] = []
        if !files.isEmpty {
            lines.append(FizzL10n.text("- 报错会话记录的文件：\(files.joined(separator: ", "))", "- Files recorded in the failed session: \(files.joined(separator: ", "))"))
        } else if !contextFiles.isEmpty {
            lines.append(FizzL10n.text("- 最近对话改动（与报错关系待核对）：\(contextFiles.joined(separator: ", "))", "- Recent changes (connection to the error unconfirmed): \(contextFiles.joined(separator: ", "))"))
        } else {
            lines.append(FizzL10n.text("- 文件：暂无可关联记录。", "- Files: No associated files recorded."))
        }
        guard let failure else {
            lines += ["", FizzL10n.text("未找到可核对的失败日志或对话报错。请补充触发命令、报错输出和复现步骤。", "No failure log or session error was found. Provide the command, error output, and steps to reproduce it.")]
            return (lines, 0)
        }
        let time = failure.timestamp.map { relativeTimeLabel($0, relativeTo: now) } ?? FizzL10n.text("时间未记录", "time unknown")
        let status = failure.exitCode.map { FizzL10n.text(" · 退出码 \($0)", " · exit code \($0)") } ?? ""
        lines += ["", FizzL10n.text("## 失败记录：\(failure.source.title) · \(time)\(status)", "## Failure: \(failure.source.title) · \(time)\(status)")]
        let output = SecretRedactor.redact(failure.output)
        if let text = nonEmpty(LogTailReader.tail(output.text, maxLines: 12)) {
            let text = text.count > 720 ? "…\n" + String(text.suffix(718)) : text
            let indented = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { "    \($0)" }.joined(separator: "\n")
            lines += ["", indented]
        } else {
            lines.append(FizzL10n.text("有失败记录，但没有可核对的报错输出。请先补充当前错误和复现步骤。", "A failure was recorded without any error output. Provide the current error and steps to reproduce it."))
        }
        lines += ["", FizzL10n.text("请先根据已有证据定位原因，再给出最小修复和验证步骤。", "Use the evidence above to identify the cause. Then suggest a minimal fix and a way to verify it.")]
        return (lines, output.redactedCount)
    }

    private static func notesLines(project: RepoProject) -> [String] {
        let run = nonEmpty(project.run?.command).map { "`\($0)`" } ?? FizzL10n.text("未识别到启动命令。", "No run command found.")
        let test = nonEmpty(project.test?.command).map { "`\($0)`" } ?? FizzL10n.text("未识别到测试命令。", "No test command found.")
        let intro = nonEmpty(project.intro.text)
        let note = nonEmpty(project.note)
        var lines = [FizzL10n.text("- 启动命令：\(run)", "- Run: \(run)"), FizzL10n.text("- 测试命令：\(test)", "- Test: \(test)"), "", FizzL10n.text("## 项目背景", "## Project background")]
        if let intro { lines.append(intro) }
        if let note, note != intro { lines.append(FizzL10n.text("- 项目备注：\(note)", "- Project note: \(note)")) }
        if intro == nil, note == nil { lines.append(FizzL10n.text("未记录项目简介或备注。", "No project description or notes recorded.")) }
        return lines
    }

    @MainActor
    static func managedFailure(for project: RepoProject, actions: ProjectActions, includeDevStatus: Bool = true) -> HandoffFailure? {
        var failures = actions.scriptRuns.values.compactMap { run -> HandoffFailure? in
            guard run.projectPath == project.path, run.status == .failed else { return nil }
            return HandoffFailure(
                source: .script(run.script.name),
                timestamp: run.startedAt.addingTimeInterval(run.duration ?? 0),
                output: managedOutput(run.output), exitCode: run.exitCode
            )
        }
        if let run = actions.testRun(for: project.path), run.path == project.path, run.status == .failed {
            failures.append(HandoffFailure(
                source: .tests, timestamp: run.startedAt.addingTimeInterval(run.duration ?? 0),
                output: managedOutput(run.output), exitCode: run.exitCode
            ))
        }
        if includeDevStatus, !actions.isBusy(project.path), let dev = actions.devFailures[project.path] {
            failures.append(HandoffFailure(source: .devServer, timestamp: dev.recordedAt, output: "", exitCode: dev.exitCode))
        }
        return latestFailure(in: failures)
    }

    @MainActor
    static func loadLocalFailure(
        for project: RepoProject, actions: ProjectActions, projectPaths: [String]
    ) async -> HandoffFailure? {
        var failures = managedFailure(for: project, actions: actions, includeDevStatus: false).map { [$0] } ?? []
        if let run = ProjectTrialService.shared.runs[project.path], run.status == .failed {
            let path = run.logURL.path
            let log: DatedOutput? = if run.error == nil, run.exitCode != nil {
                await Task.detached(priority: .utility) { readLog(at: path) }.value
            } else { nil }
            if ProjectTrialService.shared.runs[project.path]?.id == run.id {
                failures.append(HandoffFailure(
                    source: .trial, timestamp: log?.timestamp,
                    output: run.error ?? log?.output ?? "", exitCode: run.exitCode
                ))
            }
        }

        if !Task.isCancelled, !actions.isBusy(project.path),
           let failure = actions.devFailures[project.path] {
            // Legacy dev logs use directory basenames and append across runs.
            let name = URL(fileURLWithPath: project.path).lastPathComponent.lowercased()
            let ambiguous = ["test-", "script-", "trial-"].contains(where: { name.hasPrefix($0) })
                || projectPaths.contains {
                    $0 != project.path && URL(fileURLWithPath: $0).lastPathComponent.lowercased() == name
                }
            let path = actions.logPath(for: project)
            let output: String? = if !ambiguous, let header = failure.logHeader {
                await Task.detached(priority: .utility) {
                    readLog(at: path).flatMap { currentDevOutput(in: $0.output, header: header) }
                }.value
            } else { nil }
            if !actions.isBusy(project.path), actions.devFailures[project.path] == failure {
                failures.append(HandoffFailure(source: .devServer, timestamp: failure.recordedAt,
                                                output: output ?? "", exitCode: failure.exitCode))
            }
        }
        return latestFailure(in: failures)
    }

    private struct DatedOutput: Sendable {
        let timestamp: Date
        let output: String
    }

    private static func readLog(at path: String) -> DatedOutput? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else { return nil }
        let tail = LogTailReader.read(path: path, maxLines: .max)
        // A bounded read can start after a credential's prefix; discard the partial line.
        let output = size.int64Value > Int64(LogTailReader.defaultMaxBytes) ? droppingFirstLine(tail) : tail
        return DatedOutput(timestamp: modified, output: output)
    }

    static func currentDevOutput(in tail: String, header expected: String) -> String? {
        let lines = tail.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for index in lines.indices.reversed() where lines[index].hasPrefix("--- ") {
            let header = lines[index].split(separator: " ", maxSplits: 2)
            guard header.count >= 2, Format.isoDate(String(header[1])) != nil else { continue }
            guard lines[index] == expected else { return nil }
            return lines.dropFirst(index + 1).joined(separator: "\n")
        }
        return nil
    }

    private static func managedOutput(_ output: String) -> String {
        // ProjectActions caps its in-memory output at 16,000 characters.
        output.count == 16_000 ? droppingFirstLine(output) : output
    }

    private static func droppingFirstLine(_ text: String) -> String {
        guard let newline = text.firstIndex(where: \.isNewline) else { return "" }
        return String(text[text.index(after: newline)...])
    }

    private static func latestFailure(in failures: [HandoffFailure]) -> HandoffFailure? {
        failures.max { lhs, rhs in
            let left = lhs.timestamp ?? .distantPast
            let right = rhs.timestamp ?? .distantPast
            return left == right ? lhs.output.isEmpty && !rhs.output.isEmpty : left < right
        }
    }

    private static func recentFiles(in sessions: [SessionRecord]) -> [String] {
        uniqueFiles(sessions.flatMap(\.touchedFiles))
    }

    private static func uniqueFiles(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var files: [String] = []
        for path in paths where !path.isEmpty && seen.insert(path).inserted {
            files.append(path)
            if files.count == 6 { break }
        }
        return files
    }

    private static func nonEmpty(_ input: String?) -> String? {
        guard let text = input?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func flattenedStacks(_ stacks: [StackGroup]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for group in stacks {
            for item in group.displayItems where seen.insert(item).inserted {
                result.append(item)
            }
        }
        return result
    }

    private static func relativeTimeLabel(_ date: Date, relativeTo now: Date) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 60 { return FizzL10n.text("刚刚", "just now") }
        if delta < 3_600 { return FizzL10n.text("\(Int(delta / 60)) 分钟前", "\(SessionSummaryText.englishCount(Int(delta / 60), "minute")) ago") }
        if delta < 86_400 { return FizzL10n.text("\(Int(delta / 3_600)) 小时前", "\(SessionSummaryText.englishCount(Int(delta / 3_600), "hour")) ago") }
        let days = Int(delta / 86_400)
        if days <= 14 { return FizzL10n.text("\(days) 天前", "\(SessionSummaryText.englishCount(days, "day")) ago") }
        return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(FizzL10n.locale))
    }
}
