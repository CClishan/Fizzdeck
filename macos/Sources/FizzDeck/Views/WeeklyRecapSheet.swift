import SwiftUI

struct WeeklyRecapSheet: View {
    let projects: [RepoProject]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SummaryPreferences.enabledKey) private var aiEnabled = false
    @AppStorage(SummaryPreferences.consentAcceptedKey) private var summaryConsent = false
    @AppStorage(SummaryPreferences.providerKindKey) private var providerKind: SummaryProviderKind = .agentCLI
    @State private var range: WeeklyRecapRange = .week
    @State private var snapshot: (recap: WeeklyRecap, byTool: [CostSegment], byProject: [CostSegment])?
    @State private var chartMetric: WeeklyRecapMetric = .agentTime
    @State private var hiddenProjects = Set<String>()
    @State private var showingShare = false
    @State private var showConsent = false
    @State private var consentFor: SummaryProviderKind?
    @State private var polished: String?
    @State private var polishing = false

    private var recap: WeeklyRecap? { snapshot?.recap.range == range ? snapshot?.recap : nil }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.panel)
            Divider().opacity(0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: FizzSpacing.section) {
                    if let recap {
                        dashboard(recap)
                    } else {
                        ProgressView("正在汇总本机记录…")
                            .frame(maxWidth: .infinity, minHeight: 280)
                    }
                }
                .padding(FizzSpacing.page)
            }
            .defaultScrollAnchor(.top, for: .sizeChanges)
            Divider().opacity(0.35)
            footer
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: 900, height: 700)
        .background(FizzTheme.page)
        .sheet(isPresented: $showingShare) {
            if let recap {
                WeeklyRecapShareSheet(data: shareData(recap))
            }
        }
        .alert("允许润色这份复盘？", isPresented: $showConsent) {
            Button("取消", role: .cancel) {}
            Button("同意并润色") { consentFor = providerKind }
        } message: {
            Text("只向当前 AI 提供方（\(providerKind.title)）发送项目、会话、文件和提交数量及估算费用。不发送名称、路径、复盘原文或聊天内容。仅本次有效。")
        }
        .onChange(of: aiEnabled && summaryConsent) { if !aiEnabled || !summaryConsent { resetPolish() } }
        .onChange(of: providerKind) { resetPolish() }
        .task(id: range) {
            let selected = range
            let task = Task.detached(priority: .userInitiated) { [projects] in
                let recap = WeeklyRecapService.build(projects: projects, range: selected)
                let usage = SelfUsageLedger.totals(since: selected == .all ? .distantPast : recap.windowStart,
                                                   through: recap.generatedAt)
                let sessions = recap.analysis.sessions
                return (recap, DashboardMetrics.costBreakdown(sessions: sessions, mode: .byTool, selfUsage: usage),
                        DashboardMetrics.costBreakdown(sessions: sessions, mode: .byProject))
            }
            let result = await task.value
            if !Task.isCancelled, range == selected { snapshot = result }
        }
        .task(id: consentFor) {
            guard let consentFor, let recap else { return }
            polishing = true
            let result = await WeeklyRecapService.polish(WeeklyRecapFigures(recap), consentFor: consentFor)
            guard !Task.isCancelled, self.consentFor == consentFor, range == recap.range else { return }
            SummaryEngine.shared.refreshUsageTotals()
            polished = result
            polishing = false
            if result == nil { self.consentFor = nil }
        }
    }

    private var header: some View {
        FizzPageHeader(title: "跨 Agent 复盘", subtitle: periodSubtitle) {
            FizzSegmentedCapsule(items: WeeklyRecapRange.allCases, selection: Binding(
                get: { range }, set: { selected in
                    guard range != selected else { return }
                    resetPolish()
                    snapshot = nil
                    range = selected
                }
            ), keyboardNavigation: true) { item, _ in
                Text(item.rawValue)
                    .font(FizzTypography.caption)
                    .accessibilityLabel(item.periodTitle)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("复盘周期")
            FizzIconButton(title: "关闭复盘", symbol: "xmark", height: .compact) { dismiss() }
        }
    }

    private var periodSubtitle: String {
        guard let recap else { return range.periodTitle }
        let span = dateSpan(recap.windowStart, recap.generatedAt)
        guard let previous = recap.analysis.previousStart,
              let end = Calendar.current.date(byAdding: .day, value: -1, to: recap.windowStart) else {
            return "\(span) · 全部已索引历史"
        }
        return "\(span) · 较上期 \(dateSpan(previous, end))"
    }

    private func dateSpan(_ first: Date, _ last: Date) -> String {
        let style = Date.FormatStyle().month(.defaultDigits).day()
        let firstStyle = Calendar.current.isDate(first, equalTo: last, toGranularity: .year) ? style : style.year()
        let lastStyle = Calendar.current.isDate(last, equalTo: Date(), toGranularity: .year) ? style : style.year()
        return "\(first.formatted(firstStyle))–\(last.formatted(lastStyle))"
    }

    @ViewBuilder private func dashboard(_ recap: WeeklyRecap) -> some View {
        let analysis = recap.analysis
        HStack(spacing: FizzSpacing.grid) {
            ForEach(WeeklyRecapMetric.allCases, id: \.self) { metric in
                FizzHeroMetricCard(
                    title: metric.title,
                    value: metric.label(analysis.totals.value(metric)),
                    subtitle: analysis.totals.detail(metric),
                    change: analysis.trend(metric).change,
                    samples: analysis.samples(metric)
                )
            }
        }

        if analysis.sessions.isEmpty {
            Panel(title: "这个周期没有对话", symbol: "bubble.left.and.bubble.right") {
                Text("切换到更长的周期，可以查看此前已索引的本机对话。")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .top, spacing: FizzSpacing.grid) {
                WeeklyRecapTrendPanel(analysis: analysis, metric: $chartMetric, hiddenProjects: $hiddenProjects)
                    .frame(maxWidth: .infinity)
                WeeklyRecapRhythmPanel(analysis: analysis)
                    .frame(width: 290)
            }
            WeeklyRecapDetails(analysis: analysis)
        }
        if let snapshot { AICostBreakdownCard(byTool: snapshot.byTool, byProject: snapshot.byProject) }
        if recap.hasActivity { polishControls }
    }

    private func resetPolish() {
        showConsent = false
        consentFor = nil
        polished = nil
        polishing = false
    }

    private var polishControls: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.row) {
            HStack(spacing: FizzSpacing.row) {
                Toggle("AI 润色", isOn: Binding(get: { consentFor != nil }, set: { on in
                    if on { showConsent = true } else { resetPolish() }
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.secondary)
                .fizzKeyboardAction { if consentFor != nil { resetPolish() } else { showConsent = true } }
                .disabled(!aiEnabled || !summaryConsent)
                if !aiEnabled || !summaryConsent {
                    FizzActionButton(title: "设置 AI 总结…", height: .compact) { openSettings() }
                        .fizzKeyboardAction { openSettings() }
                }
            }
            if let polished {
                Text(verbatim: polished)
                    .font(FizzTypography.body)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        FizzSheetFooter {
            if polishing {
                ProgressView().controlSize(.mini)
                Text("正在润色复盘…")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: FizzSpacing.row)
            FizzActionButton(title: "关闭", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .fizzKeyboardAction { dismiss() }
            FizzActionButton(title: "复制 Markdown", symbol: "doc.on.clipboard", action: copyMarkdown)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .fizzKeyboardAction(action: copyMarkdown)
                .disabled(recap?.hasActivity != true)
            FizzActionButton(title: "分享卡", symbol: "photo.on.rectangle", prominence: .primary) { showingShare = true }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .fizzKeyboardAction { showingShare = true }
                .disabled(recap?.hasActivity != true)
        }
        .focusSection()
    }

    private func copyMarkdown() {
        guard let recap else { return }
        SystemActions.copy(recap.markdown(polishedSummary: polished), feedback: "复盘已复制", microViz: .compact(state: .done))
    }

    private func shareData(_ recap: WeeklyRecap) -> WeeklyRecapShareData {
        WeeklyRecapShareData(
            period: "\(recap.range.periodTitle) · \(dateSpan(recap.windowStart, recap.generatedAt))",
            analysis: recap.analysis
        )
    }
}
