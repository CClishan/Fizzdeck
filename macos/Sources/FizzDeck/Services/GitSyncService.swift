import Foundation

enum GitSyncAction: String, CaseIterable, Identifiable, Sendable {
    case fetch
    case pull
    case push

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fetch: "获取远端"
        case .pull: "拉取"
        case .push: "推送"
        }
    }

    var confirmation: String {
        switch self {
        case .fetch:
            "只更新远端引用，不修改工作区。"
        case .pull:
            "只接受 fast-forward；有未提交文件会被拦截。"
        case .push:
            "只推送已提交内容；未提交文件不会包含。"
        }
    }

    var successMessage: String {
        switch self {
        case .fetch: "已获取远端"
        case .pull: "已拉取"
        case .push: "已推送"
        }
    }

    var arguments: [String] {
        switch self {
        case .fetch: ["fetch"]
        case .pull: ["pull", "--ff-only"]
        case .push: ["push"]
        }
    }
}

enum GitSyncStatus: Sendable {
    case succeeded
    case blocked
    case failed
}

struct GitSyncResult: Sendable {
    let status: GitSyncStatus
    let message: String

    var succeeded: Bool {
        status == .succeeded
    }
}

enum GitSyncService {
    static func run(_ action: GitSyncAction, in directory: URL) async -> GitSyncResult {
        if action == .pull {
            guard let status = await Shell.run(
                "git",
                ["status", "--porcelain=v1", "-uall"],
                cwd: directory,
                timeout: 30
            ) else {
                return GitSyncResult(status: .failed, message: "无法读取工作区状态")
            }
            guard status.succeeded else {
                return failure(action, result: status)
            }

            let changes = status.text.split(separator: "\n").filter { !$0.isEmpty }.count
            if changes > 0 {
                return GitSyncResult(
                    status: .blocked,
                    message: "有 \(changes) 个文件未提交，先处理后才能拉取"
                )
            }
        }

        guard let result = await Shell.run(
            "git",
            action.arguments,
            cwd: directory,
            timeout: 120,
            extraEnvironment: ["GIT_TERMINAL_PROMPT": "0"]
        ) else {
            return GitSyncResult(status: .failed, message: "\(action.title)超时或无法启动")
        }

        if result.timedOut {
            return GitSyncResult(
                status: .failed,
                message: "\(action.title)超时，检查网络、代理或 Git 凭据"
            )
        }

        guard result.succeeded else {
            return failure(action, result: result)
        }
        return GitSyncResult(status: .succeeded, message: action.successMessage)
    }

    static func failure(_ action: GitSyncAction, result: ShellOutput) -> GitSyncResult {
        let lines = result.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("hint:") }
        let lowercased = result.text.lowercased()

        if lowercased.contains("no upstream branch")
            || lowercased.contains("no tracking information")
            || lowercased.contains("no remote repository specified")
            || lowercased.contains("no configured push destination") {
            return GitSyncResult(
                status: .failed,
                message: "\(action.title)失败：当前分支没有 upstream，先设置远端分支"
            )
        }

        if lowercased.contains("authentication failed")
            || lowercased.contains("authorization failed")
            || lowercased.contains("could not read username")
            || lowercased.contains("terminal prompts disabled") {
            return GitSyncResult(
                status: .failed,
                message: "\(action.title)失败：Git 凭据不可用，先在终端完成登录"
            )
        }

        if lowercased.contains("permission denied (publickey)")
            || lowercased.contains("no such identity") {
            return GitSyncResult(
                status: .failed,
                message: "\(action.title)失败：SSH 密钥不可用，检查 ssh-agent 和远端配置"
            )
        }

        if lowercased.contains("not possible to fast-forward")
            || lowercased.contains("non-fast-forward")
            || lowercased.contains("fetch first") {
            return GitSyncResult(
                status: .failed,
                message: "\(action.title)失败：无法 fast-forward，先拉取并处理分叉"
            )
        }

        if lowercased.contains("not a git repository") {
            return GitSyncResult(
                status: .failed,
                message: "\(action.title)失败：当前目录不是 Git 仓库"
            )
        }

        if lowercased.contains("could not resolve host")
            || lowercased.contains("could not resolve proxy")
            || lowercased.contains("unable to access")
            || lowercased.contains("connection timed out")
            || lowercased.contains("operation timed out")
            || lowercased.contains("failed to connect")
            || lowercased.contains("network is unreachable") {
            return GitSyncResult(
                status: .failed,
                message: "\(action.title)失败：无法访问远端，检查网络、代理或凭据"
            )
        }

        let detail = lines.first(where: { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") })
            ?? lines.last
            ?? "退出状态 \(result.status)"
        let cleaned = detail
            .replacingOccurrences(of: "fatal: ", with: "")
            .replacingOccurrences(of: "error: ", with: "")
        return GitSyncResult(
            status: .failed,
            message: "\(action.title)失败：\(String(cleaned.prefix(150)))"
        )
    }
}
