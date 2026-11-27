import Foundation

enum ProjectAttentionKind: String, CaseIterable, Identifiable, Sendable {
    case doctorCritical
    case testFailed
    case sessionError
    case dirty
    case behind
    case unpushed
    case cleanup

    var id: String { rawValue }

    var priority: Int {
        switch self {
        case .doctorCritical: 0
        case .testFailed: 0
        case .sessionError: 1
        case .behind: 2
        case .unpushed: 3
        case .dirty: 4
        case .cleanup: 5
        }
    }

    var plainPriority: Int {
        switch self {
        case .doctorCritical: 0
        case .testFailed: 0
        case .sessionError: 1
        case .dirty: 2
        case .unpushed: 3
        case .behind: 4
        case .cleanup: 5
        }
    }

    var isCritical: Bool {
        self == .doctorCritical || self == .testFailed || self == .sessionError
    }

    var tab: ProjectTab {
        switch self {
        case .doctorCritical, .testFailed: .run
        case .sessionError, .cleanup: .progress
        case .dirty, .behind, .unpushed: .version
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
        items(
            projects: projects,
            testRuns: testRuns,
            focusedPaths: nil,
            copyMode: .pro
        )
    }

    static func items(
        projects: [RepoProject],
        testRuns: [String: TestRunState],
        focusedPaths: Set<String>?,
        copyMode: CopyMode,
        doctorReports: [String: DoctorProjectReport] = [:]
    ) -> [ProjectAttentionItem] {
        var items: [ProjectAttentionItem] = []

        for project in projects {
            if let focusedPaths, !focusedPaths.contains(project.path) {
                continue
            }

            if let report = doctorReports[project.path],
               let criticalDoctor = report.issues.first(where: { $0.severity == .critical }) {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .doctorCritical,
                        title: criticalDoctor.title,
                        detail: criticalDoctor.detail
                    )
                )
            }

            if let test = testRuns[project.path], test.status == .failed {
                let exit = test.exitCode.map { " · exit \($0)" } ?? ""
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .testFailed,
                        title: copyMode == .plain ? "跑不起来：检查没通过" : "测试失败",
                        detail: test.command + exit
                    )
                )
            }

            if let latestConversation = project.sessions.recentSessions
                .filter({ $0.kind == .conversation })
                .max(by: { $0.modified < $1.modified }),
               latestConversation.endedWithError {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .sessionError,
                        title: copyMode == .plain ? "上次 AI 对话报错结束" : "会话报错结束",
                        detail: latestConversation.lastError ?? "点击查看进度"
                    )
                )
            }

            if project.changes.total > 0 {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .dirty,
                        title: FizzCopy.uncommittedChanges(count: project.changes.total, mode: copyMode).text,
                        detail: branchDetail(project)
                    )
                )
            }

            if project.behind > 0 {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .behind,
                        title: FizzCopy.behind(count: project.behind, mode: copyMode).text,
                        detail: branchDetail(project)
                    )
                )
            }

            if project.ahead > 0 {
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .unpushed,
                        title: FizzCopy.unpushed(count: project.ahead, mode: copyMode).text,
                        detail: branchDetail(project)
                    )
                )
            }

            if copyMode == .pro, project.cleanup.reusableBytes >= 1_000_000_000 {
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
            let leftPriority = copyMode == .plain ? left.kind.plainPriority : left.kind.priority
            let rightPriority = copyMode == .plain ? right.kind.plainPriority : right.kind.priority
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
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
