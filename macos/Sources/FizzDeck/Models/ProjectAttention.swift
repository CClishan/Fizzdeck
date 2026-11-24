import Foundation

enum ProjectAttentionKind: String, CaseIterable, Identifiable, Sendable {
    case testFailed
    case dirty
    case behind
    case unpushed
    case cleanup

    var id: String { rawValue }

    var priority: Int {
        switch self {
        case .testFailed: 0
        case .behind: 1
        case .unpushed: 2
        case .dirty: 3
        case .cleanup: 4
        }
    }

    var tab: ProjectTab {
        switch self {
        case .testFailed: .tests
        case .dirty, .behind, .unpushed: .git
        case .cleanup: .cleanup
        }
    }
}

struct ProjectAttentionItem: Identifiable, Sendable {
    let project: RepoProject
    let kind: ProjectAttentionKind
    let title: String
    let detail: String

    var id: String { "\(project.path):\(kind.rawValue)" }
}

extension AttentionPreference {
    func suppresses(at date: Date = Date()) -> Bool {
        muted || (snoozedUntil ?? .distantPast) > date
    }

    func isSnoozed(at date: Date = Date()) -> Bool {
        !muted && (snoozedUntil ?? .distantPast) > date
    }
}

enum ProjectAttentionQueue {
    static func items(
        projects: [RepoProject],
        testRuns: [String: TestRunState]
    ) -> [ProjectAttentionItem] {
        var items: [ProjectAttentionItem] = []

        for project in projects {
            if let test = testRuns[project.path], test.status == .failed {
                let exit = test.exitCode.map { " · exit \($0)" } ?? ""
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .testFailed,
                        title: "测试失败",
                        detail: test.command + exit
                    )
                )
            }

            if project.changes.total > 0 {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .dirty,
                        title: "\(project.changes.total) 个文件未提交",
                        detail: branchDetail(project)
                    )
                )
            }

            if project.behind > 0 {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .behind,
                        title: "落后远端 \(project.behind) 个提交",
                        detail: branchDetail(project)
                    )
                )
            }

            if project.ahead > 0 {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .unpushed,
                        title: "\(project.ahead) 个提交未推送",
                        detail: branchDetail(project)
                    )
                )
            }

            if project.cleanup.reusableBytes >= 1_000_000_000 {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .cleanup,
                        title: "可回收 \(Format.bytes(project.cleanup.reusableBytes))",
                        detail: "\(project.cleanup.items.count) 个缓存或构建目录"
                    )
                )
            }
        }

        return items.sorted { left, right in
            if left.kind.priority != right.kind.priority {
                return left.kind.priority < right.kind.priority
            }
            return (left.project.recent ?? .distantPast) > (right.project.recent ?? .distantPast)
        }
    }

    private static func branchDetail(_ project: RepoProject) -> String {
        if let branch = project.branch {
            return branch
        }
        return project.group
    }
}
