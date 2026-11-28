import Foundation
import SwiftUI

struct SessionsTabView: View {
    let project: RepoProject

    @State private var toolFilter = SessionToolFilter.all
    @State private var liveProcesses: [String: [LiveSessionProcess]] = [:]
    @State private var pendingEnd: SessionRecord?
    @State private var sessionFeedback: SessionFeedback?
    @State private var resumingSessionID: String?
    @State private var endFeedbackSessionID: String?

    private var sessions: [SessionRecord] {
        project.sessions.recentSessions.filter(toolFilter.matches)
    }

    private var availableFilters: [SessionToolFilter] {
        var tools = Set(project.sessions.recentSessions.map(\.tool))
        tools.formUnion(project.sessions.detected)
        tools.formUnion(project.detectedTools.map(\.rawValue))
        let ordered = tools
            .map { tool in
                (
                    tool,
                    DetectedTool(rawValue: tool)?.title ?? tool.capitalized
                )
            }
            .sorted {
                $0.1.localizedStandardCompare($1.1) == .orderedAscending
            }
            .map { SessionToolFilter.tool($0.0, title: $0.1) }
        return [.all] + ordered
    }

    var body: some View {
        Group {
            if project.sessions.sessionCount == 0 {
                ContentUnavailableView(
                    FizzL10n.text("没有匹配的会话", "No matching sessions"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(FizzL10n.text("读取 ~/.codex/sessions、~/.claude/projects、~/.grok/sessions 与 ~/.gemini/tmp，按项目 cwd 精确匹配。", "Matches the project’s exact working directory against local records in ~/.codex/sessions, ~/.claude/projects, ~/.grok/sessions and ~/.gemini/tmp."))
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FizzSpacing.section) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: FizzSpacing.grid)],
                            spacing: FizzSpacing.grid
                        ) {
                            GlassStatCard(
                                title: FizzL10n.text("会话总数", "Total sessions"),
                                value: "\(project.sessions.sessionCount)",
                                detail: project.sessions.detected
                                    .map { DetectedTool(rawValue: $0)?.title ?? $0.capitalized }
                                    .joined(separator: " · "),
                                symbol: "bubble.left.and.bubble.right",
                                tint: Color.secondary
                            )
                            GlassStatCard(
                                title: FizzL10n.text("最近会话", "Latest session"),
                                value: Format.relative(project.sessions.lastSessionAt),
                                detail: project.sessions.lastTool?.capitalized,
                                symbol: "clock",
                                tint: Color.secondary
                            )
                            if project.sessions.totalTokens > 0 {
                                GlassStatCard(
                                    title: FizzL10n.text("Token 用量", "Token usage"),
                                    value: Format.tokens(project.sessions.totalTokens),
                                    detail: costDetail,
                                    symbol: "chart.bar.doc.horizontal",
                                    tint: FizzTheme.statusWarning
                                )
                            }
                        }

                        if let sessionFeedback {
                            HStack(spacing: 8) {
                                Label(sessionFeedback.message, systemImage: sessionFeedback.failed
                                    ? "exclamationmark.triangle"
                                    : "checkmark.circle")
                                    .font(FizzTypography.font(12))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 8)

                                if let fallback = sessionFeedback.fallbackCommand {
                                    Button(FizzL10n.text("复制命令", "Copy command")) {
                                        SystemActions.copy(fallback)
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                }

                                if sessionFeedback.needsAutomationPermission {
                                    Button(FizzL10n.text("自动化设置", "Automation settings")) {
                                        SystemPermissionService.openAutomationSettings()
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                }
                            }
                        }

                        Panel(title: FizzL10n.text("最近会话", "Recent sessions"), symbol: "clock.arrow.circlepath") {
                            if sessions.isEmpty {
                                HStack(spacing: 8) {
                                    FizzIcon(.sm, symbol: "line.3.horizontal.decrease.circle")
                                    Text(FizzL10n.text("没有 \(toolFilter.title) 会话", toolFilter == .all ? "No sessions" : "No \(toolFilter.title) sessions"))
                                    Spacer(minLength: 0)
                                }
                                .font(FizzTypography.font(12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(
                                        Array(sessions.enumerated()),
                                        id: \.element.stableID
                                    ) { index, session in
                                        sessionRow(session)
                                        if index < sessions.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        } accessory: {
                            toolPicker
                        }
                    }
                    .padding(FizzSpacing.page)
                }
                .fizzTracksScrollPastTop()
                .onChange(of: project.path) {
                    toolFilter = .all
                    sessionFeedback = nil
                    endFeedbackSessionID = nil
                }
                .onChange(of: availableFilters) {
                    if !availableFilters.contains(toolFilter) {
                        toolFilter = .all
                    }
                }
            }
        }
        .task(id: "\(project.path):\(project.sessions.sessionCount)") {
            while !Task.isCancelled {
                await refreshLiveProcesses()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .confirmationDialog(
            FizzL10n.text("结束这个会话？", "End this session?"),
            isPresented: Binding(
                get: { pendingEnd != nil },
                set: { if !$0 { pendingEnd = nil } }
            ),
            presenting: pendingEnd
        ) { session in
            Button(FizzL10n.text("结束会话", "End session"), role: .destructive) {
                Task { await end(session) }
            }
            Button(FizzL10n.text("取消", "Cancel"), role: .cancel) {
                pendingEnd = nil
            }
        } message: { session in
            Text(FizzL10n.text("只会结束命令行中明确包含 \(session.id) 的 \(toolName(session.tool)) 进程；Codex Desktop 的共享 app-server 不会被终止。", "Only \(toolName(session.tool)) processes whose command line contains \(session.id) will be stopped. Codex Desktop’s shared app-server will keep running."))
        }
    }

    private var toolPicker: some View {
        ViewThatFits(in: .horizontal) {
            FizzSegmentedCapsule(items: availableFilters, selection: $toolFilter, height: .compact) { option, selected in
                Text(option.title)
                    .font(FizzTypography.caption(selected ? .semibold : .medium))
            }
            .fixedSize()
            Picker(FizzL10n.text("会话工具筛选", "Filter sessions by tool"), selection: $toolFilter) {
                ForEach(availableFilters) { option in Text(option.title).tag(option) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FizzL10n.text("会话工具筛选", "Filter sessions by tool"))
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        let processes = liveProcesses[session.stableID] ?? []
        let exactProcesses = processes.filter(\.exactMatch)
        let isLive = !processes.isEmpty
        let isResuming = resumingSessionID == session.stableID

        return HStack(alignment: .top, spacing: 10) {
            FizzIcon(.md, symbol: toolSymbol(session.tool))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(toolName(session.tool))
                        .font(FizzTypography.font(12, weight: .semibold))
                    if session.isWorkspaceSummary {
                        TagChip(text: FizzL10n.text("工作区", "Workspace"), tint: .secondary, compact: true)
                    }
                    if isLive {
                        TagChip(text: FizzL10n.text("运行中", "Running"), tint: FizzTheme.statusSuccess, compact: true)
                    }
                    Text(Format.relative(session.modified))
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if !exactProcesses.isEmpty {
                        FizzActionButton(title: FizzL10n.text("结束", "End"), symbol: "stop.circle", height: .compact, role: .destructive) {
                            pendingEnd = session
                        }
                        .help(FizzL10n.text("结束 PID \(exactProcesses.map { String($0.pid) }.joined(separator: ", "))", "Stop PID \(exactProcesses.map { String($0.pid) }.joined(separator: ", "))"))
                        .accessibilityLabel(FizzL10n.text("结束 \(toolName(session.tool)) 会话", "End \(toolName(session.tool)) session"))
                        .accessibilityHint(FizzL10n.text("只结束命令行中明确包含这个会话 ID 的进程", "Only stop processes whose command line contains this session ID."))
                    }
                    if let command = session.resumeCommand {
                        FizzIconButton(title: FizzL10n.text("复制 \(toolName(session.tool)) 恢复命令", "Copy \(toolName(session.tool)) resume command"), symbol: "doc.on.doc", height: .compact) {
                            SystemActions.copy(command)
                            endFeedbackSessionID = nil
                            sessionFeedback = SessionFeedback(
                                message: FizzL10n.text("已复制恢复命令：\(command)", "Copied resume command: \(command)"),
                                failed: false,
                                fallbackCommand: nil,
                                needsAutomationPermission: false
                            )
                        }
                    }
                    if DetectedTool(rawValue: session.tool)?.supportsResume == true {
                        FizzActionButton(
                            title: isResuming ? FizzL10n.text("继续中…", "Resuming…") : (isLive ? FizzL10n.text("回到会话", "Return to session") : FizzL10n.text("继续", "Resume")),
                            symbol: "play.fill",
                            height: .compact,
                            prominence: .primary
                        ) {
                            Task { await resume(session) }
                        }
                        .disabled(resumingSessionID != nil)
                        .accessibilityLabel(isLive ? FizzL10n.text("回到 \(toolName(session.tool)) 会话", "Return to \(toolName(session.tool)) session") : FizzL10n.text("继续 \(toolName(session.tool)) 会话", "Resume \(toolName(session.tool)) session"))
                    }
                }

                Text(session.lastUser ?? (session.isWorkspaceSummary ? FizzL10n.text("工作区活动摘要", "Workspace activity summary") : FizzL10n.text("未读取到最后一条用户消息", "No last user message found")))
                    .font(FizzTypography.font(12))
                    .foregroundStyle(session.lastUser == nil ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let command = session.resumeCommand {
                    Text(verbatim: command)
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                if let usage = session.usage, usage.totalTokens > 0 {
                    HStack(spacing: 6) {
                        Text("\(Format.tokens(usage.totalTokens)) tokens")
                        if let cost = Format.cost(session.costUSD, estimated: session.costIsEstimate == true) {
                            Text("·")
                            Text(cost)
                        }
                        if let model = session.model {
                            Text("·")
                            Text(model)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(FizzTypography.micro)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var costDetail: String {
        if let cost = Format.cost(
            project.sessions.totalCostUSD,
            estimated: project.sessions.costIsEstimate
        ) {
            return project.sessions.costIsEstimate ? FizzL10n.text("\(cost) · 按价目估算", "\(cost) · Estimated from rates") : FizzL10n.text("\(cost) · 本地记录", "\(cost) · Local record")
        }
        if project.sessions.modelNames.isEmpty {
            return FizzL10n.text("已读取本地会话记录", "Read from local session records")
        }
        return FizzL10n.text("未记录价格", "No price recorded")
    }

    private func resume(_ session: SessionRecord) async {
        resumingSessionID = session.stableID
        let result = await SessionResumeService.resume(
            session: session,
            projectPath: project.path
        )
        resumingSessionID = nil
        endFeedbackSessionID = nil
        sessionFeedback = SessionFeedback(
            message: result.message,
            failed: !result.success,
            fallbackCommand: result.fallbackCommand,
            needsAutomationPermission: result.needsAutomationPermission
        )
        await refreshLiveProcesses()
    }

    private func end(_ session: SessionRecord) async {
        pendingEnd = nil
        let result = await SessionProcessService.end(session)
        endFeedbackSessionID = session.stableID
        sessionFeedback = SessionFeedback(
            message: result.message,
            failed: !result.success,
            fallbackCommand: nil,
            needsAutomationPermission: false
        )
        await refreshLiveProcesses()
    }

    private func refreshLiveProcesses() async {
        liveProcesses = await SessionProcessService.liveProcessesDetailed(
            for: project.sessions.recentSessions,
            projectPath: project.path
        )
        if let endFeedbackSessionID,
           sessionFeedback?.failed == true,
           (liveProcesses[endFeedbackSessionID] ?? []).isEmpty {
            sessionFeedback = nil
            self.endFeedbackSessionID = nil
        }
    }

    private func toolName(_ tool: String) -> String {
        DetectedTool(rawValue: tool)?.title ?? tool.capitalized
    }

    private func toolSymbol(_ tool: String) -> String {
        DetectedTool(rawValue: tool)?.symbol ?? "sparkles"
    }

}

private struct SessionFeedback {
    let message: String
    let failed: Bool
    let fallbackCommand: String?
    let needsAutomationPermission: Bool
}

private enum SessionToolFilter: Identifiable, Hashable {
    case all
    case tool(String, title: String)

    var id: String {
        switch self {
        case .all: "all"
        case .tool(let tool, _): tool
        }
    }

    var title: String {
        switch self {
        case .all: FizzL10n.text("全部", "All")
        case .tool(_, let title): title
        }
    }

    func matches(_ session: SessionRecord) -> Bool {
        if case .tool(let tool, _) = self { return session.tool == tool }
        return true
    }
}
