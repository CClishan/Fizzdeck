import SwiftUI

struct WorkbenchDashboardView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @AppStorage(CopyModePreferences.onboardingSeenKey) private var onboardingSeen = false

    @State private var freeDiskBytes: Int64?
    @State private var scrolledPastTop = false
    @State private var onboardingStep = 0
    @State private var showingHeatmap = false
    let onShowRecap: () -> Void

    private var focusPartition: FocusPartition {
        ProjectFocusPolicy.partition(projects: store.projects)
    }

    private var attentionItems: [ProjectAttentionItem] {
        let now = Date()
        return ProjectAttentionQueue.items(
            projects: store.projects,
            testRuns: actions.testRuns,
            focusedPaths: copyMode == .plain ? focusPartition.focusedPaths : nil,
            copyMode: copyMode,
            doctorReports: store.doctorReports
        )
        .filter { !store.isAttentionSuppressed(for: $0.project, kind: $0.kind, at: now) }
    }

    private var brokenFocusedCount: Int {
        focusPartition.focused.filter { entry in
            ProjectFocusPolicy.statusDot(
                for: entry.project,
                testRuns: actions.testRuns,
                activeAIProjectPaths: store.activeAIProjectPaths
            ) == .broken
        }.count
    }

    private var continueItems: [ContinueWorkItem] {
        DashboardMetrics.continueWorkItems(
            projects: store.projects,
            limit: copyMode == .plain ? 3 : 4
        )
    }

    private var runningProjects: [RepoProject] {
        store.projects
            .filter { $0.port == .running }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var healthAlerts: [HealthAlert] {
        DashboardMetrics.healthAlerts(projects: store.projects, freeDiskBytes: freeDiskBytes)
    }

    private var cloudProjects: [RepoProject] {
        focusPartition.focused.map(\.project).filter { $0.behind > 0 && !store.isAttentionSuppressed(for: $0, kind: .behind) }
    }

    private var timelineColumns: [TimelineDayColumn] {
        DashboardMetrics.weeklyTimeline(
            projects: store.projects,
            commitActivity: store.commitActivity
        )
    }

    private var isAllClear: Bool {
        continueItems.isEmpty
            && attentionItems.isEmpty
            && runningProjects.isEmpty
            && (copyMode == .pro || store.activeAIProjectPaths.isEmpty)
            && healthAlerts.isEmpty
            && !store.projects.isEmpty
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
                            header
                            actionPanels(width: contentWidth)
                            timeline
                            statusCard
                            if copyMode == .plain && !onboardingSeen { onboardingCard }
                            if isAllClear { allClearCard }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(FizzSpacing.page)
                    }
                    .frame(width: outerWidth, height: proxy.size.height)
                    .fizzTracksScrollPastTop()
                    .overlay(alignment: .top) {
                        FizzScrollTopHairline(
                            visible: scrolledPastTop
                        )
                    }
                }
            }
        }
        .task {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            freeDiskBytes = values?.volumeAvailableCapacityForImportantUsage
        }
        .onPreferenceChange(FizzScrollPastTopKey.self) { value in
            scrolledPastTop = value
        }
        .sheet(isPresented: $showingHeatmap) {
            VStack(spacing: FizzSpacing.row) {
                HStack {
                    Spacer()
                    FizzIconButton(title: "关闭热力图", symbol: "xmark", height: .compact) { showingHeatmap = false }
                        .keyboardShortcut(.cancelAction)
                }
                CommitHeatmapCard(snapshot: store.commitActivity, projects: store.projects) { dayKey in
                    showingHeatmap = false
                    if copyMode == .plain {
                        store.openConversations()
                    } else {
                        store.openLibrary(LibraryQuery(commitDayKey: dayKey))
                    }
                }
            }
            .padding(FizzSpacing.panel)
            .frame(width: 600)
            .background(FizzTheme.page)
        }
    }

    private var header: some View {
        FizzPageHeader(
            title: copyMode == .plain ? FizzCopy.dashboardStatusLine(
                activeCount: focusPartition.focused.count,
                brokenCount: brokenFocusedCount,
                attentionCount: attentionItems.count,
                mode: .plain
            ) : "工作台",
            subtitle: "\(FizzCopy.greeting()) · \(formattedToday)"
        ) {
            let summary = weeklySummary
            Button(action: onShowRecap) {
                HStack(spacing: 6) {
                    Text(summary).foregroundStyle(.secondary)
                    Text("复盘").font(FizzTypography.caption(.medium))
                    FizzIcon(.xs, symbol: "arrow.up.right").accessibilityHidden(true)
                }
                .font(FizzTypography.caption)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fizzKeyboardAction(action: onShowRecap)
            .accessibilityLabel("复盘")
            .accessibilityValue(summary)
        }
    }

    private var formattedToday: String {
        Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_Hans")))
    }

    private var weeklySummary: String {
        let totals = DashboardMetrics.weeklyConversationTotals(projects: store.projects)
        var parts = ["近 7 天 \(totals.sessions) 次对话"]
        if let amount = totals.cost.amount { parts.append(WeeklyRecapMetric.cost.label(amount)) }
        if let tokens = totals.value(.tokens) { parts.append("\(WeeklyRecapMetric.tokens.label(tokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    private func actionPanels(width: CGFloat) -> some View {
        let columns = OverviewLayoutPolicy.splitWidths(totalWidth: width, spacing: FizzSpacing.grid, leadingRatio: 0.52)
        return HStack(alignment: .top, spacing: FizzSpacing.grid) {
            ContinueWorkSection(items: continueItems)
                .frame(width: columns.leading)
            AttentionQueueView(showsTabs: copyMode == .pro, focusedOnly: copyMode == .plain, fillHeight: true)
                .frame(width: columns.trailing)
        }
    }

    private var timeline: some View {
        WeeklyTimelineCard(columns: timelineColumns, copyMode: copyMode) { path in
            if let project = store.projects.first(where: { $0.path == path }) {
                store.openProject(project, tab: .progress)
            }
        } onOpenHeatmap: {
            showingHeatmap = true
        }
    }

    private var statusCard: some View {
        WorkbenchStatusCard(runningProjects: runningProjects, cloudProjects: cloudProjects, healthAlerts: healthAlerts)
    }

    private var onboardingCard: some View {
        let steps: [(title: String, body: String)] = [
            ("1/3 认识侧栏状态点", "绿点脉冲 = AI 正在干活，红点 = 跑不起来或上次对话报错，橙点 = 有改动还没存版本。只有你关注的项目才会亮灯。"),
            ("2/3 从「接着做」回到上次进度", "不用翻终端或记住命令，点一下「继续对话」直接回到上次聊到的地方。"),
            ("3/3 用「接力卡」跨工具交接", "换了别的 AI 或对话太长时，点「复制接力卡」一键把最近进度贴给新对话（自动打码密钥）。"),
        ]
        let clamped = min(steps.count - 1, max(0, onboardingStep))
        let current = steps[clamped]

        return Panel(title: current.title, symbol: "sparkles") {
            Text(current.body)
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } accessory: {
            FizzActionButton(title: "跳过", height: .compact) { onboardingSeen = true }
            FizzActionButton(title: clamped < steps.count - 1 ? "下一步" : "知道了", height: .compact,
                             prominence: continueItems.isEmpty ? .primary : .secondary) {
                if clamped < steps.count - 1 {
                    onboardingStep += 1
                } else {
                    onboardingSeen = true
                }
            }
        }
    }

    private var allClearCard: some View {
        let recentProjects = Array(HomeSort.recent.sort(store.projects).prefix(4))

        return Panel(title: FizzCopy.allClearTitle(copyMode), symbol: "checkmark.circle") {
            HStack(spacing: FizzSpacing.row) {
                ForEach(recentProjects) { project in
                    FizzActionButton(title: project.displayName, height: .compact) {
                        store.openProject(project)
                    }
                }
            }
        }
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
                VStack(spacing: FizzSpacing.row) {
                    FizzIcon(.lg, symbol: "square.stack.3d.up").accessibilityHidden(true)
                    Text("还没有项目").font(FizzTypography.sectionTitle)
                }
            } description: {
                Text("扫描常用目录或手动添加文件夹，FizzDeck 会分析 Git、AI 会话和体积。")
            } actions: {
                HStack(spacing: FizzSpacing.row) {
                    FizzActionButton(title: "手动添加文件夹") {
                        Task { await store.addRoot() }
                    }
                    FizzActionButton(title: "智能扫描本机项目", prominence: .primary) {
                        store.presentFirstRunScan()
                    }
                }
            }
        }
    }
}
