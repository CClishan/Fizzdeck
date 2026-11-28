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
            if showsCoverPreview {
                LibraryCoverPreview(project: project)
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
                                text: FizzL10n.text("\(project.dirtyCount) 处改动", SessionSummaryText.englishCount(project.dirtyCount, "change")),
                                tint: FizzTheme.statusWarning,
                                compact: true
                            )
                            .fixedSize()
                            .help(FizzL10n.text("\(project.dirtyCount) 处未提交改动", "\(project.dirtyCount) uncommitted \(project.dirtyCount == 1 ? "change" : "changes")"))
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
                } else if !showsCoverPreview, let artwork = project.artwork, !artwork.isEmpty {
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
            minHeight: showsCoverPreview ? 188 : 122,
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
            ? (selected ? FizzL10n.text("取消选择 \(project.displayName)", "Deselect \(project.displayName)") : FizzL10n.text("选择 \(project.displayName)", "Select \(project.displayName)"))
            : FizzL10n.text("打开 \(project.displayName)", "Open \(project.displayName)"))
        .accessibilityLabel(selecting
            ? (selected ? FizzL10n.text("取消选择 \(project.displayName)", "Deselect \(project.displayName)") : FizzL10n.text("选择 \(project.displayName)", "Select \(project.displayName)"))
            : FizzL10n.text("打开 \(project.displayName)", "Open \(project.displayName)"))
        .accessibilityHint(selecting ? FizzL10n.text("点击或按空格切换选择", "Click or press Space to toggle selection") : FizzL10n.text("点击或按回车打开项目详情，Command 加回车继续最近 AI 会话", "Press Return to open project details, or Command-Return to resume the latest AI session"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button(project.starred ? FizzL10n.text("取消星标", "Unstar") : FizzL10n.text("设为星标", "Star")) {
                store.toggleStar(project)
            }
            Menu(FizzL10n.text("标签颜色", "Tag color")) {
                Button(FizzL10n.text("无标签", "No tag")) { store.setColor(nil, for: project) }
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
            return "\(project.groupTitle) · \(branch)"
        }
        return project.groupTitle
    }

    private var primaryDetail: String {
        if !project.note.isEmpty { return project.note }
        if let subject = project.lastCommit?.subject { return subject }
        return project.intro.text
    }

    private var firstStack: String? {
        project.stacks.first?.displayItems.first
    }
}

private struct LibraryCoverPreview: View {
    @Environment(\.calendar) private var calendar
    let project: RepoProject

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        Rectangle()
            .fill(FizzTheme.recessedFill)
            .frame(height: 64)
            .overlay {
                if let path = project.artwork, !path.isEmpty {
                    LibraryCoverImage(path: path) { raster }
                } else {
                    raster
                }
            }
            .clipShape(outline)
            .overlay { outline.strokeBorder(FizzTheme.stroke, lineWidth: 1) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var raster: some View {
        let pattern = ProjectRasterPattern(
            weekly: project.weekly, sessions: project.sessions.recentSessions, now: .now, calendar: calendar
        )
        let ink = ProjectAccentColor.color(for: project.path)
        return Canvas { context, size in
            var path = Path()
            path.addRects(pattern.bars(in: size))
            context.fill(path, with: .color(ink))
        }
        .padding(FizzSpacing.row)
    }
}

struct ProjectRasterPattern {
    let dailyActivity: [Double]

    init(weekly: [String: Int], sessions: [SessionRecord], now: Date, calendar: Calendar) {
        let start = DashboardMetrics.sevenDayWindowStart(now: now, calendar: calendar)
        let window = calendar.startOfDay(for: start)...now
        var conversations: [String: Int] = [:]
        for session in sessions where session.kind == .conversation && window.contains(session.modified) {
            let key = WorkbenchMetrics.dayKey(session.modified, calendar: calendar)
            conversations[key, default: 0] += 1
        }
        dailyActivity = WorkbenchMetrics.lastSevenDays(counts: weekly, now: now, calendar: calendar).map { day in
            Double(day.count) + Double(conversations[day.key, default: 0])
        }
    }

    func bars(in size: CGSize) -> [CGRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        let barsPerDay = 6
        let count = dailyActivity.count * barsPerDay
        let pitch = size.width / CGFloat(count)
        let width = min(3, pitch / 2)
        let heights = dailyActivity.map { min(size.height, 2 + 8 * CGFloat(log2(1 + $0))) }
        return (0..<count).map { index in
            let height = heights[index / barsPerDay]
            let center = (CGFloat(index) + 0.5) * pitch
            return CGRect(x: center - width / 2, y: (size.height - height) / 2, width: width, height: height)
        }
    }
}

private struct LibraryCoverMiniThumbnail: View {
    let path: String

    var body: some View {
        LibraryCoverImage(path: path) {
            FizzIcon(.sm, symbol: "photo")
                .foregroundStyle(.tertiary)
        }
        .frame(width: 46, height: 28)
        .background(FizzTheme.recessedFill)
        .clipShape(RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
    }
}

private struct LibraryCoverImage<Placeholder: View>: View {
    let path: String
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: path) {
            image = nil
            let data = await loadLibraryCoverData(at: path)
            guard !Task.isCancelled, let data else { return }
            image = NSImage(data: data)
        }
    }
}

private func loadLibraryCoverData(at path: String) async -> Data? {
    await Task.detached(priority: .utility) { [path] in
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }.value
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
