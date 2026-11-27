import SwiftUI

struct GitTabView: View {
    let project: RepoProject
    let detail: ProjectDetail
    let loading: Bool
    let onSyncCompleted: () async -> Void

    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @State private var changes: [GitChange] = []
    @State private var worktrees: [GitWorktree] = []
    @State private var showAdvancedGit = false
    @State private var loadingWorkspace = false
    @State private var expandedPaths: Set<String> = []
    @State private var diffs: [String: GitFileDiff] = [:]
    @State private var loadingDiffs: Set<String> = []
    @State private var commitMessage = ""
    @State private var confirmation: GitConfirmation?
    @State private var runningAction: GitSyncAction?
    @State private var busyOperation: String?
    @State private var feedback: GitSyncFeedback?
    @State private var showInlineSaveVersion = false
    @State private var saveVersionMessage = ""
    @State private var saveVersionIsAIGenerated = false
    @State private var saveVersionHasUserEdited = false
    @State private var saveVersionAlsoPush = false
    @State private var isGeneratingSaveMessage = false
    @State private var envGuardIssue: LightweightProjectIssue?
    @State private var trackedSecretFiles: [String] = []
    @State private var showEnvGuardPanel = false
    @State private var markDiffTarget: SessionMark?

    private var directory: URL {
        URL(fileURLWithPath: project.path)
    }

    private var isBusy: Bool {
        runningAction != nil || busyOperation != nil
    }

    private var stagedCount: Int {
        changes.filter(\.hasStagedChanges).count
    }

    private var unstagedCount: Int {
        changes.filter(\.hasUnstagedChanges).count
    }

    private var hasDirtyChanges: Bool {
        !changes.isEmpty || (detail.git?.changedCount ?? 0) > 0
    }

