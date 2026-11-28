import SwiftUI

struct SessionContinueButton: View {
    enum Style {
        case compact
        case prominent
        case dock
        case hero
    }

    let project: RepoProject
    var style: Style = .compact

    @State private var running = false
    @State private var feedback: SessionResumeResult?
    @State private var showFeedbackPopover = false
    @State private var ideEditors: [ProjectEditor] = []

    private var resumableSessions: [SessionRecord] {
        var result: [SessionRecord] = []
        for toolSession in project.sessions.byTool {
            guard DetectedTool(rawValue: toolSession.tool)?.supportsResume == true,
                  let sessionID = toolSession.lastSessionID,
                  let record = project.sessions.recentSessions.first(where: {
                      $0.tool == toolSession.tool && $0.id == sessionID
                  })
            else { continue }
            result.append(record)
        }
        return result
    }

    private var primarySession: SessionRecord? {
        resumableSessions.first
    }

    private var evidenceOnlyTools: [DetectedTool] {
        let installed = Set(ideEditors.map(\.rawValue))
        return project.allTools
            .compactMap(DetectedTool.init(rawValue:))
            .filter { !$0.supportsResume && !installed.contains($0.rawValue) }
    }

    private var height: FizzControlHeight {
        style == .dock ? .standard : .compact
    }

    private var usesPrimaryAction: Bool {
        style == .hero || style == .prominent
    }

    private var presentsFeedbackPopover: Bool {
        style == .compact || style == .hero
    }

    private var showsToolMenu: Bool {
        guard let primary = primarySession else { return style != .hero && ideEditors.count > 1 }
        return resumableSessions.count > 1
            || primary.tool == "codex"
            || !evidenceOnlyTools.isEmpty
            || (style != .hero && !ideEditors.isEmpty)
    }

    var body: some View {
        Group {
            if primarySession != nil || (style != .hero && !ideEditors.isEmpty) {
                if presentsFeedbackPopover {
                    controls
                        .popover(isPresented: $showFeedbackPopover, arrowEdge: .bottom) {
                            feedbackPopoverContent
                        }
                } else {
                    VStack(alignment: style == .dock ? .center : .trailing, spacing: FizzSpacing.row) {
                        if let feedback, !feedback.success || feedback.needsAutomationPermission {
                            feedbackBanner(feedback)
                        }
                        controls
                    }
                }
            }
        }
        .task(id: project.path) {
            let used = Set(project.allTools)
            ideEditors = ProjectEditor.available(for: project.path)
                .filter { Self.isIDEEditor($0) && used.contains($0.rawValue) }
        }
    }

    private static func isIDEEditor(_ editor: ProjectEditor) -> Bool {
        editor == .cursor || editor == .trae || editor == .windsurf
    }

    private var controls: some View {
        HStack(spacing: FizzSpacing.row) {
            if showsToolMenu {
                toolMenu
            }

            if let primary = primarySession {
                let tool = toolTitle(primary.tool)
                FizzActionButton(
                    title: running ? "继续中…" : (style == .compact ? "继续" : "继续 · \(tool)"),
                    symbol: "play.fill",
                    height: height,
                    prominence: usesPrimaryAction ? .primary : .secondary
                ) {
                    Task { await trigger(session: primary, target: .auto) }
                }
                .disabled(running)
                .help("继续最近 \(tool) 会话")
                .accessibilityLabel("继续 \(tool) 会话")
                .accessibilityValue(running ? "继续中" : "")
                .accessibilityHint("在终端恢复最近一次会话")
            } else if let editor = ideEditors.first {
                FizzActionButton(
                    title: "打开 \(editor.title)",
                    symbol: "arrow.up.forward.app",
                    height: height,
                    prominence: usesPrimaryAction ? .primary : .secondary
                ) {
                    SystemActions.open(project.path, in: editor)
                }
                .help("在 \(editor.title) 中打开项目")
                .accessibilityLabel("在 \(editor.title) 中打开项目")
                .accessibilityHint("用 \(editor.title) 打开当前项目目录")
            }
        }
    }

