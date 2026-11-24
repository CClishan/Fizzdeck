import SwiftUI

struct HomeDashboardView: View {
    @Environment(RepositoryStore.self) private var store
    let filter: HomeFilter

    @AppStorage("fizzdeck.home.viewMode") private var modeRaw = HomeViewMode.cards.rawValue
    @AppStorage("fizzdeck.home.sort") private var sortRaw = HomeSort.recent.rawValue
    @State private var colorFilter: TagColor?
    @State private var toolFilter: String?

    private var mode: HomeViewMode {
        HomeViewMode(rawValue: modeRaw) ?? .cards
    }

    private var sort: HomeSort {
        HomeSort(rawValue: sortRaw) ?? .recent
    }

    private var matchingProjects: [RepoProject] {
        store.filteredProjects.filter(filter.matches)
    }

    private var visibleProjects: [RepoProject] {
        sort.sort(
            matchingProjects.filter { project in
                if let colorFilter, project.color != colorFilter { return false }
                if let toolFilter, !project.sessions.detected.contains(toolFilter) { return false }
                return true
            }
        )
    }

    private var availableTools: [String] {
        let detected = Set(matchingProjects.flatMap(\.sessions.detected))
        let preferred = ["codex", "claude"].filter(detected.contains)
        return preferred + detected.subtracting(preferred).sorted()
    }

    private var running: [RepoProject] {
        visibleProjects.filter { $0.port == .running }
    }

    private var totalBytes: Int64 {
        visibleProjects.reduce(0) { $0 + $1.size.totalBytes }
    }

    private var cleanupBytes: Int64 {
        visibleProjects.reduce(0) { $0 + $1.cleanup.reusableBytes }
    }

    private var hasFacets: Bool {
        colorFilter != nil || toolFilter != nil
    }

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        summary

