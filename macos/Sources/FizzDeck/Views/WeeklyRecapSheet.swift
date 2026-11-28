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
                        ProgressView(FizzL10n.text("正在汇总本机记录…", "Gathering local activity…"))
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
                WeeklyRecapShareSheet(data: .init(recap: recap))
            }
        }
        .alert(FizzL10n.text("允许润色这份复盘？", "Send recap totals to AI?"), isPresented: $showConsent) {
            Button(FizzL10n.text("取消", "Cancel"), role: .cancel) {}
            Button(FizzL10n.text("同意并润色", "Allow and Edit")) { consentFor = providerKind }
        } message: {
            Text(FizzL10n.text("只向当前 AI 提供方（\(providerKind.title)）发送项目、会话、文件和提交数量及估算费用。不发送名称、路径、复盘原文或聊天内容。仅本次有效。", "\(providerKind.title) will receive only project, session, file, and commit counts and the estimated cost. Names, paths, the recap itself, and chats stay on this Mac. This permission applies once."))
        }
        .onChange(of: aiEnabled && summaryConsent) { if !aiEnabled || !summaryConsent { resetPolish() } }
        .onChange(of: providerKind) { resetPolish() }
        .onChange(of: FizzL10n.isEnglish) { resetPolish() }
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
        FizzPageHeader(title: FizzL10n.text("跨 Agent 复盘", "Agent Recap"), subtitle: periodSubtitle) {
            FizzSegmentedCapsule(items: WeeklyRecapRange.allCases, selection: Binding(
                get: { range }, set: { selected in
                    guard range != selected else { return }
                    resetPolish()
                    snapshot = nil
                    range = selected
                }
            ), keyboardNavigation: true) { item, _ in
                Text(item.shortTitle)
                    .font(FizzTypography.caption)
                    .accessibilityLabel(item.periodTitle)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(FizzL10n.text("复盘周期", "Recap period"))
            FizzIconButton(title: FizzL10n.text("关闭复盘", "Close recap"), symbol: "xmark", height: .compact) { dismiss() }
        }
    }

    private var periodSubtitle: String {
        guard let recap else { return range.periodTitle }
        let span = dateSpan(recap.windowStart, recap.generatedAt)
        guard let previous = recap.analysis.previousStart,
              let end = Calendar.current.date(byAdding: .day, value: -1, to: recap.windowStart) else {
            return FizzL10n.text("\(span) · 全部已索引历史", "\(span) · All indexed history")
        }
        return FizzL10n.text("\(span) · 较上期 \(dateSpan(previous, end))", "\(span) · Compared with \(dateSpan(previous, end))")
    }

    private func dateSpan(_ first: Date, _ last: Date) -> String {
        let style = Date.FormatStyle().month(.abbreviated).day().locale(FizzL10n.locale)
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
            Panel(title: FizzL10n.text("这个周期没有对话", "No sessions in this period"), symbol: "bubble.left.and.bubble.right") {
                Text(FizzL10n.text("切换到更长的周期，可以查看此前已索引的本机对话。", "Choose a longer period to see earlier sessions indexed on this Mac."))
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
                Toggle(FizzL10n.text("AI 润色", "Edit with AI"), isOn: Binding(get: { consentFor != nil }, set: { on in
                    if on { showConsent = true } else { resetPolish() }
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.secondary)
                .fizzKeyboardAction { if consentFor != nil { resetPolish() } else { showConsent = true } }
                .disabled(!aiEnabled || !summaryConsent)
                if !aiEnabled || !summaryConsent {
                    FizzActionButton(title: FizzL10n.text("设置 AI 总结…", "Set Up AI Summaries…"), height: .compact) { openSettings() }
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
                Text(FizzL10n.text("正在润色复盘…", "Editing recap…"))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: FizzSpacing.row)
            FizzActionButton(title: FizzL10n.text("关闭", "Close"), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .fizzKeyboardAction { dismiss() }
            FizzActionButton(title: FizzL10n.text("复制 Markdown", "Copy Markdown"), symbol: "doc.on.clipboard", action: copyMarkdown)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .fizzKeyboardAction(action: copyMarkdown)
                .disabled(recap?.hasActivity != true)
            FizzActionButton(title: FizzL10n.text("分享卡", "Share Card"), symbol: "photo.on.rectangle", prominence: .primary) { showingShare = true }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .fizzKeyboardAction { showingShare = true }
                .disabled(recap?.hasActivity != true)
        }
        .focusSection()
    }

    private func copyMarkdown() {
        guard let recap else { return }
        SystemActions.copy(recap.markdown(polishedSummary: polished), feedback: FizzL10n.text("复盘已复制", "Recap copied"), microViz: .compact(state: .done))
    }
}
