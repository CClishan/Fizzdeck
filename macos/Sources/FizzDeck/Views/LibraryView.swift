import SwiftUI

struct LibraryView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let query: LibraryQuery

    @AppStorage("fizzdeck.home.viewMode") private var modeRaw = HomeViewMode.cards.rawValue
    @AppStorage("fizzdeck.home.sort") private var sortRaw = HomeSort.recent.rawValue
    @AppStorage(LibraryCoverPreference.key) private var showCoverPreview = LibraryCoverPreference.defaultValue
    @State private var localQuery = LibraryQuery()
    @State private var selectionMode = false
    @State private var selectedPaths: Set<String> = []
    @State private var batchFeedback: LibraryBatchResult?
    @State private var batchRunning = false
    @State private var showIdleProjects = false
    @State private var focusedProjectPath: String?
    @State private var browserWidth: CGFloat = 960
    @State private var scrolledPastTop = false
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

    private var availableFrameworks: [HomeDashboardModel.FrameworkChoice] {
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

    private var estimatedColumns: Int {
        max(1, Int((browserWidth + FizzSpacing.grid) / (260 + FizzSpacing.grid)))
    }

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    let outerWidth = max(320, proxy.size.width)
                    let contentWidth = max(260, outerWidth - FizzSpacing.page * 2)

                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: FizzSpacing.section) {
                            HomeHeaderView(
                                title: FizzL10n.text("项目库", "Library"),
                                detail: headerDetail,
                                mode: mode,
                                showsCoverPreview: showCoverPreview,
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
                                onToggleSelection: toggleSelectionMode,
                                onToggleCoverPreview: toggleCoverPreview
                            )

                            filterToolbar

                            if let dayKey = localQuery.commitDayKey {
                                commitDayBanner(dayKey)
                                    .transition(
                                        .opacity.combined(with: .move(edge: .top))
                                    )
                            }

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
                                    batchFeedback: batchFeedback?.message,
                                    showsCoverPreview: showCoverPreview,
                                    knownGroups: store.knownGroups,
                                    allSelectedStarred: allSelectedStarred,
                                    focusedProjectPath: focusedProjectPath,
                                    onBatchStar: batchStar,
                                    onBatchGroup: batchGroup,
                                    onBatchFetch: { Task { await fetchSelected() } },
                                    onToggleSelection: toggleSelection,
                                    onCopyCleanup: copyCleanupCommands,
                                    onRescanSelected: { Task { await rescanSelected() } },
                                    onToggleSelectAll: toggleSelectAll,
                                    onClearSelection: clearSelection
                                )

                                if !split.idle.isEmpty {
                                    idleSection(split.idle)
                                }
                            }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(FizzSpacing.page)
                    }
                    .frame(width: outerWidth, height: proxy.size.height)
                    .onChange(of: contentWidth, initial: true) { _, newValue in
                        if abs(browserWidth - newValue) > 0.5 {
                            browserWidth = newValue
                        }
                    }
                    .fizzTracksScrollPastTop()
                    .overlay(alignment: .top) {
                        FizzScrollTopHairline(
                            visible: scrolledPastTop
                        )
                    }
                }
            }
        }
        .focusable(mode == .cards, interactions: .edit)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            moveFocus(.up)
        }
        .onKeyPress(.downArrow) {
            moveFocus(.down)
        }
        .onKeyPress(.leftArrow) {
            moveFocus(.left)
        }
        .onKeyPress(.rightArrow) {
            moveFocus(.right)
        }
        .onKeyPress(keys: [.return]) { press in
            guard mode == .cards, !searchFocused, let project = focusedProject else { return .ignored }
            if press.modifiers.contains(.command) {
                Task { await resumeFocusedProject(project) }
            } else {
                store.openProject(project)
            }
            return .handled
        }
        .onKeyPress(.space) {
            guard mode == .cards, !searchFocused, let project = focusedProject else { return .ignored }
            if selectionMode {
                toggleSelection(project)
            } else {
                store.openProject(project)
            }
            return .handled
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
            if let focusedProjectPath, !paths.contains(focusedProjectPath) {
                self.focusedProjectPath = nil
            }
        }
        .onPreferenceChange(FizzScrollPastTopKey.self) { value in
            scrolledPastTop = value
        }
        .animation(
            FizzMotion.resolved(reduceMotion, FizzMotion.spring),
            value: localQuery.commitDayKey
        )
    }

    private var filterToolbar: some View {
        FlowLayout(spacing: FizzSpacing.row) {
            projectSearchField.frame(width: min(browserWidth, 310))
            quickFilters
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var projectSearchField: some View {
        HStack(spacing: 6) {
            FizzIcon(.sm, symbol: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(FizzL10n.text("搜索项目、分支、路径或技术栈（⌘F）", "Search Library (⌘F)"), text: $localQuery.searchText)
                .textFieldStyle(.plain)
                .font(FizzTypography.body)
                .focused($searchFocused)
                .accessibilityLabel(FizzL10n.text("搜索项目库", "Search Library"))
                .help(FizzL10n.text("搜索项目、分支、路径或技术栈（⌘F）", "Search names, branches, paths, or stacks (⌘F)"))
            if !localQuery.searchText.isEmpty {
                Button {
                    localQuery.searchText = ""
                } label: {
                    FizzIcon(.sm, symbol: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: FizzControlHeight.compact.rawValue, height: FizzControlHeight.compact.rawValue)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(FizzL10n.text("清除搜索", "Clear search"))
                .accessibilityLabel(FizzL10n.text("清除项目搜索", "Clear project search"))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, localQuery.searchText.isEmpty ? 10 : 2)
        .frame(height: FizzControlHeight.compact.rawValue)
        .background(FizzTheme.recessedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.control)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var quickFilters: some View {
        quickChip(FizzL10n.text("星标", "Starred"), active: localQuery.starredOnly) {
            localQuery.starredOnly.toggle()
        }
        quickChip(FizzL10n.text("有改动", "Changed"), active: localQuery.dirtyOnly) {
            localQuery.dirtyOnly.toggle()
        }
        quickChip(FizzL10n.text("运行中", "Running"), active: localQuery.runningOnly) {
            localQuery.runningOnly.toggle()
        }
        quickChip(FizzL10n.text("有 AI 会话", "AI sessions"), active: localQuery.hasSessionsOnly) {
            localQuery.hasSessionsOnly.toggle()
        }
        quickChip(FizzL10n.text("有未推送", "Unpushed"), active: localQuery.unpushedOnly) {
            localQuery.unpushedOnly.toggle()
        }
    }

    private func commitDayBanner(_ dayKey: String) -> some View {
        HStack(spacing: 9) {
            FizzIcon(.md, symbol: "calendar.badge.clock")
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(FizzL10n.text("提交日期筛选", "Commit date"))
                    .font(FizzTypography.micro)
                    .foregroundStyle(.secondary)
                Text(formattedCommitDay(dayKey))
                    .font(FizzTypography.cardTitle)
            }

            TagChip(text: FizzL10n.text("\(visibleProjects.count) 个项目", SessionSummaryText.englishCount(visibleProjects.count, "project")), compact: true)

            Spacer(minLength: 8)

            FizzActionButton(title: FizzL10n.text("清除", "Clear"), symbol: "xmark", height: .compact) {
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                    localQuery.commitDayKey = nil
                }
            }
            .help(FizzL10n.text("清除提交日期筛选", "Clear commit date filter"))
            .accessibilityLabel(FizzL10n.text("清除提交日期筛选", "Clear commit date filter"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .fizzAdaptiveShadow(.subtle)
        .accessibilityElement(children: .contain)
    }

    private func formattedCommitDay(_ dayKey: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayKey) else { return dayKey }
        let display = DateFormatter()
        display.locale = FizzL10n.locale
        display.setLocalizedDateFormatFromTemplate("yMMMMdEEEE")
        return display.string(from: date)
    }

    private func quickChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FizzTypography.caption(active ? .semibold : .medium))
                .foregroundStyle(active ? .white : .secondary)
                .padding(.horizontal, 10)
                .frame(height: FizzControlHeight.compact.rawValue)
                .background(
                    active ? FizzTheme.selectedFill : FizzTheme.mutedFill,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityRemoveTraits(active ? [] : .isSelected)
    }

    private func idleSection(_ idleProjects: [RepoProject]) -> some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            Button {
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                    showIdleProjects.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    FizzIcon(
                        .xs, symbol: showIdleProjects ? "chevron.down" : "chevron.right"
                    )
                    .foregroundStyle(.secondary)
                    Text(FizzL10n.text("闲置 30 天以上", "Inactive for 30+ days"))
                        .font(FizzTypography.sectionTitle)
                        .foregroundStyle(.secondary)
                    Text("\(idleProjects.count)")
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: FizzControlHeight.compact.rawValue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FizzL10n.text("闲置 30 天以上的项目，共 \(idleProjects.count) 个", "\(SessionSummaryText.englishCount(idleProjects.count, "project")) inactive for 30 days or more"))
            .accessibilityValue(showIdleProjects ? FizzL10n.text("已展开", "Expanded") : FizzL10n.text("已折叠", "Collapsed"))

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
                                showsCoverPreview: showCoverPreview,
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
        .animation(
            FizzMotion.resolved(reduceMotion, FizzMotion.spring),
            value: showIdleProjects
        )
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label(FizzL10n.text("没有匹配项目", "No matching projects"), systemImage: "square.grid.2x2")
        } description: {
            Text(localQuery.hasActiveFilters
                ? FizzL10n.text("当前筛选条件下没有项目，清除筛选后再试。", "No projects match these filters. Clear the filters to try again.")
                : FizzL10n.text("没有找到匹配的项目。", "No projects match your search."))
        } actions: {
            if localQuery.hasActiveFilters || !store.query.isEmpty {
                FizzActionButton(title: FizzL10n.text("清除筛选", "Clear filters"), height: .compact) {
                    clearFilters()
                    store.query = ""
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.phase == .scanning {
            VStack(spacing: 12) {
                ProgressView()
                Text(FizzL10n.text("正在扫描本机项目…", "Scanning local projects…"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(FizzL10n.text("还没有项目", "No projects yet"), systemImage: "square.stack.3d.up")
            } description: {
                Text(FizzL10n.text("扫描常用目录或手动添加文件夹，FizzDeck 会分析 Git、AI 会话和体积。", "Scan for projects or add a folder to see Git status, AI sessions, and disk usage."))
            } actions: {
                HStack(spacing: FizzSpacing.row) {
                    FizzActionButton(title: FizzL10n.text("手动添加文件夹", "Add a folder…")) {
                        Task { await store.addRoot() }
                    }
                    FizzActionButton(title: FizzL10n.text("智能扫描本机项目", "Scan for projects"), prominence: .primary) {
                        store.presentFirstRunScan()
                    }
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

    private var keyboardNavigableProjects: [RepoProject] {
        let split = partitioned
        return showIdleProjects ? split.active + split.idle : split.active
    }

    private var focusedProject: RepoProject? {
        guard let focusedProjectPath else { return nil }
        return keyboardNavigableProjects.first { $0.path == focusedProjectPath }
    }

    private func moveFocus(_ direction: LibraryGridDirection) -> KeyPress.Result {
        guard mode == .cards, !searchFocused else { return .ignored }
        let list = keyboardNavigableProjects
        let currentIndex = focusedProjectPath.flatMap { path in
            list.firstIndex { $0.path == path }
        }
        guard let next = LibraryKeyboardNavigation.nextIndex(
            current: currentIndex,
            direction: direction,
            count: list.count,
            columns: estimatedColumns
        ) else { return .ignored }
        focusedProjectPath = list[next].path
        return .handled
    }

    private func resumeFocusedProject(_ project: RepoProject) async {
        for toolSession in project.sessions.byTool {
            guard DetectedTool(rawValue: toolSession.tool)?.supportsResume == true,
                  let sessionID = toolSession.lastSessionID,
                  let record = project.sessions.recentSessions.first(where: {
                      $0.tool == toolSession.tool && $0.id == sessionID
                  })
            else { continue }
            _ = await SessionResumeService.resume(
                session: record,
                projectPath: project.path,
                preferredTarget: .auto
            )
            return
        }
        store.openProject(project)
    }

    private func syncFromQuery() {
        localQuery = query
        batchFeedback = nil
    }

    private func setMode(_ value: HomeViewMode) {
        guard mode != value else { return }
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
            modeRaw = value.rawValue
        }
    }

    private func toggleCoverPreview() {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
            showCoverPreview.toggle()
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

    private func endSelection() {
        selectionMode = false
        selectedPaths.removeAll()
        batchFeedback = nil
    }

    private func copyCleanupCommands() {
        let result = HomeDashboardModel.batchCleanupCommands(for: selectedProjects)
        if let script = result.script {
            SystemActions.copy(script, feedback: nil)
            ToastCenter.shared.show(
                result.feedback,
                symbol: "doc.on.doc.fill",
                tint: Color.secondary,
                microViz: .compact(state: .done)
            )
        }
        batchFeedback = result.result
    }

    private func batchStar(_ starred: Bool) {
        let projects = selectedProjects
        guard !projects.isEmpty else { return }
        store.setStarred(starred, for: projects)
        let result = LibraryBatchResult.starred(projects.count, starred)
        batchFeedback = result
        ToastCenter.shared.show(
            result.message,
            symbol: starred ? "star.fill" : "star",
            tint: Color.secondary,
            microViz: .compact(state: .done)
        )
    }

    private func batchGroup(_ group: String?) {
        let projects = selectedProjects
        guard !projects.isEmpty else { return }
        store.setGroup(group, for: projects)
        let result = LibraryBatchResult.grouped(projects.count, group)
        batchFeedback = result
        ToastCenter.shared.show(
            result.message,
            symbol: "folder.fill",
            tint: Color.secondary,
            microViz: .compact(state: .done)
        )
    }

    private func fetchSelected() async {
        guard !batchRunning, store.phase != .scanning else { return }
        let gitProjects = selectedProjects.filter {
            GitService.hasGit(URL(fileURLWithPath: $0.path))
        }
        guard !gitProjects.isEmpty else {
            batchFeedback = .fetched(succeeded: 0, failed: 0)
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
        batchFeedback = .fetched(succeeded: succeeded, failed: failed)
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
            batchFeedback = .rescanned(0, missing: missing)
            return
        }

        batchRunning = true
        batchFeedback = nil
        await store.rescanProjects(existing)
        batchRunning = false
        batchFeedback = .rescanned(existing.count, missing: missing)
        ToastCenter.shared.show(
            FizzL10n.text("批量扫描完成", "Batch scan complete"),
            symbol: "arrow.clockwise.circle.fill",
            tint: Color.secondary,
            subtitle: batchFeedback?.message,
            microViz: .bars(
                values: existing.map { Double($0.weekly.values.reduce(0, +)) },
                improved: false
            )
        )
    }
}
