import SwiftUI

struct AICostBreakdownCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    let projects: [RepoProject]
    let kpi: DashboardKPISummary

    @State private var mode: CostBreakdownMode = .byTool

    private var weeklySelfUsage: SelfUsageTotals {
        SelfUsageLedger.weeklyTotals()
    }

    private var segments: [CostSegment] {
        DashboardMetrics.costBreakdown(projects: projects, mode: mode, selfUsage: weeklySelfUsage)
    }

    private var hasData: Bool {
        !segments.isEmpty
            && (kpi.weeklyCostUSD != nil
                || kpi.weeklyTokens > 0
                || weeklySelfUsage.totalTokens > 0
                || weeklySelfUsage.estimatedCostUSD > 0)
    }

    private var centerPrimary: String {
        if let cost = Format.cost(kpi.weeklyCostUSD, estimated: kpi.costIsEstimate) {
            return cost
        }
        return Format.tokens(kpi.weeklyTokens)
    }

    private var centerSubtitle: String {
        if kpi.weeklyCostUSD != nil {
            return kpi.costIsEstimate ? "本周估" : "本周"
        }
        return "tokens"
    }

    var body: some View {
        if hasData {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    FizzIcon(symbol: "sparkles", size: 13)
                        .foregroundStyle(FizzTheme.accent)
                    Text(copyMode == .plain
                        ? FizzCopy.costTitle(.plain)
                        : (kpi.weeklyCostUSD != nil ? "费用构成" : "用量构成"))
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: 8)

                    FizzSegmentedCapsule(
                        items: CostBreakdownMode.allCases,
                        selection: $mode
                    ) { item, selected in
                        Text(item.title)
                            .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    }
                }

                HStack(alignment: .center, spacing: 18) {
                    donutChart

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(segmentColor(segment, index: index))
                                    .frame(width: 7, height: 7)

                                Text(segment.label)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 6)

                                Text(valueLabel(for: segment))
                                    .font(.system(size: 11, design: .monospaced))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(.secondary)

                                Text("\(Int((segment.fraction * 100).rounded()))%")
                                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                    .contentTransition(.numericText())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(minWidth: 36, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .fizzCard(radius: FizzRadius.panel)
            .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: mode)
        }
    }

    private var donutChart: some View {
        let ranges = trimmedRanges

        return ZStack {
            Circle()
                .stroke(FizzTheme.hairline, lineWidth: 13)

            ForEach(Array(ranges.enumerated()), id: \.element.segment.id) { index, entry in
                Circle()
                    .trim(from: entry.start, to: entry.end)
                    .stroke(
                        segmentColor(entry.segment, index: index),
                        style: StrokeStyle(lineWidth: 13, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 1) {
                Text(centerPrimary)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(centerSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72)
        }
        .frame(width: 104, height: 104)
        .padding(4)
        .accessibilityHidden(true)
    }

    private var trimmedRanges: [(segment: CostSegment, start: CGFloat, end: CGFloat)] {
        var cursor: CGFloat = 0
        let gap: CGFloat = segments.count > 1 ? 0.008 : 0
        return segments.map { segment in
            let span = max(0.01, CGFloat(segment.fraction))
            let start = cursor
            let end = min(1, cursor + max(0.005, span - gap))
            cursor = min(1, cursor + span)
            return (segment, start, end)
        }
    }

    private func valueLabel(for segment: CostSegment) -> String {
        if segment.costUSD > 0, let formatted = Format.cost(segment.costUSD, estimated: false) {
            return formatted
        }
        return "\(Format.tokens(segment.tokens)) tok"
    }

    private func segmentColor(_ segment: CostSegment, index: Int) -> Color {
        if segment.id == "fizzdeck-self" {
            return .teal
        }
        if mode == .byTool, let detected = DetectedTool(rawValue: segment.tintKey) {
            return detected.tint
        }
        if segment.id == "other" {
            return .secondary.opacity(0.45)
        }
        let palette: [Color] = [FizzTheme.accent, .blue, .green, .orange, .pink]
        return palette[index % palette.count]
    }
}
