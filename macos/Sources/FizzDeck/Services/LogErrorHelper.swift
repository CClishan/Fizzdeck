import Foundation

struct LogErrorMatch: Equatable, Sendable {
    let matchedLine: String
    let contextBlock: String
    let category: String
    let plainExplanation: String
    let suggestedAction: String
}

enum LogErrorHelper {
    private struct ErrorRule {
        let keywords: [String]
        let category: String
        let explanation: String
        let action: String
    }

    private static let benignMarkers = [
        "0 errors",
        "0 error",
        "0 failures",
        "0 unexpected",
        "no errors",
    ]

    private static let rules: [ErrorRule] = [
        ErrorRule(
            keywords: ["cannot find module", "modulenotfounderror", "err_module_not_found", "could not resolve"],
            category: "missing_module",
            explanation: "项目用到了一个还没装好（或者刚加上）的依赖包。",
            action: "先运行一次安装依赖（如 npm install），再重新启动。"
        ),
        ErrorRule(
            keywords: ["eaddrinuse", "address already in use"],
            category: "port_in_use",
            explanation: "这个端口正在被另一个程序占用，所以新服务抢不到门牌号。",
            action: "关掉占着端口的旧程序，或者换个端口再试。"
        ),
        ErrorRule(
            keywords: ["syntaxerror", "unexpected token", "unterminated"],
            category: "syntax_error",
            explanation: "代码里少了一个括号、引号，或者写法不符合语法规范。",
            action: "点下面复制求助 prompt，让 AI 直接定位并补全这一处语法。"
        ),
        ErrorRule(
            keywords: ["typeerror", "referenceerror", "is not a function", "is not defined", "cannot read propert"],
            category: "runtime_type",
            explanation: "运行到这一步时拿到了空值或类型不对的数据，程序不知道怎么继续处理。",
            action: "把这段上下文复制给 AI，它很快就能找出哪个变量没初始化。"
        ),
        ErrorRule(
            keywords: ["enoent", "no such file or directory"],
            category: "file_not_found",
            explanation: "程序想读取一个文件或目录，但在对应位置找不到它。",
            action: "检查是不是少了 .env 配置文件或文件被移动了路径。"
        ),
        ErrorRule(
            keywords: ["eacces", "permission denied"],
            category: "permission",
            explanation: "系统权限不足，无法读写对应目录或端口。",
            action: "把报错复制给 AI 看是否需要更换目录或端口。"
        ),
        ErrorRule(
            keywords: ["enotfound", "econnrefused", "etimedout", "fetch failed"],
            category: "network",
            explanation: "网络连接没通，或者需要调用的本地/外部接口还没启动。",
            action: "确认网络畅通，或先启动对应的接口/数据库服务。"
        ),
        ErrorRule(
            keywords: ["out of memory", "heap limit"],
            category: "memory",
            explanation: "打包或运行占用内存超限，被系统强制停掉了。",
            action: "清理旧进程后重试，或让 AI 排查是否有死循环/超大文件。"
        ),
        ErrorRule(
            keywords: ["failed to compile", "build failed", "error:", "fatal error", "traceback", "exception"],
            category: "build_or_runtime",
            explanation: "构建或运行过程中触发了错误导致中断。",
            action: "不用自己读懂整段日志，点「复制求助 prompt」直接让 AI 帮你修。"
        ),
    ]

    static func extractError(from logText: String) -> LogErrorMatch? {
        let lines = logText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !lines.isEmpty else { return nil }

        for index in stride(from: lines.count - 1, through: 0, by: -1) {
            let line = lines[index]
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if benignMarkers.contains(where: { lower.contains($0) }) {
                continue
            }

            guard let rule = rules.first(where: { rule in
                rule.keywords.contains(where: { lower.contains($0) })
            }) else {
                continue
            }

            let start = max(0, index - 4)
            let end = min(lines.count - 1, index + 6)
            let rawContext = lines[start ... end]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            let redactedLine = SecretRedactor.redact(String(line.prefix(240))).text
            let redactedContext = SecretRedactor.redact(String(rawContext.prefix(900))).text

            return LogErrorMatch(
                matchedLine: redactedLine,
                contextBlock: redactedContext,
                category: rule.category,
                plainExplanation: rule.explanation,
                suggestedAction: rule.action
            )
        }

        return nil
    }

    static func buildHelpPrompt(project: RepoProject, match: LogErrorMatch) -> String {
        let stacks = project.stacks.flatMap(\.items)
        let stackLine = stacks.isEmpty ? project.kind.title : stacks.prefix(6).joined(separator: " / ")

        var seenFiles = Set<String>()
        let recentFiles = project.sessions.recentSessions
            .prefix(2)
            .flatMap(\.touchedFiles)
            .map { SecretRedactor.redact(URL(fileURLWithPath: $0).lastPathComponent).text }
            .filter { seenFiles.insert($0).inserted }
            .prefix(8)

        var lines: [String] = [
            "我在运行「\(project.displayName)」时遇到了报错，请帮我分析原因并直接修复：",
            "",
            "- 技术栈：\(stackLine)",
        ]
        if !recentFiles.isEmpty {
            lines.append("- 最近改过的文件：\(recentFiles.joined(separator: ", "))")
        }
        lines.append(contentsOf: [
            "- 报错提示：\(match.matchedLine)",
            "",
            "相关日志片段：",
            "```",
            match.contextBlock,
            "```",
            "",
            "请先用大白话简单解释为什么会报这个错，再直接帮我改好。",
        ])

        return SecretRedactor.redact(lines.joined(separator: "\n")).text
    }
}
