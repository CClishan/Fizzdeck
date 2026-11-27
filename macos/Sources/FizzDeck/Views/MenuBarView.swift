import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let store: RepositoryStore
    let actions: ProjectActions

    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @State private var now = Date()

    private var attentionCount: Int {
        let focusedPaths = copyMode == .plain
            ? ProjectFocusPolicy.partition(projects: store.projects).focusedPaths
            : nil
        let items = ProjectAttentionQueue
            .items(
                projects: store.projects,
                testRuns: actions.testRuns,
                focusedPaths: focusedPaths,
                copyMode: copyMode
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
        let reports = store.doctorReports.filter { path, _ in
            guard let project = store.projects.first(where: { $0.path == path }) else {
                return false
            }
            return !store.isAttentionSuppressed(
                for: project,
                kind: .doctorCritical,
                at: now
            )
        }
        return MenuBarAttentionSummary.count(
            items: items,
            doctorReports: reports,
            focusedPaths: focusedPaths
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            FizzIcon(
                symbol: attentionCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle",
                size: 12
            )
            Text("\(attentionCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(attentionCount > 0 ? Color.red : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FizzDeck，待处理 \(attentionCount) 项")
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                now = Date()
            }
        }
    }
}

struct MenuBarMenu: View {
    let store: RepositoryStore
    let actions: ProjectActions

    @Environment(\.openWindow) private var openWindow
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    private var recentProjects: [RepoProject] {
        Array(store.projects.prefix(6))
    }

    private var attentionItems: [ProjectAttentionItem] {
        let now = Date()
        let focusedPaths = copyMode == .plain
            ? ProjectFocusPolicy.partition(projects: store.projects).focusedPaths
            : nil
        return ProjectAttentionQueue
            .items(
                projects: store.projects,
                testRuns: actions.testRuns,
                focusedPaths: focusedPaths,
                copyMode: copyMode,
                doctorReports: store.doctorReports
            )
            .filter {
                !store.isAttentionSuppressed(
                    for: $0.project,
                    kind: $0.kind,
                    at: now
                )
            }
    }

    private var activeAIProjects: [RepoProject] {
        store.projects
            .filter { store.activeAIProjectPaths.contains($0.path) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var runningProjects: [RepoProject] {
        store.projects
            .filter { $0.port == .running }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var recentSessions: [MenuBarSession] {
        var seen = Set<String>()
        return store.projects
            .flatMap { project in
                project.sessions.recentSessions.compactMap { session -> MenuBarSession? in
                    guard session.kind == .conversation,
                          session.resumeCommand != nil,
                          DetectedTool(rawValue: session.tool)?.supportsResume == true,
                          seen.insert(session.stableID).inserted
                    else { return nil }
                    return MenuBarSession(project: project, session: session)
                }
            }
            .sorted { $0.session.modified > $1.session.modified }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        Group {
            Button("打开总览") {
                show(nil)
            }
            Button("重新扫描") {
                Task { await store.scan() }
            }
            .disabled(store.phase == .scanning)

            if !activeAIProjects.isEmpty {
                Divider()
                Section("AI 正在干活") {
                    ForEach(activeAIProjects) { project in
                        Button("AI 正在 \(project.displayName) 里干活") {
                            store.openProject(project, tab: .progress)
                            presentMainWindow()
                        }
                    }
                }
            }

            if !attentionItems.isEmpty {
                Divider()
                Section(FizzCopy.attentionTitle(copyMode)) {
                    Button("查看 \(attentionItems.count) 项\(FizzCopy.attentionTitle(copyMode))") {
                        show(nil)
                    }
                }
            }

            if !runningProjects.isEmpty {
                Divider()
                Section("正在运行的服务") {
                    ForEach(runningProjects) { project in
                        if let port = project.run?.port, port > 0 {
                            MenuBarServiceRow {
                                SystemActions.openURL("http://127.0.0.1:\(port)")
                            } content: {
                                HStack(spacing: 8) {
                                    RunningPulseDot(size: 5)
                                    Text("打开 \(project.displayName) 预览")
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    Text(":\(port)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        MenuBarServiceRow {
                            Task { await actions.stop(project, store: store, presentNotice: presentMainWindow) }
                        } content: {
                            HStack(spacing: 8) {
                                FizzIcon(symbol: "stop.fill", size: 9)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 9)
                                Text("停止 \(project.displayName)…")
                                    .lineLimit(1)
                                Spacer(minLength: 12)
                            }
                        }
                    }
                }
            }

            if !recentSessions.isEmpty {
                Divider()
                Section("最近可继续的会话") {
                    ForEach(recentSessions) { item in
                        Button {
                            resume(item)
                        } label: {
                            Text(
                                "\(item.project.displayName) · "
                                    + "\(DetectedTool(rawValue: item.session.tool)?.title ?? item.session.tool)"
                                    + " · \(Format.relative(item.session.modified))"
                            )
                        }
                    }
                }
            }

            if !recentProjects.isEmpty {
                Divider()
                Section("最近项目") {
                    ForEach(recentProjects) { project in
                        Menu(project.displayName) {
                            Button("打开项目") {
                                show(project)
                            }
                            if let mark = MenuBarSnapshotMarkPolicy.latestCandidate(
                                in: store.marks(for: project.path)
                            ) {
                                Button("看最近一次对话改了什么") {
                                    openRecentMark(mark, for: project)
                                }
                            }
                            Button("复制接力卡") {
                                let result = HandoffCardBuilder.build(project: project, copyMode: copyMode)
                                SystemActions.copy(result.markdown)
                                ToastCenter.shared.show(
                                    "接力卡已复制",
                                    symbol: "doc.on.clipboard.fill",
                                    tint: FizzTheme.accent,
                                    subtitle: "\(project.displayName) · \(result.characterCount) 字"
                                )
                            }
                        }
                    }
                }
            }

            Divider()
            Button("退出 FizzDeck") {
                NSApp.terminate(nil)
            }
        }
    }

    private func resume(_ item: MenuBarSession) {
        Task {
            let result = await SessionResumeService.resume(
                session: item.session,
                projectPath: item.project.path
            )
            if !result.success {
                await LocalNotifications.send(
                    title: "会话恢复失败",
                    body: "\(item.project.displayName) · \(result.message)",
                    projectPath: item.project.path,
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
                    "这次对话的改动已经找不到了",
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    subtitle: "标记可能已被 Git 清理，可以打开进度页看当时的记录"
                )
                return
            }
            store.openProjectDiff(project: project, markID: mark.id)
            presentMainWindow()
        }
    }

    private func show(_ project: RepoProject?) {
        store.isCommandPalettePresented = false
        if let project {
            store.openProject(project)
        } else {
            store.selectedPath = RepositoryStore.homeSelection
            store.requestedTab = nil
        }
        presentMainWindow()
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

private struct MenuBarSession: Identifiable {
    let project: RepoProject
    let session: SessionRecord

    var id: String { "\(project.path):\(session.stableID)" }
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
