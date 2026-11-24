import SwiftUI

struct ProjectDetailView: View {
    @Environment(RepositoryStore.self) private var store
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
                        GitTabView(project: project, detail: detail, loading: loadingDetail)
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
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var tabPicker: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(ProjectTab.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
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
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
    }
}

private struct ProjectHero: View {
    @Environment(RepositoryStore.self) private var store
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

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        store.toggleStar(project)
                    } label: {
                        Image(systemName: project.starred ? "star.fill" : "star")
                            .foregroundStyle(project.starred ? .yellow : .secondary)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help(project.starred ? "取消星标" : "设为星标")
                    .accessibilityLabel(project.starred ? "取消星标" : "设为星标")

                    Menu {
                        Button("无标签") { store.setColor(nil, for: project) }
                        ForEach(TagColor.allCases) { color in
                            Button(color.label) { store.setColor(color, for: project) }
                        }
                    } label: {
                        Image(systemName: "tag")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("设置标签颜色")
                    .accessibilityLabel("标签颜色")

                    Button {
                        SystemActions.reveal(project.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("在 Finder 中显示")
                    .accessibilityLabel("在 Finder 中显示")
                }

                runtimeStatus
            }
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

    @ViewBuilder
    private var runtimeStatus: some View {
        if let run = project.run {
            Button {
                if project.port == .running, let url = run.previewURL {
                    SystemActions.openURL(url)
                }
            } label: {
                HStack(spacing: 6) {
                    StatusDot(state: project.port)
                    Text(verbatim: run.port > 0 ? "localhost:\(run.port)" : run.command)
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(project.port != .running)
            .help(project.port == .running ? "打开本地预览" : "端口未启动")
        } else {
            Text("未识别运行命令")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }
}
