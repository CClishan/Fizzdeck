import SwiftUI

struct ProgressTabView: View {
    private enum ViewMode: String, CaseIterable, Identifiable {
        case timeline
        case allSessions

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timeline: FizzL10n.text("进度时间线", "Timeline")
            case .allSessions: FizzL10n.text("全部会话", "All sessions")
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

    private struct ProjectShare: Identifiable {
        let id: String
        let data: WeeklyRecapShareData
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
    @State private var markAvailability = SessionMarkAvailabilityCheck.Results()
    @State private var diffTarget: MarkDiffSheetTarget?
    @State private var requestedSharePath: String?
    @State private var projectShare: ProjectShare?
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
        formatter.locale = FizzL10n.locale
        formatter.dateFormat = FizzL10n.text("M 月 d 日 EEEE", "EEEE, MMM d")

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
                    title = FizzL10n.text("今天", "Today")
                } else if let yesterday, calendar.isDate(day, inSameDayAs: yesterday) {
                    title = FizzL10n.text("昨天", "Yesterday")
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
        let check = SessionMarkAvailabilityCheck(marks: store.marks(for: project.path), scannedAt: store.scannedAt)
        return VStack(spacing: 0) {
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
            markAvailability = .init()
            requestedSharePath = nil
            projectShare = nil
        }
        .task(id: requestedSharePath) {
            guard let path = requestedSharePath, path == project.path else { return }
            let data = await Task.detached(priority: .userInitiated) { [project] in
                WeeklyRecapShareData(project: project)
            }.value
            guard !Task.isCancelled, requestedSharePath == path else { return }
            projectShare = ProjectShare(id: path, data: data)
            requestedSharePath = nil
        }
        .task(id: project.path) {
            await loadSummaries()
        }
        .task(id: check) {
            let verified = await check.run(reusing: markAvailability)
            if !Task.isCancelled { markAvailability = verified }
        }
        .onChange(of: store.requestedMarkIDForDiff, initial: true) {
            applyRequestedMarkDiff()
        }
        .sheet(item: $projectShare) { share in
            WeeklyRecapShareSheet(data: share.data, title: FizzL10n.text("项目战报", "Project recap"))
        }
        .sheet(item: $diffTarget) { target in
            MarkDiffRestoreSheet(
                project: project,
                mark: target.mark,
                initialSelectedFile: target.initialFile
            ) {
                await store.refreshGit(for: project.path)
            }
        }
    }

    private var modeBar: some View {
        HStack(spacing: FizzSpacing.grid) {
            if viewMode == .allSessions {
                Text(FizzL10n.text("共 \(project.sessions.sessionCount) 条会话记录（含工作区摘要）", "\(project.sessions.sessionCount) session \(project.sessions.sessionCount == 1 ? "record" : "records"), including workspace summaries"))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            FizzActionButton(title: FizzL10n.text("分享项目战报", "Share recap"), symbol: "photo.on.rectangle", keyboardNavigation: true) {
                requestedSharePath = project.path
            }
            .disabled(requestedSharePath != nil)
            Picker(FizzL10n.text("视图模式", "View mode"), selection: $viewMode) {
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
                    TimelineView(.everyMinute) { clock in
                        VStack(alignment: .leading, spacing: FizzSpacing.section) {
                            timelineSection(now: clock.date)
                        }
                    }
                }
                .padding([.horizontal, .bottom], FizzSpacing.page)
                .padding(.top, FizzSpacing.section)
            }
            .fizzTracksScrollPastTop()
            .onAppear {
                applyRequestedSession(proxy: scrollProxy)
            }
            .onChange(of: store.requestedSessionID) {
                applyRequestedSession(proxy: scrollProxy)
            }
        }
    }

