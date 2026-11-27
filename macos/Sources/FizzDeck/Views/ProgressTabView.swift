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
            if viewMode == .allSessions {
                allSessionsHeaderBar
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

    private var allSessionsHeaderBar: some View {
        HStack {
            Text("共 \(project.sessions.sessionCount) 条会话记录（含工作区摘要）")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            modePicker
        }
        .padding(.horizontal, FizzSpacing.page)
        .padding(.top, 8)
    }

    private var modePicker: some View {
        Picker("视图模式", selection: $viewMode) {
            ForEach(ViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 190)
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
                .padding(FizzSpacing.page)
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
            VStack(alignment: .leading, spacing: 12) {
                if projectSummary.isAIGenerated {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(projectSummary.headline)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        if let suggestion = projectSummary.suggestion, !suggestion.isEmpty {
                            Text("建议下一步：\(suggestion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        FizzTheme.accent.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    )
                }

                if conversations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有和 AI 在这里聊过")
                            .font(.system(size: 14, weight: .medium))
                        Text("打开终端或编辑器开始一次对话后，这里会自动记下每次想做什么、改了哪些文件。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button {
                                SystemActions.openTerminal(project.path)
                            } label: {
                                Label("打开终端", systemImage: "terminal")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)

                            Button {
                                SystemActions.reveal(project.path)
                            } label: {
                                Label("在 Finder 打开", systemImage: "folder")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
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
                                Circle()
                                    .fill(session.endedWithError ? Color.orange : FizzTheme.accent.opacity(0.75))
                                    .frame(width: 5, height: 5)
                                Text(aiSession.isAIGenerated
                                    ? aiSession.headline
                                    : (session.primaryIntent ?? "\(HomeDashboardModel.toolTitle(session.tool)) 会话"))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if !session.touchedFiles.isEmpty {
                                    Text("改了 \(session.touchedFiles.count) 个文件")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(Format.relative(session.modified))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if let latest = conversations.first,
                       latest.endedWithError,
                       let err = latest.lastError,
                       !err.isEmpty {
                        HStack(spacing: 6) {
                            FizzIcon(symbol: "exclamationmark.triangle.fill", size: 11)
                                .foregroundStyle(.orange)
                            Text("最近报错：\(err)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
                    }

                    HStack(spacing: 8) {
                        SessionContinueButton(project: project, style: .prominent)
                        HandoffCopyButton(project: project)
                        if project.dirtyCount > 0 {
                            Button {
                                Task { await createManualMark() }
                            } label: {
                                if isCreatingMark {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Label("记一下当前状态", systemImage: "bookmark")
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .disabled(isCreatingMark)
                        }
                        Spacer(minLength: 0)
                        Text(FizzCopy.projectStatusSummary(
                            dirtyCount: project.changes.total,
                            ahead: project.ahead,
                            behind: project.behind,
                            mode: copyMode
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }
        } accessory: {
            HStack(spacing: 8) {
                if projectSummary.isAIGenerated {
                    TagChip(text: "✦ AI 总结", tint: FizzTheme.accent, compact: true)
                    Button {
                        Task {
                            isRefreshingAISummary = true
                            defer { isRefreshingAISummary = false }
                            _ = await summaryEngine.forceRefreshProjectStatus(project, copyMode: copyMode)
                        }
                    } label: {
                        if isRefreshingAISummary {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            FizzIcon(symbol: "arrow.clockwise", size: 11)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("重新生成 AI 状态总结")
                } else {
                    TagChip(text: "自动整理", tint: .secondary, compact: true)
                    if !aiSummaryEnabled {
                        Button("开启 AI 总结") {
                            openSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(FizzTheme.accent)
                    }
                }
                modePicker
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
            VStack(alignment: .leading, spacing: 14) {
                ForEach(dayGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
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
            FizzIcon(
                symbol: isSnapshot ? "diamond.fill" : "diamond",
                size: 10
            )
            .foregroundStyle(available ? FizzTheme.accent : .secondary.opacity(0.65))

            Text("\(mark.label ?? "对话开始前的样子") · \(timeText)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(available ? .primary : .secondary)

            if !isSnapshot {
                Text("仅记录，无法还原")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            } else if !available {
                Text("已过期")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .help("超过 14 天，已被 Git 清理")
            }

            if let expiringDays {
                TagChip(
                    text: "约 \(expiringDays) 天后过期",
                    tint: .orange,
                    compact: true
                )
                .accessibilityLabel("这个对话标记约 \(expiringDays) 天后过期")
            }

            Spacer(minLength: 8)

            if available {
                Button {
                    Task {
                        let success = await store.togglePin(mark: mark)
                        if !success {
                            ToastCenter.shared.show(
                                "暂时没能更新保留状态",
                                symbol: "exclamationmark.triangle.fill",
                                tint: .orange
                            )
                        }
                    }
                } label: {
                    Label(
                        mark.pinned ? "已保留" : (expiringDays == nil ? "保留" : "固定保留"),
                        systemImage: mark.pinned ? "star.fill" : "star"
                    )
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(mark.pinned ? Color.orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(mark.pinned ? "取消永久保留" : "永久保留，不会被 Git 清理")

                Button("还原到这里") {
                    diffTarget = MarkDiffSheetTarget(mark: mark)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FizzTheme.accent)
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
                    tint: DetectedTool(rawValue: session.tool)?.tint ?? .secondary,
                    compact: true
                )

                if let mins = session.durationMinutes, mins > 0 {
                    Text("\(mins) 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let cost = Format.cost(session.costUSD, estimated: session.costIsEstimate ?? false) {
                    Text(cost)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(Format.relative(session.modified))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                if isLive {
                    HStack(spacing: 4) {
                        RunningPulseDot(size: 5)
                        Text("进行中")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else if session.endedWithError {
                    TagChip(text: "⚠ 报错结束", tint: .orange, compact: true)
                } else {
                    Text("✓ 正常结束")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("「\(session.primaryIntent ?? "\(toolTitle) 会话")」")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if aiSummary.isAIGenerated {
                Text("✦ \(aiSummary.headline)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !session.touchedFiles.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(visibleFiles, id: \.self) { file in
                        HStack(spacing: 2) {
                            if isMarkAvailable, let associatedMark {
                                Button {
                                    diffTarget = MarkDiffSheetTarget(mark: associatedMark, initialFile: file)
                                } label: {
                                    Text(URL(fileURLWithPath: file).lastPathComponent)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(FizzTheme.accent)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(FizzTheme.accent.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("点击对比「\(URL(fileURLWithPath: file).lastPathComponent)」的改动")
                            } else {
                                Text(URL(fileURLWithPath: file).lastPathComponent)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(FizzTheme.recessedFill, in: Capsule())
                                    .help(file)
                            }
                            RelatedSessionsButton(project: project, file: file, compact: true)
                        }
                    }
                    if !expanded && overflowCount > 0 {
                        Button("+\(overflowCount)") {
                            expandedFileSessions.insert(session.stableID)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(FizzTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(FizzTheme.accent.opacity(0.1), in: Capsule())
                    }
                }
            }

            if session.endedWithError, let err = session.lastError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
            }

            HStack(spacing: 8) {
                if isMarkAvailable, let associatedMark {
                    Button {
                        diffTarget = MarkDiffSheetTarget(mark: associatedMark)
                    } label: {
                        Label("看改了什么", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }

                if session.resumeCommand != nil {
                    Button {
                        Task { await resumeSession(session) }
                    } label: {
                        if isResuming {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Label(isLive ? "回到这次对话" : "继续这次对话", systemImage: "play.fill")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isResuming)
                }

                HandoffCopyButton(project: project, compact: true)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .fizzCard(radius: FizzRadius.card)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                    .strokeBorder(FizzTheme.accent, lineWidth: 1.5)
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
            tint: FizzTheme.accent,
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
