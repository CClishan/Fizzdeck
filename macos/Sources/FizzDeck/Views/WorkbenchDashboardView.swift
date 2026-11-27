import SwiftUI

struct WorkbenchDashboardView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @AppStorage(CopyModePreferences.onboardingSeenKey) private var onboardingSeen = false

    @State private var freeDiskBytes: Int64?
    @State private var scrolledPastTop = false
    @State private var onboardingStep = 0

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

    private var kpi: DashboardKPISummary {
        DashboardMetrics.kpiSummary(
            projects: store.projects,
            commitActivity: store.commitActivity
        )
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
                            header(width: contentWidth)
                            mainColumns(width: contentWidth)
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
    }

    @ViewBuilder
    private func header(width: CGFloat) -> some View {
        if width >= 660 {
            HStack(alignment: .top, spacing: 20) {
                headerDateBlock
                Spacer(minLength: 16)
                headerKPIs(alignment: .trailing)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                headerDateBlock
                headerKPIs(alignment: .leading)
            }
        }
    }

    private var headerDateBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            if copyMode == .plain {
                Text("\(FizzCopy.greeting()) · \(formattedToday)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Text(
                    FizzCopy.dashboardStatusLine(
                        activeCount: focusPartition.focused.count,
                        brokenCount: brokenFocusedCount,
                        attentionCount: attentionItems.count,
                        mode: .plain
                    )
                )
                .font(.system(size: 25, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            } else {
                Text(formattedToday)
                    .font(.system(size: 25, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .layoutPriority(1)
    }

    private func headerKPIs(alignment: HorizontalAlignment) -> some View {
        HStack(spacing: 24) {
            if copyMode == .plain {
                kpiNumber(
                    value: "\(kpi.weeklySessions)",
                    label: "本周对话",
                    alignment: alignment
                )
                kpiNumber(
                    value: "\(kpi.weeklyTouchedFiles)",
                    label: FizzCopy.weeklyOutputLabel(.plain),
                    alignment: alignment
                )
            } else {
                kpiNumber(
                    value: "\(kpi.weeklyCommits)",
                    label: FizzCopy.weeklyOutputLabel(.pro),
                    alignment: alignment
                )
                kpiNumber(
                    value: "\(kpi.weeklySessions)",
                    label: "AI 会话",
                    alignment: alignment
                )
            }

            if let cost = Format.cost(kpi.weeklyCostUSD, estimated: kpi.costIsEstimate) {
                kpiNumber(
                    value: cost,
                    label: copyMode == .plain
                        ? "本周花费"
                        : (kpi.costIsEstimate ? "本周费用(估)" : "本周费用"),
                    alignment: alignment
                )
                .help(costTooltip)
            } else if kpi.weeklyTokens > 0 {
                kpiNumber(
                    value: Format.tokens(kpi.weeklyTokens),
                    label: "本周 tokens",
                    alignment: alignment
                )
            }
        }
    }

    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M 月 d 日 EEEE"
        return formatter.string(from: Date())
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        parts.append(attentionItems.isEmpty ? "暂无待处理" : "\(attentionItems.count) 项待处理")
        let running = store.runningCount
        if running > 0 {
            parts.append("\(running) 个运行中")
        }
        return parts.joined(separator: " · ")
    }

    private var costTooltip: String {
        var parts: [String] = []
        if let monthly = Format.cost(kpi.monthlyCostUSD, estimated: kpi.costIsEstimate) {
            parts.append("近 30 天 \(monthly)")
        }
        if let delta = kpi.weekOverWeekCostDeltaPercent {
            let sign = delta >= 0 ? "↑" : "↓"
            parts.append(String(format: "较上周 %@ %.0f%%", sign, abs(delta)))
        }
        return parts.isEmpty ? "AI 会话费用估算" : parts.joined(separator: " · ")
    }

    private func kpiNumber(
        value: String,
        label: String,
        alignment: HorizontalAlignment = .trailing
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: value)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func mainColumns(width: CGFloat) -> some View {
        if width >= 920 {
            let widths = OverviewLayoutPolicy.splitWidths(
                totalWidth: width,
                spacing: FizzSpacing.grid,
                leadingRatio: 0.58
            )
            HStack(alignment: .top, spacing: FizzSpacing.grid) {
                leftColumn
                    .frame(width: widths.leading, alignment: .top)
                rightColumn
                    .frame(width: widths.trailing, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                leftColumn
                rightColumn
            }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            if copyMode == .plain && !onboardingSeen && !store.projects.isEmpty {
                onboardingCard
            }
            if isAllClear {
                allClearCard
            }
            ContinueWorkSection(items: continueItems)
            AttentionQueueView(
                showsTabs: copyMode == .pro,
                focusedOnly: copyMode == .plain
            )
            WeeklyTimelineCard(columns: timelineColumns, copyMode: copyMode) { path in
                if let project = store.projects.first(where: { $0.path == path }) {
                    store.openProject(project, tab: .progress)
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
            if copyMode == .plain {
                WorkbenchStatusCard(
                    runningProjects: runningProjects,
                    cloudProjects: cloudProjects,
                    healthAlerts: healthAlerts
                )

                AICostBreakdownCard(
                    projects: store.projects,
                    kpi: kpi
                )

                CommitHeatmapCard(
                    snapshot: store.commitActivity,
                    projects: store.projects
                ) { _ in
                    store.openConversations()
                }
            } else {
                CommitHeatmapCard(
                    snapshot: store.commitActivity,
                    projects: store.projects
                ) { dayKey in
                    store.openLibrary(LibraryQuery(commitDayKey: dayKey))
                }

                AICostBreakdownCard(
                    projects: store.projects,
                    kpi: kpi
                )

                WorkbenchStatusCard(
                    runningProjects: runningProjects,
                    cloudProjects: cloudProjects,
                    healthAlerts: healthAlerts
                )
            }
        }
    }

    private var onboardingCard: some View {
        let steps: [(title: String, body: String)] = [
            ("1/3 认识侧栏状态点", "绿点脉冲 = AI 正在干活，红点 = 跑不起来或上次对话报错，橙点 = 有改动还没存版本。只有你关注的项目才会亮灯。"),
            ("2/3 从「接着做」回到上次进度", "不用翻终端或记住命令，点一下「继续对话」直接回到上次聊到的地方。"),
            ("3/3 用「接力卡」跨工具交接", "换了别的 AI 或对话太长时，点「复制接力卡」一键把最近进度贴给新对话（自动打码密钥）。"),
        ]
        let clamped = min(steps.count - 1, max(0, onboardingStep))
        let current = steps[clamped]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FizzIcon(symbol: "sparkles", size: 13)
                    .foregroundStyle(FizzTheme.accent)
                Text(current.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button("跳过") {
                    onboardingSeen = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(current.body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                HStack(spacing: 5) {
                    ForEach(steps.indices, id: \.self) { index in
                        Circle()
                            .fill(index == clamped ? FizzTheme.accent : FizzTheme.hairline)
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button(clamped < steps.count - 1 ? "下一步" : "知道了") {
                    if clamped < steps.count - 1 {
                        onboardingStep += 1
                    } else {
                        onboardingSeen = true
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(FizzTheme.accent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .fizzCard(radius: FizzRadius.panel)
    }

    private var allClearCard: some View {
        let recentProjects = Array(HomeSort.recent.sort(store.projects).prefix(4))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FizzIcon(symbol: "checkmark.circle", size: 15)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(FizzCopy.allClearTitle(copyMode))
                        .font(.system(size: 14, weight: .semibold))
                    Text(copyMode == .plain ? "没有待处理问题，也没有运行中的服务" : "没有待处理项、陈旧改动或运行中的服务")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !recentProjects.isEmpty {
                HStack(spacing: 8) {
                    ForEach(recentProjects) { project in
                        Button {
                            store.openProject(project)
                        } label: {
                            HStack(spacing: 6) {
                                ProjectBadgeIcon(project: project, size: 18, framed: false)
                                Text(project.displayName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(FizzTheme.recessedFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .fizzCard(radius: FizzRadius.panel)
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
}
