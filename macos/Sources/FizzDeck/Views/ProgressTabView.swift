import SwiftUI

struct ProgressTabView: View {
    private enum ViewMode: String, CaseIterable, Identifiable {
        case timeline
        case allSessions

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timeline: "进度时间线"
            case .allSessions: "全部会话"
            }
        }
    }

    private struct DayGroup: Identifiable {
        let id: String
        let title: String
        let sessions: [SessionRecord]
    }

    private struct MarkDiffSheetTarget: Identifiable {
        let id: String
        let mark: SessionMark
        let initialFile: String?

        init(mark: SessionMark, initialFile: String? = nil) {
            self.id = "\(mark.id):\(initialFile ?? "")"
            self.mark = mark
            self.initialFile = initialFile
        }
    }

    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @AppStorage(SummaryPreferences.enabledKey) private var aiSummaryEnabled = false

    let project: RepoProject

    @State private var summaryEngine = SummaryEngine.shared
    @State private var viewMode: ViewMode = .timeline
    @State private var expandedFileSessions: Set<String> = []
    @State private var highlightedSessionID: String?
    @State private var resumingSessionID: String?
    @State private var markAvailability: [String: Bool] = [:]
    @State private var diffTarget: MarkDiffSheetTarget?
    @State private var isCreatingMark = false
    @State private var isRefreshingAISummary = false

    private var conversations: [SessionRecord] {
        project.sessions.recentSessions
            .filter { $0.kind == .conversation }
            .sorted { $0.modified > $1.modified }
    }

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M 月 d 日 EEEE"

        var grouped: [(key: String, title: String, sessions: [SessionRecord])] = []
        var indexByKey: [String: Int] = [:]

        for session in conversations {
            let day = calendar.startOfDay(for: session.modified)
            let key = String(Int(day.timeIntervalSince1970))
            if let index = indexByKey[key] {
                grouped[index].sessions.append(session)
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
                grouped.append((key: key, title: title, sessions: [session]))
            }
        }
        return grouped.map { DayGroup(id: $0.key, title: $0.title, sessions: $0.sessions) }
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            if viewMode == .allSessions {
                SessionsTabView(project: project)
            } else {
                timelineScrollView
            }
        }
        .onChange(of: project.path) {
            expandedFileSessions = []
            highlightedSessionID = nil
            markAvailability = [:]
        }
        .task(id: project.path) {
            await loadMarksAndSummaries()
        }
        .onChange(of: store.marks) {
            Task { await refreshMarkAvailability() }
        }
        .sheet(item: $diffTarget) { target in
            MarkDiffRestoreSheet(
                project: project,
                mark: target.mark,
                initialSelectedFile: target.initialFile
            ) {
                await store.refreshGit(for: project.path)
                await refreshMarkAvailability()
            }
        }
    }

    private var modeBar: some View {
        HStack(spacing: FizzSpacing.grid) {
            if viewMode == .allSessions {
                Text("共 \(project.sessions.sessionCount) 条会话记录（含工作区摘要）")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Picker("视图模式", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190, height: FizzControlHeight.standard.rawValue)
            .focusable(interactions: .edit)
        }
        .padding(.horizontal, FizzSpacing.page)
        .padding(.top, FizzSpacing.page)
    }

    private var timelineScrollView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: FizzSpacing.section) {
                    whereWeLeftOffCard
                    ProjectActivityPanel(project: project)
                        .id(project.path)
                    timelineSection
                }
                .padding([.horizontal, .bottom], FizzSpacing.page)
                .padding(.top, FizzSpacing.section)
            }
            .fizzTracksScrollPastTop()
            .onAppear {
                applyRequestedSession(proxy: scrollProxy)
                applyRequestedMarkDiff()
            }
            .onChange(of: store.requestedSessionID) {
                applyRequestedSession(proxy: scrollProxy)
            }
            .onChange(of: store.requestedMarkIDForDiff) {
                applyRequestedMarkDiff()
            }
        }
    }

    private var whereWeLeftOffCard: some View {
        let projectSummary = summaryEngine.cachedOrRuleBasedProjectSummary(
            for: project,
            copyMode: copyMode
        )

        return Panel(title: "做到哪了", symbol: "sparkles.rectangle.stack") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                TagChip(
                    text: projectSummary.isAIGenerated ? "✦ AI 总结" : "自动整理",
                    tint: projectSummary.isAIGenerated ? Color.secondary : .secondary,
                    compact: true
                )

                if projectSummary.isAIGenerated {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(projectSummary.headline)
                            .font(FizzTypography.cardTitle)
                            .foregroundStyle(.primary)
                        if let suggestion = projectSummary.suggestion, !suggestion.isEmpty {
                            Text("建议下一步：\(suggestion)")
                                .font(FizzTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    )
                }

                if conversations.isEmpty {
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        Text("还没有和 AI 在这里聊过")
                            .font(FizzTypography.sectionTitle)
                        Text("打开终端或编辑器开始一次对话后，这里会自动记下每次想做什么、改了哪些文件。")
                            .font(FizzTypography.body)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(conversations.prefix(3)), id: \.stableID) { session in
                            let aiSession = summaryEngine.cachedOrRuleBasedSessionSummary(
                                for: session,
                                projectName: project.displayName,
                                copyMode: copyMode
                            )
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                FizzStatusDot(tint: session.endedWithError ? FizzTheme.statusWarning : Color.secondary.opacity(0.75))
                                Text(aiSession.isAIGenerated
                                    ? aiSession.headline
                                    : (session.primaryIntent ?? "\(HomeDashboardModel.toolTitle(session.tool)) 会话"))
                                    .font(FizzTypography.body(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if !session.touchedFiles.isEmpty {
                                    Text("改了 \(session.touchedFiles.count) 个文件")
                                        .font(FizzTypography.micro)
                                        .foregroundStyle(.secondary)
                                }
                                Text(Format.relative(session.modified))
                                    .font(FizzTypography.micro)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if let latest = conversations.first,
                       latest.endedWithError,
                       let err = latest.lastError,
                       !err.isEmpty {
                        HStack(spacing: 6) {
                            FizzIcon(.sm, symbol: "exclamationmark.triangle.fill")
                                .foregroundStyle(.secondary)
                            Text("最近报错：\(err)")
                                .font(FizzTypography.mono)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
                    }

                    Text(FizzCopy.projectStatusSummary(
                        dirtyCount: project.changes.total,
                        ahead: project.ahead,
                        behind: project.behind,
                        mode: copyMode
                    ))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        } accessory: {
            HStack(spacing: FizzSpacing.row) {
                if projectSummary.isAIGenerated {
                    FizzIconButton(title: "重新生成 AI 状态总结", symbol: "arrow.clockwise", height: .compact) {
                        Task {
                            isRefreshingAISummary = true
                            defer { isRefreshingAISummary = false }
                            _ = await summaryEngine.forceRefreshProjectStatus(project, copyMode: copyMode)
                        }
                    }
                    .disabled(isRefreshingAISummary)
                    .accessibilityValue(isRefreshingAISummary ? "重新生成中" : "")
                } else if !aiSummaryEnabled {
                    FizzActionButton(title: "开启 AI 总结", height: .compact) {
                        openSettings()
                    }
                }

                if !conversations.isEmpty, project.dirtyCount > 0 {
                    FizzActionButton(
                        title: isCreatingMark ? "记录中…" : "记一下当前状态",
                        symbol: "bookmark",
                        height: .compact
                    ) {
                        Task { await createManualMark() }
                    }
                    .disabled(isCreatingMark)
                }
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        ForEach(store.marks(for: project.path).filter(\.isProtectionBaseline)) { mark in
            markNodeRow(mark)
        }
        if !dayGroups.isEmpty {
            let marksBySession = associatedMarksBySession()
            VStack(alignment: .leading, spacing: FizzSpacing.panel) {
                ForEach(dayGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(FizzTypography.cardTitle)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            ForEach(group.sessions, id: \.stableID) { session in
                                let mark = marksBySession[session.stableID]
                                VStack(alignment: .leading, spacing: 5) {
                                    if let mark {
                                        markNodeRow(mark)
                                    }
                                    sessionTimelineCard(session, associatedMark: mark)
                                        .id(session.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func markNodeRow(_ mark: SessionMark) -> some View {
        let isSnapshot = mark.kind == .gitSnapshot
        let available = isSnapshot && (markAvailability[mark.id] ?? true)
        let expiry = SessionMarkExpiryPolicy.state(
            for: mark,
            available: available
        )
        let expiringDays: Int? = if case .expiring(let days) = expiry {
            days
        } else {
            nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = mark.isProtectionBaseline ? "M 月 d 日 HH:mm" : "HH:mm"
        let timeText = formatter.string(from: mark.createdAt)

        return HStack(spacing: 8) {
            FizzIcon(.xs, symbol: isSnapshot ? "diamond.fill" : "diamond")
            .foregroundStyle(available ? Color.secondary : .secondary.opacity(0.65))

            Text("\(mark.label ?? "对话开始前的样子") · \(timeText)")
                .font(FizzTypography.caption(.medium))
                .foregroundStyle(available ? .primary : .secondary)
                .lineLimit(1)

            if !isSnapshot {
                Text("仅记录，无法还原")
                    .font(FizzTypography.micro)
                    .foregroundStyle(.tertiary)
            } else if !available {
                Text("已过期")
                    .font(FizzTypography.micro)
                    .foregroundStyle(.tertiary)
                    .help("超过 14 天，已被 Git 清理")
            }

            if let expiringDays {
                TagChip(
                    text: "约 \(expiringDays) 天后过期",
                    compact: true
                )
                .accessibilityLabel("这个对话标记约 \(expiringDays) 天后过期")
            }

            Spacer(minLength: 8)

            if available {
                FizzActionButton(
                    title: mark.pinned ? "已保留" : (expiringDays == nil ? "保留" : "固定保留"),
                    symbol: mark.pinned ? "star.fill" : "star",
                    height: .compact
                ) {
                    Task {
                        let success = await store.togglePin(mark: mark)
                        if !success {
                            ToastCenter.shared.show(
                                "暂时没能更新保留状态",
                                symbol: "exclamationmark.triangle.fill",
                                tint: FizzTheme.statusWarning
                            )
                        }
                    }
                }
                .foregroundStyle(Color.primary)
                .help(mark.pinned ? "取消永久保留" : "永久保留，不会被 Git 清理")

                FizzActionButton(title: "还原到这里", height: .compact) {
                    diffTarget = MarkDiffSheetTarget(mark: mark)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private func sessionTimelineCard(_ session: SessionRecord, associatedMark: SessionMark?) -> some View {
        let toolTitle = HomeDashboardModel.toolTitle(session.tool)
        let isMarkAvailable = associatedMark.map {
            $0.kind == .gitSnapshot && (markAvailability[$0.id] ?? true)
        } ?? false
        let aiSummary = summaryEngine.cachedOrRuleBasedSessionSummary(
            for: session,
            projectName: project.displayName,
            copyMode: copyMode
        )
        let isLive = store.activeAISessionIDs.contains(session.stableID)
        let isHighlighted = highlightedSessionID == session.id
        let expanded = expandedFileSessions.contains(session.stableID)
        let visibleFiles = expanded ? session.touchedFiles : Array(session.touchedFiles.prefix(3))
        let overflowCount = max(0, session.touchedFiles.count - 3)
        let isResuming = resumingSessionID == session.stableID

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TagChip(
                    text: toolTitle,
                    tint: .secondary,
                    compact: true
                )

                if let mins = session.durationMinutes, mins > 0 {
                    Text("\(mins) 分钟")
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }

                if let cost = Format.cost(session.costUSD, estimated: session.costIsEstimate ?? false) {
                    Text(cost)
                        .font(FizzTypography.mono)
                        .foregroundStyle(.secondary)
                }

                Text(Format.relative(session.modified))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                if isLive {
                    HStack(spacing: 4) {
                        RunningPulseDot()
                        Text("进行中")
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if session.endedWithError {
                    TagChip(text: "⚠ 报错结束", tint: FizzTheme.statusWarning, compact: true)
                } else {
                    Text("✓ 正常结束")
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("「\(session.primaryIntent ?? "\(toolTitle) 会话")」")
                .font(FizzTypography.body(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if aiSummary.isAIGenerated {
                Text("✦ \(aiSummary.headline)")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !session.touchedFiles.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(visibleFiles, id: \.self) { file in
                        HStack(spacing: 2) {
                            let fileName = URL(fileURLWithPath: file).lastPathComponent
                            if isMarkAvailable, let associatedMark {
                                FizzActionButton(title: fileName, height: .compact) {
                                    diffTarget = MarkDiffSheetTarget(mark: associatedMark, initialFile: file)
                                }
                                .frame(maxWidth: 200)
                                .truncationMode(.middle)
                                .help("对比「\(fileName)」的改动")
                            } else {
                                Text(fileName)
                                    .font(FizzTypography.monoSmall)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(FizzTheme.recessedFill, in: Capsule())
                                    .frame(maxWidth: 200)
                                    .help(file)
                            }
                            RelatedSessionsButton(project: project, file: file, compact: true)
                        }
                    }
                    if !expanded && overflowCount > 0 {
                        FizzActionButton(title: "+\(overflowCount)", height: .compact) {
                            expandedFileSessions.insert(session.stableID)
                        }
                        .help("展开其余 \(overflowCount) 个文件")
                        .accessibilityLabel("展开其余 \(overflowCount) 个文件")
                    }
                }
            }

            if session.endedWithError, let err = session.lastError, !err.isEmpty {
                Text(err)
                    .font(FizzTypography.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
            }

            if isMarkAvailable || session.resumeCommand != nil {
                HStack(spacing: FizzSpacing.row) {
                    Spacer(minLength: 0)
                    if isMarkAvailable, let associatedMark {
                        FizzActionButton(title: "看改了什么", symbol: "doc.text.magnifyingglass", height: .compact) {
                            diffTarget = MarkDiffSheetTarget(mark: associatedMark)
                        }
                    }

                    if session.resumeCommand != nil {
                        FizzActionButton(
                            title: isResuming ? "继续中…" : (isLive ? "回到这次对话" : "继续这次对话"),
                            symbol: "play.fill",
                            height: .compact
                        ) {
                            Task { await resumeSession(session) }
                        }
                        .disabled(isResuming)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FizzSpacing.panel)
        .fizzCard(radius: FizzRadius.card)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                    .strokeBorder(Color.secondary, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.quick), value: isHighlighted)
    }

    private func applyRequestedSession(proxy: ScrollViewProxy) {
        guard let target = store.requestedSessionID, !target.isEmpty else { return }
        highlightedSessionID = target
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
            proxy.scrollTo(target, anchor: .center)
        }
        Task { @MainActor in
            await Task.yield()
            if store.requestedSessionID == target {
                store.requestedSessionID = nil
            }
            try? await Task.sleep(for: .seconds(3))
            if highlightedSessionID == target {
                highlightedSessionID = nil
            }
        }
    }

    private func resumeSession(_ session: SessionRecord) async {
        resumingSessionID = session.stableID
        defer { resumingSessionID = nil }
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
                subtitle: result.fallbackCommand != nil ? "已复制命令到剪贴板" : nil
            )
        }
    }

    private func loadMarksAndSummaries() async {
        await refreshMarkAvailability()
        guard aiSummaryEnabled else { return }
        _ = await summaryEngine.summarizeProjectStatusIfNeeded(project, copyMode: copyMode)
        for session in conversations.prefix(3) {
            _ = await summaryEngine.summarizeSessionIfNeeded(
                session,
                projectName: project.displayName,
                copyMode: copyMode
            )
        }
    }

    private func refreshMarkAvailability() async {
        let projectMarks = store.marks(for: project.path)
        let directory = URL(fileURLWithPath: project.path)
        var status: [String: Bool] = [:]
        for mark in projectMarks where mark.kind == .gitSnapshot {
            status[mark.id] = await SessionMarkService.isAvailable(mark, in: directory)
        }
        guard !Task.isCancelled else { return }
        markAvailability = status
    }

    private func createManualMark() async {
        isCreatingMark = true
        defer { isCreatingMark = false }
        let mark = await store.createMark(
            for: project,
            session: conversations.first,
            label: "手动记录点",
            allowGitSnapshot: true
        )
        await refreshMarkAvailability()
        ToastCenter.shared.show(
            mark.kind == .gitSnapshot ? "已记下当前状态" : "已添加纯记录标记",
            symbol: "bookmark.circle.fill",
            tint: Color.secondary,
            subtitle: mark.kind == .gitSnapshot ? "之后随时可在时间线对比或还原" : nil
        )
    }

    private func applyRequestedMarkDiff() {
        guard let requestedID = store.requestedMarkIDForDiff, !requestedID.isEmpty else { return }
        guard let mark = store.marks(for: project.path).first(where: { $0.id == requestedID }) else { return }
        diffTarget = MarkDiffSheetTarget(mark: mark)
        store.requestedMarkIDForDiff = nil
    }

    private func associatedMarksBySession() -> [String: SessionMark] {
        let projectMarks = store.marks(for: project.path)
        var usedMarkIDs: Set<String> = []
        var result: [String: SessionMark] = [:]

        for session in conversations {
            if let exact = projectMarks.first(where: { $0.sessionStableID == session.stableID }) {
                result[session.stableID] = exact
                usedMarkIDs.insert(exact.id)
            }
        }

        for session in conversations where result[session.stableID] == nil {
            let anchor = session.startedAt ?? session.modified
            if let candidate = projectMarks.first(where: { mark in
                guard !mark.isProtectionBaseline, !usedMarkIDs.contains(mark.id) else { return false }
                let delta = anchor.timeIntervalSince(mark.createdAt)
                return delta >= -120 && delta <= 900
            }) {
                result[session.stableID] = candidate
                usedMarkIDs.insert(candidate.id)
            }
        }
        return result
    }
}
