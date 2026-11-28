import Foundation

enum HomeFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case starred
    case dirty
    case running

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: FizzL10n.text("项目总览", "Project overview")
        case .starred: FizzL10n.text("收藏", "Starred")
        case .dirty: FizzL10n.text("有改动", "Changed")
        case .running: FizzL10n.text("正在运行", "Running")
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .starred: "star"
        case .dirty: "arrow.triangle.branch"
        case .running: "play.circle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: FizzL10n.text("没有匹配项目", "No matching projects")
        case .starred: FizzL10n.text("还没有收藏项目", "No starred projects yet")
        case .dirty: FizzL10n.text("工作区都很干净", "All working trees are clean")
        case .running: FizzL10n.text("没有正在运行的项目", "No projects running")
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: FizzL10n.text("试试项目名、路径或技术栈。", "Try a project name, path, or tech stack.")
        case .starred: FizzL10n.text("在侧栏项目上右键，或使用项目头部的星标。", "Right-click a project in the sidebar or use the star in its header.")
        case .dirty: FizzL10n.text("当前没有未提交改动。", "There are no uncommitted changes.")
        case .running: FizzL10n.text("启动一个带预览端口的项目后，会出现在这里。", "Projects with a running preview appear here.")
        }
    }

    func matches(_ project: RepoProject) -> Bool {
        switch self {
        case .all: true
        case .starred: project.starred
        case .dirty: project.changes.total > 0
        case .running: project.port == .running
        }
    }
}
