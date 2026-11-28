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
    @State private var worktreeRefresh = 0
    @State private var worktreeWriteInProgress = false
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

    private var isGitWriteInProgress: Bool {
        runningAction != nil || busyOperation != nil
    }

    private var isBusy: Bool {
        isGitWriteInProgress || worktreeWriteInProgress
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
                .font(FizzTypography.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let git = detail.git {
            ScrollView {
                VStack(alignment: .leading, spacing: FizzSpacing.section) {
                    statusPanel(git)
                    if copyMode == .plain && showInlineSaveVersion {
                        inlineSaveVersionCard(git)
                    }
                    commitPanel
                    GitWorktreePanel(
                        directory: directory,
                        gitRefresh: worktreeRefresh,
                        gitIsBusy: isGitWriteInProgress,
                        isWriting: $worktreeWriteInProgress,
                        onGitChanged: refreshAfterWorktreeWrite
                    )
                    filesPanel(git)
                    if copyMode == .pro {
                        branchesPanel(git)
                    } else {
                        DisclosureGroup("进阶选项（分支）", isExpanded: $showAdvancedGit) {
                            branchesPanel(git)
                                .padding(.top, FizzSpacing.grid)
                        }
                        .font(FizzTypography.body(.medium))
                        .foregroundStyle(.secondary)
                    }
                    commitsPanel
                }
                .padding(FizzSpacing.page)
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
        } else if GitService.hasGit(directory) {
            ProgressView("读取版本记录…")
                .font(FizzTypography.body)
                .task { await onSyncCompleted() }
        } else {
            ScrollView {
                Panel(title: "还没有开启版本保护", symbol: "arrow.triangle.branch") {
                    Text("开启后可从第一条基线查看变化或还原文件。")
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                } accessory: {
                    EnableVersionProtectionButton(project: project, prominence: .primary)
                }
                .padding(FizzSpacing.page)
            }
            .fizzTracksScrollPastTop()
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
                    Text(statusSentence)
                        .font(FizzTypography.body(.medium))
                        .foregroundStyle(hasDirtyChanges ? .primary : .secondary)
                        .help("分支：\(project.branch ?? "—") · ↑\(git.ahead) ↓\(git.behind)")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240), spacing: FizzSpacing.section)],
                        alignment: .leading,
                        spacing: FizzSpacing.row
                    ) {
                        KeyValueRow(key: "当前分支", value: project.branch ?? "—", mono: true)
                        KeyValueRow(
                            key: "未提交",
                            value: "\(changeCount) 个改动",
                            tint: hasDirtyChanges ? FizzTheme.statusWarning : .secondary
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
                HStack(spacing: FizzSpacing.row) {
                    if let runningAction {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("\(runningAction.title)进行中")
                    }

                    syncMenu

                    if copyMode == .plain, hasDirtyChanges {
                        if showInlineSaveVersion {
                            FizzActionButton(title: "收起", height: .compact) {
                                showInlineSaveVersion = false
                            }
                            .disabled(isBusy)
                        } else {
                            FizzActionButton(title: "存个版本", height: .compact, prominence: .primary) {
                                openInlineSaveVersion()
                            }
                            .disabled(isBusy)
                        }
                    }
                }
            }
        )
    }

    private var syncMenu: some View {
        FizzMenuButton(title: "同步远程仓库") {
            ForEach(GitSyncAction.allCases) { action in
                Button(syncMenuTitle(for: action), systemImage: symbol(for: action)) {
                    confirmation = .sync(action)
                }
            }
        }
        .disabled(isBusy || loading)
    }

    private func feedbackLine(_ feedback: GitSyncFeedback) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            FizzIcon(.sm, symbol: feedback.failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(.secondary)
            Text(feedback.message)
                .font(FizzTypography.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(Format.relative(feedback.date))
                .font(FizzTypography.micro)
                .foregroundStyle(.tertiary)
        }
    }

    private func feedbackBanner(_ feedback: GitSyncFeedback) -> some View {
        feedbackLine(feedback)
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.row)
            .background(FizzTheme.elevatedFill)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FizzTheme.hairline)
                    .frame(height: 1)
            }
    }

    private func remoteRow(_ remote: String) -> some View {
        HStack(spacing: FizzSpacing.row) {
            VStack(alignment: .leading, spacing: 4) {
                Text("远程")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: remote)
                    .font(FizzTypography.mono)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            FizzIconButton(title: "复制远程地址", symbol: "doc.on.doc", height: .compact) {
                SystemActions.copy(remote)
            }
            if let parsed = GitRemote(raw: remote), let url = parsed.webURL {
                FizzIconButton(title: "在浏览器中打开远程仓库", symbol: "arrow.up.right.square", height: .compact) {
                    SystemActions.openURL(url.absoluteString)
                }
            }
        }
    }

    private var commitPanel: some View {
        let commitCopy = FizzCopy.commitAction(copyMode)
        let commitPushCopy = FizzCopy.commitAndPushAction(copyMode)

        return Panel(title: commitCopy.text, symbol: "arrow.up.circle") {
            VStack(alignment: .leading, spacing: FizzSpacing.row) {
                TextField(copyMode == .plain ? "写一句这次改了什么" : "一行提交信息", text: $commitMessage)
                    .textFieldStyle(.plain)
                    .font(FizzTypography.body)
                    .padding(.horizontal, 10)
                    .frame(height: FizzControlHeight.standard.rawValue)
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

                HStack(spacing: 6) {
                    Text(stagedCount > 0
                        ? (copyMode == .plain ? "已选中 \(stagedCount) 个要存的文件" : "已暂存 \(stagedCount) 个文件")
                        : (copyMode == .plain ? "先点下方文件旁的「暂存」选中要存的改动" : "先暂存文件再提交"))
                        .font(FizzTypography.caption)
                        .foregroundStyle(stagedCount > 0 ? .secondary : .tertiary)
                    Spacer(minLength: 8)
                    if let busyOperation {
                        ProgressView()
                            .controlSize(.mini)
                        Text(busyOperation)
                            .font(FizzTypography.micro)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } accessory: {
            HStack(spacing: FizzSpacing.row) {
                FizzActionButton(title: commitCopy.text, height: .compact) {
                    performCommit(push: false)
                }
                .disabled(!canCommit)
                .help(commitCopy.proHint ?? "提交已暂存改动")

                FizzActionButton(title: commitPushCopy.text, height: .compact, prominence: .primary) {
                    performCommit(push: true)
                }
                .disabled(!canCommit)
                .help(commitPushCopy.proHint ?? "提交已暂存改动并推送当前分支")
            }
        }
    }

    private var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && stagedCount > 0
            && !isBusy
    }

    private func syncMenuTitle(for action: GitSyncAction) -> String {
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
        HStack(spacing: FizzSpacing.row) {
            FizzIconButton(title: "全部暂存", symbol: "plus", height: .compact) {
                performFileWrite("暂存全部改动") {
                    await GitService.stageAll(in: directory)
                }
            }
            .disabled(isBusy || changes.allSatisfy { !$0.hasUnstagedChanges })

            FizzMenuButton(title: "更多文件操作") {
                Button("全部取消暂存", systemImage: "minus") {
                    performFileWrite("取消全部暂存") {
                        await GitService.unstageAll(in: directory)
                    }
                }
                .disabled(stagedCount == 0)

                Divider()

                Button(
                    copyMode == .plain ? FizzCopy.stashAction(.plain).text : "暂存当前改动",
                    systemImage: "archivebox"
                ) {
                    performFileWrite("暂存当前改动") {
                        await GitService.stashPush(in: directory)
                    }
                }
                .disabled(!hasDirtyChanges)
                .help(FizzCopy.stashAction(copyMode).proHint ?? "")

                Button(
                    copyMode == .plain ? "取回之前收起的改动" : "恢复最近一次 Stash",
                    systemImage: "arrow.uturn.backward"
                ) {
                    confirmation = .stashRestore
                }
                .disabled(git.stashCount == 0)
            }
            .disabled(isBusy)
        }
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
                        .font(FizzTypography.monoSmall(.bold))
                        .foregroundStyle(codeColor(change))
                        .frame(width: 24)
                        .padding(.vertical, 2)
                        .background(
                            codeColor(change).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: FizzRadius.micro)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.path)
                            .font(FizzTypography.mono)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 5) {
                            if change.hasStagedChanges {
                                Text("已暂存")
                                    .foregroundStyle(.secondary)
                            }
                            if change.hasUnstagedChanges {
                                Text("未暂存")
                                    .foregroundStyle(.secondary)
                            }
                            if let original = change.originalPath {
                                Text("← \(original)")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(FizzTypography.micro)
                    }

                    Spacer(minLength: 0)

                    FizzIcon(.xs, symbol: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expandedPaths.contains(change.path) ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(interactions: .edit)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .space, .return], phases: .down) { key in
                guard key.modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return .ignored }
                let expanded = expandedPaths.contains(change.path)
                if key.key == .leftArrow && !expanded || key.key == .rightArrow && expanded { return .handled }
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) { toggleDiff(change) }
                return .handled
            }
            .accessibilityLabel("\(change.path) Diff")
            .accessibilityValue(expandedPaths.contains(change.path) ? "已展开" : "已收起")
            .accessibilityHint(expandedPaths.contains(change.path) ? "收起 Diff" : "展开 Diff")

            if change.hasStagedChanges {
                compactButton("取消暂存", help: "取消暂存 \(change.path)") {
                    performFileWrite("取消暂存 \(change.path)") {
                        await GitService.unstage([change.path], in: directory)
                    }
                }
            }
            if change.hasUnstagedChanges {
                compactButton("暂存", help: "暂存 \(change.path)") {
                    performFileWrite("暂存 \(change.path)") {
                        await GitService.stage([change.path], in: directory)
                    }
                }
            }
            RelatedSessionsButton(project: project, file: change.path, compact: true)
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
        FizzActionButton(title: title, height: .compact, action: action)
            .focusable(interactions: .edit)
            .onKeyPress(keys: [.space, .return], phases: .down) { key in
                guard !isBusy, key.modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return .ignored }
                action()
                return .handled
            }
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
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else if let diff = diffs[change.path] {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if diff.additions > 0 {
                        TagChip(text: "+\(diff.additions)", tint: FizzTheme.statusSuccess, compact: true)
                    }
                    if diff.deletions > 0 {
                        TagChip(text: "-\(diff.deletions)", tint: FizzTheme.statusDanger, compact: true)
                    }
                    if diff.truncated {
                        Text("已截断")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .font(FizzTypography.monoSmall(.semibold))

                if let note = diff.note {
                    Text(note)
                        .font(FizzTypography.caption)
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
                .font(FizzTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    private func diffSection(_ section: GitDiffSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(FizzTypography.micro(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FizzTheme.elevatedFill.opacity(0.6))

            ForEach(section.lines) { line in
                GitDiffLineRow(line: line)
            }
        }
    }

    private func branchesPanel(_ git: GitDetail) -> some View {
        Panel(title: "分支", symbol: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                ForEach(Array(git.branches.prefix(30))) { branch in
                    HStack(spacing: 8) {
                        FizzIcon(.xs, symbol: branch.name == project.branch ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(branch.name)
                                .font(FizzTypography.mono)
                                .lineLimit(1)
                            if let upstream = branch.upstream {
                                Text(upstream)
                                    .font(FizzTypography.micro)
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
                                FizzIcon(.xs, symbol: "circle.fill")
                                    .foregroundStyle(Color.secondary)
                                    .padding(.top, 4)
                                Text(commit.hash)
                                    .font(FizzTypography.monoSmall)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(commit.subject)
                                        .font(FizzTypography.body)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        if copyMode == .plain {
                                            TagChip(text: "真实版本", tint: .secondary, compact: true)
                                        }
                                        Text(commit.author)
                                        Text("·")
                                        Text(Format.relative(commit.date))
                                    }
                                    .font(FizzTypography.micro)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 7)

                        case .mark(let mark):
                            HStack(spacing: FizzSpacing.row) {
                                FizzIcon(.xs, symbol: mark.kind == .gitSnapshot ? "diamond.fill" : "diamond")
                                .foregroundStyle(mark.kind == .gitSnapshot ? Color.secondary : .secondary)

                                Text(mark.isProtectionBaseline ? "基线" : "AI 标记")
                                    .font(FizzTypography.monoSmall)
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 54, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mark.label ?? "对话开始前的样子")
                                        .font(FizzTypography.body)
                                    HStack(spacing: 6) {
                                        TagChip(
                                            text: mark.kind == .gitSnapshot ? "可还原标记" : "纯记录",
                                            tint: mark.kind == .gitSnapshot ? Color.secondary : .secondary,
                                            compact: true
                                        )
                                        if mark.pinned {
                                            TagChip(text: "⭐ 已保留", compact: true)
                                        }
                                        Text(Format.relative(mark.createdAt))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(FizzTypography.micro)
                                }

                                Spacer(minLength: 8)

                                if mark.kind == .gitSnapshot {
                                    FizzActionButton(title: mark.pinned ? "取消固定" : "固定保留", height: .compact) {
                                        Task {
                                            let success = await store.togglePin(mark: mark)
                                            if !success {
                                                ToastCenter.shared.show(
                                                    "暂时没能更新固定状态",
                                                    symbol: "exclamationmark.triangle.fill",
                                                    tint: FizzTheme.statusWarning
                                                )
                                            }
                                        }
                                    }
                                    .help(mark.pinned ? "取消永久保留" : "永久保留，不会被 Git 清理")

                                    FizzActionButton(title: "看变化", height: .compact) {
                                        markDiffTarget = mark
                                    }
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
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                HStack(spacing: FizzSpacing.row) {
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
                    .font(FizzTypography.body)
                    .padding(.horizontal, 10)
                    .frame(height: FizzControlHeight.standard.rawValue)
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
                        TagChip(text: "✦ AI 拟定", tint: Color.secondary, compact: true)
                    }
                }

                if git.remote != nil {
                    Toggle("同时上传到云端", isOn: $saveVersionAlsoPush)
                        .toggleStyle(.checkbox)
                        .font(FizzTypography.body)
                }

                if showEnvGuardPanel && hasSecretRisk {
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        if let envGuardIssue {
                            HStack(spacing: FizzSpacing.row) {
                                FizzIcon(.md, symbol: "exclamationmark.shield.fill")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(envGuardIssue.title)
                                        .font(FizzTypography.cardTitle)
                                    Text(envGuardIssue.detail)
                                        .font(FizzTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                FizzActionButton(title: "把 .env 加入忽略列表", height: .compact) {
                                    Task { await fixEnvGitignore() }
                                }
                            }
                        }
                        if !trackedSecretFiles.isEmpty {
                            HStack(spacing: 6) {
                                FizzIcon(.sm, symbol: "key.fill")
                                    .foregroundStyle(.secondary)
                                Text("已跟踪文件疑似含密钥：\(trackedSecretFiles.prefix(3).joined(separator: "、"))")
                                    .font(FizzTypography.cardTitle)
                            }
                            Text("建议先把真实密钥移到 .env 再上传到云端，避免泄露。")
                                .font(FizzTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        FizzTheme.mutedFill,
                        in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                    )
                }
            }
        } accessory: {
            HStack(spacing: FizzSpacing.row) {
                FizzActionButton(title: "取消", height: .compact) {
                    showInlineSaveVersion = false
                    showEnvGuardPanel = false
                }
                .disabled(isBusy)

                if shouldBlockPush {
                    FizzActionButton(title: "先处理密钥风险", symbol: "exclamationmark.shield", height: .compact) {
                        showEnvGuardPanel.toggle()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    FizzActionButton(
                        title: saveVersionAlsoPush ? "保存并上传" : "确认保存",
                        height: .compact,
                        prominence: .primary
                    ) {
                        performSaveVersion(push: saveVersionAlsoPush)
                    }
                    .disabled(saveVersionMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
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
            tint: FizzTheme.statusSuccess,
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
                tint: Color.secondary,
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
                    tint: FizzTheme.statusSuccess,
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
        worktreeRefresh &+= 1
    }

    private func refreshAfterWorktreeWrite(mainPath: String) async {
        diffs.removeAll()
        expandedPaths.removeAll()
        if PathTools.canonical(project.path) != mainPath {
            await store.refreshGit(for: mainPath)
        }
        await refreshAfterWrite()
    }

    private func loadWorkspace() async {
        loadingWorkspace = true
        async let changesTask = GitService.changes(directory)
        async let checkTask = LightweightProjectCheckService.check(directory: directory, copyMode: copyMode)
        async let secretsTask = DoctorService.findTrackedSecretFiles(in: directory)
        let (freshChanges, issues, secretFiles) = await (changesTask, checkTask, secretsTask)
        guard !Task.isCancelled else { return }
        changes = freshChanges
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

    private func codeColor(_ change: GitChange) -> Color {
        if change.untracked { return Color.secondary }
        if change.conflicted { return FizzTheme.statusDanger }
        if change.isDeleted { return FizzTheme.statusDanger }
        if change.displayCode.contains("A") { return FizzTheme.statusSuccess }
        if change.displayCode.contains("M") { return FizzTheme.statusWarning }
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
