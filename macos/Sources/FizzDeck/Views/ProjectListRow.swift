import SwiftUI

struct ProjectListRow: View {
    @Environment(RepositoryStore.self) private var store
    let project: RepoProject
    var selecting = false
    var selected = false
    var toggleSelection: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if selecting {
                FizzIcon(symbol: selected ? "checkmark.circle.fill" : "circle", size: 15)
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.55))
                    .frame(width: 16)
            }

            ProjectBadgeIcon(project: project, size: 28, framed: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if project.starred {
                        FizzIcon(symbol: "star.fill", size: 9)
                            .foregroundStyle(.yellow)
                    }
                    if project.dirtyCount > 0 {
                        TagChip(
                            text: "\(project.dirtyCount) 处改动",
                            tint: .orange,
                            compact: true
                        )
                        .help("\(project.dirtyCount) 处未提交改动")
                    }
                }
                Text(secondaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let tool = project.sessions.lastTool ?? project.detectedTools.first?.rawValue {
                HomeToolBadge(tool: tool)
            }
            if let stack = firstStack {
                TagChip(text: stack.0, tint: stack.1, compact: true)
            }

            Text(Format.relative(project.recent))
                .frame(width: 66, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(project.sizeLoadState == .ready ? Format.bytes(project.size.totalBytes) : "统计中")
                .frame(width: 62, alignment: .trailing)
                .foregroundStyle(.secondary)
            if project.port == .running {
                PortStatusBadge(state: project.port, port: project.run?.port)
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .fill(accent.opacity(0.10))
            } else if hovering {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .fill(FizzTheme.mutedFill)
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .strokeBorder(
                        accent.opacity(0.28),
                        lineWidth: 1
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                toggleSelection()
            } else {
                store.selectedPath = project.path
            }
        }
        .onHover { value in
            hovering = value
        }
        .help(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityLabel(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            ProjectGroupingMenu(project: project)
            ProjectQuickActions(project: project)
        }
    }

    private var secondaryText: String {
        if !project.note.isEmpty { return project.note }
        if let subject = project.lastCommit?.subject { return subject }
        return project.group
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var firstStack: (String, Color)? {
        guard let group = project.stacks.first, let item = group.items.first else { return nil }
        return (item, group.color)
    }
}
