import Charts
import SwiftUI

struct WeeklyRecapTrendPanel: View {
    let analysis: WeeklyRecapAnalysis
    @Binding var metric: WeeklyRecapMetric
    @Binding var hiddenProjects: Set<String>

    var body: some View {
        Panel(title: FizzL10n.text("项目趋势", "Project trends"), symbol: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                chart
                    .frame(height: 157)
                HStack(spacing: FizzSpacing.row) {
                    legend
                    if analysis.daysPerBucket > 1 {
                        Text(FizzL10n.text("\(analysis.daysPerBucket) 天/柱", "\(analysis.daysPerBucket) days per bar"))
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        } accessory: {
            FizzSegmentedCapsule(items: WeeklyRecapMetric.chartMetrics, selection: $metric, height: .compact, keyboardNavigation: true) { item, _ in
                Text(item.title).font(FizzTypography.caption)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(FizzL10n.text("趋势指标", "Trend metric"))
        }
    }

    private var legend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: FizzSpacing.row) {
                ForEach(analysis.projects) { project in
                    let visible = !hiddenProjects.contains(project.id)
                    let toggle = {
                        if visible { hiddenProjects.insert(project.id) } else { hiddenProjects.remove(project.id) }
                    }
                    Button(action: toggle) {
                        Label {
                            Text(verbatim: project.name).lineLimit(1)
                        } icon: {
                            ProjectAccentDot(path: project.id).opacity(visible ? 1 : 0.45)
                        }
                        .foregroundStyle(visible ? Color.primary : Color.secondary)
                        .strikethrough(!visible)
                        .padding(.horizontal, FizzSpacing.row)
                        .frame(height: FizzControlHeight.compact.rawValue)
                        .frame(maxWidth: 152)
                        .background(visible ? FizzTheme.elevatedFill : FizzTheme.recessedFill, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fizzKeyboardAction(action: toggle)
                    .font(FizzTypography.caption)
                    .help(project.name)
                    .accessibilityValue(visible ? FizzL10n.text("已显示", "Shown") : FizzL10n.text("已隐藏", "Hidden"))
                    .accessibilityAddTraits(visible ? .isSelected : [])
                }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FizzL10n.text("筛选趋势图的项目", "Filter projects in chart"))
    }

    @ViewBuilder private var chart: some View {
        let visible = analysis.projects.filter { !hiddenProjects.contains($0.id) }
        let starts = analysis.bucketStarts
        if visible.contains(where: { $0.buckets.values.contains { $0.value(metric) != nil } }) {
            let locale = FizzL10n.locale
            let categories = starts.map { $0.formatted(.dateTime.year().month().day().locale(locale)) }
            let step = max(1, (starts.count + 4) / 5)
            let ticks = stride(from: 0, to: starts.count, by: step).map { categories[$0] }
            Chart {
                ForEach(visible) { project in
                    ForEach(project.buckets.keys.sorted(), id: \.self) { index in
                        if let value = project.buckets[index]?.value(metric) {
                            BarMark(x: .value(FizzL10n.text("日期", "Date"), categories[index]), y: .value(metric.title, value), width: .ratio(0.72))
                                .foregroundStyle(ProjectAccentColor.color(for: project.id))
                                .accessibilityLabel("\(project.name) · \(categories[index])")
                                .accessibilityValue(metric.label(value))
                        }
                    }
                }
            }
            .chartXScale(domain: categories)
            .chartXAxis {
                AxisMarks(values: ticks) { tick in
                    if let key = tick.as(String.self), let index = categories.firstIndex(of: key) {
                        AxisValueLabel { Text(verbatim: Format.monthDay(starts[index], locale: locale)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { tick in
                    AxisGridLine()
                    if let value = tick.as(Double.self) {
                        AxisValueLabel { Text(metric.axisLabel(value)) }
                    }
                }
            }
            .accessibilityLabel(FizzL10n.text("按项目堆叠的\(metric.title)趋势", "\(metric.title) by project"))
        } else {
            Text(visible.isEmpty ? FizzL10n.text("没有选中的项目", "No projects selected") : FizzL10n.text("所选项目没有\(metric.title)记录", "No data for the selected projects"))
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FizzTheme.recessedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control))
        }
    }
}

struct WeeklyRecapRhythmPanel: View {
    let analysis: WeeklyRecapAnalysis

    var body: some View {
        Panel(title: FizzL10n.text("活跃节奏", "Activity"), symbol: "calendar") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                HStack(alignment: .center, spacing: FizzSpacing.panel) {
                    heatmap
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        number(FizzL10n.text("活跃天数", "Active days"), value: analysis.activeDays)
                        number(FizzL10n.text("连续活跃", "Current streak"), value: analysis.streak)
                    }
                }
                Divider().opacity(0.35)
                VStack(spacing: 5) {
                    fact(FizzL10n.text("最忙的一天", "Busiest day"), analysis.busiestDay.map {
                        let date = Format.monthDay($0.date)
                        return FizzL10n.text("\(date) · \($0.sessions) 次", "\(date) · \(SessionSummaryText.englishCount($0.sessions, "session"))")
                    } ?? "—")
                    fact(FizzL10n.text("最长一次对话", "Longest session"), WeeklyRecapMetric.agentTime.label(analysis.longestSession?.record.agentTimeSeconds.map(Double.init)))
                    fact(FizzL10n.text("平均单次时长", "Average session time"), WeeklyRecapMetric.agentTime.label(analysis.totals.averageSeconds))
                    fact(FizzL10n.text("平均单次花费", "Average session cost"), WeeklyRecapMetric.cost.label(analysis.totals.averageCost))
                }
            }
        }
    }

    private var heatmap: some View {
        let cells = analysis.heatmap
        let blanks = analysis.heatmapLeadingBlanks
        let columns = (cells.count + blanks + 6) / 7
        let peak = max(1, cells.map(\.sessions).max() ?? 0)
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<7) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = column * 7 + row - blanks
                        if cells.indices.contains(index) {
                            let cell = cells[index]
                            let date = cell.date.formatted(.dateTime.year().month().day().locale(FizzL10n.locale))
                            let text = FizzL10n.text("\(date) · \(cell.sessions) 次对话", "\(date) · \(SessionSummaryText.englishCount(cell.sessions, "session"))")
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cell.sessions == 0 ? FizzTheme.recessedFill : Color.secondary.opacity(0.25 + 0.50 * Double(cell.sessions) / Double(peak)))
                                .frame(width: 11, height: 11)
                                .help(text)
                                .accessibilityLabel(text)
                        } else {
                            Color.clear.frame(width: 11, height: 11).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cells.count == 42 ? FizzL10n.text("最近 42 天的对话热力图", "Session activity over the last 42 days") : FizzL10n.text("本周期对话热力图", "Session activity in this period"))
        .frame(minWidth: 105, alignment: .leading)
    }

