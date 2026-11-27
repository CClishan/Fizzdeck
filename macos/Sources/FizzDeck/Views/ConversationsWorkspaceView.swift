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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusFilter: StatusFilter = .all
    @State private var toolFilter = "all"
    @State private var searchQuery = ""
    @State private var searchResults: [SessionSearchResult] = []
    @State private var isSearching = false
    @State private var scrolledPastTop = false
    @State private var resumingID: String?

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
                header

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
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.secondary)

                            VStack(spacing: 8) {
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(FizzCopy.conversationsNavTitle)
                        .font(.system(size: 24, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("跨项目按天汇总的 AI 对话记录，点击任意一条回到对应项目进度")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(isSearchActive ? "命中 \(searchResults.count) 条" : "共 \(filteredEntries.count) 条")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                FizzIcon(symbol: "magnifyingglass", size: 13)
                    .foregroundStyle(.secondary)

                TextField("搜索所有项目的对话（支持中文、报错关键字、文件名）", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if isSearching {
                    ProgressView()
                        .controlSize(.mini)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        FizzIcon(symbol: "xmark.circle.fill", size: 13)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                FizzTheme.cardFill,
                in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }

            HStack(spacing: 10) {
                Picker("状态筛选", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)

                Picker("工具筛选", selection: $toolFilter) {
                    Text("全部工具").tag("all")
                    ForEach(availableTools, id: \.self) { tool in
                        Text(HomeDashboardModel.toolTitle(tool)).tag(tool)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()

                Spacer(minLength: 0)
            }
        }
    }

    private func conversationCard(_ entry: ConversationEntry) -> some View {
        let project = entry.project
        let session = entry.session
        let toolTitle = HomeDashboardModel.toolTitle(session.tool)
        let isLive = store.activeAISessionIDs.contains(session.stableID)
        let isResuming = resumingID == session.stableID

        return HStack(alignment: .top, spacing: 12) {
            Button {
                store.openProject(project, tab: .progress, sessionID: session.id)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ProjectBadgeIcon(project: project, size: 24, framed: false)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Text(project.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)

                            TagChip(
                                text: toolTitle,
                                tint: DetectedTool(rawValue: session.tool)?.tint ?? .secondary,
                                compact: true
                            )

                            statusBadge(isLive: isLive, session: session)

                            Text(Format.relative(session.modified))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)

                            Spacer(minLength: 0)
                        }

                        Text(session.primaryIntent ?? "\(toolTitle) 会话")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if !session.touchedFiles.isEmpty {
                            HStack(spacing: 5) {
                                ForEach(Array(session.touchedFiles.prefix(3)), id: \.self) { file in
                                    Text(URL(fileURLWithPath: file).lastPathComponent)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(FizzTheme.recessedFill, in: Capsule())
                                        .help(file)
                                }
                                if session.touchedFiles.count > 3 {
                                    Text("+\(session.touchedFiles.count - 3)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        if session.endedWithError, let err = session.lastError, !err.isEmpty {
                            Text(err)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                HandoffCopyButton(project: project, compact: true)

                if session.resumeCommand != nil {
                    Button {
                        Task { await resume(session, in: project) }
                    } label: {
                        if isResuming {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Label(isLive ? "回到会话" : "继续", systemImage: "play.fill")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(FizzTheme.accent)
                    .controlSize(.small)
                    .disabled(isResuming)
                }
            }
        }
        .padding(14)
        .fizzCard(radius: FizzRadius.card)
    }

    @ViewBuilder
    private func statusBadge(isLive: Bool, session: SessionRecord) -> some View {
        if isLive {
            HStack(spacing: 4) {
                RunningPulseDot(size: 5)
                Text("进行中")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
            }
        } else if session.endedWithError {
            TagChip(text: "报错结束", tint: .orange, compact: true)
        } else {
            Text("✓ 正常结束")
                .font(.system(size: 10))
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
                tint: .green,
                subtitle: project.displayName
            )
        } else {
            if let fallback = result.fallbackCommand {
                SystemActions.copy(fallback)
            }
            ToastCenter.shared.show(
                result.message,
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
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
            VStack(spacing: 8) {
                ForEach(searchResults) { result in
                    searchResultRow(result)
                }
            }
        }
    }

    private func searchResultRow(_ result: SessionSearchResult) -> some View {
        let project = store.projects.first { $0.path == result.projectPath }
        let toolTitle = HomeDashboardModel.toolTitle(result.tool)
        let isLive = store.activeAISessionIDs.contains(result.sessionStableID)

        return Button {
            if let project {
                store.openProject(project, tab: .progress, sessionID: result.sessionID)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let project {
                    ProjectBadgeIcon(project: project, size: 24, framed: false)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(result.projectName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        TagChip(
                            text: toolTitle,
                            tint: DetectedTool(rawValue: result.tool)?.tint ?? .secondary,
                            compact: true
                        )

                        if isLive {
                            TagChip(text: "进行中", tint: .green, compact: true)
                        } else if result.endedWithError {
                            TagChip(text: "报错结束", tint: .orange, compact: true)
                        }

                        Text(Format.relative(result.modified))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 0)
                    }

                    Text("「\(result.primaryIntent)」")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let snippet = result.matchedSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.system(size: 11))
                            .foregroundStyle(FizzTheme.accent)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(14)
        .fizzCard(radius: FizzRadius.card)
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
