import SwiftUI

struct SessionsTabView: View {
    let project: RepoProject

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

                    if let message = project.sessions.lastUserMessage {
                        Panel(title: "最后一条需求", symbol: "quote.bubble") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(message)
                                    .font(.callout)
                                    .lineLimit(8)
                                    .fixedSize(horizontal: false, vertical: true)
                                CopyButton(title: "复制需求", value: message, symbol: "doc.on.doc")
                            }
                        }
                    }

                    ForEach(project.sessions.byTool) { tool in
                        toolPanel(tool)
                    }
                }
                .padding(24)
            }
        }
    }

    private func toolPanel(_ tool: ToolSession) -> some View {
        Panel(title: toolName(tool.tool), symbol: toolSymbol(tool.tool)) {
            VStack(alignment: .leading, spacing: 10) {
                KeyValueRow(key: "会话数", value: "\(tool.sessionCount)")
                KeyValueRow(key: "最近使用", value: Format.relative(tool.lastSessionAt))
                if let message = tool.lastUserMessage {
                    Divider()
                    Text(message)
                        .font(.callout)
                        .lineLimit(5)
                        .foregroundStyle(.primary)
                }

                if let id = tool.lastSessionID {
                    Divider()
                    Text(verbatim: resumeCommand(tool: tool.tool, id: id))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        CopyButton(
                            title: "复制 resume",
                            value: resumeCommand(tool: tool.tool, id: id),
                            symbol: "play.fill"
                        )
                        if let message = tool.lastUserMessage {
                            CopyButton(title: "复制需求", value: message)
                        }
                    }
                }
            }
        }
    }

    private func toolName(_ tool: String) -> String {
        tool == "codex" ? "Codex" : "Claude Code"
    }

    private func toolSymbol(_ tool: String) -> String {
        tool == "codex" ? "terminal" : "sparkles"
    }

    private func resumeCommand(tool: String, id: String) -> String {
        tool == "codex" ? "codex resume \(id)" : "claude --resume \(id)"
    }
}
