import SwiftUI

struct SessionContinueButton: View {
    enum Style {
        case compact
        case prominent
        case dock
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

    private var showsChevronMenu: Bool {
        guard let primary = primarySession else { return ideEditors.count > 1 }
        return resumableSessions.count > 1
            || primary.tool == "codex"
            || !evidenceOnlyTools.isEmpty
            || !ideEditors.isEmpty
    }

    var body: some View {
        Group {
            if let primary = primarySession {
                switch style {
                case .compact:
                    compactControls(primary: primary)
                        .popover(isPresented: $showFeedbackPopover, arrowEdge: .bottom) {
                            feedbackPopoverContent
                        }
                case .prominent:
                    prominentControls(primary: primary)
                case .dock:
                    dockControls(primary: primary)
                }
            } else if !ideEditors.isEmpty {
                ideOnlyControls
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

    @ViewBuilder
    private var ideOnlyControls: some View {
        if let editor = ideEditors.first {
            switch style {
            case .compact:
                ideButton(editor: editor, controlSize: .small, fontSize: 10.5, iconSize: 9, spacing: 3)
                    .popover(isPresented: $showFeedbackPopover, arrowEdge: .bottom) {
                        feedbackPopoverContent
                    }
            case .prominent:
                ideButton(editor: editor, controlSize: .regular, fontSize: 12, iconSize: 11, spacing: 4)
            case .dock:
                dockIDEControls(editor: editor)
            }
        }
    }

    private func ideButton(
        editor: ProjectEditor,
        controlSize: ControlSize,
        fontSize: CGFloat,
        iconSize: CGFloat,
        spacing: CGFloat
    ) -> some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) {
                Button {
                    SystemActions.open(project.path, in: editor)
                } label: {
                    HStack(spacing: 4) {
                        FizzIcon(symbol: "arrow.up.forward.app", size: iconSize)
                            .foregroundStyle(FizzTheme.accent)
                        Text("打开 \(editor.title)")
                            .font(.system(size: fontSize, weight: .semibold))
                    }
                }
                .buttonStyle(.glass)
                .controlSize(controlSize)
                .help("在 \(editor.title) 中打开项目")
                .accessibilityLabel("在 \(editor.title) 中打开项目")
                .accessibilityHint("用 \(editor.title) 打开当前项目目录")

                if showsChevronMenu {
                    chevronMenuButton(
                        controlSize: controlSize,
                        iconSize: max(8, iconSize - 1),
                        help: "选择打开方式",
                        label: "选择打开方式"
                    )
                }
            }
        }
    }

