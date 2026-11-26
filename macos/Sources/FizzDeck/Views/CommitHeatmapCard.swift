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

    private var surfaceFill: Color {
        colorScheme == .dark
            ? Color(red: 0x22 / 255, green: 0x25 / 255, blue: 0x2A / 255)
            : Color(red: 0x1B / 255, green: 0x1D / 255, blue: 0x20 / 255)
    }

    private var surfaceStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.09 : 0.07)
    }

    var body: some View {
        let data = summary

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("提交热力图")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(data.totalCommits)")
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)

                        Text("次 · 连续 \(data.currentStreak) 天")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.65))
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
        .background(
            surfaceFill,
            in: RoundedRectangle(cornerRadius: FizzRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.panel, style: .continuous)
                .strokeBorder(surfaceStroke, lineWidth: 1)
        }
        .fizzAdaptiveShadow(.raised)
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
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.72))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            selected ? Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255) : Color.clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.08), in: Capsule())
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
                            .strokeBorder(Color.white, lineWidth: 1.2)
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
        let gold = Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255)
        switch level {
        case 0: return Color.white.opacity(0.10)
        case 1: return gold.opacity(0.32)
        case 2: return gold.opacity(0.56)
        case 3: return gold.opacity(0.78)
        default: return gold
        }
    }

    private func footer(summary: HeatmapSummary) -> some View {
        HStack(spacing: 8) {
            if let hoveredCell {
                Text(hoverLabel(for: hoveredCell))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("最长连续 \(summary.longestStreak) 天 · 点击有提交的日期筛选项目")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.56))
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
