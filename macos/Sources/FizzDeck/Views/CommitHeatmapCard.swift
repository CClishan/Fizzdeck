import SwiftUI

enum CommitHeatmapLayout {
    static func metrics(
        availableWidth: CGFloat,
        columnCount: Int,
        range: HeatmapRange
    ) -> (dotSize: CGFloat, spacing: CGFloat) {
        let cols = max(1, columnCount)
        let preferredSize: CGFloat = range == .weeks26 ? 8.5 : 5.2
        let preferredSpacing: CGFloat = range == .weeks26 ? 4.0 : 2.2
        guard availableWidth > 20 else {
            return (preferredSize, preferredSpacing)
        }

        let gaps = CGFloat(max(0, cols - 1))
        var spacing = preferredSpacing
        if availableWidth < cols.cgFloat * 3.0 + gaps * spacing {
            spacing = max(1.0, (availableWidth - CGFloat(cols) * 3.0) / max(1, gaps))
        }
        let maxDot = floor(((availableWidth - spacing * gaps) / CGFloat(cols)) * 10) / 10
        let dotSize = max(3.0, min(preferredSize, maxDot))
        return (dotSize, spacing)
    }

    static func hoverBubbleOriginX(
        column: Int,
        columnCount: Int,
        matrixWidth: CGFloat,
        dotSize: CGFloat,
        spacing: CGFloat,
        bubbleWidth: CGFloat,
        containerWidth: CGFloat,
        contentInset: CGFloat = 16,
        edgeInset: CGFloat = 8
    ) -> CGFloat {
        let count = max(1, columnCount)
        let index = min(count - 1, max(0, column))
        let usableMatrixWidth = matrixWidth > 20
            ? matrixWidth
            : max(20, containerWidth - contentInset * 2)
        let contentWidth = min(
            usableMatrixWidth,
            CGFloat(count) * dotSize + CGFloat(max(0, count - 1)) * spacing
        )
        let matrixLeading = contentInset + max(0, (usableMatrixWidth - contentWidth) / 2)
        let columnCenter = matrixLeading
            + CGFloat(index) * (dotSize + spacing)
            + dotSize / 2
        let maximumOrigin = max(edgeInset, containerWidth - edgeInset - bubbleWidth)
        return min(max(columnCenter - bubbleWidth / 2, edgeInset), maximumOrigin)
    }
}

private extension Int {
    var cgFloat: CGFloat { CGFloat(self) }
}

