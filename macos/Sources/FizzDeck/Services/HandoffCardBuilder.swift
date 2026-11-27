import Foundation

struct HandoffCardResult: Equatable, Sendable {
    let markdown: String
    let characterCount: Int
    let redactedCount: Int
    let includedSessionCount: Int
}

enum HandoffCardBuilder {
    static func build(
        project: RepoProject,
        sessionLimit: Int = 3,
        copyMode: CopyMode = .plain,
        maxCharacters: Int = 1_500,
        now: Date = Date()
    ) -> HandoffCardResult {
        let limit = max(1, sessionLimit)
        let conversations = project.sessions.recentSessions
            .filter { $0.kind == .conversation }
            .sorted { $0.modified > $1.modified }
        let selected = Array(conversations.prefix(limit))

        var lines: [String] = []
        lines.append("# 项目接力：\(project.displayName)")
        lines.append("- 路径：`\(project.path)`")

        let stackItems = flattenedStacks(project.stacks)
        if !stackItems.isEmpty {
            lines.append("- 技术栈：\(stackItems.joined(separator: " / "))")
        }

        if let runCommand = project.run?.command.trimmingCharacters(in: .whitespacesAndNewlines),
           !runCommand.isEmpty {
            lines.append("- 启动命令：`\(runCommand)`")
        }

        let statusText = FizzCopy.projectStatusSummary(
            dirtyCount: project.changes.total,
            ahead: project.ahead,
            behind: project.behind,
            mode: copyMode
        )
        lines.append("- 当前状态：\(statusText)")

        if !selected.isEmpty {
            lines.append("")
            lines.append("## 最近对话")
            for session in selected {
                let toolTitle = HomeDashboardModel.toolTitle(session.tool)
                let when = relativeTimeLabel(session.modified, relativeTo: now)
                let intent = session.primaryIntent ?? "\(toolTitle) 会话"
                let status = session.endedWithError ? "报错结束" : "正常结束"
                var line = "- [\(toolTitle) · \(when) · \(status)] \(intent)"
                if !session.touchedFiles.isEmpty {
                    let shown = session.touchedFiles.prefix(6)
                    let overflow = session.touchedFiles.count - shown.count
                    let fileList = shown.joined(separator: ", ") + (overflow > 0 ? " 等 +\(overflow) 个" : "")
                    line += "（改过：\(fileList)）"
                }
                lines.append(line)
            }
        }

        if let latestError = selected.compactMap(\.lastError)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            lines.append("")
            lines.append("## 最近报错")
            lines.append("```text")
            lines.append(latestError)
            lines.append("```")
        }

        lines.append("")
        lines.append("请先简要确认你理解当前进度，再继续下一步。")

        let rawMarkdown = lines.joined(separator: "\n")
        let redacted = SecretRedactor.redact(rawMarkdown)

        let finalMarkdown: String
        if redacted.text.count > maxCharacters {
            let suffix = "\n…（已截断）"
            if maxCharacters > suffix.count {
                finalMarkdown = String(redacted.text.prefix(maxCharacters - suffix.count)) + suffix
            } else {
                finalMarkdown = String(redacted.text.prefix(max(0, maxCharacters)))
            }
        } else {
            finalMarkdown = redacted.text
        }

        return HandoffCardResult(
            markdown: finalMarkdown,
            characterCount: finalMarkdown.count,
            redactedCount: redacted.redactedCount,
            includedSessionCount: selected.count
        )
    }

    private static func flattenedStacks(_ stacks: [StackGroup]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for group in stacks {
            for item in group.items where seen.insert(item).inserted {
                result.append(item)
            }
        }
        return result
    }

    private static func relativeTimeLabel(_ date: Date, relativeTo now: Date) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 60 { return "刚刚" }
        if delta < 3_600 { return "\(Int(delta / 60)) 分钟前" }
        if delta < 86_400 { return "\(Int(delta / 3_600)) 小时前" }
        let days = Int(delta / 86_400)
        if days <= 14 { return "\(days) 天前" }
        return Format.shortDate(date)
    }
}