    private var whereWeLeftOffCard: some View {
        let projectSummary = summaryEngine.cachedOrRuleBasedProjectSummary(
            for: project,
            copyMode: copyMode
        )

        return Panel(title: FizzL10n.text("做到哪了", "Where you left off"), symbol: "sparkles.rectangle.stack") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                TagChip(
                    text: projectSummary.isAIGenerated ? FizzL10n.text("✦ AI 总结", "✦ AI summary") : FizzL10n.text("自动整理", "Automatic summary"),
                    tint: projectSummary.isAIGenerated ? Color.secondary : .secondary,
                    compact: true
                )

                if projectSummary.isAIGenerated {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(projectSummary.headline)
                            .font(FizzTypography.cardTitle)
                            .foregroundStyle(.primary)
                        if let suggestion = projectSummary.suggestion, !suggestion.isEmpty {
                            Text(FizzL10n.text("建议下一步：\(suggestion)", "Suggested next step: \(suggestion)"))
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
                        Text(FizzL10n.text("还没有和 AI 在这里聊过", "No AI conversations here yet"))
                            .font(FizzTypography.sectionTitle)
                        Text(FizzL10n.text("打开终端或编辑器开始一次对话后，这里会自动记下每次想做什么、改了哪些文件。", "Start a conversation in your terminal or editor. Its goal and the files changed will appear here."))
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
                                    : (session.primaryIntent ?? FizzL10n.text("\(HomeDashboardModel.toolTitle(session.tool)) 会话", "\(HomeDashboardModel.toolTitle(session.tool)) session")))
                                    .font(FizzTypography.body(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if !session.touchedFiles.isEmpty {
                                    Text(FizzL10n.text("改了 \(session.touchedFiles.count) 个文件", "Changed \(session.touchedFiles.count) \(session.touchedFiles.count == 1 ? "file" : "files")"))
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
                            Text(FizzL10n.text("最近报错：\(err)", "Latest error: \(err)"))
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
                    FizzIconButton(title: FizzL10n.text("重新生成 AI 状态总结", "Regenerate AI status summary"), symbol: "arrow.clockwise", height: .compact) {
                        Task {
                            isRefreshingAISummary = true
                            defer { isRefreshingAISummary = false }
                            _ = await summaryEngine.forceRefreshProjectStatus(project, copyMode: copyMode)
                        }
                    }
                    .disabled(isRefreshingAISummary)
                    .accessibilityValue(isRefreshingAISummary ? FizzL10n.text("重新生成中", "Regenerating") : "")
                } else if !aiSummaryEnabled {
                    FizzActionButton(title: FizzL10n.text("开启 AI 总结", "Enable AI summaries"), height: .compact) {
                        openSettings()
                    }
                }

                if !conversations.isEmpty, project.dirtyCount > 0 {
                    FizzActionButton(
                        title: isCreatingMark ? FizzL10n.text("记录中…", "Recording…") : FizzL10n.text("记一下当前状态", "Mark this point"),
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
    private func timelineSection(now: Date) -> some View {
        let projectMarks = store.marks(for: project.path)
        let marksBySession = associatedMarksBySession(in: projectMarks)
        let attachedIDs = Set(marksBySession.values.map(\.id))
        ForEach(projectMarks.filter { !attachedIDs.contains($0.id) }) { mark in
            markNodeRow(mark, now: now, standalone: true)
        }
        if !dayGroups.isEmpty {
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
                                        markNodeRow(mark, now: now)
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

    private func markNodeRow(_ mark: SessionMark, now: Date, standalone: Bool = false) -> some View {
        let isSnapshot = mark.kind == .gitSnapshot
        let available = markAvailability.byID[mark.id] == true
        let expiry = SessionMarkExpiryPolicy.state(
            for: mark,
            now: now,
            available: available
        )
        let expiringDays: Int? = if case .expiring(let days) = expiry {
            days
        } else {
            nil
        }
        let formatter = DateFormatter()
        formatter.locale = FizzL10n.locale
        formatter.dateFormat = standalone ? FizzL10n.text("M 月 d 日 HH:mm", "MMM d, HH:mm") : "HH:mm"
        let timeText = formatter.string(from: mark.createdAt)

        return HStack(spacing: 8) {
            FizzIcon(.xs, symbol: isSnapshot ? "diamond.fill" : "diamond")
            .foregroundStyle(available ? Color.secondary : .secondary.opacity(0.65))

            Text("\(mark.projectCheckpointTitle) · \(timeText)")
                .font(FizzTypography.caption(.medium))
                .foregroundStyle(available ? .primary : .secondary)
                .lineLimit(1)

            if !isSnapshot {
                Text(FizzL10n.text("仅记录，无法还原", "Record only; cannot restore"))
                    .font(FizzTypography.micro)
                    .foregroundStyle(.tertiary)
            } else if markAvailability.byID[mark.id] == false {
                Text(FizzL10n.text("快照不可用", "Snapshot unavailable"))
                    .font(FizzTypography.micro)
                    .foregroundStyle(.tertiary)
                    .help(FizzL10n.text("找不到这个标记的 Git 快照，无法还原", "The Git snapshot for this checkpoint could not be found. Restore is unavailable."))
            }

            if let expiringDays {
                TagChip(
                    text: FizzL10n.text("约 \(expiringDays) 天后过期", "Expires in ~\(expiringDays) \(expiringDays == 1 ? "day" : "days")"),
                    tint: FizzTheme.statusWarning,
                    compact: true
                )
                .fixedSize()
                .accessibilityLabel(FizzL10n.text("这个对话标记约 \(expiringDays) 天后过期", "This session checkpoint expires in about \(expiringDays) \(expiringDays == 1 ? "day" : "days")."))
            }

            Spacer(minLength: 8)

            if available {
                FizzActionButton(
                    title: mark.pinned ? FizzL10n.text("已保留", "Pinned") : (expiringDays == nil ? FizzL10n.text("保留", "Keep") : FizzL10n.text("固定保留", "Pin")),
                    symbol: mark.pinned ? "star.fill" : "star",
                    height: .compact,
                    keyboardNavigation: true
                ) {
                    Task {
                        let success = await store.setPinned(!mark.pinned, for: mark)
                        if !success {
                            ToastCenter.shared.show(
                                FizzL10n.text("暂时没能更新保留状态", "Couldn’t update the pin. Try again."),
                                symbol: "exclamationmark.triangle.fill",
                                tint: FizzTheme.statusWarning
                            )
                        }
                    }
                }
                .disabled(store.updatingMarkPins.contains(mark.id))
                .foregroundStyle(Color.primary)
                .help(mark.pinned ? FizzL10n.text("取消永久保留", "Stop keeping this checkpoint permanently") : FizzL10n.text("永久保留，不会被 Git 清理", "Keep permanently so Git won’t remove this checkpoint"))

                FizzActionButton(title: FizzL10n.text("还原到这里", "Restore to here"), height: .compact) {
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
            markAvailability.byID[$0.id] == true
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
                    Text(FizzL10n.text("\(mins) 分钟", "\(mins) min"))
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
                        Text(FizzL10n.text("进行中", "In progress"))
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if session.endedWithError {
                    TagChip(text: FizzL10n.text("⚠ 报错结束", "⚠ Ended with an error"), tint: FizzTheme.statusWarning, compact: true)
                } else {
                    Text(FizzL10n.text("✓ 正常结束", "✓ Finished"))
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(FizzL10n.text("「\(session.primaryIntent ?? "\(toolTitle) 会话")」", "“\(session.primaryIntent ?? "\(toolTitle) session")”"))
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
                                .help(FizzL10n.text("对比「\(fileName)」的改动", "Compare changes to “\(fileName)”"))
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
                        .help(FizzL10n.text("展开其余 \(overflowCount) 个文件", "Show \(overflowCount) more \(overflowCount == 1 ? "file" : "files")"))
                        .accessibilityLabel(FizzL10n.text("展开其余 \(overflowCount) 个文件", "Show \(overflowCount) more \(overflowCount == 1 ? "file" : "files")"))
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
                        FizzActionButton(title: FizzL10n.text("看改了什么", "View changes"), symbol: "doc.text.magnifyingglass", height: .compact) {
                            diffTarget = MarkDiffSheetTarget(mark: associatedMark)
                        }
                    }

                    if session.resumeCommand != nil {
                        FizzActionButton(
                            title: isResuming ? FizzL10n.text("继续中…", "Resuming…") : (isLive ? FizzL10n.text("回到这次对话", "Return to conversation") : FizzL10n.text("继续这次对话", "Resume conversation")),
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
                FizzL10n.text("已唤起 \(HomeDashboardModel.toolTitle(session.tool))", "Opened \(HomeDashboardModel.toolTitle(session.tool))"),
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
                subtitle: result.fallbackCommand != nil ? FizzL10n.text("已复制命令到剪贴板", "Copied command to clipboard") : nil
            )
        }
    }

    private func loadSummaries() async {
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

    private func createManualMark() async {
        isCreatingMark = true
        defer { isCreatingMark = false }
        let mark = await store.createMark(
            for: project,
            session: conversations.first,
            label: SessionMark.manualCheckpointLabel,
            allowGitSnapshot: true
        )
        ToastCenter.shared.show(
            mark.kind == .gitSnapshot ? FizzL10n.text("已记下当前状态", "Recorded the current state") : FizzL10n.text("已添加纯记录标记", "Added a record-only checkpoint"),
            symbol: "bookmark.circle.fill",
            tint: Color.secondary,
            subtitle: mark.kind == .gitSnapshot ? FizzL10n.text("之后随时可在时间线对比或还原", "Compare or restore it later from the timeline.") : nil
        )
    }

    private func applyRequestedMarkDiff() {
        guard let requestedID = store.requestedMarkIDForDiff, !requestedID.isEmpty else { return }
        guard let mark = store.marks(for: project.path).first(where: { $0.id == requestedID }) else { return }
        viewMode = .timeline
        diffTarget = MarkDiffSheetTarget(mark: mark)
        store.requestedMarkIDForDiff = nil
    }

    private func associatedMarksBySession(in projectMarks: [SessionMark]) -> [String: SessionMark] {
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