struct CommitHeatmapCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("fizzdeck.heatmap.range") private var rangeRaw = HeatmapRange.weeks26.rawValue
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    let snapshot: CommitActivitySnapshot
    let projects: [RepoProject]
    let onSelectDay: (String) -> Void

    @State private var hoveredCell: HeatmapDayCell?
    @State private var hoveredColumn: Int?
    @State private var matrixWidth: CGFloat = 0

    private var range: HeatmapRange {
        HeatmapRange(rawValue: rangeRaw) ?? .weeks26
    }

    private var summary: HeatmapSummary {
        if copyMode == .plain {
            return DashboardMetrics.buildAIActivityHeatmap(
                projects: projects,
                range: range
            )
        }
        return DashboardMetrics.buildHeatmap(
            snapshot: snapshot,
            projects: projects,
            range: range
        )
    }

    var body: some View {
        let data = summary

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(copyMode == .plain ? FizzCopy.heatmapTitle(.plain) : FizzL10n.text("提交热力图", "Commit heatmap"))
                        .font(FizzTypography.cardTitle)
                        .foregroundStyle(.primary)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(data.totalCommits)")
                            .font(FizzTypography.pageTitle)
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)

                        Text(copyMode == .plain
                            ? FizzL10n.text("次活动 · 连续 \(data.currentStreak) 天", "\(data.totalCommits == 1 ? "activity" : "activities") · \(data.currentStreak)-day streak")
                            : FizzL10n.text("次 · 连续 \(data.currentStreak) 天", "\(data.totalCommits == 1 ? "commit" : "commits") · \(data.currentStreak)-day streak"))
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: rangeRaw)
                }

                Spacer(minLength: 8)

                rangePicker
            }

            Color.clear
                .frame(height: 0)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: { newWidth in
                    if abs(matrixWidth - newWidth) > 0.5 {
                        matrixWidth = newWidth
                    }
                }

            dotMatrix(columns: data.columns)

            footer(summary: data)
        }
        .padding(16)
        .fizzCard(radius: FizzRadius.panel)
        .overlay(alignment: .topLeading) {
            if let hoveredCell, let hoveredColumn {
                GeometryReader { proxy in
                    let layout = CommitHeatmapLayout.metrics(
                        availableWidth: matrixWidth,
                        columnCount: data.columns.count,
                        range: range
                    )
                    let bubbleWidth = min(238, max(140, proxy.size.width - 32))
                    let originX = CommitHeatmapLayout.hoverBubbleOriginX(
                        column: hoveredColumn,
                        columnCount: data.columns.count,
                        matrixWidth: matrixWidth,
                        dotSize: layout.dotSize,
                        spacing: layout.spacing,
                        bubbleWidth: bubbleWidth,
                        containerWidth: proxy.size.width
                    )

                    Text(hoverLabel(for: hoveredCell))
                        .font(FizzTypography.monoSmall(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(width: bubbleWidth, alignment: .leading)
                        .glassEffect(.regular, in: Capsule())
                        .fizzAdaptiveShadow(.floating)
                        .offset(x: originX, y: 46)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                .allowsHitTesting(false)
            }
        }
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: hoveredCell?.id)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: hoveredColumn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(data))
    }

    private func accessibilitySummary(_ data: HeatmapSummary) -> String {
        let title = copyMode == .plain ? FizzCopy.heatmapTitle(.plain) : FizzL10n.text("提交热力图", "Commit heatmap")
        let total = copyMode == .plain
            ? FizzL10n.text("\(data.totalCommits) 次活动", "Activities: \(data.totalCommits)")
            : FizzL10n.text("\(data.totalCommits) 次本人提交", "Your commits: \(data.totalCommits)")
        return FizzL10n.text(
            "\(title)，\(range.title)共 \(total)，当前连续 \(data.currentStreak) 天，最长连续 \(data.longestStreak) 天",
            "\(title), \(range.title). \(total). Current streak: \(data.currentStreak) \(data.currentStreak == 1 ? "day" : "days"); longest: \(data.longestStreak) \(data.longestStreak == 1 ? "day" : "days")."
        )
    }

    private var rangePicker: some View {
        FizzSegmentedCapsule(
            items: HeatmapRange.allCases,
            selection: Binding(
                get: { range },
                set: { rangeRaw = $0.rawValue }
            )
        ) { item, selected in
            Text(item.title)
                .font(FizzTypography.monoSmall(selected ? .semibold : .medium))
            }
    }

    private func dotMatrix(columns: [[HeatmapDayCell]]) -> some View {
        let layout = CommitHeatmapLayout.metrics(
            availableWidth: matrixWidth,
            columnCount: columns.count,
            range: range
        )

        return HStack(alignment: .top, spacing: layout.spacing) {
            ForEach(columns.indices, id: \.self) { colIndex in
                VStack(spacing: layout.spacing) {
                    ForEach(columns[colIndex]) { cell in
                        dotView(
                            cell: cell,
                            size: layout.dotSize,
                            column: colIndex
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dotView(cell: HeatmapDayCell, size: CGFloat, column: Int) -> some View {
        if cell.isFuture {
            Circle()
                .fill(Color.clear)
                .frame(width: size, height: size)
        } else {
            let isHovered = hoveredCell?.id == cell.id
            Circle()
                .fill(dotColor(level: cell.level))
                .frame(width: size, height: size)
                .scaleEffect(isHovered ? 1.38 : 1.0)
                .overlay {
                    if isHovered {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 1.2)
                            .scaleEffect(1.38)
                    }
                }
                .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: isHovered)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hoveredCell = cell
                        hoveredColumn = column
                    } else if hoveredCell?.id == cell.id {
                        hoveredCell = nil
                        hoveredColumn = nil
                    }
                }
                .onTapGesture {
                    if cell.count > 0 {
                        onSelectDay(cell.id)
                    }
                }
        }
    }

    private func dotColor(level: Int) -> Color {
        switch level {
        case 0: FizzTheme.selectedFill
        case 1: FizzTheme.accent.opacity(0.30)
        case 2: FizzTheme.accent.opacity(0.50)
        case 3: FizzTheme.accent.opacity(0.73)
        default: FizzTheme.accent
        }
    }

    private func footer(summary: HeatmapSummary) -> some View {
        HStack(spacing: 8) {
            if let hoveredCell {
                Text(hoverLabel(for: hoveredCell))
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(copyMode == .plain
                    ? FizzL10n.text("最长连续 \(summary.longestStreak) 天 · 点击查看对话", "Longest streak: \(summary.longestStreak) d · Select a day to see conversations")
                    : FizzL10n.text("最长连续 \(summary.longestStreak) 天 · 点击有提交的日期筛选项目", "Longest streak: \(summary.longestStreak) d · Select a commit date to filter projects"))
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(FizzL10n.isEnglish ? 2 : 1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                ForEach(0...4, id: \.self) { level in
                    Circle()
                        .fill(dotColor(level: level))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    private func hoverLabel(for cell: HeatmapDayCell) -> String {
        let formatter = DateFormatter()
        formatter.locale = FizzL10n.locale
        formatter.dateFormat = FizzL10n.text("M 月 d 日", "MMM d")
        let dateText = formatter.string(from: cell.date)
        if cell.count == 0 {
            return FizzL10n.text("\(dateText) · \(copyMode == .plain ? "无对话活动" : "无提交")", "\(dateText) · \(copyMode == .plain ? "No conversations" : "No commits")")
        }
        let breakdown = cell.projects.prefix(3).map { "\($0.name) \($0.count)" }.joined(separator: FizzL10n.text("、", ", "))
        return breakdown.isEmpty
            ? FizzL10n.text("\(dateText) · \(cell.count) 次", "\(dateText) · \(copyMode == .plain ? "Activities" : "Commits"): \(cell.count)")
            : FizzL10n.text("\(dateText) · \(cell.count) 次 · \(breakdown)", "\(dateText) · \(copyMode == .plain ? "Activities" : "Commits"): \(cell.count) · \(breakdown)")
    }
}
