import Foundation

enum GitSyncAction: String, CaseIterable, Identifiable, Sendable {
    case fetch
    case pull
    case push

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fetch: FizzL10n.text("获取远端", "Fetch")
        case .pull: FizzL10n.text("拉取", "Pull")
        case .push: FizzL10n.text("推送", "Push")
        }
    }

    var confirmation: String { confirmation(for: .pro) }

    func confirmation(for mode: CopyMode) -> String {
        switch self {
        case .fetch:
            FizzL10n.text("只更新远端引用，不修改工作区。", mode == .plain
                ? "Check for updates. Your files stay as they are." : "Update remote refs without changing the working tree.")
        case .pull:
            FizzL10n.text("只接受 fast-forward；有未提交文件会被拦截。", mode == .plain
                ? "Download updates only if your versions haven’t diverged and there are no unsaved changes."
                : "Only a fast-forward pull is allowed. Uncommitted files will block it.")
        case .push:
            FizzL10n.text("只推送已提交内容；未提交文件不会包含。", mode == .plain
                ? "Upload saved versions. Changes you haven’t saved as a version stay on this Mac."
                : "Push committed changes only. Uncommitted files are excluded.")
        }
    }

    var successMessage: String {
        switch self {
        case .fetch: FizzL10n.text("已获取远端", "Fetched remote refs")
        case .pull: FizzL10n.text("已拉取", "Pulled changes")
        case .push: FizzL10n.text("已推送", "Pushed commits")
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
                return GitSyncResult(status: .failed, message: FizzL10n.text("无法读取工作区状态", "Couldn’t read the working tree status."))
            }
            guard status.succeeded else {
                return failure(action, result: status)
            }

            let changes = status.text.split(separator: "\n").filter { !$0.isEmpty }.count
            if changes > 0 {
                return GitSyncResult(
                    status: .blocked,
                    message: FizzL10n.text("有 \(changes) 个文件未提交，先处理后才能拉取", "Uncommitted files: \(changes). Resolve them before pulling.")
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
            return GitSyncResult(status: .failed, message: FizzL10n.text("\(action.title)超时或无法启动", "\(action.title) timed out or could not start."))
        }

        if result.timedOut {
            return GitSyncResult(
                status: .failed,
                message: FizzL10n.text("\(action.title)超时，检查网络、代理或 Git 凭据", "\(action.title) timed out. Check your network, proxy or Git credentials.")
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
                message: FizzL10n.text("\(action.title)失败：当前分支没有 upstream，先设置远端分支", "\(action.title) failed: set an upstream branch first.")
            )
        }

        if lowercased.contains("authentication failed")
            || lowercased.contains("authorization failed")
            || lowercased.contains("could not read username")
            || lowercased.contains("terminal prompts disabled") {
            return GitSyncResult(
                status: .failed,
                message: FizzL10n.text("\(action.title)失败：Git 凭据不可用，先在终端完成登录", "\(action.title) failed: Git credentials are unavailable. Sign in from Terminal first.")
            )
        }

        if lowercased.contains("permission denied (publickey)")
            || lowercased.contains("no such identity") {
            return GitSyncResult(
                status: .failed,
                message: FizzL10n.text("\(action.title)失败：SSH 密钥不可用，检查 ssh-agent 和远端配置", "\(action.title) failed: SSH key unavailable. Check ssh-agent and your remote settings.")
            )
        }

        if lowercased.contains("not possible to fast-forward")
            || lowercased.contains("non-fast-forward")
            || lowercased.contains("fetch first") {
            return GitSyncResult(
                status: .failed,
                message: FizzL10n.text("\(action.title)失败：无法 fast-forward，先拉取并处理分叉", "\(action.title) failed: a fast-forward is not possible. Reconcile the diverged branches first.")
            )
        }

        if lowercased.contains("not a git repository") {
            return GitSyncResult(
                status: .failed,
                message: FizzL10n.text("\(action.title)失败：当前目录不是 Git 仓库", "\(action.title) failed: this folder is not a Git repository.")
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
                message: FizzL10n.text("\(action.title)失败：无法访问远端，检查网络、代理或凭据", "\(action.title) failed: the remote is unreachable. Check your network, proxy or credentials.")
            )
        }

        let detail = lines.first(where: { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") })
            ?? lines.last
            ?? FizzL10n.text("退出状态 \(result.status)", "Exit status \(result.status)")
        let cleaned = detail
            .replacingOccurrences(of: "fatal: ", with: "")
            .replacingOccurrences(of: "error: ", with: "")
        return GitSyncResult(
            status: .failed,
            message: FizzL10n.text("\(action.title)失败：\(String(cleaned.prefix(150)))", "\(action.title) failed: \(String(cleaned.prefix(150)))")
        )
    }
}
