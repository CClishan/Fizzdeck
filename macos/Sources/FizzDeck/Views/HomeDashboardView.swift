import SwiftUI

struct HomeDashboardView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let filter: HomeFilter

    @AppStorage("fizzdeck.home.viewMode") private var modeRaw = HomeViewMode.cards.rawValue
    @AppStorage("fizzdeck.home.sort") private var sortRaw = HomeSort.recent.rawValue
    @State private var colorFilter: TagColor?
    @State private var toolFilter: String?
    @State private var groupFilter: String?
    @State private var selectionMode = false
    @State private var selectedPaths: Set<String> = []
    @State private var batchFeedback: String?
    @State private var batchRunning = false

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
                if let groupFilter, project.group != groupFilter { return false }
                if let colorFilter, project.color != colorFilter { return false }
                if let toolFilter, !project.allTools.contains(toolFilter) { return false }
                return true
            }
        )
    }

    private var selectedProjects: [RepoProject] {
        visibleProjects.filter { selectedPaths.contains($0.path) }
    }

    private var availableGroups: [String] {
        ProjectGrouping.ordered(matchingProjects.map(\.group))
    }

    private var allVisibleSelected: Bool {
        !visibleProjects.isEmpty && visibleProjects.allSatisfy { selectedPaths.contains($0.path) }
    }

    private var availableTools: [String] {
        let detected = Set(matchingProjects.flatMap(\.allTools))
        let preferred = DetectedTool.allCases.map(\.rawValue).filter(detected.contains)
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
        groupFilter != nil || colorFilter != nil || toolFilter != nil
    }

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FizzSpacing.section) {
                        header
                        overviewTop

                        if matchingProjects.isEmpty {
                            emptyResults
                        } else {
                            projectBrowser
                        }
                    }
                    .padding(FizzSpacing.page)
                }
            }
        }
        .onChange(of: filter) {
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                groupFilter = nil
                colorFilter = nil
                toolFilter = nil
                selectionMode = false
                selectedPaths.removeAll()
                batchFeedback = nil
            }
        }
        .onChange(of: visibleProjects.map(\.path)) { _, paths in
            selectedPaths.formIntersection(Set(paths))
        }
        .onAppear {
            if HomeViewMode(rawValue: modeRaw) == nil {
                modeRaw = HomeViewMode.cards.rawValue
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(filter.title)
                        .font(.system(size: 27, weight: .semibold))
                    Text(headerDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    modePicker
                    filterMenu
                    selectionToggle
                }
                .fixedSize()
                .padding(.top, 2)
            }

            if hasFacets {
                activeFilterChips
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.standard), value: hasFacets)
    }

    private var showsAttention: Bool {
        filter == .all && store.query.isEmpty && !hasFacets
    }

    private var overviewTop: some View {
        Group {
            if showsAttention {
                HStack(alignment: .top, spacing: FizzSpacing.grid) {
                    AttentionQueueView()
                        .frame(maxWidth: .infinity, alignment: .top)

                    summaryCards
                        .frame(maxWidth: .infinity)
                }
            } else {
                summary
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
        } else if store.pendingSizeCount > 0 {
            parts.append("正在统计体积 (\(store.pendingSizeCount))")
        } else if let scannedAt = store.scannedAt {
            parts.append("\(Format.relative(scannedAt))更新")
        }
        return parts.joined(separator: " · ")
    }

    private var modePicker: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 1) {
                ForEach(HomeViewMode.allCases) { item in
                    let selected = mode == item

                    Button {
                        guard !selected else { return }
                        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.standard)) {
                            modeRaw = item.rawValue
                        }
                    } label: {
                        FizzIcon(symbol: item.symbol, size: 13)
                            .foregroundStyle(selected ? FizzTheme.accent : Color.secondary)
                            .frame(width: 30, height: 26)
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(FizzTheme.elevatedFill)
                                        .fizzAdaptiveShadow(.subtle)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityRemoveTraits(selected ? [] : .isSelected)
                }
            }
            .padding(2)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("布局")
    }

    private var filterMenu: some View {
        Menu {
            Section("排序") {
                ForEach(HomeSort.allCases) { item in
                    Button {
                        setSort(item)
                    } label: {
                        Label(item.title, systemImage: item == sort ? "checkmark" : item.symbol)
                    }
                }
            }

            Menu {
                Button {
                    setGroupFilter(nil)
                } label: {
                    Label(
                        "全部分组",
                        systemImage: groupFilter == nil ? "checkmark" : "square.grid.2x2"
                    )
                }

                Divider()

                ForEach(availableGroups, id: \.self) { group in
                    Button {
                        setGroupFilter(group)
                    } label: {
                        Label(
                            "\(group) · \(groupCount(group))",
                            systemImage: groupFilter == group ? "checkmark" : "circle.fill"
                        )
                    }
                }
            } label: {
                Label(
                    groupFilter.map { "分组 · \($0)" } ?? "分组",
                    systemImage: "square.grid.2x2"
                )
            }
            .disabled(availableGroups.isEmpty)

            Menu {
                Button {
                    setColorFilter(nil)
                } label: {
                    Label("全部颜色", systemImage: colorFilter == nil ? "checkmark" : "circle")
                }

                Divider()

                ForEach(TagColor.allCases) { color in
                    Button {
                        setColorFilter(color)
                    } label: {
                        Label(
                            "\(color.label) · \(colorCount(color))",
                            systemImage: colorFilter == color ? "checkmark" : "circle.fill"
                        )
                    }
                }
            } label: {
                Label(
                    colorFilter.map { "颜色 · \($0.label)" } ?? "颜色",
                    systemImage: "paintpalette"
                )
            }

            Menu {
                Button {
                    setToolFilter(nil)
                } label: {
                    Label("全部工具", systemImage: toolFilter == nil ? "checkmark" : "sparkles")
                }

                Divider()

                ForEach(availableTools, id: \.self) { tool in
                    Button {
                        setToolFilter(tool)
                    } label: {
                        Label(
                            "\(toolTitle(tool)) · \(toolCount(tool))",
                            systemImage: toolFilter == tool ? "checkmark" : toolSymbol(tool)
                        )
                    }
                }
            } label: {
                Label(
                    toolFilter.map { "AI · \(toolTitle($0))" } ?? "AI 工具",
                    systemImage: "sparkles"
                )
            }
            .disabled(availableTools.isEmpty)

            if hasFacets {
                Divider()
                Button(role: .destructive) {
                    clearFacets()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
            }
        } label: {
            filterMenuLabel
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .controlSize(.small)
        .glassEffect(.regular.interactive(), in: Capsule())
        .help("排序与筛选")
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: hasFacets)
    }

    private var selectionToggle: some View {
        Button {
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                if selectionMode {
                    endSelection()
                } else {
                    selectionMode = true
                }
            }
        } label: {
            FizzIcon(symbol: selectionMode ? "checkmark.circle.fill" : "checklist", size: 13)
                .foregroundStyle(selectionMode ? FizzTheme.accent : Color.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(selectionMode ? "退出批量选择" : "批量选择项目")
        .accessibilityLabel(selectionMode ? "退出批量选择" : "批量选择项目")
        .accessibilityAddTraits(selectionMode ? .isSelected : [])
    }

    private var filterMenuLabel: some View {
        HStack(spacing: 5) {
            FizzIcon(symbol: "line.3.horizontal.decrease", size: 12)
            Text("筛选")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.primary)
    }

    private var activeFilterChips: some View {
        HStack(spacing: 6) {
            if let groupFilter {
                ActiveFilterChip(
                    text: groupFilter,
                    tint: ProjectGrouping.color(for: groupFilter)
                ) {
                    setGroupFilter(nil)
                }
            }
            if let colorFilter {
                ActiveFilterChip(text: colorFilter.label, tint: colorFilter.color) {
                    setColorFilter(nil)
                }
            }
            if let toolFilter {
                ActiveFilterChip(text: toolTitle(toolFilter), tint: .purple) {
                    setToolFilter(nil)
                }
            }

            Button("清除") {
                clearFacets()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("活动筛选")
    }

    private var summaryCards: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                GlassStatCard(
                    title: "项目",
                    value: "\(visibleProjects.count)",
                    detail: filter.title,
                    symbol: "square.stack.3d.up",
                    tint: FizzTheme.accent
                )
                GlassStatCard(
                    title: "正在运行",
                    value: "\(running.count)",
                    detail: running.isEmpty ? "没有运行中的服务" : "端口已就绪",
                    symbol: "play.circle",
                    tint: .green
                )
            }
            GridRow {
                GlassStatCard(
                    title: "磁盘占用",
                    value: Format.bytes(totalBytes),
                    detail: "已扫描 \(visibleProjects.count) 个项目",
                    symbol: "internaldrive",
                    tint: .blue
                )
                GlassStatCard(
                    title: "可清理",
                    value: Format.bytes(cleanupBytes),
                    detail: "\(cleanupItemCount) 个目录",
                    symbol: "trash.slash",
                    tint: .orange
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cleanupItemCount: Int {
        visibleProjects.reduce(0) { $0 + $1.cleanup.items.count }
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
        .fizzCard()
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(FizzTheme.hairline)
            .frame(width: 1, height: 26)
    }

    private var projectBrowser: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("项目")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(visibleProjects.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }

            if selectionMode {
                batchBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            switch mode {
            case .cards:
                cards
            case .list:
                projectList
            }
        }
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: selectionMode)
    }

    private var batchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FizzIcon(symbol: "checkmark.circle", size: 13)
                    .foregroundStyle(FizzTheme.accent)
                Text("已选 \(selectedProjects.count) 个")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()

                Spacer(minLength: 8)

                Button("复制清理命令") {
                    copyCleanupCommands()
                }
                .disabled(selectedProjects.isEmpty)
                .opacity(selectedProjects.isEmpty ? 0.42 : 1)
                .buttonStyle(.glass)

                Button {
                    Task { await rescanSelected() }
                } label: {
                    if batchRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text("重新扫描")
                    }
                }
                .disabled(selectedProjects.isEmpty || batchRunning || store.phase == .scanning)
                .opacity(selectedProjects.isEmpty || batchRunning || store.phase == .scanning ? 0.42 : 1)
                .buttonStyle(.glass)

                Button(allVisibleSelected ? "取消全选" : "全选") {
                    toggleSelectAll()
                }
                .disabled(visibleProjects.isEmpty)
                .opacity(visibleProjects.isEmpty ? 0.42 : 1)
                .buttonStyle(.glass)

                Button("清除") {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                        selectedPaths.removeAll()
                        batchFeedback = nil
                    }
                }
                .disabled(selectedPaths.isEmpty)
                .opacity(selectedPaths.isEmpty ? 0.42 : 1)
                .buttonStyle(.glass)

                Button("完成") {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                        endSelection()
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(FizzTheme.accent)
                .controlSize(.regular)
            }
            .controlSize(.small)

            if let batchFeedback {
                HStack(spacing: 5) {
                    FizzIcon(symbol: "info.circle", size: 11)
                        .foregroundStyle(FizzTheme.accent)
                    Text(batchFeedback)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fizzCard(radius: FizzRadius.card)
    }

    private var cards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: FizzSpacing.grid)],
            spacing: FizzSpacing.grid
        ) {
            ForEach(visibleProjects) { project in
                ProjectFolderCard(
                    project: project,
                    selecting: selectionMode,
                    selected: selectedPaths.contains(project.path),
                    toggleSelection: { toggleSelection(project) }
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var projectList: some View {
        VStack(spacing: 0) {
            ForEach(visibleProjects) { project in
                ProjectListRow(
                    project: project,
                    selecting: selectionMode,
                    selected: selectedPaths.contains(project.path),
                    toggleSelection: { toggleSelection(project) }
                )

                if project.id != visibleProjects.last?.id {
                    Divider()
                        .padding(.leading, 50)
                        .opacity(0.45)
                }
            }
        }
        .padding(.vertical, 4)
        .fizzCard()
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySymbol)
        } description: {
            Text(emptyDescription)
        } actions: {
            if hasFacets || !store.query.isEmpty {
                Button("清除筛选") {
                    clearFacets()
                    store.query = ""
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var emptyTitle: String {
        hasFacets ? "没有匹配项目" : filter.emptyTitle
    }

    private var emptyDescription: String {
        if hasFacets {
            return "当前分组、颜色或工具条件下没有项目，清除筛选后再试。"
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
                Text("扫描常用目录或手动添加文件夹，FizzDeck 会分析 Git、AI 会话和体积。")
            } actions: {
                HStack(spacing: 10) {
                    Button("智能扫描本机项目") {
                        store.presentFirstRunScan()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(FizzTheme.accent)

                    Button("手动添加文件夹") {
                        Task { await store.addRoot() }
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private func colorCount(_ color: TagColor) -> Int {
        matchingProjects.filter { project in
            guard project.color == color else { return false }
            if let groupFilter, project.group != groupFilter {
                return false
            }
            if let toolFilter, !project.allTools.contains(toolFilter) {
                return false
            }
            return true
        }.count
    }

    private func toolCount(_ tool: String) -> Int {
        matchingProjects.filter { project in
            guard project.allTools.contains(tool) else { return false }
            if let groupFilter, project.group != groupFilter {
                return false
            }
            if let colorFilter, project.color != colorFilter {
                return false
            }
            return true
        }.count
    }

    private func groupCount(_ group: String) -> Int {
        matchingProjects.filter { project in
            guard project.group == group else { return false }
            if let colorFilter, project.color != colorFilter {
                return false
            }
            if let toolFilter, !project.allTools.contains(toolFilter) {
                return false
            }
            return true
        }.count
    }

    private func setSort(_ value: HomeSort) {
        guard sort != value else { return }
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            sortRaw = value.rawValue
        }
    }

    private func setGroupFilter(_ value: String?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            groupFilter = value
            batchFeedback = nil
        }
    }

    private func setColorFilter(_ value: TagColor?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            colorFilter = value
        }
    }

    private func setToolFilter(_ value: String?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            toolFilter = value
        }
    }

    private func clearFacets() {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.standard)) {
            groupFilter = nil
            colorFilter = nil
            toolFilter = nil
            batchFeedback = nil
        }
    }

    private func toggleSelection(_ project: RepoProject) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            if selectedPaths.contains(project.path) {
                selectedPaths.remove(project.path)
            } else {
                selectedPaths.insert(project.path)
            }
            batchFeedback = nil
        }
    }

    private func toggleSelectAll() {
        let paths = Set(visibleProjects.map(\.path))
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            if paths.isSubset(of: selectedPaths) {
                selectedPaths.subtract(paths)
            } else {
                selectedPaths.formUnion(paths)
            }
            batchFeedback = nil
        }
    }

    private func endSelection() {
        selectionMode = false
        selectedPaths.removeAll()
        batchFeedback = nil
    }

    private func copyCleanupCommands() {
        let projects = selectedProjects
        let commands = projects.compactMap { project -> String? in
            let command = project.cleanup.removalCommand
            guard !command.isEmpty else { return nil }
            return "# \(project.displayName)\n\(command)"
        }
        guard !commands.isEmpty else {
            batchFeedback = "所选项目没有可清理项"
            return
        }

        SystemActions.copy(commands.joined(separator: "\n"))
        let skipped = projects.count - commands.count
        batchFeedback = skipped == 0
            ? "已复制 \(commands.count) 个项目的清理命令"
            : "已复制 \(commands.count) 个；\(skipped) 个没有可清理项"
    }

    private func rescanSelected() async {
        guard !batchRunning, store.phase != .scanning else { return }
        let projects = selectedProjects
        guard !projects.isEmpty else { return }

        let existing = projects.filter {
            FileTools.isDirectory(URL(fileURLWithPath: $0.path))
        }
        let missing = projects.count - existing.count
        guard !existing.isEmpty else {
            batchFeedback = "所选目录都不存在"
            return
        }

        batchRunning = true
        batchFeedback = nil
        await store.rescanProjects(existing)
        batchRunning = false
        batchFeedback = missing == 0
            ? "已重新扫描 \(existing.count) 个项目"
            : "已重新扫描 \(existing.count) 个；\(missing) 个目录不存在"
    }

}

