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
    @State private var now = Date()
    @State private var markAvailability = SessionMarkAvailabilityCheck.Results()
    let onShowRecap: () -> Void

    private var focusPartition: FocusPartition {
        ProjectFocusPolicy.partition(projects: store.projects, now: now)
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
            commitActivity: store.commitActivity,
            copyMode: copyMode
        )
    }

    private func isAllClear(attentionCount: Int) -> Bool {
        continueItems.isEmpty
            && attentionCount == 0
            && runningProjects.isEmpty
            && (copyMode == .pro || store.activeAIProjectPaths.isEmpty)
            && healthAlerts.isEmpty
            && !store.projects.isEmpty
    }

    var body: some View {
        let focusedPaths = focusPartition.focusedPaths
        let candidates = SessionMarkExpiryPolicy.attentionCandidates(in: store.marks, focusedPaths: focusedPaths, now: now)
        let check = SessionMarkAvailabilityCheck(marks: candidates.map(\.mark), scannedAt: store.scannedAt)
        let items = ProjectAttentionQueue.items(
            projects: store.projects, testRuns: actions.testRuns, focusedPaths: copyMode == .plain ? focusedPaths : nil,
            copyMode: copyMode, doctorReports: store.doctorReports,
            expiringMarks: markAvailability.confirmed(candidates)
        )
        let attentionCount = items.filter { !store.isAttentionSuppressed(for: $0.project, kind: $0.kind, at: now) }.count
        return Group {
            if store.projects.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    let outerWidth = max(320, proxy.size.width)
                    let contentWidth = max(260, outerWidth - FizzSpacing.page * 2)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: FizzSpacing.section) {
                            header(attentionCount: attentionCount)
                            actionPanels(width: contentWidth, items: items)
                            timeline
                            statusCard
                            if copyMode == .plain && !onboardingSeen { onboardingCard }
                            if isAllClear(attentionCount: attentionCount) { allClearCard }
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
        .task(id: check) {
            let verified = await check.run(reusing: markAvailability)
            if !Task.isCancelled { markAvailability = verified }
        }
        .task {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            freeDiskBytes = values?.volumeAvailableCapacityForImportantUsage
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { now = Date() }
            }
        }
        .onPreferenceChange(FizzScrollPastTopKey.self) { value in
            scrolledPastTop = value
        }
        .sheet(isPresented: $showingHeatmap) {
            VStack(spacing: FizzSpacing.row) {
                HStack {
                    Spacer()
                    FizzIconButton(title: FizzL10n.text("关闭热力图", "Close heatmap"), symbol: "xmark", height: .compact) { showingHeatmap = false }
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

    private func header(attentionCount: Int) -> some View {
        let title = copyMode == .plain ? FizzCopy.dashboardStatusLine(
            activeCount: focusPartition.focused.count, brokenCount: brokenFocusedCount,
            attentionCount: attentionCount, mode: .plain
        ) : FizzL10n.text("工作台", "Workbench")
        let heading = VStack(alignment: .leading, spacing: 4) {
            Text(title).font(FizzTypography.pageTitle).accessibilityAddTraits(.isHeader)
            Text("\(FizzCopy.greeting()) · \(formattedToday)").font(FizzTypography.body).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        let summary = weeklySummary
        let recap = Button(action: onShowRecap) {
            HStack(spacing: 6) {
                Text(summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(FizzL10n.text("复盘", "Recap")).font(FizzTypography.caption(.medium)).fixedSize()
                FizzIcon(.xs, symbol: "arrow.up.right").accessibilityHidden(true)
            }
            .font(FizzTypography.caption)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fizzKeyboardAction(action: onShowRecap)
        .accessibilityLabel(FizzL10n.text("复盘", "Recap"))
        .accessibilityValue(summary)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: FizzSpacing.grid) {
                heading.fixedSize()
                Spacer(minLength: 0)
                recap.fixedSize()
            }
            VStack(alignment: .leading, spacing: FizzSpacing.row) {
                heading
                recap
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattedToday: String {
        Date().formatted(.dateTime.month().day().weekday(.wide).locale(FizzL10n.locale))
    }

    private var weeklySummary: String {
        let totals = DashboardMetrics.weeklyConversationTotals(projects: store.projects)
        var parts = [FizzL10n.text("近 7 天 \(totals.sessions) 次对话", "Past 7 days: \(SessionSummaryText.englishCount(totals.sessions, "conversation"))")]
        if let amount = totals.cost.amount { parts.append(WeeklyRecapMetric.cost.label(amount)) }
        if let tokens = totals.value(.tokens) { parts.append("\(WeeklyRecapMetric.tokens.label(tokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    private func actionPanels(width: CGFloat, items: [ProjectAttentionItem]) -> some View {
        let columns = OverviewLayoutPolicy.splitWidths(totalWidth: width, spacing: FizzSpacing.grid, leadingRatio: 0.52)
        return HStack(alignment: .top, spacing: FizzSpacing.grid) {
            ContinueWorkSection(items: continueItems)
                .frame(width: columns.leading)
            AttentionQueueView(showsTabs: copyMode == .pro, fillHeight: true, workbenchItems: items, workbenchDate: now)
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
            (FizzL10n.text("1/3 认识侧栏状态点", "1/3 Read sidebar status dots"), FizzL10n.text("绿点脉冲 = AI 正在干活，红点 = 跑不起来或上次对话报错，橙点 = 有改动还没存版本。只有你关注的项目才会亮灯。", "Only followed projects show dots. Pulsing green means the AI is working, red means a run or conversation failed, and orange means changes haven’t been saved as a version.")),
            (FizzL10n.text("2/3 从「接着做」回到上次进度", "2/3 Pick up where you left off"), FizzL10n.text("不用翻终端或记住命令，点一下「继续对话」直接回到上次聊到的地方。", "Choose Resume to return to your last conversation without searching your terminal history.")),
            (FizzL10n.text("3/3 用「接力卡」跨工具交接", "3/3 Switch tools with a Handoff card"), FizzL10n.text("换了别的 AI 或对话太长时，点「复制接力卡」一键把最近进度贴给新对话（自动打码密钥）。", "Switching AI tools or starting a fresh conversation? Copy a Handoff card and paste it into the new chat. FizzDeck redacts secrets automatically.")),
        ]
        let clamped = min(steps.count - 1, max(0, onboardingStep))
        let current = steps[clamped]

        return Panel(title: current.title, symbol: "sparkles") {
            Text(current.body)
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } accessory: {
            FizzActionButton(title: FizzL10n.text("跳过", "Skip"), height: .compact) { onboardingSeen = true }
            FizzActionButton(title: clamped < steps.count - 1 ? FizzL10n.text("下一步", "Next") : FizzL10n.text("知道了", "Got it"), height: .compact,
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
                Text(FizzL10n.text("正在扫描本机项目…", "Scanning local projects…"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                VStack(spacing: FizzSpacing.row) {
                    FizzIcon(.lg, symbol: "square.stack.3d.up").accessibilityHidden(true)
                    Text(FizzL10n.text("还没有项目", "No projects yet")).font(FizzTypography.sectionTitle)
                }
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
}
