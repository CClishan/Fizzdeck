import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let store: RepositoryStore
    let actions: ProjectActions

    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    private static let initialDate = Date()
    @State private var asOf = MenuBarLabel.initialDate

    private func attentionCount(at now: Date) -> Int {
        let focusedPaths = copyMode == .plain
            ? ProjectFocusPolicy.partition(projects: store.projects, now: now).focusedPaths
            : nil
        let items = ProjectAttentionQueue
            .items(
                projects: store.projects,
                testRuns: actions.testRuns,
                focusedPaths: focusedPaths,
                copyMode: copyMode,
                doctorReports: store.doctorReports
            )
            .filter { item in
                if copyMode == .plain && !item.kind.isCritical {
                    return false
                }
                return !store.isAttentionSuppressed(
                    for: item.project,
                    kind: item.kind,
                    at: now
                )
            }
        return MenuBarAttentionSummary.count(items: items)
    }

    static func nextExpiry(in projects: [RepoProject], mode: CopyMode, after asOf: Date,
                           preference: (RepoProject, ProjectAttentionKind) -> AttentionPreference?) -> Date? {
        var next: Date?
        func consider(_ date: Date?) {
            guard let date, date > asOf else { return }
            next = min(next ?? date, date)
        }
        for project in projects {
            if mode == .plain, let expiry = ProjectFocusPolicy.autoFocusExpiry(for: project) {
                consider(expiry.addingTimeInterval(1)) // Focus includes the cutoff itself.
            }
            for kind in ProjectAttentionKind.allCases where mode == .pro || kind.isCritical {
                if let rule = preference(project, kind), !rule.muted {
                    consider(rule.snoozedUntil)
                }
            }
        }
        return next
    }

    var body: some View {
        let count = attentionCount(at: asOf)
        let deadline = Self.nextExpiry(in: store.projects, mode: copyMode, after: asOf, preference: store.attentionPreference)
        let feedback = MenuBarHandoff.shared.feedback.current
        let description = MenuBarHandoff.shared.feedbackTitle ?? FizzL10n.text("待处理 \(count) 项", "\(count) pending")
        // Status-item layout snapshots this view: keep its shape and image size stable.
        HStack(spacing: 4) {
            FizzIcon(.sm, symbol: feedback?.symbol ?? (count > 0 ? "exclamationmark.circle.fill" : "checkmark.circle"))
            Text("\(count)").font(FizzTypography.caption(.semibold))
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FizzL10n.text("FizzDeck，\(description)", "FizzDeck, \(description)"))
        .help(description)
        .task(id: deadline) {
            guard let deadline else { return }
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
            asOf = max(deadline, Date())
        }
    }
}

struct MenuBarMenu: View {
    let store: RepositoryStore
    let actions: ProjectActions

    @Environment(\.openWindow) private var openWindow
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    private func attentionCount(focusedPaths: Set<String>?) -> Int {
        let now = Date()
        return ProjectAttentionQueue
            .items(
                projects: store.projects,
                testRuns: actions.testRuns,
                focusedPaths: focusedPaths,
                copyMode: copyMode,
                doctorReports: store.doctorReports
            )
            .count {
                !store.isAttentionSuppressed(
                    for: $0.project,
                    kind: $0.kind,
                    at: now
                )
            }
    }

