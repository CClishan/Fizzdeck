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
                    "没有匹配的会话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("读取 ~/.codex/sessions、~/.claude/projects、~/.grok/sessions 与 ~/.gemini/tmp，按项目 cwd 精确匹配。")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FizzSpacing.section) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: FizzSpacing.grid)],
                            spacing: FizzSpacing.grid
                        ) {
                            GlassStatCard(
                                title: "会话总数",
                                value: "\(project.sessions.sessionCount)",
                                detail: project.sessions.detected
                                    .map { DetectedTool(rawValue: $0)?.title ?? $0.capitalized }
                                    .joined(separator: " · "),
                                symbol: "bubble.left.and.bubble.right",
                                tint: Color.secondary
                            )
                            GlassStatCard(
                                title: "最近会话",
                                value: Format.relative(project.sessions.lastSessionAt),
                                detail: project.sessions.lastTool?.capitalized,
                                symbol: "clock",
                                tint: Color.secondary
                            )
                            if project.sessions.totalTokens > 0 {
                                GlassStatCard(
                                    title: "Token 用量",
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
                                    Button("复制命令") {
                                        SystemActions.copy(fallback)
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                }

                                if sessionFeedback.needsAutomationPermission {
                                    Button("自动化设置") {
                                        SystemPermissionService.openAutomationSettings()
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                }
                            }
                        }

                        Panel(title: "最近会话", symbol: "clock.arrow.circlepath") {
                            if sessions.isEmpty {
                                HStack(spacing: 8) {
                                    FizzIcon(.sm, symbol: "line.3.horizontal.decrease.circle")
                                Text("没有 \(toolFilter.title) 会话")
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
            "结束这个会话？",
            isPresented: Binding(
                get: { pendingEnd != nil },
                set: { if !$0 { pendingEnd = nil } }
            ),
            presenting: pendingEnd
        ) { session in
            Button("结束会话", role: .destructive) {
                Task { await end(session) }
            }
            Button("取消", role: .cancel) {
                pendingEnd = nil
            }
        } message: { session in
            Text("只会结束命令行中明确包含 \(session.id) 的 \(toolName(session.tool)) 进程；Codex Desktop 的共享 app-server 不会被终止。")
        }
    }

    private var toolPicker: some View {
        FizzSegmentedCapsule(items: availableFilters, selection: $toolFilter, height: .compact) { option, selected in
            Text(option.title)
                .font(FizzTypography.caption(selected ? .semibold : .medium))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("会话工具筛选")
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
                        TagChip(text: "工作区", tint: .secondary, compact: true)
                    }
                    if isLive {
                        TagChip(text: "运行中", tint: FizzTheme.statusSuccess, compact: true)
                    }
                    Text(Format.relative(session.modified))
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if !exactProcesses.isEmpty {
                        FizzActionButton(title: "结束", symbol: "stop.circle", height: .compact, role: .destructive) {
                            pendingEnd = session
                        }
                        .help("结束 PID \(exactProcesses.map { String($0.pid) }.joined(separator: ", "))")
                        .accessibilityLabel("结束 \(toolName(session.tool)) 会话")
                        .accessibilityHint("只结束命令行中明确包含这个会话 ID 的进程")
                    }
                    if let command = session.resumeCommand {
                        FizzIconButton(title: "复制 \(toolName(session.tool)) 恢复命令", symbol: "doc.on.doc", height: .compact) {
                            SystemActions.copy(command)
                            endFeedbackSessionID = nil
                            sessionFeedback = SessionFeedback(
                                message: "已复制恢复命令：\(command)",
                                failed: false,
                                fallbackCommand: nil,
                                needsAutomationPermission: false
                            )
                        }
                    }
                    if DetectedTool(rawValue: session.tool)?.supportsResume == true {
                        FizzActionButton(
                            title: isResuming ? "继续中…" : (isLive ? "回到会话" : "继续"),
                            symbol: "play.fill",
                            height: .compact,
                            prominence: .primary
                        ) {
                            Task { await resume(session) }
                        }
                        .disabled(resumingSessionID != nil)
                        .accessibilityLabel(isLive ? "回到 \(toolName(session.tool)) 会话" : "继续 \(toolName(session.tool)) 会话")
                    }
                }

                Text(session.lastUser ?? (session.isWorkspaceSummary ? "工作区活动摘要" : "未读取到最后一条用户消息"))
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
            return project.sessions.costIsEstimate ? "\(cost) · 按价目估算" : "\(cost) · 本地记录"
        }
        if project.sessions.modelNames.isEmpty {
            return "已读取本地会话记录"
        }
        return "未记录价格"
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

private struct SessionToolFilter: Identifiable, Hashable {
    let id: String
    let tool: String?
    let title: String

    static let all = SessionToolFilter(id: "all", tool: nil, title: "全部")

    static func tool(_ tool: String, title: String) -> SessionToolFilter {
        SessionToolFilter(id: tool, tool: tool, title: title)
    }

    func matches(_ session: SessionRecord) -> Bool {
        tool == nil || session.tool == tool
    }
}
