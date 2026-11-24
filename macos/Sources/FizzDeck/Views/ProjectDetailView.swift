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
            .padding(.bottom, showsActionDock ? 96 : 0)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .overlay(alignment: .bottom) {
                if showsActionDock {
                    ProjectActionDock(project: project)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                FizzMotion.resolved(reduceMotion, FizzMotion.panel),
                value: showsActionDock
            )
        }
        .task(id: project.path) {
            noteDraft = project.note
            let target = project.path
            loadingDetail = true
            detail = .empty
            let value = await store.detail(for: project)
            guard !Task.isCancelled, target == project.path else { return }
            detail = value
            loadingDetail = false
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
            ForEach(ProjectTab.allCases) { item in
                ToolbarItem(id: "project-tab-\(item.rawValue)", placement: .principal) {
                    projectTabButton(item)
                }
            }
        }
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var showsActionDock: Bool {
        project.run != nil || project.test != nil
    }

    private func projectTabButton(_ item: ProjectTab) -> some View {
        Button {
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                tab = item
            }
        } label: {
            Text(item.title)
                .font(.system(size: 11.5, weight: tab == item ? .semibold : .medium))
                .foregroundStyle(tab == item ? FizzTheme.accent : Color.secondary)
        }
        .help(item.title)
        .accessibilityAddTraits(tab == item ? .isSelected : [])
        .accessibilityRemoveTraits(tab == item ? [] : .isSelected)
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
    @State private var artwork: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artworkBackground

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.32),
                    .init(color: .black.opacity(0.34), location: 0.56),
                    .init(color: .black.opacity(0.88), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 5) {
                Text(project.displayName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Button {
                    SystemActions.copy(project.path)
                } label: {
                    HStack(spacing: 5) {
                        Text(PathTools.displayPath(project.path))
                            .font(.system(size: 10.5, design: .monospaced))
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8.5))
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
                .help("复制完整路径")

                FlowLayout(spacing: 6) {
                    TagChip(text: project.group, tint: accent)
                    if let branch = project.branch {
                        TagChip(text: branch, tint: .blue)
                    }
                    if project.dirtyCount > 0 {
                        TagChip(text: "\(project.dirtyCount) 个改动", tint: .orange)
                    }
                    if let tool = project.sessions.lastTool {
                        TagChip(text: tool == "codex" ? "Codex" : "Claude", tint: .purple)
                    }
                    if let test = project.test {
                        TagChip(text: test.label, tint: .green)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)

            ProjectHeroActions(project: project)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
        .task(id: project.artwork) {
            artwork = nil
            guard let path = project.artwork else {
                return
            }
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: URL(fileURLWithPath: path))
            }.value
            guard !Task.isCancelled else { return }
            artwork = data.flatMap(NSImage.init(data:))
        }
    }

    private var artworkBackground: some View {
        GeometryReader { proxy in
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    fallbackArtwork
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.44), accent.opacity(0.18), .black.opacity(0.58)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
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
                    Image(systemName: project.starred ? "star.fill" : "star")
                        .font(.system(size: 12.5, weight: .semibold))
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
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
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
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
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
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
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
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private func segmentBackground(_ action: Action) -> Color {
        hovering == action ? Color.black.opacity(0.05) : .clear
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
                Image(systemName: mode.symbol)
                    .font(.system(size: 18, weight: .semibold))
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
                Button(mode.actionTitle, role: .destructive) {
                    onConfirm(confirmation)
                }
                .buttonStyle(.borderedProminent)
                .disabled(confirmation != expectedName || blockedReason != nil)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
