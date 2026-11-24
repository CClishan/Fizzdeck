import Foundation

enum ProjectRemovalMode: String, Sendable {
    case trash
    case permanent

    var title: String {
        switch self {
        case .trash: "移入废纸篓"
        case .permanent: "永久删除"
        }
    }

    var actionTitle: String {
        switch self {
        case .trash: "移入废纸篓"
        case .permanent: "永久删除"
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
            return "项目目录会移到 macOS 废纸篓，文件仍可从废纸篓恢复。"
        case .permanent:
            return "删除前会先复制到 ~/.repodeck/trash 作为本地副本，然后从原路径删除。副本不会自动清理。"
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
            return failure("项目不在受管目录内，拒绝移除")
        }
        guard !protected.contains(normalized),
              url.pathComponents.count > 3
        else {
            return failure("拒绝移除过高层级的目录")
        }
        guard FileTools.isDirectory(url) else {
            return failure("项目目录不存在")
        }
        guard !devServerRunning else {
            return failure("开发服务仍在运行，先停止后再移除")
        }
        guard !testRunning else {
            return failure("测试仍在运行，先停止后再移除")
        }

        let base = url.lastPathComponent
        guard confirmation.trimmingCharacters(in: .whitespacesAndNewlines) == base else {
            return failure("确认名称不匹配，请输入「\(base)」")
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
            return ProjectRemovalResult(success: true, message: "已移到废纸篓：\(base)")
        } catch {
            return failure("移到废纸篓失败，未做任何删除：\(error.localizedDescription)")
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
            return failure("备份到 ~/.repodeck/trash 失败，未删除：\(error.localizedDescription)")
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return failure(
                "副本已保存到 \(PathTools.displayPath(destination.path))，但原目录删除失败：\(error.localizedDescription)"
            )
        }
        return ProjectRemovalResult(
            success: true,
            message: "已删除 \(base)，副本保存在 \(PathTools.displayPath(destination.path))"
        )
    }

    private static func failure(_ message: String) -> ProjectRemovalResult {
        ProjectRemovalResult(success: false, message: message)
    }
}
