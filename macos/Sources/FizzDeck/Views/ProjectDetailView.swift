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
            ZStack(alignment: .top) {
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
                .padding(.top, 54)

                tabPicker
                    .padding(.top, 10)
            }
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
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var tabPicker: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(ProjectTab.allCases) { item in
                    Button {
                        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                            tab = item
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 10.5, weight: .medium))
                            Text(item.title)
                                .font(.system(size: 11.5, weight: tab == item ? .semibold : .medium))
                        }
                        .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background {
                            if tab == item {
                                Capsule()
                                    .fill(Color.white.opacity(0.92))
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                    .accessibilityRemoveTraits(tab == item ? [] : .isSelected)
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
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
            projectMark

            VStack(alignment: .leading, spacing: 5) {
                Text(project.displayName)
                    .font(.system(size: 24, weight: .semibold))
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
                    .foregroundStyle(.secondary)
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

            Spacer(minLength: 12)

            ProjectHeroActions(project: project)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var projectMark: some View {
        Text(String(project.displayName.prefix(1)))
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 46, height: 46)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(accent.opacity(0.16), lineWidth: 1)
            }
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }
}

private struct ProjectHeroActions: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject

    @State private var hovering: Action?
    @State private var remote: GitRemote?
    @State private var remoteResolved = false

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
