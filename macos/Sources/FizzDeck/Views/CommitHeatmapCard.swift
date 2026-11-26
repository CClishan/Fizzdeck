import SwiftUI

struct CommitHeatmapCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("fizzdeck.heatmap.range") private var rangeRaw = HeatmapRange.weeks26.rawValue

    let snapshot: CommitActivitySnapshot
    let projects: [RepoProject]
    let onSelectDay: (String) -> Void

    @State private var hoveredCell: HeatmapDayCell?

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
                            .foregroundStyle(.primary)

                        Text("次 · 连续 \(data.currentStreak) 天")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: 8)

                rangePicker
            }

            dotMatrix(columns: data.columns)

            footer(summary: data)
        }
        .padding(16)
        .fizzCard(radius: FizzRadius.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("提交热力图，\(range.title)共 \(data.totalCommits) 次本人提交，当前连续 \(data.currentStreak) 天，最长连续 \(data.longestStreak) 天")
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(HeatmapRange.allCases) { item in
                let selected = range == item
                Button {
                    rangeRaw = item.rawValue
                } label: {
                    Text(item.title)
                        .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            selected ? FizzTheme.elevatedFill : Color.clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(FizzTheme.recessedFill, in: Capsule())
    }

    private func dotMatrix(columns: [[HeatmapDayCell]]) -> some View {
        let dotSpacing: CGFloat = range == .weeks26 ? 4 : 2.2
        let dotSize: CGFloat = range == .weeks26 ? 8.5 : 5.2

        return HStack(alignment: .top, spacing: dotSpacing) {
            ForEach(columns.indices, id: \.self) { colIndex in
                VStack(spacing: dotSpacing) {
                    ForEach(columns[colIndex]) { cell in
                        dotView(cell: cell, size: dotSize)
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
                .overlay {
                    if isHovered {
                        Circle()
                            .strokeBorder(colorScheme == .dark ? Color.white : FizzTheme.accent, lineWidth: 1.2)
                    }
                }
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
