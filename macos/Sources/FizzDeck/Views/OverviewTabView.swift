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
        panel.prompt = "设为项目截图"
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
    @State private var contentWidth: CGFloat = 960

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
        return "还没有可识别的活动"
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
        ScrollView {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                projectSummaryPanel
                metricGrid

                if project.run != nil || project.test != nil {
                    ServicesPanel(project: project)
                }

                logsAndActivitySection

                notePanel
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: { newWidth in
                contentWidth = newWidth
            }
            .padding(FizzSpacing.page)
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
                title: "本周提交",
                symbol: "arrow.triangle.branch",
                tint: .green,
                value: "\(weekTotal)",
                unit: "次",
                bars: WorkbenchMetrics.normalized(weekValues),
                emphasis: WorkbenchMetrics.emphasisIndex(weekValues),
                detail: project.branch ?? "无 Git 分支"
            )

            diskCard

            WorkbenchMetricCard(
                title: "AI 会话",
                symbol: "bubble.left.and.bubble.right",
                tint: .purple,
                value: "\(project.sessions.sessionCount)",
                unit: "会话",
                bars: WorkbenchMetrics.normalized(sessionValues),
                emphasis: WorkbenchMetrics.emphasisIndex(sessionValues),
                detail: aiDetail
            )

            WorkbenchMetricCard(
                title: "最近活动",
                symbol: "clock",
                tint: .blue,
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
            detail = "正在后台统计"
        } else if project.cleanup.items.isEmpty {
            detail = "没有命中清理规则"
        } else {
            detail = "可清理 \(Format.bytes(project.cleanup.reusableBytes)) · \(project.cleanup.items.count) 个目录"
        }

        return WorkbenchMetricCard(
            title: "磁盘占用",
            symbol: "internaldrive",
            tint: .indigo,
            value: ready ? parts.value : "统计中…",
            unit: ready ? parts.unit : "",
            bars: ready ? WorkbenchMetrics.normalized(cleanupValues) : Array(repeating: 0, count: 7),
            emphasis: ready ? WorkbenchMetrics.emphasisIndex(cleanupValues) : nil,
            detail: detail
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
        return parts.isEmpty ? "还没有会话" : parts.joined(separator: " · ")
    }

    private var activityEntries: [ActivityEntry] {
        var entries: [ActivityEntry] = []
        if let commit = project.lastCommit, let date = commit.date {
            entries.append(ActivityEntry(
                id: "commit-\(commit.hash)",
                date: date,
                title: commit.subject,
                detail: "\(commit.hash.prefix(7)) · 提交",
                symbol: "arrow.triangle.branch",
                tint: .green
            ))
        }
        for session in project.sessions.recentSessions.prefix(4) {
            entries.append(ActivityEntry(
                id: "session-\(session.stableID)",
                date: session.modified,
                title: session.lastUser ?? "\(DetectedTool(rawValue: session.tool)?.title ?? session.tool) 会话",
                detail: DetectedTool(rawValue: session.tool)?.title ?? session.tool,
                symbol: DetectedTool(rawValue: session.tool)?.symbol ?? "bubble.left.and.bubble.right",
                tint: DetectedTool(rawValue: session.tool)?.tint ?? .secondary
            ))
        }
        return entries.sorted { $0.date > $1.date }
    }

    private var activityPanel: some View {
        Panel(title: "最近活动", symbol: "clock.arrow.circlepath") {
            VStack(spacing: 0) {
                ForEach(Array(activityEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 10) {
                        FizzIcon(symbol: entry.symbol, size: 12)
                            .foregroundStyle(entry.tint)
                            .frame(width: 16, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.callout)
                                .lineLimit(2)
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(Format.relative(entry.date))
                            .font(.caption2)
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
    private var logsAndActivitySection: some View {
        let hasActivity = !activityEntries.isEmpty
        if OverviewLayoutPolicy.showsLogsAndActivitySideBySide(
            width: contentWidth,
            hasLogs: logsVisible,
            hasActivity: hasActivity
        ) {
            let widths = OverviewLayoutPolicy.splitWidths(
                totalWidth: contentWidth,
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

    private var projectSummaryPanel: some View {
        Panel(title: "项目", symbol: "text.quote") {
            switch OverviewLayoutPolicy.summaryLayout(
                width: contentWidth,
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
                if let url = ArtworkFilePicker.pickImageURL() {
                    _ = store.setCustomArtwork(from: url, for: project)
                }
            },
            onDropImage: { url in
                _ = store.setCustomArtwork(from: url, for: project)
            },
            onResetCustom: {
                store.clearCustomArtwork(for: project)
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
                Text("还没有项目简介")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(project.intro.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let source = project.intro.source {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var projectStack: some View {
        Group {
            if project.stacks.isEmpty {
                Text("未识别技术栈")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(project.stacks) { group in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            FlowLayout(spacing: 5) {
                                ForEach(group.items, id: \.self) { item in
                                    TagChip(text: item, tint: group.color)
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
                FizzIcon(symbol: "note.text", size: 12)
                    .foregroundStyle(.secondary)
                Text("备注")
                    .font(.system(size: 12, weight: .semibold))
            }

            TextField("给这个项目留一句话", text: $noteDraft)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit(saveNote)

            Text("\(noteDraft.count)/200")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Button {
                saveNote()
            } label: {
                Label("保存", systemImage: "checkmark")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                FizzIcon(symbol: symbol, size: 13)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 23, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if !bars.isEmpty {
                MicroBars(values: bars, emphasis: emphasis, tint: tint)
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
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
                        FizzIcon(symbol: "photo", size: 18)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 5) {
                            FizzIcon(symbol: "photo.badge.plus", size: 17)
                                .foregroundStyle(.secondary)
                            Text("上传项目截图")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
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
            .help(path == nil ? "点击或拖拽上传项目截图" : "点击查看大图，可右键或悬停替换")
            .accessibilityLabel(path == nil ? "上传项目截图" : "打开项目封面图")

            if path != nil && hovering {
                Button {
                    onPickImage()
                } label: {
                    Label("替换", systemImage: "photo.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.mini)
                .padding(6)
                .help("替换项目截图")
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
                Label(path == nil ? "上传项目截图…" : "替换项目截图…", systemImage: "photo.badge.plus")
            }
            if let path {
                Button {
                    SystemActions.open(path)
                } label: {
                    Label("预览大图", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            if project.customArtwork != nil {
                Divider()
                Button {
                    onResetCustom()
                } label: {
                    Label("恢复自动识别截图", systemImage: "arrow.uturn.backward")
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
