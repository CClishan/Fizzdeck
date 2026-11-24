import SwiftUI

struct GitTabView: View {
    let project: RepoProject
    let detail: ProjectDetail
    let loading: Bool
    let onSyncCompleted: () async -> Void

    @State private var pendingAction: GitSyncAction?
    @State private var runningAction: GitSyncAction?
    @State private var feedback: GitSyncFeedback?

    var body: some View {
        if loading {
            ProgressView("读取 Git 信息…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let git = detail.git {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusPanel(git)
                    filesPanel(git)
                    branchesPanel(git)
                    commitsPanel
                }
                .padding(24)
            }
            .alert(item: $pendingAction) { action in
                Alert(
                    title: Text("\(action.title) \(project.displayName)？"),
                    message: Text(action.confirmation),
                    primaryButton: .cancel(Text("取消")),
                    secondaryButton: .default(Text(action.title)) {
                        Task { await perform(action) }
                    }
                )
            }
        } else {
            ContentUnavailableView(
                "不是 Git 仓库",
                systemImage: "arrow.triangle.branch",
                description: Text("这个目录没有 .git，仍可在概览里查看体积和文件信息。")
            )
        }
    }

    private func statusPanel(_ git: GitDetail) -> some View {
        Panel(
            title: "状态",
            symbol: "point.3.connected.trianglepath.dotted",
            content: {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 20)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    KeyValueRow(key: "当前分支", value: project.branch ?? "—", mono: true)
                    KeyValueRow(key: "未提交", value: "\(git.changedCount) 个改动", tint: git.changedCount > 0 ? .orange : .secondary)
                    KeyValueRow(key: "领先 / 落后", value: "↑ \(git.ahead)  ↓ \(git.behind)", mono: true)
                    KeyValueRow(key: "Stash", value: "\(git.stashCount)")
                    KeyValueRow(key: "最近标签", value: git.lastTag ?? "—", mono: true)
                    KeyValueRow(key: "分支数", value: "\(git.branches.count)")
                }
                if let feedback {
                    Divider()
                        .padding(.vertical, 6)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: feedback.failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(feedback.failed ? Color.red : Color.green)
                        Text(feedback.message)
                            .font(.caption)
                            .foregroundStyle(feedback.failed ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(Format.relative(feedback.date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let remote = git.remote {
                    Divider()
                        .padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("远程")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: remote)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
            },
            accessory: {
                syncControls
            }
        )
    }

    private var syncControls: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 1) {
                ForEach(GitSyncAction.allCases) { action in
                    Button {
                        pendingAction = action
                    } label: {
                        Group {
                            if runningAction == action {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: symbol(for: action))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(tint(for: action))
                            }
                        }
                        .frame(width: 28, height: 26)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(runningAction != nil || loading)
                    .help(action.title)
                    .accessibilityLabel(action.title)
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func perform(_ action: GitSyncAction) async {
        guard runningAction == nil else { return }
        runningAction = action
        feedback = nil

        let result = await GitSyncService.run(
            action,
            in: URL(fileURLWithPath: project.path)
        )
        feedback = GitSyncFeedback(
            message: result.message,
            failed: !result.succeeded,
            date: Date()
        )
        if result.succeeded {
            await onSyncCompleted()
        }
        runningAction = nil
    }

    private func symbol(for action: GitSyncAction) -> String {
        switch action {
        case .fetch: "arrow.triangle.2.circlepath"
        case .pull: "arrow.down"
        case .push: "arrow.up"
        }
    }

    private func tint(for action: GitSyncAction) -> Color {
        switch action {
        case .fetch: .blue
        case .pull: .teal
        case .push: .purple
        }
    }

    private func filesPanel(_ git: GitDetail) -> some View {
        Panel(title: "未提交改动", symbol: "square.and.pencil") {
            if git.files.isEmpty {
                Text("工作区干净")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(git.files.prefix(60)) { file in
                        HStack(spacing: 9) {
                            Text(file.code.isEmpty ? "??" : file.code)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(codeColor(file.code))
                                .frame(width: 24)
                                .padding(.vertical, 2)
                                .background(codeColor(file.code).opacity(0.11), in: RoundedRectangle(cornerRadius: 4))
                            Text(file.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        if file != git.files.prefix(60).last {
                            Divider()
                                .opacity(0.25)
                        }
                    }
                }
                if git.files.count > 60 {
                    Text("另有 \(git.files.count - 60) 个文件未显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func branchesPanel(_ git: GitDetail) -> some View {
        Panel(title: "分支", symbol: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                ForEach(Array(git.branches.prefix(20))) { branch in
                    HStack(spacing: 8) {
                        Image(systemName: branch.name == project.branch ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(branch.name == project.branch ? .green : .secondary)
                        Text(branch.name)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        if let upstream = branch.upstream {
                            Text(upstream)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var commitsPanel: some View {
        Panel(title: "最近提交", symbol: "clock.arrow.circlepath") {
            if detail.commits.isEmpty {
                Text("没有提交记录")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(detail.commits) { commit in
                        HStack(alignment: .top, spacing: 10) {
                            Text(commit.hash)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(commit.subject)
                                    .font(.callout)
                                    .lineLimit(2)
                                HStack(spacing: 6) {
                                    Text(commit.author)
                                    Text("·")
                                    Text(Format.relative(commit.date))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        if commit != detail.commits.last {
                            Divider()
                                .opacity(0.25)
                        }
                    }
                }
            }
        }
    }

    private func codeColor(_ code: String) -> Color {
        if code.hasPrefix("??") { return .blue }
        if code.contains("D") { return .red }
        if code.contains("A") { return .green }
        if code.contains("M") { return .orange }
        return .secondary
    }
}

private struct GitSyncFeedback {
    let message: String
    let failed: Bool
    let date: Date
}
