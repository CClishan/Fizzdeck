import SwiftUI

struct LibraryView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let query: LibraryQuery

    @AppStorage("fizzdeck.home.viewMode") private var modeRaw = HomeViewMode.cards.rawValue
    @AppStorage("fizzdeck.home.sort") private var sortRaw = HomeSort.recent.rawValue
    @State private var localQuery = LibraryQuery()
    @State private var selectionMode = false
    @State private var selectedPaths: Set<String> = []
    @State private var batchFeedback: String?
    @State private var batchRunning = false
    @State private var showIdleProjects = false
    @FocusState private var searchFocused: Bool

    private var mode: HomeViewMode {
        HomeViewMode(rawValue: modeRaw) ?? .cards
    }

    private var sort: HomeSort {
        HomeSort(rawValue: sortRaw) ?? .recent
    }

    private var facets: HomeFacets {
        HomeFacets(group: localQuery.group, color: localQuery.color, tool: localQuery.tool)
    }

    private var baseProjects: [RepoProject] {
        store.filteredProjects
    }

    private var visibleProjects: [RepoProject] {
        HomeDashboardModel.libraryProjects(
            from: baseProjects,
            query: localQuery,
            sort: sort,
            commitActivity: store.commitActivity
        )
    }

    private var partitioned: (active: [RepoProject], idle: [RepoProject]) {
        guard localQuery.commitDayKey == nil else {
            return (visibleProjects, [])
        }
        return DashboardMetrics.partitionByActivity(visibleProjects)
    }

    private var selectedProjects: [RepoProject] {
        visibleProjects.filter { selectedPaths.contains($0.path) }
    }

    private var availableGroups: [String] {
        HomeDashboardModel.availableGroups(in: baseProjects)
    }

    private var availableTools: [String] {
        HomeDashboardModel.availableTools(in: baseProjects)
    }

    private var availableFrameworks: [String] {
        HomeDashboardModel.availableFrameworks(in: baseProjects)
    }

    private var allVisibleSelected: Bool {
        !visibleProjects.isEmpty && visibleProjects.allSatisfy { selectedPaths.contains($0.path) }
    }

    private var allSelectedStarred: Bool {
        !selectedProjects.isEmpty && selectedProjects.allSatisfy(\.starred)
    }

    private var runningCount: Int {
        visibleProjects.filter { $0.port == .running }.count
    }

    private var headerDetail: String {
        HomeDashboardModel.headerDetail(
            visibleCount: visibleProjects.count,
            matchingCount: baseProjects.count,
            hasFacets: localQuery.hasActiveFilters,
            filter: .all,
            runningCount: runningCount,
            isScanning: store.phase == .scanning,
            pendingSizeCount: store.pendingSizeCount,
            relativeScannedAt: store.scannedAt.map { Format.relative($0) }
        )
    }

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FizzSpacing.section) {
                        HomeHeaderView(
                            title: "项目库",
                            detail: headerDetail,
                            mode: mode,
                            sort: sort,
                            facets: facets,
                            availableGroups: availableGroups,
                            availableTools: availableTools,
                            availableFrameworks: availableFrameworks,
                            selectedFramework: localQuery.framework,
                            selectionMode: selectionMode,
                            groupCount: { HomeDashboardModel.groupCount($0, in: baseProjects, facets: facets) },
                            colorCount: { HomeDashboardModel.colorCount($0, in: baseProjects, facets: facets) },
                            toolCount: { HomeDashboardModel.toolCount($0, in: baseProjects, facets: facets) },
                            frameworkCount: frameworkCount,
                            onSelectMode: setMode,
                            onSelectSort: setSort,
                            onSetGroup: setGroupFilter,
                            onSetColor: setColorFilter,
                            onSetTool: setToolFilter,
                            onSetFramework: setFrameworkFilter,
                            extraActiveFilterCount: extraFilterCount,
                            onClearFacets: clearFilters,
                            onToggleSelection: toggleSelectionMode
                        )

                        filterToolbar

                        if visibleProjects.isEmpty {
                            emptyResults
                        } else {
                            let split = partitioned
                            HomeProjectBrowser(
                                projects: split.active,
                                mode: mode,
                                selectionMode: selectionMode,
                                selectedPaths: $selectedPaths,
                                selectedCount: selectedProjects.count,
                                allVisibleSelected: allVisibleSelected,
                                batchRunning: batchRunning,
                                isScanning: store.phase == .scanning,
                                batchFeedback: batchFeedback,
                                knownGroups: store.knownGroups,
                                allSelectedStarred: allSelectedStarred,
                                onBatchStar: batchStar,
                                onBatchGroup: batchGroup,
                                onBatchFetch: { Task { await fetchSelected() } },
                                onToggleSelection: toggleSelection,
                                onCopyCleanup: copyCleanupCommands,
                                onRescanSelected: { Task { await rescanSelected() } },
                                onToggleSelectAll: toggleSelectAll,
                                onClearSelection: clearSelection,
                                onEndSelection: endSelectionAnimated
                            )

                            if !split.idle.isEmpty {
                                idleSection(split.idle)
                            }
                        }
                    }
                    .padding(FizzSpacing.page)
                }
            }
        }
        .background {
            Button("") {
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: [.command])
            .hidden()
        }
        .onAppear {
            syncFromQuery()
            if HomeViewMode(rawValue: modeRaw) == nil {
                modeRaw = HomeViewMode.cards.rawValue
            }
        }
        .onChange(of: query) {
            syncFromQuery()
        }
        .onChange(of: visibleProjects.map(\.path)) { _, paths in
            selectedPaths.formIntersection(Set(paths))
        }
    }

    private var filterToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    FizzIcon(symbol: "magnifyingglass", size: 12)
                        .foregroundStyle(.secondary)
                    TextField("搜索项目、分支、路径或技术栈（⌘F）", text: $localQuery.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($searchFocused)
                    if !localQuery.searchText.isEmpty {
                        Button {
                            localQuery.searchText = ""
                        } label: {
                            FizzIcon(symbol: "xmark.circle.fill", size: 12)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("清除搜索")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .frame(maxWidth: 340)
                .background(
                    FizzTheme.recessedFill,
                    in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        .strokeBorder(FizzTheme.stroke, lineWidth: 1)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        quickChip("星标", active: localQuery.starredOnly) {
                            localQuery.starredOnly.toggle()
                        }
                        quickChip("有改动", active: localQuery.dirtyOnly) {
                            localQuery.dirtyOnly.toggle()
                        }
                        quickChip("运行中", active: localQuery.runningOnly) {
                            localQuery.runningOnly.toggle()
                        }
                        quickChip("有 AI 会话", active: localQuery.hasSessionsOnly) {
                            localQuery.hasSessionsOnly.toggle()
                        }
                        quickChip("有未推送", active: localQuery.unpushedOnly) {
                            localQuery.unpushedOnly.toggle()
                        }

                        if let dayKey = localQuery.commitDayKey {
                            Button {
                                localQuery.commitDayKey = nil
                            } label: {
                                HStack(spacing: 4) {
                                    Text("提交日期 · \(dayKey)")
                                    FizzIcon(symbol: "xmark", size: 8)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(FizzTheme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func quickChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? .white : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    active ? FizzTheme.accent : FizzTheme.mutedFill,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func idleSection(_ idleProjects: [RepoProject]) -> some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            Button {
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                    showIdleProjects.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    FizzIcon(
                        symbol: showIdleProjects ? "chevron.down" : "chevron.right",
                        size: FizzIconScale.micro
                    )
                    .foregroundStyle(.secondary)
                    Text("闲置 30 天以上")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(idleProjects.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showIdleProjects {
                switch mode {
                case .cards:
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: FizzSpacing.grid)],
                        spacing: FizzSpacing.grid
                    ) {
                        ForEach(idleProjects) { project in
                            ProjectFolderCard(
                                project: project,
                                selecting: selectionMode,
                                selected: selectedPaths.contains(project.path),
                                toggleSelection: { toggleSelection(project) }
                            )
                        }
                    }
                case .list:
                    VStack(spacing: 0) {
                        ForEach(idleProjects) { project in
                            ProjectListRow(
                                project: project,
                                selecting: selectionMode,
                                selected: selectedPaths.contains(project.path),
                                toggleSelection: { toggleSelection(project) }
                            )
                            if project.id != idleProjects.last?.id {
                                Divider()
                                    .padding(.leading, 50)
                                    .opacity(0.45)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .fizzCard()
                }
            }
        }
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label("没有匹配项目", systemImage: "square.grid.2x2")
        } description: {
            Text(localQuery.hasActiveFilters
                ? "当前筛选条件下没有项目，清除筛选后再试。"
                : "没有找到匹配的项目。")
        } actions: {
            if localQuery.hasActiveFilters || !store.query.isEmpty {
                Button("清除筛选") {
                    clearFilters()
                    store.query = ""
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
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

    private var extraFilterCount: Int {
        var count = 0
        if localQuery.starredOnly { count += 1 }
        if localQuery.dirtyOnly { count += 1 }
        if localQuery.runningOnly { count += 1 }
        if localQuery.hasSessionsOnly { count += 1 }
        if localQuery.unpushedOnly { count += 1 }
        if localQuery.commitDayKey != nil { count += 1 }
        if !localQuery.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        return count
    }

    private func frameworkCount(_ framework: String) -> Int {
        baseProjects.filter { project in
            project.stacks.contains { $0.items.contains(framework) }
        }.count
    }

    private func syncFromQuery() {
        localQuery = query
        batchFeedback = nil
    }

    private func setMode(_ value: HomeViewMode) {
        guard mode != value else { return }
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.standard)) {
            modeRaw = value.rawValue
        }
    }

    private func setSort(_ value: HomeSort) {
        guard sort != value else { return }
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            sortRaw = value.rawValue
        }
    }

    private func setGroupFilter(_ value: String?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            localQuery.group = value
            batchFeedback = nil
        }
    }

    private func setColorFilter(_ value: TagColor?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            localQuery.color = value
        }
    }

    private func setToolFilter(_ value: String?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            localQuery.tool = value
        }
    }

    private func setFrameworkFilter(_ value: String?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            localQuery.framework = value
        }
    }

    private func clearFilters() {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.standard)) {
            localQuery.clearFilters()
            batchFeedback = nil
        }
    }

    private func toggleSelectionMode() {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            if selectionMode {
                endSelection()
            } else {
                selectionMode = true
            }
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

    private func clearSelection() {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            selectedPaths.removeAll()
            batchFeedback = nil
        }
    }

    private func endSelectionAnimated() {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            endSelection()
        }
    }

    private func endSelection() {
        selectionMode = false
        selectedPaths.removeAll()
        batchFeedback = nil
    }

    private func copyCleanupCommands() {
        let result = HomeDashboardModel.batchCleanupCommands(for: selectedProjects)
        if let script = result.script {
            SystemActions.copy(script)
        }
        batchFeedback = result.feedback
    }

    private func batchStar(_ starred: Bool) {
        let projects = selectedProjects
        guard !projects.isEmpty else { return }
        store.setStarred(starred, for: projects)
        batchFeedback = starred
            ? "已为 \(projects.count) 个项目设为星标"
            : "已取消 \(projects.count) 个项目的星标"
    }

    private func batchGroup(_ group: String?) {
        let projects = selectedProjects
        guard !projects.isEmpty else { return }
        store.setGroup(group, for: projects)
        batchFeedback = group.map { "已将 \(projects.count) 个项目移至「\($0)」" }
            ?? "已将 \(projects.count) 个项目恢复自动分组"
    }

    private func fetchSelected() async {
        guard !batchRunning, store.phase != .scanning else { return }
        let gitProjects = selectedProjects.filter {
            GitService.hasGit(URL(fileURLWithPath: $0.path))
        }
        guard !gitProjects.isEmpty else {
            batchFeedback = "所选项目均非 Git 仓库"
            return
        }

        batchRunning = true
        batchFeedback = nil
        var succeeded = 0
        var failed = 0
        for project in gitProjects {
            let result = await GitSyncService.run(.fetch, in: URL(fileURLWithPath: project.path))
            if result.status == .succeeded {
                succeeded += 1
                await store.refreshGit(for: project.path)
            } else {
                failed += 1
            }
        }
        batchRunning = false
        batchFeedback = failed == 0
            ? "已 Fetch \(succeeded) 个仓库"
            : "Fetch 完成：\(succeeded) 个成功，\(failed) 个失败"
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
