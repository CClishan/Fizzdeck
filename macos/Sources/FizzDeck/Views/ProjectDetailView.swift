import AppKit
import SwiftUI

struct ProjectDetailView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject

    @State private var tab: ProjectTab = .overview
    @State private var detail: ProjectDetail = .empty
    @State private var loadingDetail = false
    @State private var noteDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            ProjectHero(project: project)
            Group {
                switch tab {
                case .overview:
                    OverviewTabView(
                        project: project,
                        noteDraft: $noteDraft,
                        saveNote: { store.setNote(noteDraft, for: project) }
                    )
                case .git:
                    GitTabView(project: project, detail: detail, loading: loadingDetail) {
                        await store.refreshGit(for: project.path)
                        await reloadDetail()
                    }
                    .id(project.path)
                case .docs:
                    DocsTabView(project: project, docs: detail.docs)
                case .sessions:
                    SessionsTabView(project: project)
                case .tests:
                    TestsTabView(project: project)
                case .cleanup:
                    CleanupTabView(project: project)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 8)
            .contentMargins(.bottom, 76, for: .scrollContent)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .overlay(alignment: .bottom) {
                HStack(spacing: 10) {
                    if showsActionDock {
                        ProjectActionDock(project: project, tab: tab)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    SessionContinueButton(project: project, style: .dock)
                }
                .padding(.horizontal, FizzSpacing.page)
                .padding(.bottom, 16)
            }
            .animation(
                FizzMotion.resolved(reduceMotion, FizzMotion.panel),
                value: showsActionDock
            )
        }
        .task(id: project.path) {
            store.startWatchingGit(for: project.path)
            noteDraft = project.note
            let target = project.path
            loadingDetail = true
            detail = .empty
            let value = await store.detail(for: project)
            guard !Task.isCancelled, target == project.path else { return }
            detail = value
            loadingDetail = false
        }
        .onDisappear {
            store.stopWatchingGit()
        }
        .onChange(of: project.note) { _, value in
            if noteDraft != value { noteDraft = value }
        }
        .onAppear {
            applyRequestedTab()
        }
        .onChange(of: store.requestedTab) {
            applyRequestedTab()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 2) {
                    ForEach(ProjectTab.allCases) { item in
                        projectTabButton(item)
                    }
                }
                .padding(2)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("项目页签")
            }
        }
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var showsActionDock: Bool {
        switch tab {
        case .overview:
            false
        case .tests:
            project.test != nil
        default:
            false
        }
    }

    private func projectTabButton(_ item: ProjectTab) -> some View {
        let selected = tab == item

        return Button {
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                tab = item
            }
        } label: {
            Text(item.title)
                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    selected ? FizzTheme.accent : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }

    private func applyRequestedTab() {
        guard let requested = store.requestedTab else { return }
        tab = requested
        Task { @MainActor in
            await Task.yield()
            if store.requestedTab == requested {
                store.requestedTab = nil
            }
        }
    }

    private func reloadDetail() async {
        let target = project.path
        let value = await store.detail(for: project)
        guard !Task.isCancelled, target == project.path else { return }
        detail = value
    }
}

