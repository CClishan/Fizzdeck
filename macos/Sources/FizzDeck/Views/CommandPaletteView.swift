import SwiftUI

struct CommandPaletteView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var selection = 0
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
                groups.append(PaletteGroup(id: "recent", title: "最近", entries: recent))
            }

            let visibleActions = actions.filter { !recentIDs.contains($0.id) }
            if !visibleActions.isEmpty {
                groups.append(PaletteGroup(id: "actions", title: "快捷操作", entries: visibleActions))
            }

            let visibleProjects = Array(
                projects.filter { !recentIDs.contains($0.id) }.prefix(8)
            )
            if !visibleProjects.isEmpty {
                groups.append(PaletteGroup(id: "projects", title: "项目", entries: visibleProjects))
            }

            let remainingCommands = commands.filter { !recentIDs.contains($0.id) }
            let visibleCommands = remainingCommands.filter(\.pinned)
                + remainingCommands.filter { !$0.pinned }
            if !visibleCommands.isEmpty {
                groups.append(PaletteGroup(id: "commands", title: "命令", entries: visibleCommands))
            }

            return groups
        }

        var groups: [PaletteGroup] = []

        let matchedActions = sortedMatches(actions, query: trimmed)
        if !matchedActions.isEmpty {
            groups.append(PaletteGroup(id: "actions", title: "快捷操作", entries: matchedActions))
        }

        let matchedProjects = Array(sortedMatches(projects, query: trimmed).prefix(20))
        if !matchedProjects.isEmpty {
            groups.append(PaletteGroup(id: "projects", title: "项目", entries: matchedProjects))
        }

        let matchedCommands = sortedMatches(commands, query: trimmed)
        if !matchedCommands.isEmpty {
            groups.append(PaletteGroup(id: "commands", title: "命令", entries: matchedCommands))
        }

        return groups
    }

    private var entries: [PaletteEntry] {
        groups.flatMap(\.entries)
    }

    private var selectedIndex: Int {
        guard !entries.isEmpty else { return 0 }
        return min(selection, entries.count - 1)
    }

    private var quickActionEntries: [PaletteEntry] {
        guard let project = store.selectedProject else { return [] }
        var result: [PaletteEntry] = []

        result.append(
            PaletteEntry(
                id: "action.terminal.\(project.path)",
                group: "快捷操作",
                title: "在 Terminal 中打开",
                subtitle: project.displayName,
                symbol: "terminal",
                tint: .green,
                shortcut: nil,
                keywords: "终端 shell 命令行"
            ) {
                SystemActions.openTerminal(project.path)
            }
        )

        result.append(
            PaletteEntry(
                id: "action.finder.\(project.path)",
                group: "快捷操作",
                title: "在 Finder 中显示",
                subtitle: project.displayName,
                symbol: "folder",
                tint: .blue,
                shortcut: nil,
                keywords: "目录 文件"
            ) {
                SystemActions.reveal(project.path)
            }
        )

        for editor in ProjectEditor.available(for: project.path) {
            result.append(
                PaletteEntry(
                    id: "action.editor.\(editor.rawValue).\(project.path)",
                    group: "快捷操作",
                    title: "用 \(editor.title) 打开",
                    subtitle: project.displayName,
                    symbol: "chevron.left.forwardslash.chevron.right",
                    tint: .indigo,
                    shortcut: nil,
                    keywords: "编辑器 IDE \(editor.title.lowercased())"
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
                    group: "快捷操作",
                    title: isRunning ? "停止开发服务" : "启动开发服务",
                    subtitle: "\(project.displayName) · \(run.command)",
                    symbol: isRunning ? "stop.fill" : "play.fill",
                    tint: isRunning ? .red : .green,
                    shortcut: nil,
                    keywords: "服务 端口 启动 停止 dev server"
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
                    group: "快捷操作",
                    title: "运行测试",
                    subtitle: project.displayName,
                    symbol: "checkmark.shield",
                    tint: .teal,
                    shortcut: nil,
                    keywords: "test 检查 check"
                ) {
                    actions.runTests(project, store: store)
                }
            )
        }

        if let tool = project.sessions.lastTool,
           let id = project.sessions.lastSessionID {
            let command = tool == "codex" ? "codex resume \(id)" : "claude --resume \(id)"
            result.append(
                PaletteEntry(
                    id: "action.resume.\(project.path)",
                    group: "快捷操作",
                    title: "复制 AI 恢复命令",
                    subtitle: "\(project.displayName) · \(tool == "codex" ? "Codex" : "Claude Code")",
                    symbol: "bubble.left.and.bubble.right",
                    tint: .purple,
                    shortcut: nil,
                    keywords: "会话 resume codex claude"
                ) {
                    SystemActions.copy(command)
                }
            )
        }

        if let remote = store.cachedRemote(for: project.path) {
            if let url = remote.webURL {
                result.append(
                    PaletteEntry(
                        id: "action.remote.open.\(project.path)",
                        group: "快捷操作",
                        title: "在浏览器中打开远程仓库",
                        subtitle: remote.raw,
                        symbol: "arrow.up.right.square",
                        tint: .blue,
                        shortcut: nil,
                        keywords: "远程 remote origin 仓库 browser \(url.absoluteString)"
                    ) {
                        SystemActions.openURL(url.absoluteString)
                    }
                )
            }

            result.append(
                PaletteEntry(
                    id: "action.remote.copy.\(project.path)",
                    group: "快捷操作",
                    title: "复制远程地址",
                    subtitle: remote.raw,
                    symbol: "link",
                    tint: .teal,
                    shortcut: nil,
                    keywords: "远程 remote origin 地址 url"
                ) {
                    SystemActions.copy(remote.raw)
                }
            )
        } else if store.hasResolvedRemote(for: project.path) {
            result.append(
                PaletteEntry(
                    id: "action.remote.missing.\(project.path)",
                    group: "快捷操作",
                    title: "没有远程仓库",
                    subtitle: "在 Git 中设置 origin 后可打开",
                    symbol: "link.badge.plus",
                    tint: .secondary,
                    shortcut: nil,
                    keywords: "远程 remote origin 未配置",
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
                project.group,
            ].compactMap { $0 }.joined(separator: " · ")

            return PaletteEntry(
                id: "project.\(project.path)",
                group: "项目",
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
                group: "命令",
                title: "打开总览",
                subtitle: "项目总览",
                symbol: "square.grid.2x2",
                tint: FizzTheme.accent,
                shortcut: "⌘0",
                keywords: "首页 home dashboard",
                pinned: true
            ) {
                store.selectedPath = RepositoryStore.homeSelection
            },
            PaletteEntry(
                id: "command.rescan",
                group: "命令",
                title: "重新扫描项目",
                subtitle: "更新 Git、体积和运行状态",
                symbol: "arrow.clockwise",
                tint: .blue,
                shortcut: "⌘R",
                keywords: "刷新 refresh scan",
                pinned: true
            ) {
                Task { await store.scan() }
            },
            PaletteEntry(
                id: "command.add",
                group: "命令",
                title: "添加项目目录",
                subtitle: "选择一个目录加入看板",
                symbol: "plus",
                tint: .green,
                shortcut: nil,
                keywords: "新增 导入 folder"
            ) {
                Task { await store.addRoot() }
            }
        ]

        if let project = store.selectedProject {
            result.append(
                PaletteEntry(
                    id: "command.star.\(project.path)",
                    group: "命令",
                    title: project.starred ? "取消当前项目星标" : "收藏当前项目",
                    subtitle: project.displayName,
                    symbol: project.starred ? "star.slash" : "star",
                    tint: .yellow,
                    shortcut: nil,
                    keywords: "星标 收藏 star"
                ) {
                    store.toggleStar(project)
                }
            )
        }

        return result
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 0) {
                searchField

                Divider()
                    .opacity(0.55)

                if entries.isEmpty {
                    emptyState
                } else {
                    results
                }

                Divider()
                    .opacity(0.45)

                keyboardHints
            }
            .frame(width: 620)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.thickMaterial)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.58), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 34, y: 16)
            .padding(.top, 88)
        }
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
            }
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
        .onExitCommand(perform: dismiss)
        .task {
            await store.loadRemotes(for: store.projects)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索项目、分支、远程或动作", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit {
                    runSelected()
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }

            Text("⌘K")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var results: some View {
        ScrollViewReader { proxy in
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
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
            }
            .frame(height: resultsHeight)
            .onChange(of: selectedIndex) {
                guard entries.indices.contains(selectedIndex) else { return }
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                    proxy.scrollTo(entries[selectedIndex].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text("没有匹配结果")
                .font(.system(size: 12.5, weight: .medium))
            Text("试试项目名、路径、分支、远程或动作")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private var resultsHeight: CGFloat {
        min(420, CGFloat(entries.count) * 43 + CGFloat(groups.count) * 27 + 12)
    }

    private var keyboardHints: some View {
        HStack(spacing: 12) {
            hint("↑↓", "选择")
            hint("↵", "打开")
            hint("esc", "关闭")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(height: 36)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 3)
    }

    private func paletteRow(_ entry: PaletteEntry, selected: Bool) -> some View {
        Button {
            selection = entries.firstIndex(where: { $0.id == entry.id }) ?? selection
            execute(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.tint)
                    .frame(width: 28, height: 28)
                    .background(
                        entry.tint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                if let shortcut = entry.shortcut {
                    Text(shortcut)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 43)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FizzTheme.accent.opacity(0.09))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
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
            result.append(entry.inGroup("最近"))
            if result.count == 3 { break }
        }

        for path in store.recentProjectPaths where path != selectedPath {
            guard let entry = byID["project.\(path)"],
                  entry.isEnabled,
                  seen.insert(entry.id).inserted
            else { continue }
            result.append(entry.inGroup("最近"))
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
        let stacks = project.stacks.flatMap(\.items).joined(separator: " ")
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
        guard !entries.isEmpty else { return }
        var index = selectedIndex
        for _ in entries.indices {
            index = (index + delta + entries.count) % entries.count
            if entries[index].isEnabled {
                selection = index
                return
            }
        }
    }

    private func runSelected() {
        guard entries.indices.contains(selectedIndex), entries[selectedIndex].isEnabled else { return }
        execute(entries[selectedIndex])
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
            locale: .current
        )
    }
}
