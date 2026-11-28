import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    @State private var query = ""
    @State private var selection = 0
    @State private var editorChoices: (path: String, editors: [ProjectEditor])?
    @State private var returnMonitor: Any?
    @State private var sessionSearchResults: [WorkbenchSearchHit] = []
    @Namespace private var selectionNamespace
    @FocusState private var searchFocused: Bool

    private var groups: [PaletteGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let actions = quickActionEntries
        let projects = projectEntries
        let commands = commandEntries

        guard !trimmed.isEmpty else {
            let recent = recentEntries(from: actions + projects + commands)
            let recentIDs = Set(recent.map(\.id))
            var groups: [PaletteGroup] = []

            if !recent.isEmpty {
                groups.append(PaletteGroup(id: "recent", title: FizzL10n.text("最近", "Recent"), entries: recent))
            }

            let visibleActions = actions.filter { !recentIDs.contains($0.id) }
            if !visibleActions.isEmpty {
                groups.append(PaletteGroup(id: "actions", title: FizzL10n.text("快捷操作", "Quick actions"), entries: visibleActions))
            }

            let visibleProjects = Array(
                projects.filter { !recentIDs.contains($0.id) }.prefix(8)
            )
            if !visibleProjects.isEmpty {
                groups.append(PaletteGroup(id: "projects", title: FizzL10n.text("项目", "Projects"), entries: visibleProjects))
            }

            let remainingCommands = commands.filter { !recentIDs.contains($0.id) }
            let visibleCommands = remainingCommands.filter(\.pinned)
                + remainingCommands.filter { !$0.pinned }
            if !visibleCommands.isEmpty {
                groups.append(PaletteGroup(id: "commands", title: FizzL10n.text("命令", "Commands"), entries: visibleCommands))
            }

            return groups
        }

        var groups: [PaletteGroup] = []

        let matchedActions = sortedMatches(actions, query: trimmed)
        if !matchedActions.isEmpty {
            groups.append(PaletteGroup(id: "actions", title: FizzL10n.text("快捷操作", "Quick actions"), entries: matchedActions))
        }

        let matchedProjects = Array(sortedMatches(projects, query: trimmed).prefix(20))
        if !matchedProjects.isEmpty {
            groups.append(PaletteGroup(id: "projects", title: FizzL10n.text("项目", "Projects"), entries: matchedProjects))
        }

        let matchedSessions = sessionEntries
        if !matchedSessions.isEmpty {
            groups.append(PaletteGroup(id: "sessions", title: FizzL10n.text("对话", "Conversations"), entries: matchedSessions))
        }

        let matchedCommands = sortedMatches(commands, query: trimmed)
        if !matchedCommands.isEmpty {
            groups.append(PaletteGroup(id: "commands", title: FizzL10n.text("命令", "Commands"), entries: matchedCommands))
        }

        return groups
    }

    private var entries: [PaletteEntry] {
        groups.flatMap(\.entries)
    }

    private func selectedIndex(in entries: [PaletteEntry]) -> Int {
        max(0, min(selection, entries.count - 1))
    }

    private var quickActionEntries: [PaletteEntry] {
        guard let project = store.selectedProject else { return [] }
        var result: [PaletteEntry] = []

        result.append(
            PaletteEntry(
                id: "action.handoff.\(project.path)",
                group: FizzL10n.text("快捷操作", "Quick actions"),
                title: FizzL10n.text("复制接力卡", "Copy Handoff card"),
                subtitle: project.displayName,
                symbol: "doc.on.clipboard",
                tint: Color.secondary,
                shortcut: nil,
                keywords: "复制接力卡 copy handoff card 交接 \(project.displayName)"
            ) {
                let card = HandoffCardBuilder.build(project: project, copyMode: copyMode)
                SystemActions.copy(card.markdown)
                ToastCenter.shared.show(
                    FizzL10n.text("接力卡已复制", "Handoff card copied"),
                    symbol: "doc.on.clipboard.fill",
                    tint: Color.secondary,
                    subtitle: FizzL10n.text("\(card.characterCount) 字", SessionSummaryText.englishCount(card.characterCount, "character"))
                )
            }
        )

        if let resumable = resumableSession(for: project) {
            result.append(
                PaletteEntry(
                    id: "action.continue.\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: FizzL10n.text("接着做", "Continue work"),
                    subtitle: "\(project.displayName) · \(HomeDashboardModel.toolTitle(resumable.tool))",
                    symbol: "play.fill",
                    tint: .secondary,
                    shortcut: nil,
                    keywords: "接着做 继续 continue work resume \(project.displayName)"
                ) {
                    Task {
                        let res = await SessionResumeService.resume(session: resumable, projectPath: project.path)
                        if !res.success {
                            if let fallback = res.fallbackCommand { SystemActions.copy(fallback) }
                            ToastCenter.shared.show(
                                res.message,
                                symbol: "exclamationmark.triangle.fill",
                                tint: FizzTheme.statusWarning,
                                subtitle: res.fallbackCommand != nil ? FizzL10n.text("已复制命令到剪贴板", "Command copied to the clipboard") : nil
                            )
                        }
                    }
                }
            )
        }

        if let latestMark = store.marks(for: project.path).first(where: { $0.kind == .gitSnapshot }) {
            result.append(
                PaletteEntry(
                    id: "action.diff.\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: FizzL10n.text("看改了什么", "See what changed"),
                    subtitle: project.displayName,
                    symbol: "doc.text.magnifyingglass",
                    tint: Color.secondary,
                    shortcut: nil,
                    keywords: "看改了什么 see what changed changes diff restore compare mark 还原 对比 标记 \(project.displayName)"
                ) {
                    store.openProjectDiff(project: project, markID: latestMark.id)
                }
            )
        }

        if project.dirtyCount > 0 {
            result.append(
                PaletteEntry(
                    id: "action.saveVersion.\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: FizzCopy.commitAction(copyMode).text,
                    subtitle: FizzL10n.text("\(project.displayName) · \(project.dirtyCount) 个未保存改动", "\(project.displayName) · \(project.dirtyCount) unsaved \(project.dirtyCount == 1 ? "change" : "changes")"),
                    symbol: "bookmark.circle",
                    tint: Color.secondary,
                    shortcut: nil,
                    keywords: "存个版本 提交 commit save version \(project.displayName)"
                ) {
                    store.openProjectSaveVersion(project: project)
                }
            )
        }

        result.append(
            PaletteEntry(
                id: "action.terminal.\(project.path)",
                group: FizzL10n.text("快捷操作", "Quick actions"),
                title: FizzL10n.text("在终端中打开", "Open in Terminal"),
                subtitle: project.displayName,
                symbol: "terminal",
                tint: .secondary,
                shortcut: nil,
                keywords: "在终端中打开 open in terminal iterm ghostty warp shell 命令行"
            ) {
                SystemActions.openTerminal(project.path)
            }
        )

        result.append(
            PaletteEntry(
                id: "action.finder.\(project.path)",
                group: FizzL10n.text("快捷操作", "Quick actions"),
                title: FizzL10n.text("在 Finder 中显示", "Show in Finder"),
                subtitle: project.displayName,
                symbol: "folder",
                tint: Color.secondary,
                shortcut: nil,
                keywords: "在 Finder 中显示 目录 文件 show in finder reveal file folder"
            ) {
                SystemActions.reveal(project.path)
            }
        )

        let editors = editorChoices?.path == project.path ? editorChoices?.editors ?? [] : []
        for editor in editors {
            result.append(
                PaletteEntry(
                    id: "action.editor.\(editor.rawValue).\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: FizzL10n.text("用 \(editor.title) 打开", "Open in \(editor.title)"),
                    subtitle: project.displayName,
                    symbol: "chevron.left.forwardslash.chevron.right",
                    tint: Color.secondary,
                    shortcut: nil,
                    keywords: "用 打开 编辑器 open in editor IDE \(editor.title.lowercased())"
                ) {
                    SystemActions.open(project.path, in: editor)
                }
            )
        }

        if let run = project.run {
            let isRunning = project.port == .running
            result.append(
                PaletteEntry(
                    id: "action.server.\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: isRunning ? FizzL10n.text("停止开发服务…", "Stop dev server…") : FizzL10n.text("启动开发服务", "Start dev server"),
                    subtitle: "\(project.displayName) · \(run.command)",
                    symbol: isRunning ? "stop.fill" : "play.fill",
                    tint: .secondary,
                    shortcut: nil,
                    keywords: "启动开发服务 停止开发服务 端口 start stop dev server port"
                ) {
                    Task {
                        if isRunning {
                            await actions.stop(project, store: store)
                        } else {
                            await actions.launch(project, store: store)
                        }
                    }
                }
            )
        }

        if project.test != nil {
            result.append(
                PaletteEntry(
                    id: "action.test.\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: FizzL10n.text("运行测试", "Run tests"),
                    subtitle: project.displayName,
                    symbol: "checkmark.shield",
                    tint: Color.secondary,
                    shortcut: nil,
                    keywords: "运行测试 run tests 检查 check"
                ) {
                    actions.runTests(project, store: store)
                }
            )
        }

        if let tool = project.sessions.lastTool,
           let id = project.sessions.lastSessionID,
           let session = project.sessions.recentSessions.first(where: { $0.tool == tool && $0.id == id }) {
            let toolLabel = HomeDashboardModel.toolTitle(tool)
            if DetectedTool(rawValue: tool)?.supportsResume == true {
                result.append(
                    PaletteEntry(
                        id: "action.continue.\(project.path)",
                        group: FizzL10n.text("快捷操作", "Quick actions"),
                        title: FizzL10n.text("继续最近会话", "Resume latest session"),
                        subtitle: "\(project.displayName) · \(toolLabel)",
                        symbol: "play.fill",
                        tint: Color.secondary,
                        shortcut: nil,
                        keywords: "继续最近会话 resume latest session codex claude"
                    ) {
                        Task {
                            _ = await SessionResumeService.resume(session: session, projectPath: project.path)
                        }
                    }
                )
            }
            if let command = session.resumeCommand {
                result.append(
                    PaletteEntry(
                        id: "action.resume.\(project.path)",
                        group: FizzL10n.text("快捷操作", "Quick actions"),
                        title: FizzL10n.text("复制 AI 恢复命令", "Copy resume command"),
                        subtitle: "\(project.displayName) · \(toolLabel)",
                        symbol: "doc.on.doc",
                        tint: Color.secondary,
                        shortcut: nil,
                        keywords: "复制 AI 恢复命令 会话 copy resume command codex claude"
                    ) {
                        SystemActions.copy(command)
                    }
                )
            }
        }

        if let remote = store.cachedRemote(for: project.path) {
            if let url = remote.webURL {
                result.append(
                    PaletteEntry(
                        id: "action.remote.open.\(project.path)",
                        group: FizzL10n.text("快捷操作", "Quick actions"),
                        title: FizzL10n.text("在浏览器中打开远程仓库", "Open remote repository in browser"),
                        subtitle: remote.raw,
                        symbol: "arrow.up.right.square",
                        tint: Color.secondary,
                        shortcut: nil,
                        keywords: "在浏览器中打开远程仓库 open remote repository in browser origin \(url.absoluteString)"
                    ) {
                        SystemActions.openURL(url.absoluteString)
                    }
                )
            }

            result.append(
                PaletteEntry(
                    id: "action.remote.copy.\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: FizzL10n.text("复制远程地址", "Copy remote URL"),
                    subtitle: remote.raw,
                    symbol: "link",
                    tint: Color.secondary,
                    shortcut: nil,
                    keywords: "复制远程地址 copy remote url origin"
                ) {
                    SystemActions.copy(remote.raw)
                }
            )
        } else if store.hasResolvedRemote(for: project.path) {
            result.append(
                PaletteEntry(
                    id: "action.remote.missing.\(project.path)",
                    group: FizzL10n.text("快捷操作", "Quick actions"),
                    title: FizzL10n.text("没有远程仓库", "No remote repository"),
                    subtitle: FizzL10n.text("在 Git 中设置 origin 后可打开", "Set an origin remote in Git to open it here."),
                    symbol: "link.badge.plus",
                    tint: .secondary,
                    shortcut: nil,
                    keywords: "没有远程仓库 未配置 no remote repository origin missing unconfigured",
                    isEnabled: false
                ) {}
            )
        }

        return result
    }

    private var projectEntries: [PaletteEntry] {
        store.projects.map { project in
            let subtitle = [
                PathTools.displayPath(project.path),
                project.branch,
                project.groupTitle,
            ].compactMap { $0 }.joined(separator: " · ")

            return PaletteEntry(
                id: "project.\(project.path)",
                group: FizzL10n.text("项目", "Projects"),
                title: project.displayName,
                subtitle: subtitle,
                symbol: "folder.fill",
                tint: project.color?.color ?? ProjectGrouping.color(for: project.group),
                shortcut: nil,
                keywords: projectKeywords(project)
            ) {
                store.openProject(project)
            }
        }
    }

    private var commandEntries: [PaletteEntry] {
        var result: [PaletteEntry] = [
            PaletteEntry(
                id: "command.home",
                group: FizzL10n.text("命令", "Commands"),
                title: FizzL10n.text("打开总览", "Open Workbench"),
                subtitle: FizzL10n.text("项目总览", "Project overview"),
                symbol: "square.grid.2x2",
                tint: Color.secondary,
                shortcut: "⌘0",
                keywords: "首页 打开总览 工作台 open workbench home dashboard overview",
                pinned: true
            ) {
                store.selectedPath = RepositoryStore.homeSelection
            },
            PaletteEntry(
                id: "command.rescan",
                group: FizzL10n.text("命令", "Commands"),
                title: FizzL10n.text("重新扫描项目", "Rescan projects"),
                subtitle: FizzL10n.text("更新 Git、体积和运行状态", "Refresh Git status, project sizes, and running services"),
                symbol: "arrow.clockwise",
                tint: Color.secondary,
                shortcut: "⌘R",
                keywords: "重新扫描项目 刷新 rescan projects refresh scan",
                pinned: true
            ) {
                Task { await store.scan() }
            },
            PaletteEntry(
                id: "command.conversations",
                group: FizzL10n.text("命令", "Commands"),
                title: FizzL10n.text("打开对话", "Open Conversations"),
                subtitle: FizzL10n.text("跨项目 AI 对话时间线", "AI conversations across projects"),
                symbol: "bubble.left.and.bubble.right",
                tint: Color.secondary,
                shortcut: nil,
                keywords: "打开对话 会话 open conversations sessions"
            ) {
                store.openConversations()
            },
            PaletteEntry(
                id: "command.add",
                group: FizzL10n.text("命令", "Commands"),
                title: FizzL10n.text("管理项目文件夹", "Manage project folders"),
                subtitle: FizzL10n.text("查看文件夹或扫描新的父目录", "View folders or scan a new parent folder"),
                symbol: "plus",
                tint: .secondary,
                shortcut: nil,
                keywords: "管理项目文件夹 新增 导入 manage project folders add import"
            ) {
                Task { await store.addRoot() }
            }
        ]

        if let project = store.selectedProject {
            let starTitle = copyMode == .plain
                ? (project.starred ? FizzL10n.text("取消关注当前项目", "Unfollow this project") : FizzL10n.text("关注当前项目", "Follow this project"))
                : (project.starred ? FizzL10n.text("取消当前项目星标", "Unstar this project") : FizzL10n.text("收藏当前项目", "Star this project"))
            result.append(
                PaletteEntry(
                    id: "command.star.\(project.path)",
                    group: FizzL10n.text("命令", "Commands"),
                    title: starTitle,
                    subtitle: project.displayName,
                    symbol: project.starred ? "star.slash" : "star",
                    tint: Color.secondary,
                    shortcut: nil,
                    keywords: "取消关注当前项目 关注当前项目 取消当前项目星标 收藏当前项目 star unstar follow unfollow project focus"
                ) {
                    store.toggleStar(project)
                }
            )
        }

        let focused = ProjectFocusPolicy.partition(projects: store.projects).focused
        for entry in focused {
            let project = entry.project
            result.append(
                PaletteEntry(
                    id: "command.handoff.\(project.path)",
                    group: FizzL10n.text("命令", "Commands"),
                    title: FizzL10n.text("复制接力卡 · \(project.displayName)", "Copy Handoff card · \(project.displayName)"),
                    subtitle: PathTools.displayPath(project.path),
                    symbol: "doc.on.clipboard",
                    tint: Color.secondary,
                    shortcut: nil,
                    keywords: "复制接力卡 copy handoff card \(project.displayName)"
                ) {
                    let card = HandoffCardBuilder.build(project: project, copyMode: copyMode)
                    SystemActions.copy(card.markdown)
                    ToastCenter.shared.show(
                        FizzL10n.text("接力卡已复制", "Handoff card copied"),
                        symbol: "doc.on.clipboard.fill",
                        tint: Color.secondary,
                        subtitle: FizzL10n.text("\(project.displayName) · \(card.characterCount) 字", "\(project.displayName) · \(SessionSummaryText.englishCount(card.characterCount, "character"))")
                    )
                }
            )
            if let resumable = resumableSession(for: project) {
                result.append(
                    PaletteEntry(
                        id: "command.continue.\(project.path)",
                        group: FizzL10n.text("命令", "Commands"),
                        title: FizzL10n.text("接着做 · \(project.displayName)", "Continue work · \(project.displayName)"),
                        subtitle: HomeDashboardModel.toolTitle(resumable.tool),
                        symbol: "play.fill",
                        tint: .secondary,
                        shortcut: nil,
                        keywords: "接着做 继续 continue work resume \(project.displayName)"
                    ) {
                        Task {
                            let res = await SessionResumeService.resume(session: resumable, projectPath: project.path)
                            if !res.success {
                                if let fallback = res.fallbackCommand { SystemActions.copy(fallback) }
                                ToastCenter.shared.show(
                                    res.message,
                                    symbol: "exclamationmark.triangle.fill",
                                    tint: FizzTheme.statusWarning,
                                    subtitle: res.fallbackCommand != nil ? FizzL10n.text("已复制命令到剪贴板", "Command copied to the clipboard") : nil
                                )
                            }
                        }
                    }
                )
            }
        }

        return result
    }

    private func resumableSession(for project: RepoProject) -> SessionRecord? {
        project.sessions.recentSessions
            .filter {
                $0.kind == .conversation
                    && $0.resumeCommand != nil
                    && DetectedTool(rawValue: $0.tool)?.supportsResume == true
            }
            .max { $0.modified < $1.modified }
    }

    var body: some View {
        let groups = self.groups
        let entries = groups.flatMap(\.entries)
        let index = selectedIndex(in: entries)

        ZStack(alignment: .top) {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.30)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 0) {
                searchField

                Divider()
                    .opacity(0.55)

                if entries.isEmpty {
                    emptyState
                } else {
                    results(entries, groupSizes: groups.map(\.entries.count))
                }

                Divider()
                    .opacity(0.45)

                footer(canExecute: entries.indices.contains(index) && entries[index].isEnabled)
            }
            .frame(width: 620)
            .background(
                FizzTheme.elevatedFill.opacity(colorScheme == .dark ? 0.97 : 0.92),
                in: RoundedRectangle(cornerRadius: FizzRadius.frame, style: .continuous)
            )
            .glassEffect(
                .regular.tint(FizzTheme.elevatedFill.opacity(colorScheme == .dark ? 0.18 : 0.14)),
                in: RoundedRectangle(cornerRadius: FizzRadius.frame, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: FizzRadius.frame, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.frame, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : FizzTheme.stroke,
                        lineWidth: 1
                    )
            }
            .fizzAdaptiveShadow(.floating)
            .padding(.top, 88)
        }
        .onAppear {
            installReturnMonitor()
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
        .onDisappear {
            removeReturnMonitor()
        }
        .onChange(of: query) {
            selection = 0
        }
        .onChange(of: entries.count) { _, count in
            if selection >= count {
                selection = max(0, count - 1)
            }
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !hasMarkedText else { return .ignored }
            runSelected()
            return .handled
        }
        .onExitCommand(perform: dismiss)
        .task(id: store.selectedProject?.path) {
            guard let path = store.selectedProject?.path else { editorChoices = nil; return }
            let editors = await Task.detached(priority: .utility) { ProjectEditor.available(for: path) }.value
            if !Task.isCancelled { editorChoices = (path, editors) }
        }
        .task {
            await store.loadRemotes(for: store.projects)
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                sessionSearchResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let hits = await store.searchSessions(query: trimmed, limit: 8)
            guard !Task.isCancelled else { return }
            sessionSearchResults = WorkbenchSearchHit.make(hits, query: trimmed)
        }
    }

    private var sessionEntries: [PaletteEntry] {
        sessionSearchResults.compactMap { hit in
            let result = hit.result
            guard let project = store.projects.first(where: { $0.path == result.projectPath }) else {
                return nil
            }
            let toolTitle = HomeDashboardModel.toolTitle(result.tool)
            var subtitleParts = [
                result.projectName,
                toolTitle,
                Format.relative(result.modified),
            ]
            if let snippet = hit.snippet, !snippet.isEmpty {
                subtitleParts.append(snippet)
            }
            return PaletteEntry(
                id: "session.\(result.id)",
                group: FizzL10n.text("对话", "Conversations"),
                title: FizzL10n.text("「\(hit.title)」", "“\(hit.title)”"),
                subtitle: subtitleParts.joined(separator: " · "),
                symbol: result.endedWithError ? "exclamationmark.triangle" : "bubble.left.and.bubble.right",
                tint: result.endedWithError ? FizzTheme.statusWarning : Color.secondary,
                shortcut: nil,
                keywords: "\(result.projectName) \(result.primaryIntent) \(result.touchedFilesText)"
            ) {
                store.openProject(project, tab: .progress, sessionID: result.sessionID)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: FizzSpacing.row) {
            FizzIcon(.md, symbol: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(FizzL10n.text("搜索项目、对话、分支或快捷操作", "Search projects, conversations, branches, or actions"), text: $query)
                .textFieldStyle(.plain)
                .font(FizzTypography.sectionTitle(.regular))
                .focused($searchFocused)
                .onSubmit {
                    runSelected()
                }

            if !query.isEmpty {
                FizzIconButton(title: FizzL10n.text("清除搜索", "Clear search"), symbol: "xmark.circle.fill", height: .compact) {
                    query = ""
                    searchFocused = true
                }
            }

            Text("⌘K")
                .font(FizzTypography.monoSmall(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous))

            FizzIconButton(title: FizzL10n.text("关闭命令面板", "Close command palette"), symbol: "xmark", height: .compact, action: dismiss)
        }
        .padding(.horizontal, FizzSpacing.page)
        .frame(height: 52)
    }

    private func results(_ entries: [PaletteEntry], groupSizes: [Int]) -> some View {
        let selectedIndex = selectedIndex(in: entries)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index == 0 || entries[index - 1].group != entry.group {
                            sectionHeader(entry.group)
                        }

                        paletteRow(entry, selected: index == selectedIndex)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, FizzSpacing.row)
                .padding(.vertical, CommandPaletteLayout.contentPadding / 2)
                .animation(
                    FizzMotion.resolved(reduceMotion, FizzMotion.quick),
                    value: selectedIndex
                )
            }
            .frame(height: CommandPaletteLayout.resultsHeight(groupSizes: groupSizes))
            .onChange(of: selectedIndex) {
                guard entries.indices.contains(selectedIndex) else { return }
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                    proxy.scrollTo(entries[selectedIndex].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: FizzSpacing.row) {
            FizzIcon(.lg, symbol: "magnifyingglass")
                .foregroundStyle(.tertiary)
            Text(FizzL10n.text("没有匹配结果", "No matches"))
                .font(FizzTypography.body(.medium))
            Text(FizzL10n.text("试试项目名、路径、分支、远程或动作", "Try a project name, path, branch, remote, or action."))
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private func footer(canExecute: Bool) -> some View {
        FizzSheetFooter {
            HStack(spacing: FizzSpacing.grid) {
                hint("↑↓", FizzL10n.text("选择", "Select"))
                hint("↵", FizzL10n.text("执行", "Run"))
                hint("esc", FizzL10n.text("关闭", "Close"))
            }
            Spacer(minLength: 0)

            FizzActionButton(title: FizzL10n.text("执行所选", "Run selected"), prominence: .primary, action: runSelected)
                .disabled(!canExecute)
        }
        .padding(.horizontal, FizzSpacing.page)
        .padding(.vertical, FizzSpacing.row)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(FizzTypography.monoSmall(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous))
            Text(title)
                .font(FizzTypography.micro)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(FizzTypography.micro)
                .foregroundStyle(.tertiary)
                .frame(height: CommandPaletteLayout.sectionTextHeight, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FizzSpacing.row)
        .padding(.top, CommandPaletteLayout.sectionTopPadding)
        .padding(.bottom, CommandPaletteLayout.sectionBottomPadding)
    }

    private func paletteRow(_ entry: PaletteEntry, selected: Bool) -> some View {
        Button {
            selection = entries.firstIndex(where: { $0.id == entry.id }) ?? selection
            execute(entry)
        } label: {
            HStack(spacing: FizzSpacing.row) {
                FizzIcon(.md, symbol: entry.symbol)
                    .foregroundStyle(entry.tint)
                    .frame(width: FizzControlHeight.compact.rawValue, height: FizzControlHeight.standard.rawValue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(FizzTypography.body(selected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: FizzSpacing.row)

                if let shortcut = entry.shortcut {
                    Text(shortcut)
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous))
                }
            }
            .padding(.horizontal, FizzSpacing.row)
            .frame(height: CommandPaletteLayout.rowHeight)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .fill(FizzTheme.selectedFill)
                        .matchedGeometryEffect(id: "palette-selection", in: selectionNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(!entry.isEnabled)
        .opacity(entry.isEnabled ? 1 : 0.55)
    }

    private func recentEntries(from base: [PaletteEntry]) -> [PaletteEntry] {
        let byID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [PaletteEntry] = []
        var seen = Set<String>()
        let selectedPath = store.selectedProject?.path

        for id in store.recentActionIDs {
            guard let entry = byID[id], entry.isEnabled, seen.insert(entry.id).inserted else { continue }
            result.append(entry.inGroup(FizzL10n.text("最近", "Recent")))
            if result.count == 3 { break }
        }

        for path in store.recentProjectPaths where path != selectedPath {
            guard let entry = byID["project.\(path)"],
                  entry.isEnabled,
                  seen.insert(entry.id).inserted
            else { continue }
            result.append(entry.inGroup(FizzL10n.text("最近", "Recent")))
            if result.count == 5 { break }
        }

        return result
    }

    private func sortedMatches(_ entries: [PaletteEntry], query: String) -> [PaletteEntry] {
        entries
            .compactMap { entry -> (PaletteEntry, Int)? in
                guard let score = entry.matchScore(query) else { return nil }
                return (entry, score)
            }
            .sorted { lhs, rhs in
                if lhs.0.pinned != rhs.0.pinned { return lhs.0.pinned }
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.title.localizedStandardCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)
    }

    private func projectKeywords(_ project: RepoProject) -> String {
        let stacks = project.stacks.flatMap { $0.items + $0.displayItems }.joined(separator: " ")
        let remote = store.cachedRemote(for: project.path)
        return [
            project.displayName,
            project.name,
            project.path,
            project.branch ?? "",
            project.group,
            stacks,
            project.sessions.detected.joined(separator: " "),
            remote?.raw ?? "",
            remote?.webURL?.absoluteString ?? "",
        ].joined(separator: " ")
    }

    private func moveSelection(_ delta: Int) {
        let entries = self.entries
        guard !entries.isEmpty else { return }
        var index = selectedIndex(in: entries)
        for _ in entries.indices {
            index = (index + delta + entries.count) % entries.count
            if entries[index].isEnabled {
                selection = index
                return
            }
        }
    }

    private func runSelected() {
        let entries = self.entries
        let index = selectedIndex(in: entries)
        guard entries.indices.contains(index) else { return }
        execute(entries[index])
    }

    private var hasMarkedText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private func installReturnMonitor() {
        guard returnMonitor == nil else { return }
        returnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            guard keyCode == 36 || keyCode == 76 else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.isEmpty else { return event }
            guard !hasMarkedText else { return event }
            runSelected()
            return nil
        }
    }

    private func removeReturnMonitor() {
        guard let returnMonitor else { return }
        NSEvent.removeMonitor(returnMonitor)
        self.returnMonitor = nil
    }

    private func execute(_ entry: PaletteEntry) {
        guard entry.isEnabled else { return }
        dismiss()
        store.recordPaletteAction(entry.id)
        entry.action()
    }

    private func dismiss() {
        store.isCommandPalettePresented = false
    }
}

private struct PaletteGroup: Identifiable {
    let id: String
    let title: String
    let entries: [PaletteEntry]
}

private struct PaletteEntry: Identifiable {
    let id: String
    let group: String
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    let shortcut: String?
    let keywords: String
    var isEnabled = true
    var pinned = false
    let action: () -> Void

    func matchScore(_ query: String) -> Int? {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return 0 }
        var total = 0
        for token in tokens {
            guard let score = PaletteMatcher.score(token, in: searchText) else { return nil }
            total += score
        }
        return total
    }

    func inGroup(_ title: String) -> PaletteEntry {
        PaletteEntry(
            id: id,
            group: title,
            title: self.title,
            subtitle: subtitle,
            symbol: symbol,
            tint: tint,
            shortcut: shortcut,
            keywords: keywords,
            isEnabled: isEnabled,
            pinned: pinned,
            action: action
        )
    }

    private var searchText: String {
        [title, subtitle ?? "", keywords].joined(separator: " ")
    }
}

private enum PaletteMatcher {
    static func score(_ query: String, in text: String) -> Int? {
        let needle = normalized(query)
        let haystack = normalized(text)
        guard !needle.isEmpty else { return 0 }

        if let range = haystack.range(of: needle) {
            let distance = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            return 200 - min(distance, 120) + (range.lowerBound == haystack.startIndex ? 40 : 0)
        }

        var searchStart = haystack.startIndex
        var previous: String.Index?
        var score = 0
        for character in needle {
            guard let index = haystack[searchStart...].firstIndex(of: character) else { return nil }
            if let previous {
                score += haystack.index(after: previous) == index ? 12 : 3
            } else {
                score += 8
            }

            if index == haystack.startIndex {
                score += 6
            } else {
                let before = haystack[haystack.index(before: index)]
                if before == " " || before == "/" || before == "-" || before == "." || before == ":" {
                    score += 5
                }
            }

            score += max(0, 6 - haystack.distance(from: haystack.startIndex, to: index) / 10)
            previous = index
            searchStart = haystack.index(after: index)
        }
        return score
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: FizzL10n.locale
        )
    }
}
