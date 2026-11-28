import SwiftUI

struct WeeklyTimelineCard: View {
    let columns: [TimelineDayColumn]
    var copyMode: CopyMode = .plain
    let onOpenProject: (String) -> Void
    let onOpenHeatmap: () -> Void

    private var hasActivity: Bool {
        columns.contains { !$0.blocks.isEmpty }
    }

    var body: some View {
        Panel(title: FizzCopy.timelineTitle(copyMode), symbol: "calendar") {
            if hasActivity {
                HStack(alignment: .top, spacing: FizzSpacing.row) {
                    ForEach(columns) { column in
                        dayColumn(column)
                    }
                }
            } else {
                Text(FizzL10n.text("近 7 天暂无活动", "No activity in the last 7 days"))
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            }
        } accessory: {
            if hasActivity {
                legend(.session, label: copyMode == .plain ? FizzL10n.text("对话", "Conversations") : FizzL10n.text("会话", "Sessions"))
                legend(.commit, label: copyMode == .plain ? FizzL10n.text("版本", "Versions") : FizzL10n.text("提交", "Commits"))
            }
            FizzIconButton(title: copyMode == .plain ? FizzCopy.heatmapTitle(.plain) : FizzL10n.text("提交热力图", "Commit heatmap"),
                           symbol: "square.grid.3x3", height: .compact, action: onOpenHeatmap)
        }
    }

    private func dayColumn(_ column: TimelineDayColumn) -> some View {
        VStack(alignment: .leading, spacing: FizzSpacing.row) {
            HStack(spacing: 5) {
                Text(column.dayNumber)
                    .font(FizzTypography.cardTitle)
                    .foregroundStyle(.primary)
                Text(column.weekdayLabel)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(height: FizzControlHeight.compact.rawValue)
            .background(column.isToday ? FizzTheme.selectedFill : Color.clear, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(column.isToday ? FizzL10n.text("今天，\(column.dayNumber) 日，\(column.weekdayLabel)", "Today, \(column.weekdayLabel) \(column.dayNumber)") : FizzL10n.text("\(column.dayNumber) 日，\(column.weekdayLabel)", "\(column.weekdayLabel) \(column.dayNumber)"))

            let orderedBlocks: [TimelineBlock] = copyMode == .plain
                ? column.blocks.sorted { left, right in
                    if left.kind != right.kind {
                        return left.kind == .session
                    }
                    return left.startHour < right.startHour
                }
                : column.blocks
            let visibleBlocks = orderedBlocks.prefix(4)
            let overflow = orderedBlocks.dropFirst(visibleBlocks.count)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleBlocks) { block in
                    blockPill(block)
                }

                if !overflow.isEmpty {
                    Menu {
                        ForEach(overflow) { block in
                            Button("\(block.projectName) · \(block.detail)") { onOpenProject(block.projectPath) }
                        }
                    } label: {
                        Text("+\(overflow.count)")
                            .font(FizzTypography.micro)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityLabel(FizzL10n.text("另有 \(overflow.count) 项活动", "\(overflow.count) more \(overflow.count == 1 ? "event" : "events")"))
                }
            }
            .padding(3)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control))
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }

    private func blockPill(_ block: TimelineBlock) -> some View {
        let tint = ProjectAccentColor.color(for: block.projectPath)

        return Button {
            onOpenProject(block.projectPath)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                FizzIcon(.xs, symbol: symbol(for: block.kind))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(verbatim: block.projectName)
                    .font(FizzTypography.caption(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: FizzControlHeight.compact.rawValue, alignment: .leading)
            .background(tint.opacity(block.kind == .session ? 0.19 : 0.11), in: RoundedRectangle(cornerRadius: FizzRadius.micro))
        }
        .buttonStyle(.plain)
        .help("\(block.projectName) · \(block.detail)")
        .accessibilityLabel(block.projectName)
        .accessibilityValue(block.detail)
    }

    private func legend(_ kind: TimelineBlock.Kind, label: String) -> some View {
        HStack(spacing: 4) {
            FizzIcon(.xs, symbol: symbol(for: kind)).accessibilityHidden(true)
            Text(label).font(FizzTypography.micro)
        }
        .foregroundStyle(.secondary)
    }

    private func symbol(for kind: TimelineBlock.Kind) -> String {
        kind == .session ? "bubble.left.fill" : "arrow.triangle.branch"
    }
}
