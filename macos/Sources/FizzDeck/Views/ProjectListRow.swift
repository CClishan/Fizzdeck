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
                FizzIcon(.md, symbol: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.primary : Color.secondary.opacity(0.55))
                    .frame(width: 16)
            }

            ProjectBadgeIcon(project: project, size: 28, framed: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.displayName)
                        .font(FizzTypography.cardTitle)
                        .lineLimit(1)
                    if project.starred {
                        FizzIcon(.xs, symbol: "star.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    if project.dirtyCount > 0 {
                        TagChip(
                            text: "\(project.dirtyCount) 处改动",
                            tint: FizzTheme.statusWarning,
                            compact: true
                        )
                        .help("\(project.dirtyCount) 处未提交改动")
                    }
                }
                Text(secondaryText)
                    .font(FizzTypography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let tool = project.sessions.lastTool ?? project.detectedTools.first?.rawValue {
                HomeToolBadge(tool: tool)
            }
            if let stack = firstStack {
                TagChip(text: stack, compact: true)
            }

            Text(Format.relative(project.recent))
                .frame(width: 66, alignment: .trailing)
                .foregroundStyle(.secondary)
            Group {
                if project.sizeLoadState == .ready {
                    Text(Format.bytes(project.size.totalBytes))
                        .foregroundStyle(.secondary)
                } else if project.sizeLoadState == .loading {
                    FizzShimmerPlaceholder(width: 38, height: 10)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 62, alignment: .trailing)
            if project.port == .running {
                PortStatusBadge(state: project.port, port: project.run?.port)
            }
        }
        .font(FizzTypography.micro)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .fill(FizzTheme.selectedFill)
            } else if hovering {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .fill(FizzTheme.mutedFill)
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .strokeBorder(
                        FizzTheme.stroke,
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

    private var firstStack: String? {
        project.stacks.first?.items.first
    }
}