    var body: some View {
        if loading {
            ProgressView("读取 Git 信息…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let git = detail.git {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusPanel(git)
                    if copyMode == .plain && showInlineSaveVersion {
                        inlineSaveVersionCard(git)
                    }
                    commitPanel
                    filesPanel(git)
                    if copyMode == .pro {
                        branchesPanel(git)
                        worktreesPanel
                    } else {
                        DisclosureGroup("进阶选项（分支、工作树、暂存）", isExpanded: $showAdvancedGit) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 8) {
                                    Button(FizzCopy.stashAction(.plain).text) {
                                        performFileWrite("暂存当前改动") {
                                            await GitService.stashPush(in: directory)
                                        }
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                    .disabled(isBusy || !hasDirtyChanges)
                                    .help(FizzCopy.stashAction(.plain).proHint ?? "")

                                    Button("取回之前收起的改动") {
                                        confirmation = .stashRestore
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                    .disabled(isBusy || git.stashCount == 0)
                                }
                                branchesPanel(git)
                                worktreesPanel
                            }
                            .padding(.top, 10)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    commitsPanel
                }
                .padding(24)
            }
            .fizzTracksScrollPastTop()
            .safeAreaInset(edge: .top, spacing: 0) {
                if let feedback {
                    feedbackBanner(feedback)
                }
            }
            .task(id: project.path) {
                await loadWorkspace()
            }
            .onChange(of: store.requestedSaveVersionForPath) {
                if store.requestedSaveVersionForPath == project.path {
                    store.requestedSaveVersionForPath = nil
                    openInlineSaveVersion()
                }
            }
            .alert(item: $confirmation) { confirmation in
                alert(for: confirmation)
            }
            .sheet(item: $markDiffTarget) { mark in
                MarkDiffRestoreSheet(project: project, mark: mark) {
                    await refreshAfterWrite()
                }
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
        let changeCount = changes.isEmpty ? git.changedCount : changes.count
        let statusSentence = FizzCopy.projectStatusSummary(
            dirtyCount: changeCount,
            ahead: git.ahead,
            behind: git.behind,
            mode: copyMode
        )

        return Panel(
            title: copyMode == .plain ? "当前版本状态" : "状态",
            symbol: "point.3.connected.trianglepath.dotted",
            content: {
                if copyMode == .plain {
                    HStack(spacing: 10) {
                        Text(statusSentence)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(hasDirtyChanges ? .primary : .secondary)
                            .help("分支：\(project.branch ?? "—") · ↑\(git.ahead) ↓\(git.behind)")
                        Spacer(minLength: 8)
                        if hasDirtyChanges {
                            Button(showInlineSaveVersion ? "收起" : "存个版本") {
                                if showInlineSaveVersion {
                                    showInlineSaveVersion = false
                                } else {
                                    openInlineSaveVersion()
                                }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(FizzTheme.accent)
                            .controlSize(.small)
                            .disabled(isBusy)
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240), spacing: 20)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        KeyValueRow(key: "当前分支", value: project.branch ?? "—", mono: true)
                        KeyValueRow(
                            key: "未提交",
                            value: "\(changeCount) 个改动",
                            tint: hasDirtyChanges ? .orange : .secondary
                        )
                        KeyValueRow(key: "领先 / 落后", value: "↑ \(git.ahead)  ↓ \(git.behind)", mono: true)
                        KeyValueRow(key: "Stash", value: "\(git.stashCount)")
                        KeyValueRow(key: "已暂存 / 未暂存", value: "\(stagedCount) / \(unstagedCount)", mono: true)
                        KeyValueRow(key: "最近标签", value: git.lastTag ?? "—", mono: true)
                    }
                }
                if let remote = git.remote {
                    Divider()
                        .padding(.vertical, 6)
                    remoteRow(remote)
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
                        confirmation = .sync(action)
                    } label: {
                        Group {
                            if runningAction == action {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                FizzIcon(symbol: symbol(for: action), size: 11)
                                    .foregroundStyle(tint(for: action))
                            }
                        }
                        .frame(width: 28, height: 26)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || loading)
                    .help(syncTooltip(for: action))
                    .accessibilityLabel(syncTooltip(for: action))
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .fizzAdaptiveShadow(.subtle)
    }

    private func feedbackLine(_ feedback: GitSyncFeedback) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            FizzIcon(
                symbol: feedback.failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                size: 12
            )
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

    private func feedbackBanner(_ feedback: GitSyncFeedback) -> some View {
        feedbackLine(feedback)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(FizzTheme.elevatedFill)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FizzTheme.hairline)
                    .frame(height: 1)
            }
    }

    private func remoteRow(_ remote: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("远程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let parsed = GitRemote(raw: remote), let url = parsed.webURL {
                    Button {
                        SystemActions.openURL(url.absoluteString)
                    } label: {
                        FizzIcon(symbol: "arrow.up.right.square", size: 11)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("在浏览器中打开远程仓库")
                    .accessibilityLabel("在浏览器中打开远程仓库")
                }
                Button {
                    SystemActions.copy(remote)
                } label: {
                    FizzIcon(symbol: "doc.on.doc", size: 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("复制远程地址")
                .accessibilityLabel("复制远程地址")
            }
            Text(verbatim: remote)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var commitPanel: some View {
        let commitCopy = FizzCopy.commitAction(copyMode)
        let commitPushCopy = FizzCopy.commitAndPushAction(copyMode)

        return Panel(title: commitCopy.text, symbol: "arrow.up.circle") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    TextField(copyMode == .plain ? "写一句这次改了什么" : "一行提交信息", text: $commitMessage)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            FizzTheme.recessedFill,
                            in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                                .strokeBorder(FizzTheme.hairline, lineWidth: 1)
                        }
                        .onSubmit {
                            performCommit(push: false)
                        }
                        .disabled(isBusy)

                    Button(commitCopy.text) {
                        performCommit(push: false)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(!canCommit)
                    .help(commitCopy.proHint ?? "提交已暂存改动")

                    Button(commitPushCopy.text) {
                        performCommit(push: true)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(FizzTheme.accent)
                    .controlSize(.small)
                    .disabled(!canCommit)
                    .help(commitPushCopy.proHint ?? "提交已暂存改动并推送当前分支")
                }

                HStack(spacing: 6) {
                    Text(stagedCount > 0
                        ? (copyMode == .plain ? "已选中 \(stagedCount) 个要存的文件" : "已暂存 \(stagedCount) 个文件")
                        : (copyMode == .plain ? "先点下方文件旁的 + 选中要存的改动" : "先暂存文件再提交"))
                        .font(.caption)
                        .foregroundStyle(stagedCount > 0 ? .secondary : .tertiary)
                    Spacer(minLength: 8)
                    if let busyOperation {
                        ProgressView()
                            .controlSize(.mini)
                        Text(busyOperation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && stagedCount > 0
            && !isBusy
    }

    private func syncTooltip(for action: GitSyncAction) -> String {
        guard copyMode == .plain else { return action.title }
        switch action {
        case .fetch: return "检查云端有没有更新"
        case .pull: return FizzCopy.pullAction(.plain).text
        case .push: return "上传已存版本到云端"
        }
    }

    private func filesPanel(_ git: GitDetail) -> some View {
        let dirtyCopy = FizzCopy.uncommittedChanges(mode: copyMode)
        return Panel(
            title: dirtyCopy.text,
            symbol: "square.and.pencil",
            content: {
                if loadingWorkspace && changes.isEmpty {
                    ProgressView("读取改动…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if changes.isEmpty {
                    Text(copyMode == .plain ? "没有还没存的改动" : "工作区干净")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(changes) { change in
                            fileRow(change)
                            if change.id != changes.last?.id {
                                Divider()
                                    .opacity(0.25)
                            }
                        }
                    }
                }
            },
            accessory: {
                fileActions(git)
            }
        )
    }

    private func fileActions(_ git: GitDetail) -> some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 1) {
                actionIcon(
                    "全部暂存",
                    symbol: "plus",
                    disabled: isBusy || changes.allSatisfy { !$0.hasUnstagedChanges }
                ) {
                    performFileWrite("暂存全部改动") {
                        await GitService.stageAll(in: directory)
                    }
                }

                actionIcon(
                    "全部取消暂存",
                    symbol: "minus",
                    disabled: isBusy || stagedCount == 0
                ) {
                    performFileWrite("取消全部暂存") {
                        await GitService.unstageAll(in: directory)
                    }
                }

                if copyMode == .pro {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)

                    actionIcon(
                        "暂存当前改动",
                        symbol: "archivebox",
                        disabled: isBusy || !hasDirtyChanges
                    ) {
                        performFileWrite("暂存当前改动") {
                            await GitService.stashPush(in: directory)
                        }
                    }

                    actionIcon(
                        "恢复最近一次 Stash",
                        symbol: "arrow.uturn.backward",
                        disabled: isBusy || git.stashCount == 0
                    ) {
                        confirmation = .stashRestore
                    }
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .fizzAdaptiveShadow(.subtle)
    }

    private func actionIcon(
        _ title: String,
        symbol: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            FizzIcon(symbol: symbol, size: 10)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.45) : Color.secondary)
                .frame(width: 25, height: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func fileRow(_ change: GitChange) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                    toggleDiff(change)
                }
            } label: {
                HStack(spacing: 9) {
                    Text(change.displayCode)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(codeColor(change))
                        .frame(width: 24)
                        .padding(.vertical, 2)
                        .background(
                            codeColor(change).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: FizzRadius.micro)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 5) {
                            if change.hasStagedChanges {
                                Text("已暂存")
                                    .foregroundStyle(.green)
                            }
                            if change.hasUnstagedChanges {
                                Text("未暂存")
                                    .foregroundStyle(.orange)
                            }
                            if let original = change.originalPath {
                                Text("← \(original)")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.system(size: 9.5))
                    }

                    Spacer(minLength: 0)

                    FizzIcon(
                        symbol: "chevron.right",
                        size: 8
                    )
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expandedPaths.contains(change.path) ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(change.path) Diff")
            .accessibilityHint(expandedPaths.contains(change.path) ? "收起 Diff" : "展开 Diff")

            if change.hasUnstagedChanges {
                compactButton("暂存", help: "暂存 \(change.path)") {
                    performFileWrite("暂存 \(change.path)") {
                        await GitService.stage([change.path], in: directory)
                    }
                }
            }
            if change.hasStagedChanges {
                compactButton("取消暂存", help: "取消暂存 \(change.path)") {
                    performFileWrite("取消暂存 \(change.path)") {
                        await GitService.unstage([change.path], in: directory)
                    }
                }
            }
        }
        .padding(.vertical, 5)

        if expandedPaths.contains(change.path) {
            diffView(change)
                .padding(.leading, 33)
                .padding(.bottom, 7)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func compactButton(
        _ title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.glass)
            .controlSize(.mini)
            .disabled(isBusy)
            .help(help)
            .accessibilityLabel(help)
    }

    @ViewBuilder
    private func diffView(_ change: GitChange) -> some View {
        if loadingDiffs.contains(change.path) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("读取 Diff…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else if let diff = diffs[change.path] {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if diff.additions > 0 {
                        Text("+\(diff.additions)")
                            .foregroundStyle(.green)
                    }
                    if diff.deletions > 0 {
                        Text("-\(diff.deletions)")
                            .foregroundStyle(.red)
                    }
                    if diff.truncated {
                        Text("已截断")
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))

                if let note = diff.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !diff.isEmpty {
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(diff.sections) { section in
                                diffSection(section)
                            }
                        }
                    }
                    .frame(height: 260)
                    .background(
                        FizzTheme.recessedFill,
                        in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                            .strokeBorder(FizzTheme.hairline, lineWidth: 1)
                    }
                }
            }
        } else {
            Text("没有可显示的 Diff")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    private func diffSection(_ section: GitDiffSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FizzTheme.elevatedFill.opacity(0.6))

            ForEach(section.lines) { line in
                diffLine(line)
            }
        }
    }

