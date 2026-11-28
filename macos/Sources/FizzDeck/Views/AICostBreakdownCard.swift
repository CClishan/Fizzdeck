import SwiftUI

struct AICostBreakdownCard: View {
    let byTool: [CostSegment]
    let byProject: [CostSegment]
    @State private var mode: CostBreakdownMode = .byTool

    var body: some View {
        let segments = mode == .byTool ? byTool : byProject
        let showsRing = segments.count > 1
        if !byTool.isEmpty || !byProject.isEmpty {
            let hasCost = segments.contains { $0.costUSD > 0 }
            Panel(title: hasCost || segments.isEmpty ? "估算费用构成" : "用量构成", symbol: "chart.pie") {
                HStack(spacing: FizzSpacing.panel) {
                    if showsRing { donutChart(segments) }
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        if segments.isEmpty {
                            Text("该分类暂无计价或用量记录")
                                .font(FizzTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            HStack(spacing: FizzSpacing.row) {
                                if showsRing {
                                    Circle().fill(segmentColor(index)).frame(width: 6, height: 6)
                                        .accessibilityHidden(true)
                                }
                                Text(segment.label).font(FizzTypography.caption)
                                Spacer(minLength: FizzSpacing.row)
                                Text(valueLabel(for: segment)).font(FizzTypography.mono)
                                Text(segment.fraction.formatted(.percent.precision(.fractionLength(0...1))))
                                    .font(FizzTypography.monoSmall)
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } accessory: {
                FizzSegmentedCapsule(items: CostBreakdownMode.allCases, selection: $mode, height: .compact, keyboardNavigation: true) { item, _ in
                    Text(item.title).font(FizzTypography.caption(.medium))
                }
            }
        }
    }

    private func donutChart(_ segments: [CostSegment]) -> some View {
        let boundaries = segments.reduce(into: [0.0]) { $0.append(min(1, ($0.last ?? 0) + $1.fraction)) }
        return ZStack {
            Circle().stroke(FizzTheme.hairline, lineWidth: 9)
            ForEach(segments.indices, id: \.self) { index in
                let start = boundaries[index]
                let end = boundaries[index + 1]
                Circle()
                    .trim(from: start, to: end - min(0.008, (end - start) / 2))
                    .stroke(segmentColor(index), lineWidth: 9)
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 68, height: 68)
        .padding(5)
        .accessibilityHidden(true)
    }

    private func valueLabel(for segment: CostSegment) -> String {
        if segment.costUSD > 0 { return WeeklyRecapMetric.cost.label(segment.costUSD) }
        return "\(WeeklyRecapMetric.tokens.label(segment.tokens)) tokens"
    }

    private func segmentColor(_ index: Int) -> Color {
        Color.primary.opacity(0.72 - Double(index) * 0.10)
    }
}
