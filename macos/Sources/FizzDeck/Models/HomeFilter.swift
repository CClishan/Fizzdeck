import Foundation

enum HomeFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case starred
    case dirty
    case running

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "项目总览"
        case .starred: "收藏"
        case .dirty: "有改动"
        case .running: "正在运行"
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
        case .all: "没有匹配项目"
        case .starred: "还没有收藏项目"
        case .dirty: "工作区都很干净"
        case .running: "没有正在运行的项目"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: "试试项目名、路径或技术栈。"
        case .starred: "在侧栏项目上右键，或使用项目头部的星标。"
        case .dirty: "当前没有未提交改动。"
        case .running: "启动一个带预览端口的项目后，会出现在这里。"
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
