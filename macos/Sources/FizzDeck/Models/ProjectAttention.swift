import Foundation

enum ProjectAttentionKind: String, CaseIterable, Identifiable, Sendable {
    case doctorCritical
    case testFailed
    case sessionError
    case dirty
    case behind
    case unpushed
    case cleanup
    case expiringMarks

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
        case .expiringMarks: 6
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
        case .expiringMarks: 6
        }
    }

    var isCritical: Bool {
        self == .doctorCritical || self == .testFailed || self == .sessionError
    }

    var tab: ProjectTab {
        switch self {
        case .doctorCritical, .testFailed: .run
        case .sessionError, .cleanup, .expiringMarks: .progress
        case .dirty, .behind, .unpushed: .version
        }
    }
}

struct ProjectAttentionItem: Identifiable, Sendable {
    let project: RepoProject
    let kind: ProjectAttentionKind
    let title: String
    let detail: String
    var expiringMarks: [ExpiringSessionMark] = []

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
        doctorReports: [String: DoctorProjectReport] = [:],
        expiringMarks: [ExpiringSessionMark] = []
    ) -> [ProjectAttentionItem] {
        var items: [ProjectAttentionItem] = []
        let marksByProject = Dictionary(grouping: expiringMarks, by: \.projectPath)

        for project in projects {
            if let focusedPaths, !focusedPaths.contains(project.path) {
                continue
            }

            if let reminders = marksByProject[project.path], let first = reminders.first {
                let name = first.mark.displayLabel
                let date = first.mark.createdAt.formatted(.dateTime.month().day().hour().minute().locale(FizzL10n.locale))
                items.append(ProjectAttentionItem(
                    project: project, kind: .expiringMarks, title: FizzL10n.text("\(reminders.count) 个标记即将过期", "\(reminders.count) expiring \(reminders.count == 1 ? "mark" : "marks")"),
                    detail: FizzL10n.text("约 \(first.daysRemaining) 天后过期 · \(name) · \(date)", "Expires in about \(SessionSummaryText.englishCount(first.daysRemaining, "day")) · \(name) · \(date)"), expiringMarks: reminders
                ))
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
                let exit = test.exitCode.map { FizzL10n.text(" · 退出码 \($0)", " · exit \($0)") } ?? ""
                items.append(
                    ProjectAttentionItem(
                        project: project,
                        kind: .testFailed,
                        title: copyMode == .plain ? FizzL10n.text("跑不起来：检查没通过", "Can’t run: check failed") : FizzL10n.text("测试失败", "Tests failed"),
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
                        title: copyMode == .plain ? FizzL10n.text("上次 AI 对话报错结束", "Last AI conversation ended with an error") : FizzL10n.text("会话报错结束", "Session ended with an error"),
                        detail: latestConversation.lastError ?? FizzL10n.text("点击查看进度", "View Progress")
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
                        title: FizzL10n.text("可回收 \(Format.bytes(project.cleanup.reusableBytes))", "Reclaim \(Format.bytes(project.cleanup.reusableBytes))"),
                        detail: FizzL10n.text("\(project.cleanup.items.count) 个缓存或构建目录", "\(project.cleanup.items.count) cache or build \(project.cleanup.items.count == 1 ? "folder" : "folders")")
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
        return project.groupTitle
    }
}
