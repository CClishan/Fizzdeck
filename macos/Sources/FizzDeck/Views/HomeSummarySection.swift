import SwiftUI

struct HomeSummarySection: View {
    let showsAttention: Bool
    let filterTitle: String
    let stats: HomeSummaryStats

    var body: some View {
        Group {
            if showsAttention {
                HStack(alignment: .top, spacing: FizzSpacing.grid) {
                    AttentionQueueView()
                        .frame(maxWidth: .infinity, alignment: .top)

                    summaryCards
                        .frame(maxWidth: .infinity)
                }
            } else {
                summary
            }
        }
    }

    private var summaryCards: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                GlassStatCard(
                    title: "项目",
                    value: "\(stats.projectCount)",
                    detail: filterTitle,
                    symbol: "square.stack.3d.up",
                    tint: .secondary
                )
                GlassStatCard(
                    title: "正在运行",
                    value: "\(stats.runningCount)",
                    detail: stats.runningCount == 0 ? "没有运行中的服务" : "端口已就绪",
                    symbol: "play.circle",
                    tint: .secondary
                )
            }
            GridRow {
                GlassStatCard(
                    title: "磁盘占用",
                    value: Format.bytes(stats.totalBytes),
                    detail: "已扫描 \(stats.projectCount) 个项目",
                    symbol: "internaldrive",
                    tint: .secondary
                )
                GlassStatCard(
                    title: "可清理",
                    value: Format.bytes(stats.cleanupBytes),
                    detail: "\(stats.cleanupItemCount) 个目录",
                    symbol: "trash.slash",
                    tint: .secondary
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            HomeSummaryMetric(
                title: "项目",
                value: "\(stats.projectCount)",
                symbol: "square.stack.3d.up",
                tint: .secondary
            )
            summaryDivider
            HomeSummaryMetric(
                title: "正在运行",
                value: "\(stats.runningCount)",
                symbol: "play.circle",
                tint: .secondary
            )
            summaryDivider
            HomeSummaryMetric(
                title: "磁盘占用",
                value: Format.bytes(stats.totalBytes),
                symbol: "internaldrive",
                tint: .secondary
            )
            summaryDivider
            HomeSummaryMetric(
                title: "可清理",
                value: Format.bytes(stats.cleanupBytes),
                symbol: "trash.slash",
                tint: .secondary
            )
        }
        .padding(.vertical, 10)
        .fizzCard()
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(FizzTheme.hairline)
            .frame(width: 1, height: 26)
    }
}

private struct HomeSummaryMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            FizzIcon(.md, symbol: symbol)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(FizzTypography.font(16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
