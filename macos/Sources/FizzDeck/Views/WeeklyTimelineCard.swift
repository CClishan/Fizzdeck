import SwiftUI

struct WeeklyTimelineCard: View {
    let columns: [TimelineDayColumn]
    let onOpenProject: (String) -> Void

    private var hasActivity: Bool {
        columns.contains { !$0.blocks.isEmpty }
    }

    var body: some View {
        if hasActivity {
            Panel(title: "本周活动时间线", symbol: "clock") {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(columns) { column in
                        dayColumn(column)
                    }
                }
                .padding(.top, 2)
            } accessory: {
                HStack(spacing: 10) {
                    legendDot(color: .green, label: "提交")
                    legendDot(color: FizzTheme.accent, label: "会话")
                }
            }
        }
    }

    private func dayColumn(_ column: TimelineDayColumn) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text(column.weekdayLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(column.dayNumber)
                    .font(.system(size: 11, weight: column.isToday ? .semibold : .medium).monospacedDigit())
                    .foregroundStyle(column.isToday ? Color.white : Color.primary)
                    .frame(width: 22, height: 22)
                    .background(
                        column.isToday ? FizzTheme.accent : Color.clear,
                        in: Circle()
                    )
            }

            let visibleBlocks = Array(column.blocks.prefix(4))
            let overflowCount = max(0, column.blocks.count - visibleBlocks.count)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleBlocks) { block in
                    blockPill(block)
                }

                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    .fill(FizzTheme.recessedFill)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func blockPill(_ block: TimelineBlock) -> some View {
        let tint: Color = block.kind == .commit ? .green : FizzTheme.accent

        return Button {
            onOpenProject(block.projectPath)
        } label: {
            Text(block.projectName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
                .background(tint.opacity(0.88), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(block.projectName) · \(block.detail)")
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
