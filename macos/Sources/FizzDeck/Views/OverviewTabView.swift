import SwiftUI

struct OverviewTabView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    let project: RepoProject
    @Binding var noteDraft: String
    let saveNote: () -> Void

    private var weekTotal: Int {
        project.weekly.values.reduce(0, +)
    }

    private var lastActiveText: String {
        if let commit = project.lastCommit {
            return commit.subject
        }
        if let message = project.sessions.lastUserMessage {
            return message
        }
        return "还没有可识别的活动"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !project.intro.text.isEmpty {
                    Panel(title: "简介", symbol: "text.quote") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(project.intro.text)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let source = project.intro.source {
                                Text(source)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 150), spacing: 12),
                            GridItem(.flexible(minimum: 150), spacing: 12),
                            GridItem(.flexible(minimum: 150), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        GlassStatCard(
                            title: "最近活动",
                            value: Format.relative(project.recent),
                            detail: project.lastCommit?.subject ?? project.sessions.lastUserMessage,
                            symbol: "clock",
                            tint: .blue
                        )
                        GlassStatCard(
                            title: "磁盘体积",
                            value: Format.bytes(project.size.totalBytes),
                            detail: "du 统计的磁盘占用",
                            symbol: "internaldrive",
                            tint: .indigo
                        )
                        GlassStatCard(
                            title: "可清理",
                            value: Format.bytes(project.cleanup.reusableBytes),
                            detail: project.cleanup.items.isEmpty ? "没有命中清理规则" : "\(project.cleanup.items.count) 个目录",
                            symbol: "trash.slash",
                            tint: .orange
                        )
                        GlassStatCard(
                            title: "AI 会话",
                            value: "\(project.sessions.sessionCount)",
                            detail: project.sessions.detected.map { $0 == "codex" ? "Codex" : "Claude" }.joined(separator: " · "),
                            symbol: "bubble.left.and.bubble.right",
                            tint: .purple
                        )
                        GlassStatCard(
                            title: "本周提交",
                            value: "\(weekTotal)",
                            detail: project.branch ?? "无 Git 分支",
                            symbol: "arrow.triangle.branch",
                            tint: .green
                        )
                        GlassStatCard(
                            title: "预览端口",
                            value: project.run.flatMap { $0.port > 0 ? String($0.port) : nil } ?? "—",
                            detail: portText,
                            symbol: "network",
                            tint: .cyan,
                            statusColor: portColor
                        )
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 20)],
                    alignment: .leading,
                    spacing: 20
                ) {
                    stackPanel
                    runtimePanel
                }

                notePanel

                if !project.weekly.isEmpty {
                    weeklyPanel
                }
            }
            .padding(24)
        }
    }

    private var portText: String {
        switch project.port {
        case .running: "端口运行中"
        case .stopped: "端口未启动"
        case .noPreview: "未配置预览端口"
        }
    }

    private var portColor: Color {
        switch project.port {
        case .running: .green
        case .stopped: .orange
        case .noPreview: .secondary
        }
    }

    private var stackPanel: some View {
        Panel(title: "技术栈", symbol: "cpu") {
            if project.stacks.isEmpty {
                Text("未识别")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(project.stacks) { group in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            FlowLayout(spacing: 5) {
                                ForEach(group.items, id: \.self) { item in
                                    TagChip(text: item, tint: group.color)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var runtimePanel: some View {
        Panel(title: "运行与测试", symbol: "play.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                if let run = project.run {
                    KeyValueRow(key: "启动", value: run.command, mono: true)
                    KeyValueRow(
                        key: "端口",
                        value: run.port > 0 ? "\(run.port)" : "无",
                        mono: true,
                        tint: portColor
                    )
                    FlowLayout(spacing: 8) {
                        if project.port == .running {
                            Button {
                                Task { await actions.stop(project, store: store) }
                            } label: {
                                Label(actions.isBusy(project.path) ? "停止中" : "停止", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(actions.isBusy(project.path))

                            if let url = run.previewURL {
                                Button {
                                    SystemActions.openURL(url)
                                } label: {
                                    Label("打开预览", systemImage: "safari")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        } else {
                            Button {
                                Task { await actions.launch(project, store: store) }
                            } label: {
                                Label(actions.isBusy(project.path) ? "启动中" : "启动", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(actions.isBusy(project.path))
                        }

                        CopyButton(title: "复制命令", value: run.command)
                        Button {
                            SystemActions.openTerminal(project.path)
                        } label: {
                            Label("终端", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            actions.openLog(for: project)
                        } label: {
                            Label("日志", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let message = actions.message(for: project.path) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("未识别到 dev 脚本")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let test = project.test {
                    Divider()
                    KeyValueRow(key: "测试", value: test.command, mono: true)
                    FlowLayout(spacing: 8) {
                        CopyButton(title: "复制测试命令", value: test.command, symbol: "checkmark.seal")
                        if let runState = actions.testRun(for: project.path) {
                            Text(testStatusLabel(runState))
                                .font(.caption)
                                .foregroundStyle(testStatusColor(runState.status))
                        }
                    }
                }
            }
        }
    }

    private func testStatusLabel(_ run: TestRunState) -> String {
        switch run.status {
        case .running: "测试运行中…"
        case .passed: "测试通过 · \(String(format: "%.1f", run.duration ?? 0))s"
        case .failed: "测试失败"
        }
    }

    private func testStatusColor(_ status: TestStatus) -> Color {
        switch status {
        case .running: .secondary
        case .passed: .green
        case .failed: .red
        }
    }

    private var notePanel: some View {
        Panel(title: "备注", symbol: "note.text") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("给这个项目留一句话", text: $noteDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .onSubmit(saveNote)
                HStack {
                    Text("\(noteDraft.count)/200")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        saveNote()
                    } label: {
                        Label("保存备注", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var weeklyPanel: some View {
        Panel(title: "本周提交", symbol: "chart.bar") {
            WeeklyBars(weekly: project.weekly)
        }
    }
}

private struct WeeklyBars: View {
    let weekly: [String: Int]

    private var days: [(String, Date?, Int)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let key = formatter.string(from: date)
            return (key, date, weekly[key] ?? 0)
        }
    }

    var body: some View {
        let maxValue = max(1, days.map(\.2).max() ?? 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days.indices, id: \.self) { index in
                let item = days[index]
                VStack(spacing: 6) {
                    Text("\(item.2)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(item.2 == 0 ? .tertiary : .secondary)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(item.2 == 0 ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.75))
                        .frame(height: max(4, CGFloat(item.2) / CGFloat(maxValue) * 54))
                    Text(item.1.map { $0.formatted(.dateTime.day()) } ?? String(item.0.suffix(2)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