                        if matchingProjects.isEmpty {
                            emptyResults
                        } else {
                            projectBrowser
                        }
                    }
                    .padding(24)
                }
            }
        }
        .onChange(of: filter) {
            colorFilter = nil
            toolFilter = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(filter.title)
                    .font(.system(size: 27, weight: .semibold))
                Text(headerDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                modePicker
                sortMenu
                colorMenu
                toolMenu

                if hasFacets {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            colorFilter = nil
                            toolFilter = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清除颜色和工具筛选")
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var headerDetail: String {
        var parts: [String] = []
        if hasFacets {
            parts.append("显示 \(visibleProjects.count) / \(matchingProjects.count) 个项目")
        } else {
            parts.append("\(visibleProjects.count) 个项目")
        }
        if filter != .running, !running.isEmpty {
            parts.append("\(running.count) 个运行中")
        }
        if store.phase == .scanning {
            parts.append("正在扫描")
        } else if let scannedAt = store.scannedAt {
            parts.append("\(Format.relative(scannedAt))更新")
        }
        return parts.joined(separator: " · ")
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(HomeViewMode.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        modeRaw = item.rawValue
                    }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mode == item ? FizzTheme.accent : Color.secondary)
                        .frame(width: 29, height: 24)
                        .background {
                            if mode == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
    }

    private var sortMenu: some View {
        Menu {
            ForEach(HomeSort.allCases) { item in
                Button {
                    sortRaw = item.rawValue
                } label: {
                    Label(item.title, systemImage: item == sort ? "checkmark" : item.symbol)
                }
            }
        } label: {
            Label(sort.title, systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .help("排序方式")
    }

    private var colorMenu: some View {
        Menu {
            Button {
                colorFilter = nil
            } label: {
                Label("全部颜色", systemImage: colorFilter == nil ? "checkmark" : "circle")
            }

            Divider()

            ForEach(TagColor.allCases) { color in
                Button {
                    colorFilter = color
                } label: {
                    Label(
                        "\(color.label) · \(colorCount(color))",
                        systemImage: colorFilter == color ? "checkmark" : "circle.fill"
                    )
                }
            }
        } label: {
            Label(colorFilter?.label ?? "颜色", systemImage: "paintpalette")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .help("按标签颜色筛选")
    }

    private var toolMenu: some View {
        Menu {
            Button {
                toolFilter = nil
            } label: {
                Label("全部工具", systemImage: toolFilter == nil ? "checkmark" : "sparkles")
            }

            Divider()

            ForEach(availableTools, id: \.self) { tool in
                Button {
                    toolFilter = tool
                } label: {
                    Label(
                        "\(toolTitle(tool)) · \(toolCount(tool))",
                        systemImage: toolFilter == tool ? "checkmark" : toolSymbol(tool)
                    )
                }
            }
        } label: {
            Label(toolFilter.map(toolTitle) ?? "AI 工具", systemImage: "sparkles")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(availableTools.isEmpty)
        .help(availableTools.isEmpty ? "还没有检测到 AI 会话" : "按 AI 工具筛选")
    }

    private var summary: some View {
        HStack(spacing: 0) {
            HomeSummaryMetric(
                title: "项目",
                value: "\(visibleProjects.count)",
                symbol: "square.stack.3d.up",
                tint: FizzTheme.accent
            )
            summaryDivider
            HomeSummaryMetric(
                title: "正在运行",
                value: "\(running.count)",
                symbol: "play.circle",
                tint: .green
            )
            summaryDivider
            HomeSummaryMetric(
                title: "磁盘占用",
                value: Format.bytes(totalBytes),
                symbol: "internaldrive",
                tint: .blue
            )
            summaryDivider
            HomeSummaryMetric(
                title: "可清理",
                value: Format.bytes(cleanupBytes),
                symbol: "trash.slash",
                tint: .orange
            )
        }
        .padding(.vertical, 10)
        .fizzCard(radius: 16)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(FizzTheme.hairline)
            .frame(width: 1, height: 26)
    }

    private var projectBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("项目")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(visibleProjects.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }

            switch mode {
            case .cards:
                cards
            case .list:
                projectList
            case .gallery:
                gallery
            }
        }
    }

    private var cards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)],
            spacing: 12
        ) {
            ForEach(visibleProjects) { project in
                ProjectFolderCard(project: project)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var projectList: some View {
        VStack(spacing: 0) {
            ForEach(visibleProjects) { project in
                ProjectListRow(project: project)

                if project.id != visibleProjects.last?.id {
                    Divider()
                        .padding(.leading, 50)
                        .opacity(0.45)
                }
            }
        }
        .padding(.vertical, 4)
        .fizzCard(radius: 16)
    }

    private var gallery: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(visibleProjects) { project in
                    ProjectFolderCard(project: project)
                        .frame(width: 276)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .frame(height: 138)
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySymbol)
        } description: {
            Text(emptyDescription)
        } actions: {
            if hasFacets || !store.query.isEmpty {
                Button("清除筛选") {
                    colorFilter = nil
                    toolFilter = nil
                    store.query = ""
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var emptyTitle: String {
        hasFacets ? "没有匹配项目" : filter.emptyTitle
    }

    private var emptyDescription: String {
        if hasFacets {
            return "当前颜色或工具条件下没有项目，清除筛选后再试。"
        }
        if !store.query.isEmpty {
            return "没有找到包含“\(store.query)”的项目。"
        }
        return filter.emptyDescription
    }

    private var emptySymbol: String {
        hasFacets ? "line.3.horizontal.decrease.circle" : filter.symbol
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.phase == .scanning {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在扫描本机项目…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("还没有项目", systemImage: "square.stack.3d.up")
            } description: {
                Text("添加一个项目目录，FizzDeck 会扫描其中的 Git、体积和运行脚本。")
            } actions: {
                Button("添加项目目录") {
                    Task { await store.addRoot() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func colorCount(_ color: TagColor) -> Int {
        matchingProjects.filter { $0.color == color }.count
    }

    private func toolCount(_ tool: String) -> Int {
        matchingProjects.filter { $0.sessions.detected.contains(tool) }.count
    }
}

private enum HomeViewMode: String, CaseIterable, Identifiable {
    case cards
    case list
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: "卡片墙"
        case .list: "极简列表"
        case .gallery: "横向画廊"
        }
    }

    var symbol: String {
        switch self {
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        case .gallery: "rectangle.split.3x1"
        }
    }
}

private enum HomeSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近活动"
        case .name: "名称"
        case .size: "体积"
        }
    }

    var symbol: String {
        switch self {
        case .recent: "clock"
        case .name: "textformat.abc"
        case .size: "internaldrive"
        }
    }

    func sort(_ projects: [RepoProject]) -> [RepoProject] {
        projects.sorted { left, right in
            switch self {
            case .recent:
                return (left.recent ?? .distantPast) > (right.recent ?? .distantPast)
            case .name:
                return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
            case .size:
                return left.size.totalBytes > right.size.totalBytes
            }
        }
    }
}

private struct HomeSummaryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectFolderCard: View {
    @Environment(RepositoryStore.self) private var store
    let project: RepoProject

    @State private var hovering = false

    var body: some View {
        Button {
            store.selectedPath = project.path
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    FolderBadge(project: project, size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(project.displayName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .lineLimit(1)

                            if project.starred {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                            }

                            if project.dirtyCount > 0 {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 5, height: 5)
                            }
                        }

                        Text(projectSubtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    StatusDot(state: project.port)
                }

                Text(primaryDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(project.note.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)

                HStack(spacing: 5) {
                    Text(Format.bytes(project.size.totalBytes))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(Format.relative(project.recent))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 4)

                    if let tool = project.sessions.lastTool {
                        HomeToolBadge(tool: tool, compact: true)
                    }

                    if let stack = firstStack {
                        TagChip(text: stack.0, tint: stack.1, compact: true)
                    }
                }
                .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .topLeading)
            .background(FizzTheme.cardFill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        hovering ? accent.opacity(0.24) : FizzTheme.stroke,
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(hovering ? 0.07 : 0.025),
                radius: hovering ? 9 : 3,
                y: hovering ? 4 : 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.snappy(duration: 0.18)) {
                hovering = value
            }
        }
        .help("打开 \(project.displayName)")
        .accessibilityLabel("打开 \(project.displayName)")
        .contextMenu {
            Button(project.starred ? "取消星标" : "设为星标") {
                store.toggleStar(project)
            }
            Menu("标签颜色") {
                Button("无标签") { store.setColor(nil, for: project) }
                ForEach(TagColor.allCases) { color in
                    Button(color.label) { store.setColor(color, for: project) }
                }
            }
            Divider()
            Button("在 Finder 中显示") { SystemActions.reveal(project.path) }
            Button("复制路径") { SystemActions.copy(project.path) }
        }
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var projectSubtitle: String {
        if let branch = project.branch {
            return "\(project.group) · \(branch)"
        }
        return project.group
    }

    private var primaryDetail: String {
        if !project.note.isEmpty { return project.note }
        if let subject = project.lastCommit?.subject { return subject }
        return project.intro.text
    }

    private var firstStack: (String, Color)? {
        guard let group = project.stacks.first, let item = group.items.first else { return nil }
        return (item, group.color)
    }
}

private struct ProjectListRow: View {
    @Environment(RepositoryStore.self) private var store
    let project: RepoProject

    @State private var hovering = false

    var body: some View {
        Button {
            store.selectedPath = project.path
        } label: {
            HStack(spacing: 10) {
                FolderBadge(project: project, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(project.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if project.starred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                        }
                        if project.dirtyCount > 0 {
                            Circle()
                                .fill(.orange)
                                .frame(width: 5, height: 5)
                        }
                    }
                    Text(secondaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let tool = project.sessions.lastTool {
                    HomeToolBadge(tool: tool)
                }
                if let stack = firstStack {
                    TagChip(text: stack.0, tint: stack.1, compact: true)
                }

                Text(Format.relative(project.recent))
                    .frame(width: 66, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(Format.bytes(project.size.totalBytes))
                    .frame(width: 62, alignment: .trailing)
                    .foregroundStyle(.secondary)
                StatusDot(state: project.port)
            }
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FizzTheme.mutedFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            hovering = value
        }
        .help("打开 \(project.displayName)")
    }

    private var secondaryText: String {
        if !project.note.isEmpty { return project.note }
        if let subject = project.lastCommit?.subject { return subject }
        return project.group
    }

    private var firstStack: (String, Color)? {
        guard let group = project.stacks.first, let item = group.items.first else { return nil }
        return (item, group.color)
    }
}

private struct FolderBadge: View {
    let project: RepoProject
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(color.opacity(0.11))
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.52, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(color.opacity(project.color == nil ? 0.10 : 0.24), lineWidth: 1)
        }
    }

    private var color: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }
}

private struct HomeToolBadge: View {
    let tool: String
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if !compact {
                Text(title)
            }
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 4 : 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.09), in: Capsule())
        .lineLimit(1)
        .help(title)
    }

    private var title: String {
        tool == "codex" ? "Codex" : tool == "claude" ? "Claude" : tool.capitalized
    }

    private var symbol: String {
        tool == "codex" ? "terminal" : "sparkles"
    }

    private var tint: Color {
        tool == "codex" ? .purple : .orange
    }
}

private func toolTitle(_ tool: String) -> String {
    tool == "codex" ? "Codex" : tool == "claude" ? "Claude Code" : tool.capitalized
}

private func toolSymbol(_ tool: String) -> String {
    tool == "codex" ? "terminal" : "sparkles"
}
