import SwiftUI

struct ConversationsWorkspaceView: View {
    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all
        case active
        case error

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "全部"
            case .active: "进行中"
            case .error: "报错结束"
            }
        }
    }

    private struct ConversationEntry: Identifiable {
        let project: RepoProject
        let session: SessionRecord

        var id: String { "\(project.path)::\(session.stableID)" }
    }

    private struct DaySection: Identifiable {
        let id: String
        let title: String
        let entries: [ConversationEntry]
    }

    @Environment(RepositoryStore.self) private var store
    @State private var statusFilter: StatusFilter = .all
    @State private var toolFilter = "all"
    @State private var searchQuery = ""
    @State private var searchResults: [SessionSearchResult] = []
    @State private var isSearching = false
    @State private var scrolledPastTop = false
    @State private var resumingID: String?
    let onShowRecap: () -> Void

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        !trimmedSearchQuery.isEmpty
    }

    private var allEntries: [ConversationEntry] {
        var result: [ConversationEntry] = []
        for project in store.projects {
            for session in project.sessions.recentSessions where session.kind == .conversation {
                result.append(ConversationEntry(project: project, session: session))
            }
        }
        return result.sorted { $0.session.modified > $1.session.modified }
    }

    private var availableTools: [String] {
        let present = Set(allEntries.map(\.session.tool))
        let ordered = DetectedTool.allCases.map(\.rawValue).filter(present.contains)
        return ordered + present.subtracting(ordered).sorted()
    }

    private var filteredEntries: [ConversationEntry] {
        allEntries.filter { entry in
            switch statusFilter {
            case .all: break
            case .active:
                guard store.activeAISessionIDs.contains(entry.session.stableID) else { return false }
            case .error:
                guard entry.session.endedWithError else { return false }
            }
            if toolFilter != "all", entry.session.tool != toolFilter {
                return false
            }
            return true
        }
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M 月 d 日 EEEE"

        var grouped: [(key: String, title: String, entries: [ConversationEntry])] = []
        var indexByKey: [String: Int] = [:]

        for entry in filteredEntries {
            let day = calendar.startOfDay(for: entry.session.modified)
            let key = String(Int(day.timeIntervalSince1970))
            if let existing = indexByKey[key] {
                grouped[existing].entries.append(entry)
            } else {
                let title: String
                if calendar.isDate(day, inSameDayAs: today) {
                    title = "今天"
                } else if let yesterday, calendar.isDate(day, inSameDayAs: yesterday) {
                    title = "昨天"
                } else {
                    title = formatter.string(from: day)
                }
                indexByKey[key] = grouped.count
                grouped.append((key: key, title: title, entries: [entry]))
            }
        }

        return grouped.map { DaySection(id: $0.key, title: $0.title, entries: $0.entries) }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                FizzPageHeader(
                    title: FizzCopy.conversationsNavTitle,
                    subtitle: "跨项目按天汇总的 AI 对话记录"
                ) {
                    FizzActionButton(title: "复盘", symbol: "calendar.badge.clock", keyboardNavigation: true, action: onShowRecap)
                }
                filters

                if allEntries.isEmpty {
                    ContentUnavailableView(
                        "还没有 AI 对话记录",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("当你用 Codex、Claude Code、DeepSeek 或 AGY 在受管项目里工作后，对话会自动汇总到这里。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else if isSearchActive {
                    searchResultsBody
                } else if daySections.isEmpty {
                    ContentUnavailableView(
                        "没有符合条件的对话",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("试试切换状态或工具筛选。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(daySections) { section in
                        VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                            Text(section.title)
                                .font(FizzTypography.sectionTitle)
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            VStack(spacing: FizzSpacing.row) {
                                ForEach(section.entries) { entry in
                                    conversationCard(entry)
                                }
                            }
                        }
                    }
                }
            }
            .padding(FizzSpacing.page)
        }
        .fizzTracksScrollPastTop()
        .overlay(alignment: .top) {
            FizzScrollTopHairline(visible: scrolledPastTop)
        }
        .onPreferenceChange(FizzScrollPastTopKey.self) { scrolledPastTop = $0 }
        .task {
            await store.refreshActiveAISessions()
        }
        .task(id: "\(searchQuery)|\(statusFilter.rawValue)|\(toolFilter)|\(store.projects.count)|\(store.hasIndexedSessionSearch)") {
            await runSearch()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            FizzIcon(.sm, symbol: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("搜索对话（支持中文、报错关键字、文件名）", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(FizzTypography.body)
                .accessibilityLabel("搜索所有项目的对话")

            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: FizzControlHeight.compact.rawValue)
                    .accessibilityLabel("正在搜索对话")
            } else if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    FizzIcon(.sm, symbol: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: FizzControlHeight.compact.rawValue, height: FizzControlHeight.compact.rawValue)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除对话搜索")
                .help("清除搜索")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, isSearching || !searchQuery.isEmpty ? 2 : 10)
        .frame(height: FizzControlHeight.compact.rawValue)
        .background(FizzTheme.recessedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.control)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var filters: some View {
        HStack(spacing: FizzSpacing.row) {
            searchField

            FizzSegmentedCapsule(items: StatusFilter.allCases, selection: $statusFilter, height: .compact, keyboardNavigation: true) { item, _ in
                Text(item.title)
                    .font(FizzTypography.caption(.medium))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("状态筛选")

            Menu {
                ForEach(["all"] + availableTools, id: \.self) { tool in
                    Button {
                        toolFilter = tool
                    } label: {
                        if toolFilter == tool {
                            Label(toolFilterTitle(tool), systemImage: "checkmark")
                        } else {
                            Text(toolFilterTitle(tool))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(toolFilterTitle(toolFilter))
                        .font(FizzTypography.caption(.medium))
                    FizzIcon(.xs, symbol: "chevron.down")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 8)
                .frame(height: FizzControlHeight.compact.rawValue)
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .fixedSize()
            .accessibilityLabel("工具筛选")
            .accessibilityValue(toolFilterTitle(toolFilter))

            Text(isSearchActive ? "命中 \(searchResults.count) 条" : "共 \(filteredEntries.count) 条")
                .font(FizzTypography.monoSmall)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func toolFilterTitle(_ tool: String) -> String {
        tool == "all" ? "全部工具" : HomeDashboardModel.toolTitle(tool)
    }

    private func conversationCard(_ entry: ConversationEntry) -> some View {
        let project = entry.project
        let session = entry.session
        let toolTitle = HomeDashboardModel.toolTitle(session.tool)
        let isLive = store.activeAISessionIDs.contains(session.stableID)
        let isResuming = resumingID == session.stableID
        let resumeTitle = isLive ? "回到会话" : "继续"
        let openSession = { store.openProject(project, tab: .progress, sessionID: session.id) }

        return conversationRow(projectPath: project.path, modified: session.modified, durationMinutes: session.durationMinutes) {
            Button(action: openSession) {
                VStack(alignment: .leading, spacing: 6) {
                    projectMetadata(project.displayName, tool: session.tool) {
                        statusBadge(isLive: isLive, session: session)
                    }
                    conversationTitle(session.primaryIntent ?? "\(toolTitle) 会话")
                    if !session.touchedFiles.isEmpty {
                        touchedFiles(session.touchedFiles)
                    }
                    if session.endedWithError, let err = session.lastError, !err.isEmpty {
                        Text(err)
                            .font(FizzTypography.monoSmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fizzKeyboardAction(action: openSession)
        } actions: {
            HStack(spacing: 6) {
                HandoffCopyButton(project: project, compact: true)

                if session.resumeCommand != nil {
                    FizzActionButton(
                        title: isResuming ? "恢复中…" : resumeTitle,
                        symbol: "play.fill", height: .compact, prominence: .primary
                    ) {
                        Task { await resume(session, in: project) }
                    }
                    .disabled(isResuming)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func conversationRow<Details: View, Actions: View>(
        projectPath: String, modified: Date, durationMinutes: Int? = nil,
        @ViewBuilder details: () -> Details, @ViewBuilder actions: () -> Actions
    ) -> some View {
        ConversationColumns {
            HStack(alignment: .top, spacing: FizzSpacing.row) {
                Capsule()
                    .fill(ProjectAccentColor.color(for: projectPath))
                    .frame(width: 2, height: 24)
                    .accessibilityHidden(true)
                details()
            }

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: FizzSpacing.row) {
                    if let durationMinutes, durationMinutes > 0 {
                        Text("\(durationMinutes) 分钟")
                    }
                    Text(Format.relative(modified))
                        .minimumScaleFactor(0.85)
                        .frame(width: 96, alignment: .trailing)
                        .help(Format.shortDate(modified))
                }
                .font(FizzTypography.monoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                actions()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(FizzSpacing.card)
        .fizzCard(radius: FizzRadius.card)
    }

    private func projectMetadata<Status: View>(
        _ name: String, tool: String, @ViewBuilder status: () -> Status
    ) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(FizzTypography.caption(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            TagChip(
                text: HomeDashboardModel.toolTitle(tool),
                tint: .secondary,
                compact: true
            )
            .fixedSize()

            status()
                .fixedSize()
        }
    }

    private func conversationTitle(_ title: String) -> some View {
        Text(title)
            .font(FizzTypography.cardTitle)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private func touchedFiles(_ files: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(files.prefix(3)), id: \.self) { file in
                Text(URL(fileURLWithPath: file).lastPathComponent)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(FizzTheme.recessedFill, in: Capsule())
                    .help(file)
            }
            if files.count > 3 {
                Text("+\(files.count - 3)")
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .font(FizzTypography.monoSmall)
        .lineLimit(1)
    }

    @ViewBuilder
    private func statusBadge(isLive: Bool, session: SessionRecord) -> some View {
        if isLive {
            HStack(spacing: 4) {
                RunningPulseDot()
                Text("进行中")
                    .font(FizzTypography.micro)
                    .foregroundStyle(.secondary)
            }
        } else if session.endedWithError {
            TagChip(text: "报错结束", tint: FizzTheme.statusWarning, compact: true)
        } else {
            Text("✓ 正常结束")
                .font(FizzTypography.micro)
                .foregroundStyle(.tertiary)
        }
    }

    private func resume(_ session: SessionRecord, in project: RepoProject) async {
        resumingID = session.stableID
        defer { resumingID = nil }
        let result = await SessionResumeService.resume(session: session, projectPath: project.path)
        if result.success {
            ToastCenter.shared.show(
                "已唤起 \(HomeDashboardModel.toolTitle(session.tool))",
                symbol: "terminal.fill",
                tint: FizzTheme.statusSuccess,
                subtitle: project.displayName
            )
        } else {
            if let fallback = result.fallbackCommand {
                SystemActions.copy(fallback)
            }
            ToastCenter.shared.show(
                result.message,
                symbol: "exclamationmark.triangle.fill",
                tint: FizzTheme.statusWarning,
                subtitle: result.fallbackCommand != nil ? "已复制恢复命令到剪贴板" : nil
            )
        }
    }

    @ViewBuilder
    private var searchResultsBody: some View {
        if searchResults.isEmpty && !isSearching {
            ContentUnavailableView(
                "没有找到相关对话",
                systemImage: "magnifyingglass",
                description: Text("没有匹配「\(trimmedSearchQuery)」的会话，试试换个关键字或取消工具筛选。")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            VStack(spacing: FizzSpacing.row) {
                ForEach(searchResults) { result in
                    searchResultRow(result)
                }
            }
        }
    }

    private func searchResultRow(_ result: SessionSearchResult) -> some View {
        let project = store.projects.first { $0.path == result.projectPath }
        let isLive = store.activeAISessionIDs.contains(result.sessionStableID)
        let openSession = {
            if let project {
                store.openProject(project, tab: .progress, sessionID: result.sessionID)
            }
        }

        return Button(action: openSession) {
            conversationRow(projectPath: result.projectPath, modified: result.modified) {
                VStack(alignment: .leading, spacing: 5) {
                    projectMetadata(result.projectName, tool: result.tool) {
                        if isLive {
                            TagChip(text: "进行中", tint: FizzTheme.statusSuccess, compact: true)
                        } else if result.endedWithError {
                            TagChip(text: "报错结束", tint: FizzTheme.statusWarning, compact: true)
                        }
                    }

                    conversationTitle("「\(result.primaryIntent)」")

                    if let snippet = result.matchedSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(FizzTypography.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } actions: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fizzKeyboardAction(action: openSession)
    }

    private func runSearch() async {
        let query = trimmedSearchQuery
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        var results = await store.searchSessions(
            query: query,
            toolFilter: toolFilter == "all" ? nil : toolFilter,
            errorOnly: statusFilter == .error,
            limit: 60
        )
        guard !Task.isCancelled else { return }

        if statusFilter == .active {
            results = results.filter { store.activeAISessionIDs.contains($0.sessionStableID) }
        }
        searchResults = results
        isSearching = false
    }
}

private struct ConversationColumns: Layout {
    private let leadingShare: CGFloat = 0.65

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = proposedWidth
        } else {
            width = FizzSpacing.grid + max(
                subviews[0].sizeThatFits(.unspecified).width / leadingShare,
                subviews[1].sizeThatFits(.unspecified).width / (1 - leadingShare)
            )
        }
        let (leading, trailing) = widths(for: width)
        let height = max(
            subviews[0].sizeThatFits(.init(width: leading, height: nil)).height,
            subviews[1].sizeThatFits(.init(width: trailing, height: nil)).height
        )
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (leading, trailing) = widths(for: bounds.width)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: leading, height: nil))
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - trailing, y: bounds.minY), anchor: .topLeading,
            proposal: .init(width: trailing, height: nil)
        )
    }

    private func widths(for width: CGFloat) -> (CGFloat, CGFloat) {
        let available = max(0, width - FizzSpacing.grid)
        return (available * leadingShare, available * (1 - leadingShare))
    }
}