    private var toolMenu: some View {
        let title = if style == .hero { "选择要继续的工具" }
            else if primarySession == nil { "选择打开方式" }
            else { "选择要继续的工具或打开方式" }

        return FizzMenuButton(title: title, symbol: "chevron.down", height: height) {
            toolMenuItems
        }
        .disabled(running)
    }

    private func feedbackBanner(_ feedback: SessionResumeResult) -> some View {
        HStack(spacing: 8) {
            FizzIcon(.xs, symbol: "exclamationmark.triangle")
                .foregroundStyle(.secondary)

            Text(feedback.message)
                .font(FizzTypography.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let fallback = feedback.fallbackCommand {
                FizzActionButton(title: "复制命令", height: .compact) {
                    SystemActions.copy(fallback)
                }
            }

            if feedback.needsAutomationPermission {
                FizzActionButton(title: "自动化设置", height: .compact) {
                    SystemPermissionService.openAutomationSettings()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            FizzTheme.elevatedFill,
            in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var toolMenuItems: some View {
        ForEach(resumableSessions, id: \.stableID) { session in
            if session.tool == "codex" {
                Button {
                    Task { await trigger(session: session, target: .cli) }
                } label: {
                    Label("Codex CLI（终端）", systemImage: "terminal")
                }
                Button {
                    Task { await trigger(session: session, target: .desktop) }
                } label: {
                    Label("Codex Desktop（直达线程）", systemImage: "macwindow")
                }
            } else if style != .hero || session.stableID != primarySession?.stableID {
                Button {
                    Task { await trigger(session: session, target: .auto) }
                } label: {
                    Label(toolTitle(session.tool), systemImage: toolSymbol(session.tool))
                }
            }
        }

        if style != .hero, !ideEditors.isEmpty {
            if !resumableSessions.isEmpty {
                Divider()
            }
            Section("在 IDE 中打开项目") {
                ForEach(ideEditors) { editor in
                    Button {
                        SystemActions.open(project.path, in: editor)
                    } label: {
                        Label("在 \(editor.title) 中打开项目", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }

        if !evidenceOnlyTools.isEmpty {
            Divider()
            Section("仅识别工具痕迹") {
                ForEach(evidenceOnlyTools) { tool in
                    Button {} label: {
                        Label("\(tool.title)（暂不支持恢复）", systemImage: tool.symbol)
                    }
                    .disabled(true)
                }
            }
        }
    }

    private var feedbackPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let feedback {
                Label(
                    feedback.message,
                    systemImage: feedback.success ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if feedback.needsAutomationPermission {
                        FizzActionButton(title: "打开自动化设置", height: .compact) {
                            SystemPermissionService.openAutomationSettings()
                            showFeedbackPopover = false
                        }
                    }
                    if let fallback = feedback.fallbackCommand {
                        FizzActionButton(title: "复制命令", height: .compact, prominence: .primary) {
                            SystemActions.copy(fallback)
                            showFeedbackPopover = false
                        }
                    }
                }
            }
        }
        .padding(FizzSpacing.panel)
        .frame(width: 300)
    }

    private func trigger(session: SessionRecord, target: ResumeTarget) async {
        guard !running else { return }
        running = true
        let result = await SessionResumeService.resume(
            session: session,
            projectPath: project.path,
            preferredTarget: target
        )
        running = false
        feedback = result
        if presentsFeedbackPopover && (!result.success || result.needsAutomationPermission) {
            showFeedbackPopover = true
        }
    }

    private func toolTitle(_ raw: String) -> String {
        DetectedTool(rawValue: raw)?.title ?? raw.capitalized
    }

    private func toolSymbol(_ raw: String) -> String {
        DetectedTool(rawValue: raw)?.symbol ?? "sparkles"
    }
}