private enum HomeViewMode: String, CaseIterable, Identifiable {
    case cards
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: "卡片墙"
        case .list: "极简列表"
        }
    }

    var symbol: String {
        switch self {
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

private struct ActiveFilterChip: View {
    let text: String
    let tint: Color
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text(text)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                FizzIcon(symbol: "xmark", size: 8)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                hovering ? FizzTheme.selectedFill : FizzTheme.mutedFill,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("移除 \(text) 筛选")
        .accessibilityLabel("移除 \(text) 筛选")
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
            FizzIcon(symbol: symbol, size: 14)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject
    var selecting = false
    var selected = false
    var toggleSelection: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProjectBadgeIcon(project: project, size: 32, framed: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(project.displayName)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)

                        if project.starred {
                            FizzIcon(symbol: "star.fill", size: 9)
                                .foregroundStyle(.yellow)
                        }

                        if project.dirtyCount > 0 {
                            TagChip(
                                text: "\(project.dirtyCount) 处改动",
                                tint: .orange,
                                compact: true
                            )
                            .help("\(project.dirtyCount) 处未提交改动")
                        }
                    }

                    Text(projectSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if selecting {
                    FizzIcon(
                        symbol: selected ? "checkmark.circle.fill" : "circle",
                        size: 16
                    )
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                } else {
                    PortStatusBadge(state: project.port)
                }
            }

            Text(primaryDetail)
                .font(.system(size: 11.5))
                .foregroundStyle(project.note.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)

            HStack(spacing: 5) {
                Text(project.sizeLoadState == .ready ? Format.bytes(project.size.totalBytes) : "统计中")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text(Format.relative(project.recent))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                if let tool = project.sessions.lastTool ?? project.detectedTools.first?.rawValue {
                    HomeToolBadge(tool: tool, compact: true)
                }

                if let stack = firstStack {
                    TagChip(text: stack.0, tint: stack.1, compact: true)
                }

                if !selecting {
                    SessionContinueButton(project: project, style: .compact)
                }
            }
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, maxHeight: 134, alignment: .topLeading)
        .background(FizzTheme.cardFill, in: RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                .strokeBorder(
                    selected
                        ? accent.opacity(0.55)
                        : hovering ? accent.opacity(0.24) : FizzTheme.stroke,
                    lineWidth: selected ? 1.5 : 1
                )
        }
        .fizzAdaptiveShadow(hovering ? .raised : .subtle)
        .contentShape(RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .onTapGesture {
            if selecting {
                toggleSelection()
            } else {
                store.selectedPath = project.path
            }
        }
        .onHover { value in
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                hovering = value
            }
        }
        .help(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityLabel(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            ProjectGroupingMenu(project: project)
            Divider()
            ProjectQuickActions(project: project)
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
    var selecting = false
    var selected = false
    var toggleSelection: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if selecting {
                FizzIcon(symbol: selected ? "checkmark.circle.fill" : "circle", size: 15)
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.55))
                    .frame(width: 16)
            }

            ProjectBadgeIcon(project: project, size: 28, framed: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if project.starred {
                        FizzIcon(symbol: "star.fill", size: 9)
                            .foregroundStyle(.yellow)
                    }
                    if project.dirtyCount > 0 {
                        TagChip(
                            text: "\(project.dirtyCount) 处改动",
                            tint: .orange,
                            compact: true
                        )
                        .help("\(project.dirtyCount) 处未提交改动")
                    }
                }
                Text(secondaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let tool = project.sessions.lastTool ?? project.detectedTools.first?.rawValue {
                HomeToolBadge(tool: tool)
            }
            if let stack = firstStack {
                TagChip(text: stack.0, tint: stack.1, compact: true)
            }

            Text(Format.relative(project.recent))
                .frame(width: 66, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(project.sizeLoadState == .ready ? Format.bytes(project.size.totalBytes) : "统计中")
                .frame(width: 62, alignment: .trailing)
                .foregroundStyle(.secondary)
            PortStatusBadge(state: project.port)

            if !selecting {
                SessionContinueButton(project: project, style: .compact)
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .fill(accent.opacity(0.10))
            } else if hovering {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .fill(FizzTheme.mutedFill)
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .strokeBorder(
                        accent.opacity(0.28),
                        lineWidth: 1
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                toggleSelection()
            } else {
                store.selectedPath = project.path
            }
        }
        .onHover { value in
            hovering = value
        }
        .help(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityLabel(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            ProjectGroupingMenu(project: project)
            ProjectQuickActions(project: project)
        }
    }

    private var secondaryText: String {
        if !project.note.isEmpty { return project.note }
        if let subject = project.lastCommit?.subject { return subject }
        return project.group
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var firstStack: (String, Color)? {
        guard let group = project.stacks.first, let item = group.items.first else { return nil }
        return (item, group.color)
    }
}

private struct HomeToolBadge: View {
    let tool: String
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            FizzIcon(symbol: symbol, size: 10)
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
        toolTitle(tool)
    }

    private var symbol: String {
        toolSymbol(tool)
    }

    private var tint: Color {
        DetectedTool(rawValue: tool)?.tint ?? .secondary
    }
}

private func toolTitle(_ tool: String) -> String {
    DetectedTool(rawValue: tool)?.title ?? tool.capitalized
}

private func toolSymbol(_ tool: String) -> String {
    DetectedTool(rawValue: tool)?.symbol ?? "sparkles"
}