private struct ProjectHero: View {
    let project: RepoProject

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ProjectBadgeIcon(project: project, size: 42, framed: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(project.displayName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if project.port == .running {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    SystemActions.copy(project.path)
                } label: {
                    HStack(spacing: 5) {
                        Text(PathTools.displayPath(project.path))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        FizzIcon(symbol: "doc.on.doc", size: 9)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制完整路径")
                .accessibilityLabel("复制项目路径")

                FlowLayout(spacing: 6) {
                    TagChip(text: project.group, tint: accent)
                    if let branch = project.branch {
                        TagChip(text: branch, tint: .blue)
                    }
                    if project.dirtyCount > 0 {
                        TagChip(text: "\(project.dirtyCount) 个改动", tint: .orange)
                    }
                    if let tool = project.sessions.lastTool {
                        TagChip(
                            text: DetectedTool(rawValue: tool)?.title ?? tool.capitalized,
                            tint: .purple
                        )
                    }
                    if let test = project.test {
                        TagChip(text: test.label, tint: .green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProjectHeroActions(project: project)
                .layoutPriority(1)
        }
        .padding(17)
        .fizzCard(radius: FizzRadius.panel)
        .padding(.horizontal, FizzSpacing.page)
        .padding(.top, FizzSpacing.row)
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }
}

private struct ProjectHeroActions: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject

    @State private var hovering: Action?
    @State private var remote: GitRemote?
    @State private var remoteResolved = false
    @State private var removalRequest: ProjectRemovalRequest?
    @State private var removalError: String?
    @State private var removalWorking = false

    private enum Action {
        case star
        case open
        case more
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                        store.toggleStar(project)
                    }
                } label: {
                    FizzIcon(symbol: project.starred ? "star.fill" : "star", size: 13)
                        .foregroundStyle(project.starred ? Color.yellow : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(segmentBackground(.star), in: segmentShape)
                        .contentShape(segmentShape)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(project.starred ? "取消星标" : "设为星标")
                .accessibilityLabel(project.starred ? "取消星标" : "设为星标")
                .onHover { hovering = $0 ? .star : nil }

                segmentDivider

                Menu {
                    ProjectQuickActions(project: project)
                } label: {
                    HStack(spacing: 3) {
                        FizzIcon(symbol: "folder", size: 12)
                        FizzIcon(symbol: "chevron.down", size: 7)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 39, height: 30)
                    .background(segmentBackground(.open), in: segmentShape)
                    .contentShape(segmentShape)
                    .accessibilityElement(children: .ignore)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("打开方式")
                .accessibilityLabel("打开方式")
                .onHover { hovering = $0 ? .open : nil }

                segmentDivider

                Menu {
                    Menu("标签颜色") {
                        Button("无标签") { store.setColor(nil, for: project) }
                        ForEach(TagColor.allCases) { color in
                            Button(color.label) { store.setColor(color, for: project) }
                        }
                    }
                    ProjectGroupingMenu(project: project)
                    Divider()
                    Button {
                        if let url = ArtworkFilePicker.pickImageURL() {
                            _ = store.setCustomArtwork(from: url, for: project)
                        }
                    } label: {
                        Label(
                            project.artwork == nil ? "上传项目截图…" : "替换项目截图…",
                            systemImage: "photo.badge.plus"
                        )
                    }
                    if project.customArtwork != nil {
                        Button {
                            store.clearCustomArtwork(for: project)
                        } label: {
                            Label("恢复自动识别截图", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Divider()
                    Button {
                        SystemActions.copy(project.path)
                    } label: {
                        Label("复制路径", systemImage: "doc.on.doc")
                    }

                    Divider()

                    if let remote {
                        if let url = remote.webURL {
                            Button {
                                SystemActions.openURL(url.absoluteString)
                            } label: {
                                Label("在浏览器中打开远程仓库", systemImage: "arrow.up.right.square")
                            }
                        }
                        Button {
                            SystemActions.copy(remote.raw)
                        } label: {
                            Label("复制远程地址", systemImage: "link")
                        }
                    } else if remoteResolved {
                        Button {} label: {
                            Label("没有远程仓库", systemImage: "link.badge.plus")
                        }
                        .disabled(true)
                    }

                    Divider()

                    Button("移入废纸篓…", role: .destructive) {
                        removalRequest = ProjectRemovalRequest(mode: .trash)
                    }
                    Button("永久删除…", role: .destructive) {
                        removalRequest = ProjectRemovalRequest(mode: .permanent)
                    }
                } label: {
                    FizzIcon(symbol: "ellipsis", size: 12)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(segmentBackground(.more), in: segmentShape)
                        .contentShape(segmentShape)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("更多")
                .accessibilityLabel("更多")
                .onHover { hovering = $0 ? .more : nil }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .fizzAdaptiveShadow(.subtle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("项目操作")
        .task(id: project.path) {
            remote = store.cachedRemote(for: project.path)
            remoteResolved = store.hasResolvedRemote(for: project.path)
            remote = await store.remote(for: project)
            remoteResolved = true
        }
        .sheet(item: $removalRequest) { request in
            ProjectRemovalSheet(
                project: project,
                mode: request.mode,
                blockedReason: removalBlockedReason,
                onCancel: { removalRequest = nil },
                onConfirm: { confirmation in
                    removalRequest = nil
                    removalWorking = true
                    Task {
                        let result = await store.removeProject(
                            project,
                            mode: request.mode,
                            confirmation: confirmation,
                            testRunning: actions.testRun(for: project.path)?.status == .running
                        )
                        removalWorking = false
                        if !result.success {
                            removalError = result.message
                        }
                    }
                }
            )
        }
        .alert(
            "无法移除项目",
            isPresented: Binding(
                get: { removalError != nil },
                set: { if !$0 { removalError = nil } }
            )
        ) {
            Button("好") { removalError = nil }
        } message: {
            Text(removalError ?? "")
        }
    }

    private var removalBlockedReason: String? {
        if removalWorking { return "正在处理移除操作。" }
        if project.port == .running { return "先停止运行中的开发服务。" }
        if actions.testRun(for: project.path)?.status == .running {
            return "先停止运行中的测试。"
        }
        if actions.isBusy(project.path) { return "正在启动或停止服务，稍后再试。" }
        return nil
    }

    private var segmentShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
    }

    private func segmentBackground(_ action: Action) -> Color {
        hovering == action ? FizzTheme.selectedFill : .clear
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(FizzTheme.hairline)
            .frame(width: 1, height: 15)
            .padding(.horizontal, 2)
    }
}

private struct ProjectRemovalRequest: Identifiable {
    let mode: ProjectRemovalMode

    var id: String { mode.rawValue }
}

private struct ProjectRemovalSheet: View {
    let project: RepoProject
    let mode: ProjectRemovalMode
    let blockedReason: String?
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var confirmation = ""

    private var expectedName: String {
        URL(fileURLWithPath: project.path).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                FizzIcon(symbol: mode.symbol, size: 18)
                    .foregroundStyle(.red)
                Text("\(mode.title) \(project.displayName)")
                    .font(.headline)
            }

            Text(mode.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let blockedReason {
                Label(blockedReason, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("输入目录名「\(expectedName)」确认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(expectedName, text: $confirmation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.glass)
                Button(mode.actionTitle, role: .destructive) {
                    onConfirm(confirmation)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .disabled(confirmation != expectedName || blockedReason != nil)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
