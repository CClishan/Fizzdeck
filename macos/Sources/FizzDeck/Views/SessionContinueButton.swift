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
                    title: running ? FizzL10n.text("继续中…", "Resuming…") : (style == .compact ? FizzL10n.text("继续", "Resume") : FizzL10n.text("继续 · \(tool)", "Resume · \(tool)")),
                    symbol: "play.fill",
                    height: height,
                    prominence: usesPrimaryAction ? .primary : .secondary
                ) {
                    Task { await trigger(session: primary, target: .auto) }
                }
                .disabled(running)
                .help(FizzL10n.text("继续最近 \(tool) 会话", "Resume latest \(tool) session"))
                .accessibilityLabel(FizzL10n.text("继续 \(tool) 会话", "Resume \(tool) session"))
                .accessibilityValue(running ? FizzL10n.text("继续中", "Resuming") : "")
                .accessibilityHint(FizzL10n.text("在终端恢复最近一次会话", "Resume the latest session in Terminal"))
            } else if let editor = ideEditors.first {
                FizzActionButton(
                    title: FizzL10n.text("打开 \(editor.title)", "Open \(editor.title)"),
                    symbol: "arrow.up.forward.app",
                    height: height,
                    prominence: usesPrimaryAction ? .primary : .secondary
                ) {
                    SystemActions.open(project.path, in: editor)
                }
                .help(FizzL10n.text("在 \(editor.title) 中打开项目", "Open project in \(editor.title)"))
                .accessibilityLabel(FizzL10n.text("在 \(editor.title) 中打开项目", "Open project in \(editor.title)"))
                .accessibilityHint(FizzL10n.text("用 \(editor.title) 打开当前项目目录", "Open this project folder with \(editor.title)"))
            }
        }
    }

    private var toolMenu: some View {
        let title = if style == .hero { FizzL10n.text("选择要继续的工具", "Choose a tool to resume") }
            else if primarySession == nil { FizzL10n.text("选择打开方式", "Choose how to open") }
            else { FizzL10n.text("选择要继续的工具或打开方式", "Choose a tool to resume or an app to open") }

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
                FizzActionButton(title: FizzL10n.text("复制命令", "Copy command"), height: .compact) {
                    SystemActions.copy(fallback)
                }
            }

            if feedback.needsAutomationPermission {
                FizzActionButton(title: FizzL10n.text("自动化设置", "Automation settings"), height: .compact) {
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
                    Label(FizzL10n.text("Codex CLI（终端）", "Codex CLI (Terminal)"), systemImage: "terminal")
                }
                Button {
                    Task { await trigger(session: session, target: .desktop) }
                } label: {
                    Label(FizzL10n.text("Codex Desktop（直达线程）", "Codex Desktop (open chat)"), systemImage: "macwindow")
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
            Section(FizzL10n.text("在 IDE 中打开项目", "Open project in IDE")) {
                ForEach(ideEditors) { editor in
                    Button {
                        SystemActions.open(project.path, in: editor)
                    } label: {
                        Label(FizzL10n.text("在 \(editor.title) 中打开项目", "Open project in \(editor.title)"), systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }

        if !evidenceOnlyTools.isEmpty {
            Divider()
            Section(FizzL10n.text("仅识别工具痕迹", "Tool traces only")) {
                ForEach(evidenceOnlyTools) { tool in
                    Button {} label: {
                        Label(FizzL10n.text("\(tool.title)（暂不支持恢复）", "\(tool.title) (resume unavailable)"), systemImage: tool.symbol)
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
                        FizzActionButton(title: FizzL10n.text("打开自动化设置", "Open automation settings"), height: .compact) {
                            SystemPermissionService.openAutomationSettings()
                            showFeedbackPopover = false
                        }
                    }
                    if let fallback = feedback.fallbackCommand {
                        FizzActionButton(title: FizzL10n.text("复制命令", "Copy command"), height: .compact, prominence: .primary) {
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