    private func diffLine(_ line: GitDiffLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(foreground(for: line.kind))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(background(for: line.kind))
    }

    private func background(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .addition: .green.opacity(0.11)
        case .deletion: .red.opacity(0.11)
        case .hunk: .blue.opacity(0.08)
        default: .clear
        }
    }

    private func foreground(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .blue
        case .meta: .secondary
        case .header: .secondary
        case .context: .primary
        }
    }

    private func branchesPanel(_ git: GitDetail) -> some View {
        Panel(title: "分支", symbol: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                ForEach(Array(git.branches.prefix(30))) { branch in
                    HStack(spacing: 8) {
                        FizzIcon(
                            symbol: branch.name == project.branch ? "checkmark.circle.fill" : "circle",
                            size: 10
                        )
                        .foregroundStyle(branch.name == project.branch ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(branch.name)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            if let upstream = branch.upstream {
                                Text(upstream)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        if branch.name != project.branch {
                            compactButton("切换", help: "切换到 \(branch.name)") {
                                requestBranchSwitch(branch)
                            }
                        }
                    }
                    .padding(.vertical, 5)

                    if branch.id != git.branches.prefix(30).last?.id {
                        Divider()
                            .opacity(0.25)
                    }
                }
            }
        }
    }

    private var worktreesPanel: some View {
        Panel(title: "关联 Worktree", symbol: "rectangle.stack") {
            if worktrees.isEmpty {
                Text("没有读取到 Worktree 信息")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(worktrees) { worktree in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(worktree.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                    if worktree.isMain {
                                        badge("主仓")
                                    }
                                    if worktree.isDetached {
                                        badge("detached")
                                    }
                                    if worktree.isLocked {
                                        badge("locked")
                                    }
                                    if worktree.isPrunable {
                                        badge("可清理")
                                    }
                                }
                                Text(verbatim: PathTools.displayPath(worktree.path))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(worktree.branch ?? worktree.head ?? "—")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            worktreeButton("在 Finder 显示", symbol: "folder") {
                                SystemActions.reveal(worktree.path)
                            }
                            worktreeButton("在终端打开", symbol: "terminal") {
                                SystemActions.openTerminal(worktree.path)
                            }
                            worktreeButton("打开目录", symbol: "arrow.up.forward.app") {
                                SystemActions.open(worktree.path)
                            }
                        }
                        .padding(.vertical, 7)

                        if worktree.id != worktrees.last?.id {
                            Divider()
                                .opacity(0.25)
                        }
                    }
                }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(FizzTheme.recessedFill, in: Capsule())
    }

    private func worktreeButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            FizzIcon(symbol: symbol, size: 10)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var mixedTimelineEntries: [VersionTimelineEntry] {
        var entries: [VersionTimelineEntry] = detail.commits.map { .commit($0) }
        entries.append(contentsOf: store.marks(for: project.path).map { .mark($0) })
        return entries.sorted { $0.sortDate > $1.sortDate }
    }

    private var commitsPanel: some View {
        Panel(
            title: copyMode == .plain ? "历史记录（真实版本与 AI 标记）" : "最近提交",
            symbol: "clock.arrow.circlepath"
        ) {
            let entries = mixedTimelineEntries
            if entries.isEmpty {
                Text("还没有历史记录")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .commit(let commit):
                            HStack(alignment: .top, spacing: 10) {
                                FizzIcon(symbol: "circle.fill", size: 8)
                                    .foregroundStyle(FizzTheme.accent)
                                    .padding(.top, 4)
                                Text(commit.hash)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(commit.subject)
                                        .font(.callout)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        if copyMode == .plain {
                                            TagChip(text: "真实版本", tint: .secondary, compact: true)
                                        }
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

                        case .mark(let mark):
                            HStack(alignment: .top, spacing: 10) {
                                FizzIcon(
                                    symbol: mark.kind == .gitSnapshot ? "diamond.fill" : "diamond",
                                    size: 9
                                )
                                .foregroundStyle(mark.kind == .gitSnapshot ? .teal : .secondary)
                                .padding(.top, 4)

                                Text("AI 标记")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.teal)
                                    .frame(width: 54, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mark.label ?? "对话开始前的样子")
                                        .font(.callout)
                                    HStack(spacing: 6) {
                                        TagChip(
                                            text: mark.kind == .gitSnapshot ? "可还原标记" : "纯记录",
                                            tint: mark.kind == .gitSnapshot ? .teal : .secondary,
                                            compact: true
                                        )
                                        if mark.pinned {
                                            TagChip(text: "⭐ 已保留", tint: .orange, compact: true)
                                        }
                                        Text(Format.relative(mark.createdAt))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.caption2)
                                }

                                Spacer(minLength: 8)

                                if mark.kind == .gitSnapshot {
                                    Button("看变化") {
                                        markDiffTarget = mark
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 7)
                        }

                        if entry.id != entries.last?.id {
                            Divider()
                                .opacity(0.25)
                        }
                    }
                }
            }
        }
    }

    private func inlineSaveVersionCard(_ git: GitDetail) -> some View {
        let hasSecretRisk = envGuardIssue != nil || !trackedSecretFiles.isEmpty
        let shouldBlockPush = saveVersionAlsoPush && hasSecretRisk

        return Panel(title: "存个版本", symbol: "bookmark.circle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("写一句这次改了什么", text: Binding(
                        get: { saveVersionMessage },
                        set: { newValue in
                            if newValue != saveVersionMessage {
                                saveVersionHasUserEdited = true
                                saveVersionIsAIGenerated = false
                            }
                            saveVersionMessage = newValue
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        FizzTheme.recessedFill,
                        in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                            .strokeBorder(FizzTheme.hairline, lineWidth: 1)
                    }
                    .disabled(isBusy)

                    if isGeneratingSaveMessage {
                        ProgressView()
                            .controlSize(.mini)
                    } else if saveVersionIsAIGenerated {
                        TagChip(text: "✦ AI 拟定", tint: FizzTheme.accent, compact: true)
                    }
                }

                HStack(spacing: 12) {
                    if git.remote != nil {
                        Toggle("同时上传到云端", isOn: $saveVersionAlsoPush)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }

                    Spacer(minLength: 8)

                    Button("取消") {
                        showInlineSaveVersion = false
                        showEnvGuardPanel = false
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isBusy)

                    if shouldBlockPush {
                        Button("先处理密钥风险") {
                            showEnvGuardPanel.toggle()
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    } else {
                        Button(saveVersionAlsoPush ? "保存并上传" : "确认保存") {
                            performSaveVersion(push: saveVersionAlsoPush)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(FizzTheme.accent)
                        .controlSize(.small)
                        .disabled(saveVersionMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                    }
                }

                if showEnvGuardPanel && hasSecretRisk {
                    VStack(alignment: .leading, spacing: 8) {
                        if let envGuardIssue {
                            HStack(spacing: 6) {
                                FizzIcon(symbol: "exclamationmark.shield.fill", size: 13)
                                    .foregroundStyle(.orange)
                                Text(envGuardIssue.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            Text(envGuardIssue.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("把 .env 加入忽略列表") {
                                Task { await fixEnvGitignore() }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        }
                        if !trackedSecretFiles.isEmpty {
                            HStack(spacing: 6) {
                                FizzIcon(symbol: "key.fill", size: 12)
                                    .foregroundStyle(.red)
                                Text("已跟踪文件疑似含密钥：\(trackedSecretFiles.prefix(3).joined(separator: "、"))")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text("建议先把真实密钥移到 .env 再上传到云端，避免泄露。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.orange.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    )
                }
            }
        }
    }

    private func openInlineSaveVersion() {
        showInlineSaveVersion = true
        showEnvGuardPanel = false
        saveVersionHasUserEdited = false
        saveVersionIsAIGenerated = false
        saveVersionMessage = CommitMessageGenerator.ruleBased(
            project: project,
            changedFiles: changes.map(\.path),
            copyMode: copyMode
        )

        guard SummaryPreferences.isEnabled() else { return }
        let filePaths = changes.map(\.path)
        Task {
            isGeneratingSaveMessage = true
            defer { isGeneratingSaveMessage = false }
            if let aiMessage = await SummaryEngine.shared.generateCommitMessage(
                for: project,
                changedFiles: filePaths,
                copyMode: copyMode
            ), !saveVersionHasUserEdited {
                saveVersionMessage = aiMessage
                saveVersionIsAIGenerated = true
            }
        }
    }

    private func performSaveVersion(push: Bool) {
        let message = saveVersionMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isBusy else { return }
        performFileWrite(
            push ? "保存并上传版本" : "存个版本",
            onSuccess: {
                showInlineSaveVersion = false
                saveVersionMessage = ""
                showEnvGuardPanel = false
            }
        ) {
            let stageResult = await GitService.stageAll(in: directory)
            guard stageResult.succeeded else { return stageResult }
            if push {
                return await GitService.commitAndPush(message, in: directory)
            }
            return await GitService.commit(message, in: directory)
        }
    }

    private func fixEnvGitignore() async {
        guard LightweightProjectCheckService.addEnvFilesToGitignore(in: directory) else { return }
        let issues = await LightweightProjectCheckService.check(directory: directory, copyMode: copyMode)
        envGuardIssue = issues.first { $0.kind == .unignoredEnvFile }
        showEnvGuardPanel = envGuardIssue != nil
        await refreshAfterWrite()
        ToastCenter.shared.show(
            "已把 .env 加入忽略列表",
            symbol: "checkmark.shield.fill",
            tint: .green,
            subtitle: "之后上传代码不会泄露这些密钥文件"
        )
    }

    private func toggleDiff(_ change: GitChange) {
        if expandedPaths.contains(change.path) {
            expandedPaths.remove(change.path)
            return
        }
        expandedPaths.insert(change.path)
        guard diffs[change.path] == nil, !loadingDiffs.contains(change.path) else { return }
        loadingDiffs.insert(change.path)
        Task {
            let diff = await GitService.fileDiff(for: change, in: directory)
            guard !Task.isCancelled else { return }
            diffs[change.path] = diff
            loadingDiffs.remove(change.path)
        }
    }

    private func perform(_ action: GitSyncAction) async {
        guard !isBusy else { return }
        runningAction = action
        feedback = nil

        let result = await GitSyncService.run(action, in: directory)
        feedback = GitSyncFeedback(
            message: result.message,
            failed: !result.succeeded,
            date: Date()
        )
        if result.succeeded {
            ToastCenter.shared.show(
                result.message,
                symbol: "arrow.triangle.branch",
                tint: FizzTheme.accent,
                subtitle: project.displayName,
                microViz: .gitMerge
            )
        }
        await refreshAfterWrite()
        runningAction = nil
    }

    private func performFileWrite(
        _ operation: String,
        onSuccess: @escaping () -> Void = {},
        action: @escaping () async -> GitActionResult
    ) {
        guard !isBusy else { return }
        busyOperation = operation
        feedback = nil
        Task {
            let result = await action()
            feedback = GitSyncFeedback(
                message: result.message,
                failed: !result.succeeded,
                date: Date()
            )
            if result.succeeded {
                ToastCenter.shared.show(
                    result.message,
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    subtitle: project.displayName,
                    microViz: microViz(for: operation)
                )
            }
            if result.didMutate {
                onSuccess()
                diffs.removeAll()
                expandedPaths.removeAll()
            }
            await refreshAfterWrite()
            busyOperation = nil
        }
    }

    private func performCommit(push: Bool) {
        guard canCommit else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        performFileWrite(
            push ? "提交并推送" : "提交",
            onSuccess: { commitMessage = "" }
        ) {
            if push {
                return await GitService.commitAndPush(message, in: directory)
            }
            return await GitService.commit(message, in: directory)
        }
    }

    private func requestBranchSwitch(_ branch: BranchInfo) {
        guard branch.name != project.branch, !isBusy else { return }
        if hasDirtyChanges {
            confirmation = .switchBranch(branch)
        } else {
            switchBranch(branch)
        }
    }

    private func switchBranch(_ branch: BranchInfo) {
        performFileWrite("切换到 \(branch.name)") {
            await GitService.switchBranch(branch.name, in: directory)
        }
    }

    private func performStashRestore() {
        performFileWrite("恢复 Stash") {
            await GitService.stashPop(in: directory)
        }
    }

    private func refreshAfterWrite() async {
        await loadWorkspace()
        await onSyncCompleted()
    }

    private func loadWorkspace() async {
        loadingWorkspace = true
        async let changesTask = GitService.changes(directory)
        async let worktreesTask = GitWorktreeService.list(in: directory)
        async let checkTask = LightweightProjectCheckService.check(directory: directory, copyMode: copyMode)
        async let secretsTask = DoctorService.findTrackedSecretFiles(in: directory)
        let (freshChanges, freshWorktrees, issues, secretFiles) = await (changesTask, worktreesTask, checkTask, secretsTask)
        guard !Task.isCancelled else { return }
        changes = freshChanges
        worktrees = freshWorktrees
        envGuardIssue = issues.first { $0.kind == .unignoredEnvFile }
        trackedSecretFiles = secretFiles
        let paths = Set(freshChanges.map(\.path))
        diffs = diffs.filter { path, _ in paths.contains(path) }
        loadingWorkspace = false
        if store.requestedSaveVersionForPath == project.path {
            store.requestedSaveVersionForPath = nil
            openInlineSaveVersion()
        }
    }

    private func alert(for confirmation: GitConfirmation) -> Alert {
        switch confirmation {
        case .sync(let action):
            Alert(
                title: Text("\(action.title) \(project.displayName)？"),
                message: Text(action.confirmation),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .default(Text(action.title)) {
                    Task { await perform(action) }
                }
            )
        case .switchBranch(let branch):
            Alert(
                title: Text("切换到 \(branch.name)？"),
                message: Text("当前有未提交改动。Git 会尝试保留改动；如与目标分支冲突，切换会失败并保持现场。"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .default(Text("继续切换")) {
                    switchBranch(branch)
                }
            )
        case .stashRestore:
            Alert(
                title: Text("恢复最近一次 Stash？"),
                message: Text("当前工作区改动可能与 Stash 冲突。冲突时会保留 Stash，不会静默丢弃。"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .default(Text("恢复")) {
                    performStashRestore()
                }
            )
        }
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

    private func codeColor(_ change: GitChange) -> Color {
        if change.untracked { return .blue }
        if change.conflicted { return .red }
        if change.isDeleted { return .red }
        if change.displayCode.contains("A") { return .green }
        if change.displayCode.contains("M") { return .orange }
        return .secondary
    }

    private func microViz(for operation: String) -> ToastMicroViz {
        if operation.contains("暂存") || operation.contains("Stash") {
            let additions = diffs.values.reduce(0) { $0 + $1.additions }
            let deletions = diffs.values.reduce(0) { $0 + $1.deletions }
            return .diff(added: additions, removed: deletions)
        }
        return .gitMerge
    }
}

private enum GitConfirmation: Identifiable {
    case sync(GitSyncAction)
    case switchBranch(BranchInfo)
    case stashRestore

    var id: String {
        switch self {
        case .sync(let action): "sync-\(action.rawValue)"
        case .switchBranch(let branch): "branch-\(branch.name)"
        case .stashRestore: "stash-restore"
        }
    }
}

private struct GitSyncFeedback {
    let message: String
    let failed: Bool
    let date: Date
}

private enum VersionTimelineEntry: Identifiable {
    case commit(Commit)
    case mark(SessionMark)

    var id: String {
        switch self {
        case .commit(let commit): "commit-\(commit.hash)"
        case .mark(let mark): "mark-\(mark.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .commit(let commit): commit.date ?? .distantPast
        case .mark(let mark): mark.createdAt
        }
    }
}
