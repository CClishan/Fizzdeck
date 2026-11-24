import SwiftUI

struct SessionsTabView: View {
    let project: RepoProject

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toolFilter = SessionToolFilter.all

    private var sessions: [SessionRecord] {
        project.sessions.recentSessions.filter(toolFilter.matches)
    }

    var body: some View {
        if project.sessions.sessionCount == 0 {
            ContentUnavailableView(
                "没有匹配的会话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("读取 ~/.codex/sessions 与 ~/.claude/projects，按项目 cwd 精确匹配。")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 12)],
                            spacing: 12
                        ) {
                            GlassStatCard(
                                title: "会话总数",
                                value: "\(project.sessions.sessionCount)",
                                detail: project.sessions.detected
                                    .map { $0 == "codex" ? "Codex" : "Claude Code" }
                                    .joined(separator: " · "),
                                symbol: "bubble.left.and.bubble.right",
                                tint: .purple
                            )
                            GlassStatCard(
                                title: "最近会话",
                                value: Format.relative(project.sessions.lastSessionAt),
                                detail: project.sessions.lastTool?.capitalized,
                                symbol: "clock",
                                tint: .blue
                            )
                        }
                    }

                    Panel(title: "最近会话", symbol: "clock.arrow.circlepath") {
                        if sessions.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                Text("没有 \(toolFilter.title) 会话")
                                Spacer(minLength: 0)
                            }
                            .font(.callout)
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
                .padding(24)
            }
            .onChange(of: project.path) {
                toolFilter = .all
            }
        }
    }

    private var toolPicker: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 1) {
                ForEach(SessionToolFilter.allCases) { option in
                    Button {
                        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                            toolFilter = option
                        }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 10.5, weight: toolFilter == option ? .semibold : .medium))
                            .foregroundStyle(toolFilter == option ? Color.primary : Color.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background {
                                if toolFilter == option {
                                    Capsule()
                                        .fill(Color.white.opacity(0.92))
                                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(toolFilter == option ? .isSelected : [])
                    .accessibilityRemoveTraits(toolFilter == option ? [] : .isSelected)
                }
            }
            .padding(2)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("会话工具")
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toolSymbol(session.tool))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(toolTint(session.tool))
                .frame(width: 16, height: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(toolName(session.tool))
                        .font(.system(size: 12, weight: .semibold))
                    Text(Format.relative(session.modified))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let command = session.resumeCommand {
                        CopyButton(
                            title: "复制恢复命令",
                            value: command,
                            symbol: "play.fill"
                        )
                    }
                }

                Text(session.lastUser ?? "未读取到最后一条用户消息")
                    .font(.callout)
                    .foregroundStyle(session.lastUser == nil ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let command = session.resumeCommand {
                    Text(verbatim: command)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func toolName(_ tool: String) -> String {
        switch tool {
        case "codex": "Codex"
        case "claude": "Claude Code"
        default: tool.capitalized
        }
    }

    private func toolSymbol(_ tool: String) -> String {
        switch tool {
        case "codex": "terminal"
        default: "sparkles"
        }
    }

    private func toolTint(_ tool: String) -> Color {
        switch tool {
        case "codex": .blue
        case "claude": .purple
        default: .secondary
        }
    }
}

private enum SessionToolFilter: String, CaseIterable, Identifiable {
    case all
    case codex
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    func matches(_ session: SessionRecord) -> Bool {
        self == .all || session.tool == rawValue
    }
}
