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
}

private extension Int {
    var cgFloat: CGFloat { CGFloat(self) }
}

struct CommitHeatmapCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("fizzdeck.heatmap.range") private var rangeRaw = HeatmapRange.weeks26.rawValue

    let snapshot: CommitActivitySnapshot
    let projects: [RepoProject]
    let onSelectDay: (String) -> Void

    @State private var hoveredCell: HeatmapDayCell?
    @State private var matrixWidth: CGFloat = 0

    private var range: HeatmapRange {
        HeatmapRange(rawValue: rangeRaw) ?? .weeks26
    }

    private var summary: HeatmapSummary {
        DashboardMetrics.buildHeatmap(
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
                    Text("提交热力图")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(data.totalCommits)")
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)

                        Text("次 · 连续 \(data.currentStreak) 天")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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
        .overlay(alignment: .topTrailing) {
            if let hoveredCell {
                Text(hoverLabel(for: hoveredCell))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())
                    .fizzAdaptiveShadow(.floating)
                    .padding(.top, 46)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: hoveredCell?.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("提交热力图，\(range.title)共 \(data.totalCommits) 次本人提交，当前连续 \(data.currentStreak) 天，最长连续 \(data.longestStreak) 天")
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
                .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
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
                        dotView(cell: cell, size: layout.dotSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dotView(cell: HeatmapDayCell, size: CGFloat) -> some View {
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
                            .strokeBorder(colorScheme == .dark ? Color.white : FizzTheme.accent, lineWidth: 1.2)
                            .scaleEffect(1.38)
                    }
                }
                .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: isHovered)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hoveredCell = cell
                    } else if hoveredCell?.id == cell.id {
                        hoveredCell = nil
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
        if colorScheme == .dark {
            let gold = Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255)
            switch level {
            case 0: return Color.white.opacity(0.10)
            case 1: return gold.opacity(0.32)
            case 2: return gold.opacity(0.56)
            case 3: return gold.opacity(0.78)
            default: return gold
            }
        }

        switch level {
        case 0: return Color.primary.opacity(0.08)
        case 1: return Color(red: 0xF4 / 255, green: 0xD5 / 255, blue: 0x7A / 255)
        case 2: return Color(red: 0xE6 / 255, green: 0xAE / 255, blue: 0x32 / 255)
        case 3: return Color(red: 0xCE / 255, green: 0x85 / 255, blue: 0x10 / 255)
        default: return Color(red: 0x9F / 255, green: 0x5D / 255, blue: 0x06 / 255)
        }
    }

    private func footer(summary: HeatmapSummary) -> some View {
        HStack(spacing: 8) {
            if let hoveredCell {
                Text(hoverLabel(for: hoveredCell))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("最长连续 \(summary.longestStreak) 天 · 点击有提交的日期筛选项目")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M 月 d 日"
        let dateText = formatter.string(from: cell.date)
        if cell.count == 0 {
            return "\(dateText) · 无提交"
        }
        let breakdown = cell.projects.prefix(3).map { "\($0.name) \($0.count)" }.joined(separator: "、")
        return breakdown.isEmpty
            ? "\(dateText) · \(cell.count) 次"
            : "\(dateText) · \(cell.count) 次 · \(breakdown)"
    }
}
