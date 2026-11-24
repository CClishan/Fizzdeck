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

        guard result.succeeded else {
            return failure(action, result: result)
        }
        return GitSyncResult(status: .succeeded, message: action.successMessage)
    }

    private static func failure(_ action: GitSyncAction, result: ShellOutput) -> GitSyncResult {
        let lines = result.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("hint:") }
        let detail = lines.last ?? "退出状态 \(result.status)"
        return GitSyncResult(
            status: .failed,
            message: "\(action.title)失败：\(String(detail.prefix(150)))"
        )
    }
}
