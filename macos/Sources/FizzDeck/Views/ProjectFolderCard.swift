import SwiftUI

struct ProjectFolderCard: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject
    var selecting = false
    var selected = false
    var focused = false
    var showsCoverPreview = true
    var toggleSelection: () -> Void = {}

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.row) {
            if showsCoverPreview, let artwork = project.artwork {
                LibraryCoverPreview(path: artwork)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            HStack(alignment: .center, spacing: 10) {
                ProjectBadgeIcon(project: project, size: 32, framed: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(project.displayName)
                            .font(FizzTypography.cardTitle)
                            .lineLimit(1)

                        if project.starred {
                            FizzIcon(.xs, symbol: "star.fill")
                                .foregroundStyle(Color.secondary)
                        }
                    }

                    HStack(spacing: 5) {
                        Text(projectSubtitle)
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if project.dirtyCount > 0 {
                            TagChip(
                                text: "\(project.dirtyCount) 处改动",
                                tint: FizzTheme.statusWarning,
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
                        .md, symbol: selected ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(selected ? Color.primary : Color.secondary.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                } else if project.port == .running {
                    PortStatusBadge(state: project.port, port: project.run?.port)
                } else if !showsCoverPreview, let artwork = project.artwork {
                    LibraryCoverMiniThumbnail(path: artwork)
                }
            }

            Text(primaryDetail)
                .font(FizzTypography.caption)
                .foregroundStyle(project.note.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .topLeading)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                if let stack = firstStack {
                    TagChip(text: stack, compact: true)
                }

                Spacer(minLength: 4)

                Text(Format.relative(project.recent))
                    .font(FizzTypography.micro)
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
        }
        .padding(FizzSpacing.card)
        .frame(
            maxWidth: .infinity,
            minHeight: showsCoverPreview && project.artwork != nil ? 188 : 122,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(selected ? FizzTheme.selectedFill : FizzTheme.cardFill,
                    in: RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                .strokeBorder(
                    focused
                        ? FizzTheme.accent
                        : selected
                            ? Color.primary.opacity(0.35)
                            : FizzTheme.stroke,
                    lineWidth: (focused || selected) ? 1.5 : 1
                )
        }
        .fizzAdaptiveShadow(hovering ? .raised : .subtle)
        .scaleEffect(pressed ? 0.988 : 1)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: pressed)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: showsCoverPreview)
        .contentShape(RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .onTapGesture {
            if selecting {
                toggleSelection()
            } else {
                store.selectedPath = project.path
            }
        }
        .onHover { value in
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                hovering = value
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true }
                }
                .onEnded { _ in
                    pressed = false
                }
        )
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

    private var firstStack: String? {
        project.stacks.first?.items.first
    }
}

private struct LibraryCoverPreview: View {
    let path: String

    var body: some View {
        LibraryCoverImage(path: path)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }
    }
}

private struct LibraryCoverMiniThumbnail: View {
    let path: String

    var body: some View {
        LibraryCoverImage(path: path)
            .frame(width: 46, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }
    }
}

private struct LibraryCoverImage: View {
    let path: String

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(FizzTheme.recessedFill)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                FizzIcon(.sm, symbol: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: path) {
            image = nil
            let data: Data? = await Task.detached(priority: .utility) { () -> Data? in
                guard let value = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                    return nil
                }
                return Task.isCancelled ? nil : value
            }.value
            guard !Task.isCancelled, let data else { return }
            image = NSImage(data: data)
        }
    }
}

struct HomeToolBadge: View {
    let tool: String
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            FizzIcon(.xs, symbol: symbol)
            if !compact {
                Text(title)
            }
        }
        .font(FizzTypography.micro)
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 4 : 5)
        .padding(.vertical, 2)
        .background(FizzTheme.mutedFill, in: Capsule())
        .lineLimit(1)
        .help(title)
    }

    private var title: String {
        HomeDashboardModel.toolTitle(tool)
    }

    private var symbol: String {
        HomeDashboardModel.toolSymbol(tool)
    }

}