    private func compactControls(primary: SessionRecord) -> some View {
        GlassEffectContainer(spacing: 3) {
            HStack(spacing: 3) {
                Button {
                    Task { await trigger(session: primary, target: .auto) }
                } label: {
                    HStack(spacing: 4) {
                        if running {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            FizzIcon(symbol: "play.fill", size: 9)
                                .foregroundStyle(FizzTheme.accent)
                        }
                        Text("继续")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(running)
                .help("继续最近 \(toolTitle(primary.tool)) 会话")
                .accessibilityLabel("继续 \(toolTitle(primary.tool)) 会话")
                .accessibilityHint("在终端恢复最近一次会话")

                if showsChevronMenu {
                    chevronMenuButton(
                        controlSize: .small,
                        iconSize: 8,
                        help: "选择要继续的工具",
                        label: "选择要继续的工具或打开方式"
                    )
                    .disabled(running)
                }
            }
        }
    }

    private func prominentControls(primary: SessionRecord) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let feedback, !feedback.success || feedback.needsAutomationPermission {
                feedbackBanner(feedback)
            }

            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    Button {
                        Task { await trigger(session: primary, target: .auto) }
                    } label: {
                        HStack(spacing: 6) {
                            if running {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                FizzIcon(symbol: "play.fill", size: 11)
                                    .foregroundStyle(FizzTheme.accent)
                            }
                            Text("继续 · \(toolTitle(primary.tool))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                    .disabled(running)
                    .help("继续最近 \(toolTitle(primary.tool)) 会话")
                    .accessibilityLabel("继续 \(toolTitle(primary.tool)) 会话")
                    .accessibilityHint("在终端恢复最近一次会话")

                    if showsChevronMenu {
                        chevronMenuButton(
                            controlSize: .regular,
                            iconSize: 9,
                            help: "选择工具或打开方式",
                            label: "选择要继续的工具或打开方式"
                        )
                        .disabled(running)
                    }
                }
            }
        }
    }

    private func dockControls(primary: SessionRecord) -> some View {
        VStack(alignment: .center, spacing: 8) {
            if let feedback, !feedback.success || feedback.needsAutomationPermission {
                feedbackBanner(feedback)
            }

            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    Button {
                        Task { await trigger(session: primary, target: .auto) }
                    } label: {
                        HStack(spacing: 6) {
                            if running {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                FizzIcon(symbol: "play.fill", size: 10)
                                    .foregroundStyle(FizzTheme.accent)
                            }
                            Text("继续 · \(toolTitle(primary.tool))")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(running)
                    .help("继续最近 \(toolTitle(primary.tool)) 会话")
                    .accessibilityLabel("继续 \(toolTitle(primary.tool)) 会话")
                    .accessibilityHint("在终端恢复最近一次会话")

                    if showsChevronMenu {
                        chevronMenuButton(
                            controlSize: .large,
                            iconSize: 10,
                            help: "选择工具或打开方式",
                            label: "选择要继续的工具或打开方式"
                        )
                        .disabled(running)
                    }
                }
            }
        }
    }

    private func dockIDEControls(editor: ProjectEditor) -> some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    SystemActions.open(project.path, in: editor)
                } label: {
                    HStack(spacing: 6) {
                        FizzIcon(symbol: "arrow.up.forward.app", size: 11)
                            .foregroundStyle(FizzTheme.accent)
                        Text("打开 \(editor.title)")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help("在 \(editor.title) 中打开项目")
                .accessibilityLabel("在 \(editor.title) 中打开项目")
                .accessibilityHint("用 \(editor.title) 打开当前项目目录")

                if showsChevronMenu {
                    chevronMenuButton(
                        controlSize: .large,
                        iconSize: 10,
                        help: "选择打开方式",
                        label: "选择打开方式"
                    )
                }
            }
        }
    }

    private func chevronMenuButton(
        controlSize: ControlSize,
        iconSize: CGFloat,
        help: String,
        label: String
    ) -> some View {
        Menu {
            toolMenuItems
        } label: {
            FizzIcon(symbol: "chevron.down", size: iconSize)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .menuIndicator(.hidden)
        .controlSize(controlSize)
        .fixedSize()
        .help(help)
        .accessibilityLabel(label)
    }

    private func feedbackBanner(_ feedback: SessionResumeResult) -> some View {
        HStack(spacing: 8) {
            FizzIcon(symbol: "exclamationmark.triangle", size: 10)
                .foregroundStyle(.orange)

            Text(feedback.message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let fallback = feedback.fallbackCommand {
                Button("复制命令") {
                    SystemActions.copy(fallback)
                }
                .buttonStyle(.glass)
                .controlSize(.mini)
            }

            if feedback.needsAutomationPermission {
                Button("自动化设置") {
                    SystemPermissionService.openAutomationSettings()
                }
                .buttonStyle(.glass)
                .controlSize(.mini)
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
            } else {
                Button {
                    Task { await trigger(session: session, target: .auto) }
                } label: {
                    Label(toolTitle(session.tool), systemImage: toolSymbol(session.tool))
                }
            }
        }

        if !ideEditors.isEmpty {
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
                .font(.callout)
                .foregroundStyle(feedback.success ? Color.primary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let fallback = feedback.fallbackCommand {
                        Button("复制命令") {
                            SystemActions.copy(fallback)
                            showFeedbackPopover = false
                        }
                        .buttonStyle(.glassProminent)
                        .tint(FizzTheme.accent)
                        .controlSize(.small)
                    }
                    if feedback.needsAutomationPermission {
                        Button("打开自动化设置") {
                            SystemPermissionService.openAutomationSettings()
                            showFeedbackPopover = false
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
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
        if style == .compact && (!result.success || result.needsAutomationPermission) {
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
