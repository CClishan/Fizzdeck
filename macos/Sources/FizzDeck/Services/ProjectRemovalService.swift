import Foundation

enum ProjectRemovalMode: String, Sendable {
    case trash
    case permanent

    var title: String {
        switch self {
        case .trash: FizzL10n.text("移入废纸篓", "Move to Trash")
        case .permanent: FizzL10n.text("永久删除", "Delete Permanently")
        }
    }

    var actionTitle: String {
        switch self {
        case .trash: FizzL10n.text("移入废纸篓", "Move to Trash")
        case .permanent: FizzL10n.text("永久删除", "Delete Permanently")
        }
    }

    var symbol: String {
        switch self {
        case .trash: "trash"
        case .permanent: "trash.slash"
        }
    }

    var explanation: String {
        switch self {
        case .trash:
            return FizzL10n.text("项目目录会移到 macOS 废纸篓，文件仍可从废纸篓恢复。", "You can recover this folder from the macOS Trash.")
        case .permanent:
            return FizzL10n.text("删除前会先复制到 ~/.repodeck/trash 作为本地副本，然后从原路径删除。副本不会自动清理。", "FizzDeck will first copy the folder to ~/.repodeck/trash, then delete the original. The backup stays until you remove it.")
        }
    }
}

struct ProjectRemovalResult: Sendable {
    let success: Bool
    let message: String
}

enum ProjectRemovalService {
    static func remove(
        path: String,
        mode: ProjectRemovalMode,
        confirmation: String,
        managedRoots: [String],
        testRunning: Bool,
        devServerRunning: Bool,
        backupRoot: URL = AppPaths.stateDir.appendingPathComponent("trash", isDirectory: true)
    ) -> ProjectRemovalResult {
        let normalized = PathTools.normalize(path)
        let roots = Set(managedRoots.map(PathTools.normalize))
        let url = URL(fileURLWithPath: normalized)
        let protected = Set([
            "/",
            AppPaths.home.path,
            AppPaths.home.deletingLastPathComponent().path,
            "/Applications",
            "/System",
            "/Volumes",
        ])

        guard roots.contains(normalized) else {
            return failure(FizzL10n.text("项目不在受管目录内，拒绝移除", "This folder is outside your managed projects and cannot be removed"))
        }
        guard !protected.contains(normalized),
              url.pathComponents.count > 3
        else {
            return failure(FizzL10n.text("拒绝移除过高层级的目录", "Cannot remove a top-level folder"))
        }
        guard FileTools.isDirectory(url) else {
            return failure(FizzL10n.text("项目目录不存在", "Project folder not found"))
        }
        guard !devServerRunning else {
            return failure(FizzL10n.text("开发服务仍在运行，先停止后再移除", "Stop the development service before removing the project"))
        }
        guard !testRunning else {
            return failure(FizzL10n.text("测试仍在运行，先停止后再移除", "Stop the tests before removing the project"))
        }

        let base = url.lastPathComponent
        guard confirmation.trimmingCharacters(in: .whitespacesAndNewlines) == base else {
            return failure(FizzL10n.text("确认名称不匹配，请输入「\(base)」", "Enter “\(base)” to confirm"))
        }

        switch mode {
        case .trash:
            return moveToTrash(url, base: base)
        case .permanent:
            return permanentlyDelete(url, base: base, backupRoot: backupRoot)
        }
    }

    private static func moveToTrash(_ url: URL, base: String) -> ProjectRemovalResult {
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            return ProjectRemovalResult(success: true, message: FizzL10n.text("已移到废纸篓：\(base)", "Moved to Trash: \(base)"))
        } catch {
            return failure(FizzL10n.text("移到废纸篓失败，未做任何删除：\(error.localizedDescription)", "Couldn’t move to Trash. Nothing was deleted: \(error.localizedDescription)"))
        }
    }

    private static func permanentlyDelete(
        _ url: URL,
        base: String,
        backupRoot: URL
    ) -> ProjectRemovalResult {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = backupRoot.appendingPathComponent("\(base)-\(stamp)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: backupRoot,
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            return failure(FizzL10n.text("备份到 ~/.repodeck/trash 失败，未删除：\(error.localizedDescription)", "Couldn’t back up to ~/.repodeck/trash. Nothing was deleted: \(error.localizedDescription)"))
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return failure(
                FizzL10n.text("副本已保存到 \(PathTools.displayPath(destination.path))，但原目录删除失败：\(error.localizedDescription)", "Backup saved to \(PathTools.displayPath(destination.path)), but the original couldn’t be removed: \(error.localizedDescription)")
            )
        }
        return ProjectRemovalResult(
            success: true,
            message: FizzL10n.text("已删除 \(base)，副本保存在 \(PathTools.displayPath(destination.path))", "Deleted \(base). Backup saved to \(PathTools.displayPath(destination.path))")
        )
    }

    private static func failure(_ message: String) -> ProjectRemovalResult {
        ProjectRemovalResult(success: false, message: message)
    }
}
