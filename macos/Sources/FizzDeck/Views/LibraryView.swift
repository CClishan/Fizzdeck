import SwiftUI

struct LibraryView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let query: LibraryQuery

    @AppStorage("fizzdeck.home.viewMode") private var modeRaw = HomeViewMode.cards.rawValue
    @AppStorage("fizzdeck.home.sort") private var sortRaw = HomeSort.recent.rawValue
    @State private var facets = HomeFacets()
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
        store.filteredProjects
    }

    private var visibleProjects: [RepoProject] {
        HomeDashboardModel.visibleProjects(from: matchingProjects, facets: facets, sort: sort)
    }

    private var selectedProjects: [RepoProject] {
        visibleProjects.filter { selectedPaths.contains($0.path) }
    }

    private var availableGroups: [String] {
        HomeDashboardModel.availableGroups(in: matchingProjects)
    }

    private var availableTools: [String] {
        HomeDashboardModel.availableTools(in: matchingProjects)
    }

    private var allVisibleSelected: Bool {
        !visibleProjects.isEmpty && visibleProjects.allSatisfy { selectedPaths.contains($0.path) }
    }

    private var runningCount: Int {
        visibleProjects.filter { $0.port == .running }.count
    }

    private var headerDetail: String {
        HomeDashboardModel.headerDetail(
            visibleCount: visibleProjects.count,
            matchingCount: matchingProjects.count,
            hasFacets: facets.hasAny,
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
                            selectionMode: selectionMode,
                            groupCount: { HomeDashboardModel.groupCount($0, in: matchingProjects, facets: facets) },
                            colorCount: { HomeDashboardModel.colorCount($0, in: matchingProjects, facets: facets) },
                            toolCount: { HomeDashboardModel.toolCount($0, in: matchingProjects, facets: facets) },
                            onSelectMode: setMode,
                            onSelectSort: setSort,
                            onSetGroup: setGroupFilter,
                            onSetColor: setColorFilter,
                            onSetTool: setToolFilter,
                            onClearFacets: clearFacets,
                            onToggleSelection: toggleSelectionMode
                        )

                        if visibleProjects.isEmpty {
                            emptyResults
                        } else {
                            HomeProjectBrowser(
                                projects: visibleProjects,
                                mode: mode,
                                selectionMode: selectionMode,
                                selectedPaths: selectedPaths,
                                selectedCount: selectedProjects.count,
                                allVisibleSelected: allVisibleSelected,
                                batchRunning: batchRunning,
                                isScanning: store.phase == .scanning,
                                batchFeedback: batchFeedback,
                                onToggleSelection: toggleSelection,
                                onCopyCleanup: copyCleanupCommands,
                                onRescanSelected: { Task { await rescanSelected() } },
                                onToggleSelectAll: toggleSelectAll,
                                onClearSelection: clearSelection,
                                onEndSelection: endSelectionAnimated
                            )
                        }
                    }
                    .padding(FizzSpacing.page)
                }
            }
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

    private var emptyResults: some View {
        ContentUnavailableView {
            Label("没有匹配项目", systemImage: "square.grid.2x2")
        } description: {
            Text(facets.hasAny
                ? "当前分组、颜色或工具条件下没有项目，清除筛选后再试。"
                : "没有找到匹配的项目。")
        } actions: {
            if facets.hasAny || !store.query.isEmpty {
                Button("清除筛选") {
                    clearFacets()
                    store.query = ""
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
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

    private func syncFromQuery() {
        facets.group = query.group
        facets.color = query.color
        facets.tool = query.tool
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
            facets.group = value
            batchFeedback = nil
        }
    }

    private func setColorFilter(_ value: TagColor?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            facets.color = value
        }
    }

    private func setToolFilter(_ value: String?) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            facets.tool = value
        }
    }

    private func clearFacets() {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.standard)) {
            facets.clear()
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
