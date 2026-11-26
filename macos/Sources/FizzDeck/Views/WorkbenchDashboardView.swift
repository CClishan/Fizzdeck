import SwiftUI

struct WorkbenchDashboardView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions

    @State private var contentWidth: CGFloat = 1040
    @State private var freeDiskBytes: Int64?

    private var attentionItems: [ProjectAttentionItem] {
        let now = Date()
        return ProjectAttentionQueue.items(projects: store.projects, testRuns: actions.testRuns)
            .filter { !store.isAttentionSuppressed(for: $0.project, kind: $0.kind, at: now) }
    }

    private var kpi: DashboardKPISummary {
        DashboardMetrics.kpiSummary(
            projects: store.projects,
            commitActivity: store.commitActivity
        )
    }

    private var toolShares: [AIToolShare] {
        DashboardMetrics.weeklyToolShares(projects: store.projects)
    }

    private var continueItems: [ContinueWorkItem] {
        DashboardMetrics.continueWorkItems(projects: store.projects, limit: 4)
    }

    private var runningProjects: [RepoProject] {
        store.projects
            .filter { $0.port == .running }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var healthAlerts: [HealthAlert] {
        DashboardMetrics.healthAlerts(projects: store.projects, freeDiskBytes: freeDiskBytes)
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
            && healthAlerts.isEmpty
            && !store.projects.isEmpty
    }

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FizzSpacing.section) {
                        header
                        if !toolShares.isEmpty {
                            aiShareBar
                        }
                        mainColumns
                    }
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.width
                    } action: { newWidth in
                        contentWidth = newWidth
                    }
                    .padding(FizzSpacing.page)
                }
            }
        }
        .task {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            freeDiskBytes = values?.volumeAvailableCapacityForImportantUsage
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(formattedToday)
                    .font(.system(size: 25, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            HStack(spacing: 24) {
                kpiNumber(
                    value: "\(kpi.weeklyCommits)",
                    label: "本周提交"
                )
                kpiNumber(
                    value: "\(kpi.weeklySessions)",
                    label: "AI 会话"
                )
                if let cost = Format.cost(kpi.weeklyCostUSD, estimated: kpi.costIsEstimate) {
                    kpiNumber(
                        value: cost,
                        label: kpi.costIsEstimate ? "本周费用(估)" : "本周费用"
                    )
                    .help(costTooltip)
                } else if kpi.weeklyTokens > 0 {
                    kpiNumber(
                        value: Format.tokens(kpi.weeklyTokens),
                        label: "本周 tokens"
                    )
                }
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

    private func kpiNumber(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var aiShareBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(toolShares) { share in
                        let width = max(22, (proxy.size.width - CGFloat(max(0, toolShares.count - 1)) * 3) * share.fraction)
                        HStack(spacing: 4) {
                            if width >= 78 {
                                Text(share.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                Text("\(Int((share.fraction * 100).rounded()))%")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            } else if width >= 36 {
                                Text("\(Int((share.fraction * 100).rounded()))%")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: width, height: 24)
                        .background(
                            DetectedTool(rawValue: share.tool)?.tint ?? FizzTheme.accent,
                            in: Capsule()
                        )
                        .help("\(share.title) · \(share.sessions) 会话 · \(Format.tokens(share.tokens)) tokens")
                    }
                }
            }
            .frame(height: 24)

            HStack(spacing: 12) {
                ForEach(toolShares) { share in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(DetectedTool(rawValue: share.tool)?.tint ?? FizzTheme.accent)
                            .frame(width: 6, height: 6)
                        Text("\(share.title) \(Int((share.fraction * 100).rounded()))%")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("本周 AI 用量占比：" + toolShares.map { "\($0.title) \(Int(($0.fraction * 100).rounded()))%" }.joined(separator: "，"))
    }

    @ViewBuilder
    private var mainColumns: some View {
        if contentWidth >= 960 {
            let widths = OverviewLayoutPolicy.splitWidths(
                totalWidth: contentWidth,
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
            if isAllClear {
                allClearCard
            }
            ContinueWorkSection(items: continueItems)
            AttentionQueueView(showsTabs: true)
            WeeklyTimelineCard(columns: timelineColumns) { path in
                if let project = store.projects.first(where: { $0.path == path }) {
                    store.openProject(project)
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
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
                healthAlerts: healthAlerts
            )
        }
    }

    private var allClearCard: some View {
        let recentProjects = Array(HomeSort.recent.sort(store.projects).prefix(4))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FizzIcon(symbol: "checkmark.circle", size: 15)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("一切就绪")
                        .font(.system(size: 14, weight: .semibold))
                    Text("没有待处理项、陈旧改动或运行中的服务")
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
