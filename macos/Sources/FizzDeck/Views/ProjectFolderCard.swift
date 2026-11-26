import SwiftUI

struct ProjectFolderCard: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject
    var selecting = false
    var selected = false
    var focused = false
    var toggleSelection: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProjectBadgeIcon(project: project, size: 32, framed: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(project.displayName)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)

                        if project.starred {
                            FizzIcon(symbol: "star.fill", size: 9)
                                .foregroundStyle(.yellow)
                        }
                    }

                    HStack(spacing: 5) {
                        Text(projectSubtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if project.dirtyCount > 0 {
                            TagChip(
                                text: "\(project.dirtyCount) 处改动",
                                tint: .orange,
                                compact: true
                            )
                            .fixedSize()
                            .help("\(project.dirtyCount) 处未提交改动")
                        }
                    }
                }

                Spacer(minLength: 4)

                if selecting {
                    FizzIcon(
                        symbol: selected ? "checkmark.circle.fill" : "circle",
                        size: 16
                    )
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                } else if project.port == .running {
                    PortStatusBadge(state: project.port, port: project.run?.port)
                }
            }

            Text(primaryDetail)
                .font(.system(size: 11.5))
                .foregroundStyle(project.note.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)

            HStack(spacing: 5) {
                if let stack = firstStack {
                    TagChip(text: stack.0, tint: stack.1, compact: true)
                }

                Spacer(minLength: 4)

                Text(Format.relative(project.recent))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 122, maxHeight: 128, alignment: .topLeading)
        .background(FizzTheme.cardFill, in: RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                .strokeBorder(
                    focused
                        ? FizzTheme.accent
                        : selected
                            ? accent.opacity(0.55)
                            : hovering ? accent.opacity(0.24) : FizzTheme.stroke,
                    lineWidth: (focused || selected) ? 1.5 : 1
                )
        }
        .fizzAdaptiveShadow(hovering ? .raised : .subtle)
        .contentShape(RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .onTapGesture {
            if selecting {
                toggleSelection()
            } else {
                store.selectedPath = project.path
            }
        }
        .onHover { value in
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                hovering = value
            }
        }
        .help(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityLabel(selecting
            ? (selected ? "取消选择 \(project.displayName)" : "选择 \(project.displayName)")
            : "打开 \(project.displayName)")
        .accessibilityHint(selecting ? "点击或按空格切换选择" : "点击或按回车打开项目详情，Command 加回车继续最近 AI 会话")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button(project.starred ? "取消星标" : "设为星标") {
                store.toggleStar(project)
            }
            Menu("标签颜色") {
                Button("无标签") { store.setColor(nil, for: project) }
                ForEach(TagColor.allCases) { color in
                    Button(color.label) { store.setColor(color, for: project) }
                }
            }
            ProjectGroupingMenu(project: project)
            Divider()
            ProjectQuickActions(project: project)
        }
    }

    private var accent: Color {
        project.color?.color ?? ProjectGrouping.color(for: project.group)
    }

    private var projectSubtitle: String {
        if let branch = project.branch {
            return "\(project.group) · \(branch)"
        }
        return project.group
    }

    private var primaryDetail: String {
        if !project.note.isEmpty { return project.note }
        if let subject = project.lastCommit?.subject { return subject }
        return project.intro.text
    }

    private var firstStack: (String, Color)? {
        guard let group = project.stacks.first, let item = group.items.first else { return nil }
        return (item, group.color)
    }
}

struct HomeToolBadge: View {
    let tool: String
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            FizzIcon(symbol: symbol, size: 10)
            if !compact {
                Text(title)
            }
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 4 : 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.09), in: Capsule())
        .lineLimit(1)
        .help(title)
    }

    private var title: String {
        HomeDashboardModel.toolTitle(tool)
    }

    private var symbol: String {
        HomeDashboardModel.toolSymbol(tool)
    }

    private var tint: Color {
        DetectedTool(rawValue: tool)?.tint ?? .secondary
    }
}