    private var runningProjects: [RepoProject] {
        store.projects
            .filter { $0.port == .running }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        let partition = ProjectFocusPolicy.partition(projects: store.projects)
        let focused = MenuBarRemoteProject.top(in: partition, activeAIPaths: store.activeAIProjectPaths)
        let count = attentionCount(focusedPaths: copyMode == .plain ? partition.focusedPaths : nil)
        let running = runningProjects
        Group {
            if let title = MenuBarHandoff.shared.feedbackTitle {
                Text(title)
            }
            Section(FizzL10n.text("关注项目", "Followed projects")) {
                if focused.isEmpty {
                    Text(FizzL10n.text("暂无关注项目", "No followed projects"))
                }
                ForEach(focused) { item in projectMenu(item) }
            }

            Divider()
            Button(FizzL10n.text("打开总览", "Open Workbench")) {
                store.openDashboard()
                presentMainWindow()
            }
            Button(FizzL10n.text("查看全部体检", "Open Doctor")) {
                store.openCleanup()
                presentMainWindow()
            }

            if count > 0 {
                Divider()
                Section(FizzCopy.attentionTitle(copyMode)) {
                    Button(FizzL10n.text("查看 \(count) 项\(FizzCopy.attentionTitle(copyMode))", "\(FizzCopy.attentionTitle(copyMode)): \(count)")) {
                        store.openDashboard()
                        presentMainWindow()
                    }
                }
            }

            if !running.isEmpty {
                Divider()
                Section(FizzL10n.text("正在运行的服务", "Running services")) {
                    ForEach(running) { project in
                        if let port = project.run?.port, port > 0 {
                            MenuBarServiceRow {
                                SystemActions.openURL("http://127.0.0.1:\(port)")
                            } content: {
                                HStack(spacing: 8) {
                                    RunningPulseDot()
                                    Text(FizzL10n.text("打开 \(project.displayName) 预览", "Preview \(project.displayName)"))
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    Text(":\(port)")
                                        .font(FizzTypography.monoSmall)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        MenuBarServiceRow {
                            Task { await actions.stop(project, store: store, presentNotice: presentMainWindow) }
                        } content: {
                            HStack(spacing: 8) {
                                FizzIcon(.xs, symbol: "stop.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 9)
                                Text(FizzL10n.text("停止 \(project.displayName)…", "Stop \(project.displayName)…"))
                                    .lineLimit(1)
                                Spacer(minLength: 12)
                            }
                        }
                    }
                }
            }

            Divider()
            Button(FizzL10n.text("退出 FizzDeck", "Quit FizzDeck")) {
                NSApp.terminate(nil)
            }
        }
    }

    private func projectMenu(_ item: MenuBarRemoteProject) -> some View {
        let project = item.project
        return Menu(item.title) {
            if let session = item.resumableSession {
                Button(FizzL10n.text("继续最近会话 · \(HomeDashboardModel.toolTitle(session.tool))", "Resume latest session · \(HomeDashboardModel.toolTitle(session.tool))")) {
                    resume(session, for: project)
                }
            } else {
                Text(FizzL10n.text("暂无可恢复会话", "No session to resume"))
            }
            Button(FizzL10n.text("复制接力卡", "Copy Handoff card")) {
                MenuBarHandoff.shared.copy(project, copyMode: copyMode, actions: actions)
            }
            Menu(FizzL10n.text("其他接力卡", "Other Handoff cards")) {
                ForEach([HandoffCardScenario.fixError, .notes], id: \.self) { scenario in
                    Button(scenario.title) {
                        MenuBarHandoff.shared.copy(project, scenario: scenario, copyMode: copyMode, actions: actions)
                    }
                }
            }
            Divider()
            Button(FizzL10n.text("打开项目", "Open project")) {
                store.openProject(project)
                presentMainWindow()
            }
            Button(FizzL10n.text("查看体检", "View Doctor")) {
                store.openProject(project, tab: .run)
                presentMainWindow()
            }
            if let mark = MenuBarSnapshotMarkPolicy.latestCandidate(in: store.marks(for: project.path)) {
                Button(FizzL10n.text("看最近一次对话改了什么", "See what changed in the last conversation")) {
                    openRecentMark(mark, for: project)
                }
            }
        }
    }

    private func resume(_ session: SessionRecord, for project: RepoProject) {
        Task {
            let result = await SessionResumeService.resume(
                session: session,
                projectPath: project.path,
                preferredTarget: .cli
            )
            if !result.success {
                await LocalNotifications.send(
                    title: FizzL10n.text("会话恢复失败", "Couldn’t resume session"),
                    body: SecretRedactor.redact("\(project.displayName) · \(result.message)").text,
                    projectPath: project.path,
                    tab: .progress
                )
            }
        }
    }

    private func openRecentMark(_ mark: SessionMark, for project: RepoProject) {
        Task {
            let isAvailable = await SessionMarkService.isAvailable(
                mark,
                in: URL(fileURLWithPath: project.path)
            )
            guard isAvailable else {
                ToastCenter.shared.show(
                    FizzL10n.text("这次对话的改动已经找不到了", "Changes from this conversation are no longer available"),
                    symbol: "exclamationmark.triangle.fill",
                    tint: FizzTheme.statusWarning,
                    subtitle: FizzL10n.text("标记可能已被 Git 清理，可以打开进度页看当时的记录", "Git may have removed the snapshot. Open Progress to view the record.")
                )
                return
            }
            store.openProjectDiff(project: project, markID: mark.id)
            presentMainWindow()
        }
    }

    private func presentMainWindow() {
        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && $0.title == "FizzDeck"
        }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarRemoteProject: Identifiable {
    let project: RepoProject
    let isAIActive: Bool
    private let lastConversationAt: Date?

    var id: String { project.path }
    var title: String {
        let suffix = isAIActive ? FizzL10n.text(" · AI 活跃", " · AI active") : ""
        let name = SecretRedactor.redact(project.displayName).text
        let limit = 30 - suffix.count
        return (name.count > limit ? String(name.prefix(limit - 1)) + "…" : name) + suffix
    }

    var resumableSession: SessionRecord? {
        project.sessions.recentSessions.lazy.filter {
            DetectedTool(rawValue: $0.tool)?.supportsResume == true && $0.resumeCommand != nil
        }.min {
            $0.modified == $1.modified ? $0.stableID < $1.stableID : $0.modified > $1.modified
        }
    }

    static func top(in partition: FocusPartition, activeAIPaths: Set<String>) -> [Self] {
        let ranked = partition.focused.map { entry in
            let project = entry.project
            let latest = project.sessions.recentSessions.lazy.filter { $0.kind == .conversation }.map(\.modified).max()
            return Self(project: project, isAIActive: activeAIPaths.contains(project.path), lastConversationAt: latest)
        }.sorted { lhs, rhs in
            if lhs.isAIActive != rhs.isAIActive { return lhs.isAIActive }
            if lhs.lastConversationAt != rhs.lastConversationAt {
                guard let left = lhs.lastConversationAt else { return false }
                guard let right = rhs.lastConversationAt else { return true }
                return left > right
            }
            let order = lhs.project.displayName.localizedStandardCompare(rhs.project.displayName)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
        return Array(ranked.prefix(3))
    }
}

@MainActor
final class MenuBarHandoff {
    static let shared = MenuBarHandoff()
    let feedback = ToastCenter()
    private var lastCopySucceeded = false

    private var copyTitle: String {
        lastCopySucceeded ? FizzL10n.text("接力卡已复制", "Handoff card copied") : FizzL10n.text("复制失败", "Copy failed")
    }

    var feedbackTitle: String? { feedback.current == nil ? nil : copyTitle }

    func copy(
        _ project: RepoProject, scenario: HandoffCardScenario = .resume, copyMode: CopyMode, actions: ProjectActions,
        write: (String) -> Bool = SystemActions.writeClipboard
    ) {
        let failure = scenario == .fixError ? HandoffCardBuilder.managedFailure(for: project, actions: actions) : nil
        let card = HandoffCardBuilder.build(project: project, scenario: scenario, copyMode: copyMode, localFailure: failure)
        let copied = write(card.markdown)
        lastCopySucceeded = copied
        feedback.dismiss()
        feedback.show(copyTitle,
                      symbol: copied ? "doc.on.clipboard.fill" : "xmark.circle", duration: 3)
    }
}

private struct MenuBarServiceRow<Content: View>: View {
    @State private var hovering = false

    let action: () -> Void
    @ViewBuilder let content: Content

    init(
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    hovering ? FizzTheme.selectedFill.opacity(0.65) : Color.clear,
                    in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