    private func number(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(FizzTypography.caption).foregroundStyle(.secondary)
            Text(value.formatted(.number.locale(FizzL10n.locale))).font(FizzTypography.sectionTitle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(FizzL10n.text("\(value) 天", "\(SessionSummaryText.englishCount(value, "day"))"))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: FizzSpacing.row)
            Text(value)
        }
        .font(FizzTypography.caption)
        .accessibilityElement(children: .combine)
    }
}

struct WeeklyRecapDetails: View {
    let analysis: WeeklyRecapAnalysis

    var body: some View {
        Grid(horizontalSpacing: FizzSpacing.grid, verticalSpacing: FizzSpacing.section) {
            GridRow(alignment: .top) {
                Panel(title: FizzL10n.text("会话明细", "Session details"), symbol: "bubble.left.and.text.bubble.right") {
                    Table(analysis.sessions) {
                        TableColumn(FizzL10n.text("对话", "Session")) { row in
                            HStack(spacing: FizzSpacing.row) {
                                ProjectAccentDot(path: row.projectPath)
                                Text(verbatim: row.record.primaryIntent ?? row.projectName)
                                    .font(FizzTypography.body)
                                    .lineLimit(1)
                            }
                            .help(row.projectName)
                        }
                        TableColumn(FizzL10n.text("工具", "Tool")) { row in
                            Text(HomeDashboardModel.toolTitle(row.record.tool))
                                .lineLimit(1)
                        }
                        .width(min: 64, ideal: 68)
                        TableColumn(FizzL10n.text("AI 干活时长", "Agent time")) { row in
                            number(WeeklyRecapMetric.agentTime.label(row.record.agentTimeSeconds.map(Double.init)))
                        }
                        .width(94)
                        TableColumn(FizzL10n.text("轮数", "Turns")) { row in
                            number(row.record.turnCount?.formatted(.number.locale(FizzL10n.locale)) ?? "—")
                        }
                        .width(45)
                        TableColumn(FizzL10n.text("测试", "Tests")) { row in testCell(row.record.testResult) }
                            .width(62)
                    }
                    .accessibilityLabel(FizzL10n.text("会话明细", "Session details"))
                    .frame(height: CGFloat(min(260, max(77, 28 + min(12, analysis.sessions.count) * 25))))
                }
                .frame(maxWidth: .infinity)
                Panel(title: FizzL10n.text("按工具", "By tool"), symbol: "cpu") {
                    Grid(alignment: .leading, horizontalSpacing: FizzSpacing.row, verticalSpacing: 8) {
                        GridRow {
                            Text(FizzL10n.text("工具", "Tool"))
                            Text(FizzL10n.text("未计价", "Unpriced")).gridColumnAlignment(.trailing)
                            Text(FizzL10n.text("报错率", "Error rate")).gridColumnAlignment(.trailing)
                        }
                        .foregroundStyle(.secondary)
                        ForEach(analysis.tools) { tool in
                            GridRow {
                                Text(HomeDashboardModel.toolTitle(tool.id)).lineLimit(1)
                                Text(tool.totals.cost.unpriced.formatted(.number.locale(FizzL10n.locale)))
                                    .help(tool.totals.detail(.cost))
                                Text(tool.totals.errorRate, format: .percent.precision(.fractionLength(0...1)).locale(FizzL10n.locale))
                                    .help(FizzL10n.text("\(tool.totals.errors) / \(tool.totals.sessions) 次对话以报错结束", "\(tool.totals.errors) of \(SessionSummaryText.englishCount(tool.totals.sessions, "session")) ended with an error"))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .font(FizzTypography.caption)
                }
                .frame(width: 290)
            }
        }
    }

    private func number(_ value: String) -> some View {
        Text(value)
            .font(FizzTypography.monoSmall)
            .foregroundStyle(value == "—" ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private func testCell(_ result: SessionTestResult?) -> some View {
        switch result {
        case .passed: TagChip(text: FizzL10n.text("通过", "Passed"), tint: FizzTheme.statusSuccess, compact: true)
        case .failed: TagChip(text: FizzL10n.text("失败", "Failed"), tint: FizzTheme.statusDanger, compact: true)
        case .notRun: TagChip(text: FizzL10n.text("未运行", "Not run"), compact: true)
        case nil: number("—").accessibilityLabel(FizzL10n.text("测试结果未知", "Test result unknown"))
        }
    }
}

private extension WeeklyRecapMetric {
    func axisLabel(_ value: Double) -> String {
        switch self {
        case .agentTime:
            if value < 60 { return "\(value.formatted(.number.precision(.fractionLength(0))))s" }
            if value < 3_600 { return "\((value / 60).formatted(.number.precision(.fractionLength(0...1))))m" }
            return "\((value / 3_600).formatted(.number.precision(.fractionLength(0...1))))h"
        case .cost:
            return "$\(value.formatted(.number.precision(.fractionLength(0...3))))"
        case .sessions, .tokens:
            return Format.compactCount(value, locale: FizzL10n.locale)
        }
    }
}
