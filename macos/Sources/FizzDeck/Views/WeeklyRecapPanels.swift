import Charts
import SwiftUI

struct WeeklyRecapTrendPanel: View {
    let analysis: WeeklyRecapAnalysis
    @Binding var metric: WeeklyRecapMetric
    @Binding var hiddenProjects: Set<String>

    var body: some View {
        Panel(title: "项目趋势", symbol: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                chart
                    .frame(height: 157)
                HStack(spacing: FizzSpacing.row) {
                    legend
                    if analysis.daysPerBucket > 1 {
                        Text("\(analysis.daysPerBucket) 天/柱")
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
            .accessibilityLabel("趋势指标")
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
                    .accessibilityValue(visible ? "已显示" : "已隐藏")
                    .accessibilityAddTraits(visible ? .isSelected : [])
                }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("筛选趋势图的项目")
    }

    @ViewBuilder private var chart: some View {
        let visible = analysis.projects.filter { !hiddenProjects.contains($0.id) }
        let starts = analysis.bucketStarts
        if visible.contains(where: { $0.buckets.values.contains { $0.value(metric) != nil } }) {
            let categories = starts.map { $0.formatted(date: .abbreviated, time: .omitted) }
            let step = max(1, (starts.count + 4) / 5)
            let ticks = stride(from: 0, to: starts.count, by: step).map { categories[$0] }
            Chart {
                ForEach(visible) { project in
                    ForEach(project.buckets.keys.sorted(), id: \.self) { index in
                        if let value = project.buckets[index]?.value(metric) {
                            BarMark(x: .value("日期", categories[index]), y: .value(metric.title, value), width: .ratio(0.72))
                                .foregroundStyle(ProjectAccentColor.color(for: project.id))
                                .accessibilityLabel("\(project.name)，\(starts[index].formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityValue(metric.label(value))
                        }
                    }
                }
            }
            .chartXScale(domain: categories)
            .chartXAxis {
                AxisMarks(values: ticks) { tick in
                    if let key = tick.as(String.self), let index = categories.firstIndex(of: key) {
                        AxisValueLabel { Text(starts[index], format: .dateTime.month(.defaultDigits).day()) }
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
            .accessibilityLabel("按项目堆叠的\(metric.title)趋势")
        } else {
            Text(visible.isEmpty ? "没有选中的项目" : "所选项目没有\(metric.title)记录")
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
        Panel(title: "活跃节奏", symbol: "calendar") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                HStack(alignment: .center, spacing: FizzSpacing.panel) {
                    heatmap
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        number("活跃天数", value: analysis.activeDays)
                        number("连续活跃", value: analysis.streak)
                    }
                }
                Divider().opacity(0.35)
                VStack(spacing: 5) {
                    fact("最忙的一天", analysis.busiestDay.map {
                        "\($0.date.formatted(.dateTime.month(.defaultDigits).day())) · \($0.sessions) 次"
                    } ?? "—")
                    fact("最长一次对话", WeeklyRecapMetric.agentTime.label(analysis.longestSession?.record.agentTimeSeconds.map(Double.init)))
                    fact("平均单次时长", WeeklyRecapMetric.agentTime.label(analysis.totals.averageSeconds))
                    fact("平均单次花费", WeeklyRecapMetric.cost.label(analysis.totals.averageCost))
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
                            let text = "\(cell.date.formatted(date: .abbreviated, time: .omitted)) · \(cell.sessions) 次对话"
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
        .accessibilityLabel(cells.count == 42 ? "最近 42 天的对话热力图" : "本周期对话热力图")
        .frame(minWidth: 105, alignment: .leading)
    }

    private func number(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(FizzTypography.caption).foregroundStyle(.secondary)
            Text(value.formatted()).font(FizzTypography.sectionTitle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) 天")
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
                Panel(title: "会话明细", symbol: "bubble.left.and.text.bubble.right") {
                    Table(analysis.sessions) {
                        TableColumn("对话") { row in
                            HStack(spacing: FizzSpacing.row) {
                                ProjectAccentDot(path: row.projectPath)
                                Text(verbatim: row.record.primaryIntent ?? row.projectName)
                                    .font(FizzTypography.body)
                                    .lineLimit(1)
                            }
                            .help(row.projectName)
                        }
                        TableColumn("工具") { row in
                            Text(HomeDashboardModel.toolTitle(row.record.tool))
                                .lineLimit(1)
                        }
                        .width(min: 64, ideal: 68)
                        TableColumn("AI 干活时长") { row in
                            number(WeeklyRecapMetric.agentTime.label(row.record.agentTimeSeconds.map(Double.init)))
                        }
                        .width(75)
                        TableColumn("轮数") { row in
                            number(row.record.turnCount?.formatted() ?? "—")
                        }
                        .width(45)
                        TableColumn("测试") { row in testCell(row.record.testResult) }
                            .width(54)
                    }
                    .accessibilityLabel("会话明细")
                    .frame(height: CGFloat(min(260, max(77, 28 + min(12, analysis.sessions.count) * 25))))
                }
                .frame(maxWidth: .infinity)
                Panel(title: "按工具", symbol: "cpu") {
                    Grid(alignment: .leading, horizontalSpacing: FizzSpacing.row, verticalSpacing: 8) {
                        GridRow {
                            Text("工具")
                            Text("未计价").gridColumnAlignment(.trailing)
                            Text("报错率").gridColumnAlignment(.trailing)
                        }
                        .foregroundStyle(.secondary)
                        ForEach(analysis.tools) { tool in
                            GridRow {
                                Text(HomeDashboardModel.toolTitle(tool.id)).lineLimit(1)
                                Text(tool.totals.cost.unpriced.formatted())
                                    .help(tool.totals.detail(.cost))
                                Text(tool.totals.errorRate, format: .percent.precision(.fractionLength(0...1)))
                                    .help("\(tool.totals.errors) / \(tool.totals.sessions) 次对话以报错结束")
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
        case .passed: TagChip(text: "通过", tint: FizzTheme.statusSuccess, compact: true)
        case .failed: TagChip(text: "失败", tint: FizzTheme.statusDanger, compact: true)
        case .notRun: TagChip(text: "未运行", compact: true)
        case nil: number("—").accessibilityLabel("测试结果未知")
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
            return value.formatted(.number.notation(.compactName))
        }
    }
}
