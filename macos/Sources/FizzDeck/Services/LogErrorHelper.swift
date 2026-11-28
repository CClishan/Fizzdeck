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
            explanation: FizzL10n.text("项目用到了一个还没装好（或者刚加上）的依赖包。", "This project uses a dependency that hasn’t been installed yet."),
            action: FizzL10n.text("先运行一次安装依赖（如 npm install），再重新启动。", "Install the dependencies (for example, npm install), then restart.")
        ),
        ErrorRule(
            keywords: ["eaddrinuse", "address already in use"],
            category: "port_in_use",
            explanation: FizzL10n.text("这个端口正在被另一个程序占用，所以新服务抢不到门牌号。", "Another process is already using this port."),
            action: FizzL10n.text("关掉占着端口的旧程序，或者换个端口再试。", "Stop the process using the port, or try a different port.")
        ),
        ErrorRule(
            keywords: ["syntaxerror", "unexpected token", "unterminated"],
            category: "syntax_error",
            explanation: FizzL10n.text("代码里少了一个括号、引号，或者写法不符合语法规范。", "The code may have a missing bracket or quote, or another syntax error."),
            action: FizzL10n.text("点下面复制求助 prompt，让 AI 直接定位并补全这一处语法。", "Copy the error prompt below to ask your AI to find and fix it.")
        ),
        ErrorRule(
            keywords: ["typeerror", "referenceerror", "is not a function", "is not defined", "cannot read propert"],
            category: "runtime_type",
            explanation: FizzL10n.text("运行到这一步时拿到了空值或类型不对的数据，程序不知道怎么继续处理。", "A value was missing or had an unexpected type."),
            action: FizzL10n.text("把这段上下文复制给 AI，它很快就能找出哪个变量没初始化。", "Give your AI this context to trace the missing or incorrect value.")
        ),
        ErrorRule(
            keywords: ["enoent", "no such file or directory"],
            category: "file_not_found",
            explanation: FizzL10n.text("程序想读取一个文件或目录，但在对应位置找不到它。", "A required file or folder wasn’t found."),
            action: FizzL10n.text("检查是不是少了 .env 配置文件或文件被移动了路径。", "Check for a missing .env file or a file that was moved.")
        ),
        ErrorRule(
            keywords: ["eacces", "permission denied"],
            category: "permission",
            explanation: FizzL10n.text("系统权限不足，无法读写对应目录或端口。", "The process doesn’t have access to a required folder or port."),
            action: FizzL10n.text("把报错复制给 AI 看是否需要更换目录或端口。", "Copy the error to check whether a different folder or port is needed.")
        ),
        ErrorRule(
            keywords: ["enotfound", "econnrefused", "etimedout", "fetch failed"],
            category: "network",
            explanation: FizzL10n.text("网络连接没通，或者需要调用的本地/外部接口还没启动。", "A service may be offline or the network connection may have failed."),
            action: FizzL10n.text("确认网络畅通，或先启动对应的接口/数据库服务。", "Check the connection and start the required API or database.")
        ),
        ErrorRule(
            keywords: ["out of memory", "heap limit"],
            category: "memory",
            explanation: FizzL10n.text("打包或运行占用内存超限，被系统强制停掉了。", "The system stopped the process because it ran out of memory."),
            action: FizzL10n.text("清理旧进程后重试，或让 AI 排查是否有死循环/超大文件。", "Stop unused processes and retry, or check for a loop or an unusually large file.")
        ),
        ErrorRule(
            keywords: ["failed to compile", "build failed", "error:", "fatal error", "traceback", "exception"],
            category: "build_or_runtime",
            explanation: FizzL10n.text("构建或运行过程中触发了错误导致中断。", "The build or process stopped because of an error."),
            action: FizzL10n.text("不用自己读懂整段日志，点「复制求助 prompt」直接让 AI 帮你修。", "Copy the error prompt to ask your AI to diagnose it.")
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
        let stacks = project.stacks.flatMap(\.displayItems)
        let stackLine = stacks.isEmpty ? project.kind.title : stacks.prefix(6).joined(separator: " / ")

        var seenFiles = Set<String>()
        let recentFiles = project.sessions.recentSessions
            .prefix(2)
            .flatMap(\.touchedFiles)
            .map { SecretRedactor.redact(URL(fileURLWithPath: $0).lastPathComponent).text }
            .filter { seenFiles.insert($0).inserted }
            .prefix(8)

        var lines: [String] = [
            FizzL10n.text("我在运行「\(project.displayName)」时遇到了报错，请帮我分析原因并直接修复：", "I hit this error running “\(project.displayName)”. Please find the cause and fix it:"),
            "",
            FizzL10n.text("- 技术栈：\(stackLine)", "- Stack: \(stackLine)"),
        ]
        if !recentFiles.isEmpty {
            lines.append(FizzL10n.text("- 最近改过的文件：\(recentFiles.joined(separator: ", "))", "- Recently changed files: \(recentFiles.joined(separator: ", "))"))
        }
        lines.append(contentsOf: [
            FizzL10n.text("- 报错提示：\(match.matchedLine)", "- Error: \(match.matchedLine)"),
            "",
            FizzL10n.text("相关日志片段：", "Relevant log excerpt:"),
            "```",
            match.contextBlock,
            "```",
            "",
            FizzL10n.text("请先用大白话简单解释为什么会报这个错，再直接帮我改好。", "Please explain the cause in plain language, then fix it."),
        ])

        return SecretRedactor.redact(lines.joined(separator: "\n")).text
    }
}
