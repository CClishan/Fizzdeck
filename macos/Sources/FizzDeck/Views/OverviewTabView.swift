import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ArtworkFilePicker {
    @MainActor
    static func pickImageURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.prompt = FizzL10n.text("设为项目截图", "Use as project screenshot")
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct OverviewTabView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    let project: RepoProject
    @Binding var noteDraft: String
    let saveNote: () -> Void

    @State private var devLogExists = false
    @State private var testLogExists = false

    private var weekDays: [WorkbenchDay] {
        WorkbenchMetrics.lastSevenDays(counts: project.weekly)
    }

    private var weekValues: [Int] {
        weekDays.map(\.count)
    }

    private var weekTotal: Int {
        weekValues.reduce(0, +)
    }

    private var sessionValues: [Int] {
        WorkbenchMetrics.sessionDayCounts(project.sessions.recentSessions)
    }

    private var cleanupValues: [Int] {
        WorkbenchMetrics.cleanupBars(project.cleanup.items)
    }

    private var testRun: TestRunState? {
        actions.testRun(for: project.path)
    }

    private var lastActiveText: String {
        if let commit = project.lastCommit {
            return commit.subject
        }
        if let message = project.sessions.lastUserMessage {
            return message
        }
        return FizzL10n.text("还没有可识别的活动", "No activity found yet")
    }

    private var logAvailabilityKey: String {
        [
            project.path,
            project.port.rawValue,
            actions.isBusy(project.path) ? "busy" : "idle",
            testRun?.status.rawValue ?? "none",
        ].joined(separator: "|")
    }

    private var logsVisible: Bool {
        devLogExists || testLogExists || project.port == .running || testRun?.status == .running
    }

    var body: some View {
        GeometryReader { proxy in
            let outerWidth = max(320, proxy.size.width)
            let contentWidth = max(260, outerWidth - FizzSpacing.page * 2)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: FizzSpacing.section) {
                    projectSummaryPanel(width: contentWidth)
                    metricGrid

                    if project.run != nil || project.test != nil {
                        ServicesPanel(project: project)
                    }

                    logsAndActivitySection(width: contentWidth)

                    notePanel
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(FizzSpacing.page)
            }
            .frame(width: outerWidth, height: proxy.size.height)
            .fizzTracksScrollPastTop()
        }
        .task(id: logAvailabilityKey) {
            await refreshLogAvailability()
        }
        .onChange(of: project.path) {
            devLogExists = false
            testLogExists = false
        }
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 205, maximum: 360), spacing: FizzSpacing.grid)],
            spacing: FizzSpacing.grid
        ) {
            WorkbenchMetricCard(
                title: FizzL10n.text("本周提交", "Commits this week"),
                symbol: "arrow.triangle.branch",
                tint: FizzTheme.statusSuccess,
                value: project.gitLoadState == .ready ? "\(weekTotal)" : "",
                unit: FizzL10n.text("次", "\(weekTotal == 1 ? "commit" : "commits")"),
                bars: project.gitLoadState == .ready
                    ? WorkbenchMetrics.normalized(weekValues)
                    : [],
                emphasis: project.gitLoadState == .ready
                    ? WorkbenchMetrics.emphasisIndex(weekValues)
                    : nil,
                detail: project.gitLoadState == .ready
                    ? (project.branch ?? FizzL10n.text("无 Git 分支", "No Git branch"))
                    : FizzL10n.text("正在读取 Git", "Reading Git info…"),
                valuePlaceholder: project.gitLoadState != .ready
            )

            diskCard

            WorkbenchMetricCard(
                title: FizzL10n.text("AI 会话", "AI sessions"),
                symbol: "bubble.left.and.bubble.right",
                tint: Color.secondary,
                value: "\(project.sessions.sessionCount)",
                unit: FizzL10n.text("会话", "\(project.sessions.sessionCount == 1 ? "session" : "sessions")"),
                bars: WorkbenchMetrics.normalized(sessionValues),
                emphasis: WorkbenchMetrics.emphasisIndex(sessionValues),
                detail: aiDetail
            )

            WorkbenchMetricCard(
                title: FizzL10n.text("最近活动", "Recent activity"),
                symbol: "clock",
                tint: Color.secondary,
                value: Format.relative(project.recent),
                detail: lastActiveText
            )
        }
    }

    private var diskCard: some View {
        let ready = project.sizeLoadState == .ready
        let parts = WorkbenchMetrics.splitBytes(project.size.totalBytes)
        let detail: String
        if !ready {
            detail = FizzL10n.text("正在后台统计", "Calculating in the background…")
        } else if project.cleanup.items.isEmpty {
            detail = FizzL10n.text("没有命中清理规则", "No matching folders to clean up")
        } else {
            detail = FizzL10n.text("可清理 \(Format.bytes(project.cleanup.reusableBytes)) · \(project.cleanup.items.count) 个目录", "\(Format.bytes(project.cleanup.reusableBytes)) reclaimable · \(project.cleanup.items.count) \(project.cleanup.items.count == 1 ? "folder" : "folders")")
        }

        return WorkbenchMetricCard(
            title: FizzL10n.text("磁盘占用", "Disk usage"),
            symbol: "internaldrive",
            tint: Color.secondary,
            value: ready ? parts.value : "",
            unit: ready ? parts.unit : "",
            bars: ready ? WorkbenchMetrics.normalized(cleanupValues) : Array(repeating: 0, count: 7),
            emphasis: ready ? WorkbenchMetrics.emphasisIndex(cleanupValues) : nil,
            detail: detail,
            valuePlaceholder: !ready
        )
    }

    private var aiDetail: String {
        var parts = project.sessions.detected.map {
            DetectedTool(rawValue: $0)?.title ?? $0.capitalized
        }
        if project.sessions.totalTokens > 0 {
            parts.append("\(Format.tokens(project.sessions.totalTokens)) tokens")
        }
        if let cost = Format.cost(
            project.sessions.totalCostUSD,
            estimated: project.sessions.costIsEstimate
        ) {
            parts.append(cost)
        }
        return parts.isEmpty ? FizzL10n.text("还没有会话", "No sessions yet") : parts.joined(separator: " · ")
    }

    private var activityEntries: [ActivityEntry] {
        var entries: [ActivityEntry] = []
        if let commit = project.lastCommit, let date = commit.date {
            entries.append(ActivityEntry(
                id: "commit-\(commit.hash)",
                date: date,
                title: commit.subject,
                detail: FizzL10n.text("\(commit.hash.prefix(7)) · 提交", "\(commit.hash.prefix(7)) · Commit"),
                symbol: "arrow.triangle.branch",
                tint: FizzTheme.statusSuccess
            ))
        }
        for session in project.sessions.recentSessions.prefix(4) {
            entries.append(ActivityEntry(
                id: "session-\(session.stableID)",
                date: session.modified,
                title: session.lastUser ?? FizzL10n.text("\(DetectedTool(rawValue: session.tool)?.title ?? session.tool) 会话", "\(DetectedTool(rawValue: session.tool)?.title ?? session.tool) session"),
                detail: DetectedTool(rawValue: session.tool)?.title ?? session.tool,
                symbol: DetectedTool(rawValue: session.tool)?.symbol ?? "bubble.left.and.bubble.right",
                tint: .secondary
            ))
        }
        return entries.sorted { $0.date > $1.date }
    }

    private var activityPanel: some View {
        Panel(title: FizzL10n.text("最近活动", "Recent activity"), symbol: "clock.arrow.circlepath") {
            VStack(spacing: 0) {
                ForEach(Array(activityEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 10) {
                        FizzIcon(.sm, symbol: entry.symbol)
                            .foregroundStyle(entry.tint)
                            .frame(width: 16, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(FizzTypography.font(12))
                                .lineLimit(2)
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(FizzTypography.micro)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(Format.relative(entry.date))
                            .font(FizzTypography.micro)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)

                    if index < activityEntries.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logsAndActivitySection(width: CGFloat) -> some View {
        let hasActivity = !activityEntries.isEmpty
        if OverviewLayoutPolicy.showsLogsAndActivitySideBySide(
            width: width,
            hasLogs: logsVisible,
            hasActivity: hasActivity
        ) {
            let widths = OverviewLayoutPolicy.splitWidths(
                totalWidth: width,
                spacing: FizzSpacing.grid
            )
            HStack(alignment: .top, spacing: FizzSpacing.grid) {
                ProjectLogsPanel(
                    project: project,
                    devAvailable: devLogExists,
                    testAvailable: testLogExists
                )
                .frame(width: widths.leading)

                activityPanel
                    .frame(width: widths.trailing)
            }
        } else {
            if logsVisible {
                ProjectLogsPanel(
                    project: project,
                    devAvailable: devLogExists,
                    testAvailable: testLogExists
                )
            }
            if hasActivity {
                activityPanel
            }
        }
    }

    private func projectSummaryPanel(width: CGFloat) -> some View {
        Panel(title: FizzL10n.text("项目", "Project"), symbol: "text.quote") {
            switch OverviewLayoutPolicy.summaryLayout(
                width: width,
                hasArtwork: true
            ) {
            case .threeColumns:
                HStack(alignment: .top, spacing: 18) {
                    artworkSlot
                    verticalHairline
                    projectIntro
                        .frame(maxWidth: .infinity, alignment: .leading)
                    verticalHairline
                    projectStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .twoPlusBottom:
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 18) {
                        artworkSlot
                        verticalHairline
                        projectIntro
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    horizontalHairline
                    projectStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .twoColumns:
                HStack(alignment: .top, spacing: 20) {
                    projectIntro
                        .frame(maxWidth: .infinity, alignment: .leading)
                    verticalHairline
                    projectStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 14) {
                    artworkSlot
                    horizontalHairline
                    projectIntro
                        .frame(maxWidth: .infinity, alignment: .leading)
                    horizontalHairline
                    projectStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var artworkSlot: some View {
        ArtworkThumbnail(
            project: project,
            onPickImage: {
                if let url = ArtworkFilePicker.pickImageURL(),
                   store.setCustomArtwork(from: url, for: project) {
                    ToastCenter.shared.show(FizzL10n.text("已更新项目封面", "Updated project cover"), symbol: "photo.badge.checkmark", tint: Color.secondary)
                }
            },
            onDropImage: { url in
                if store.setCustomArtwork(from: url, for: project) {
                    ToastCenter.shared.show(FizzL10n.text("已更新项目封面", "Updated project cover"), symbol: "photo.badge.checkmark", tint: Color.secondary)
                }
            },
            onResetCustom: {
                store.clearCustomArtwork(for: project)
                ToastCenter.shared.show(FizzL10n.text("已恢复自动识别封面", "Restored automatic cover"), symbol: "arrow.uturn.backward.circle.fill", tint: .secondary)
            }
        )
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(FizzTheme.hairline)
            .frame(width: 1)
    }

    private var horizontalHairline: some View {
        Rectangle()
            .fill(FizzTheme.hairline)
            .frame(height: 1)
    }

    private var projectIntro: some View {
        VStack(alignment: .leading, spacing: 7) {
            if project.intro.text.isEmpty {
                Text(FizzL10n.text("还没有项目简介", "No project description yet"))
                    .font(FizzTypography.font(12))
                    .foregroundStyle(.secondary)
            } else {
                Text(project.intro.text)
                    .font(FizzTypography.font(12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let source = project.intro.source {
                    Text(source)
                        .font(FizzTypography.micro)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var projectStack: some View {
        Group {
            if project.stacks.isEmpty {
                Text(FizzL10n.text("未识别技术栈", "No technology stack found"))
                    .font(FizzTypography.font(12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(project.stacks) { group in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.displayTitle)
                                .font(FizzTypography.micro(.regular))
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            FlowLayout(spacing: 5) {
                                ForEach(group.displayItems, id: \.self) { item in
                                    TagChip(text: item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var notePanel: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                FizzIcon(.sm, symbol: "note.text")
                    .foregroundStyle(.secondary)
                Text(FizzL10n.text("备注", "Notes"))
                    .font(FizzTypography.font(12, weight: .semibold))
            }

            TextField(FizzL10n.text("给这个项目留一句话", "Add a note about this project"), text: $noteDraft)
                .textFieldStyle(.plain)
                .font(FizzTypography.font(12))
                .onSubmit(saveNote)

            Text("\(noteDraft.count)/200")
                .font(FizzTypography.micro)
                .foregroundStyle(.tertiary)

            Button {
                saveNote()
            } label: {
                Label(FizzL10n.text("保存", "Save"), systemImage: "checkmark")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fizzCard(radius: FizzRadius.panel)
    }

    private func refreshLogAvailability() async {
        let devPath = actions.logPath(for: project)
        let testPath = actions.logPath(for: project, prefix: "test-")
        let result = await Task.detached(priority: .utility) {
            (FileTools.exists(devPath), FileTools.exists(testPath))
        }.value
        guard !Task.isCancelled else { return }
        devLogExists = result.0
        testLogExists = result.1
    }
}

private struct ActivityEntry: Identifiable {
    let id: String
    let date: Date
    let title: String
    let detail: String?
    let symbol: String
    let tint: Color
}

private struct WorkbenchMetricCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var unit = ""
    var bars: [Double] = []
    var emphasis: Int? = nil
    var detail: String? = nil
    var valuePlaceholder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                FizzIcon(.md, symbol: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(FizzTypography.caption(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if valuePlaceholder {
                    FizzShimmerPlaceholder(width: 92, height: 24)
                        .padding(.vertical, 3)
                } else {
                    Text(value)
                        .font(FizzTypography.font(23, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    if !unit.isEmpty {
                        Text(unit)
                            .font(FizzTypography.font(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !bars.isEmpty {
                MicroBars(values: bars, emphasis: emphasis, tint: tint)
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(detail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .fizzCard(radius: FizzRadius.card)
    }
}

private struct MicroBars: View {
    let values: [Double]
    let emphasis: Int?
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { index in
                bar(at: index)
            }
        }
        .frame(height: 24, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func bar(at index: Int) -> some View {
        let value = min(1, max(0, values[index]))

        return RoundedRectangle(cornerRadius: FizzRadius.micro, style: .continuous)
            .fill(fill(at: index, value: value))
            .frame(maxWidth: .infinity)
            .frame(height: value <= 0 ? 3 : 3 + value * 21)
    }

    private func fill(at index: Int, value: Double) -> Color {
        if value <= 0 {
            return FizzTheme.hairline
        }
        return index == emphasis ? tint : tint.opacity(0.42)
    }
}

private struct ArtworkThumbnail: View {
    let project: RepoProject
    let onPickImage: () -> Void
    let onDropImage: (URL) -> Void
    let onResetCustom: () -> Void

    @State private var image: NSImage?
    @State private var hovering = false
    @State private var isDropTargeted = false

    private var path: String? {
        project.artwork
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                if let path {
                    SystemActions.open(path)
                } else {
                    onPickImage()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                        .fill(FizzTheme.recessedFill)

                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else if path != nil {
                        FizzIcon(.lg, symbol: "photo")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 5) {
                            FizzIcon(.lg, symbol: "photo.badge.plus")
                                .foregroundStyle(.secondary)
                            Text(FizzL10n.text("上传项目截图", "Upload project screenshot"))
                                .font(FizzTypography.monoSmall(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isDropTargeted {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            VStack(spacing: 4) {
                                FizzIcon(.md, symbol: "photo.badge.plus")
                                    .foregroundStyle(Color.secondary)
                                Text(FizzL10n.text("松开以替换封面", "Drop to replace the cover"))
                                    .font(FizzTypography.monoSmall(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .frame(width: 176, height: 99)
                .clipShape(RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous))
                .overlay {
                    if path == nil {
                        RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                            .strokeBorder(
                                isDropTargeted ? FizzTheme.accent : FizzTheme.stroke,
                                style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 1, dash: [4, 3])
                            )
                    } else {
                        RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                            .strokeBorder(isDropTargeted ? FizzTheme.accent : FizzTheme.stroke, lineWidth: isDropTargeted ? 1.5 : 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(path == nil ? FizzL10n.text("点击或拖拽上传项目截图", "Click or drag a project screenshot here") : FizzL10n.text("点击查看大图，可右键或悬停替换", "Click to enlarge. Hover or right-click to replace."))
            .accessibilityLabel(path == nil ? FizzL10n.text("上传项目截图", "Upload project screenshot") : FizzL10n.text("打开项目封面图", "Open project cover image"))

            if path != nil && hovering {
                Button {
                    onPickImage()
                } label: {
                    Label(FizzL10n.text("替换", "Replace"), systemImage: "photo.badge.plus")
                        .font(FizzTypography.micro(.semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(6)
                .help(FizzL10n.text("替换项目截图", "Replace project screenshot"))
            }
        }
        .onHover { hovering = $0 }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = {
                    if let data = item as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    if let direct = item as? URL {
                        return direct
                    }
                    return nil
                }()
                guard let url, ProjectArtwork.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                    return
                }
                Task { @MainActor in
                    onDropImage(url)
                }
            }
            return true
        }
        .contextMenu {
            Button {
                onPickImage()
            } label: {
                Label(path == nil ? FizzL10n.text("上传项目截图…", "Upload project screenshot…") : FizzL10n.text("替换项目截图…", "Replace project screenshot…"), systemImage: "photo.badge.plus")
            }
            if let path {
                Button {
                    SystemActions.open(path)
                } label: {
                    Label(FizzL10n.text("预览大图", "View full size"), systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            if project.customArtwork != nil {
                Divider()
                Button {
                    onResetCustom()
                } label: {
                    Label(FizzL10n.text("恢复自动识别截图", "Restore automatic screenshot"), systemImage: "arrow.uturn.backward")
                }
            }
        }
        .task(id: path) {
            image = nil
            guard let path else { return }
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

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
