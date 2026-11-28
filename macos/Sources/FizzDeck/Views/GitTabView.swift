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
            ProgressView(FizzL10n.text("读取 Git 信息…", "Reading Git info…"))
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
                        DisclosureGroup(FizzL10n.text("进阶选项（分支）", "Advanced options (branches)"), isExpanded: $showAdvancedGit) {
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
            ProgressView(FizzL10n.text("读取版本记录…", "Loading version history…"))
                .font(FizzTypography.body)
                .task { await onSyncCompleted() }
        } else {
            ScrollView {
                Panel(title: FizzL10n.text("还没有开启版本保护", "Version protection is off"), symbol: "arrow.triangle.branch") {
                    Text(FizzL10n.text("开启后可从第一条基线查看变化或还原文件。", "Turn it on to see changes or restore files from the first snapshot."))
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
            title: copyMode == .plain ? FizzL10n.text("当前版本状态", "Version status") : FizzL10n.text("状态", "Status"),
            symbol: "point.3.connected.trianglepath.dotted",
            content: {
                if copyMode == .plain {
                    Text(statusSentence)
                        .font(FizzTypography.body(.medium))
                        .foregroundStyle(hasDirtyChanges ? .primary : .secondary)
                        .help(FizzL10n.text("分支：\(project.branch ?? "—") · ↑\(git.ahead) ↓\(git.behind)", "Branch: \(project.branch ?? "—") · ↑\(git.ahead) ↓\(git.behind)"))
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240), spacing: FizzSpacing.section)],
                        alignment: .leading,
                        spacing: FizzSpacing.row
                    ) {
                        KeyValueRow(key: FizzL10n.text("当前分支", "Current branch"), value: project.branch ?? "—", mono: true)
                        KeyValueRow(
                            key: FizzL10n.text("未提交", "Uncommitted"),
                            value: FizzL10n.text("\(changeCount) 个改动", "\(changeCount) \(changeCount == 1 ? "change" : "changes")"),
                            tint: hasDirtyChanges ? FizzTheme.statusWarning : .secondary
                        )
                        KeyValueRow(key: FizzL10n.text("领先 / 落后", "Ahead / behind"), value: "↑ \(git.ahead)  ↓ \(git.behind)", mono: true)
                        KeyValueRow(key: "Stash", value: "\(git.stashCount)")
                        KeyValueRow(key: FizzL10n.text("已暂存 / 未暂存", "Staged / unstaged"), value: "\(stagedCount) / \(unstagedCount)", mono: true)
                        KeyValueRow(key: FizzL10n.text("最近标签", "Latest tag"), value: git.lastTag ?? "—", mono: true)
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
                            .accessibilityLabel(FizzL10n.text("\(runningAction.title)进行中", "\(runningAction.title) in progress"))
                    }

                    syncMenu

                    if copyMode == .plain, hasDirtyChanges {
                        if showInlineSaveVersion {
                            FizzActionButton(title: FizzL10n.text("收起", "Collapse"), height: .compact) {
                                showInlineSaveVersion = false
                            }
                            .disabled(isBusy)
                        } else {
                            FizzActionButton(title: FizzL10n.text("存个版本", "Save a version"), height: .compact, prominence: .primary) {
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
        FizzMenuButton(title: FizzL10n.text("同步远程仓库", copyMode == .plain ? "Sync saved versions" : "Sync with remote")) {
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
                Text(FizzL10n.text("远程", "Remote"))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: remote)
                    .font(FizzTypography.mono)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            FizzIconButton(title: FizzL10n.text("复制远程地址", "Copy remote URL"), symbol: "doc.on.doc", height: .compact) {
                SystemActions.copy(remote)
            }
            if let parsed = GitRemote(raw: remote), let url = parsed.webURL {
                FizzIconButton(title: FizzL10n.text("在浏览器中打开远程仓库", "Open remote repository in browser"), symbol: "arrow.up.right.square", height: .compact) {
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
                TextField(copyMode == .plain ? FizzL10n.text("写一句这次改了什么", "Describe what changed in one line") : FizzL10n.text("一行提交信息", "Commit message (one line)"), text: $commitMessage)
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
                        ? (copyMode == .plain ? FizzL10n.text("已选中 \(stagedCount) 个要存的文件", "\(stagedCount) \(stagedCount == 1 ? "file" : "files") selected to save") : FizzL10n.text("已暂存 \(stagedCount) 个文件", "\(stagedCount) \(stagedCount == 1 ? "file" : "files") staged"))
                        : (copyMode == .plain ? FizzL10n.text("先点下方文件旁的「暂存」选中要存的改动", "Select the files to save below.") : FizzL10n.text("先暂存文件再提交", "Stage files before committing.")))
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
                .help(commitCopy.proHint ?? FizzL10n.text("提交已暂存改动", "Commit staged changes"))

                FizzActionButton(title: commitPushCopy.text, height: .compact, prominence: .primary) {
                    performCommit(push: true)
                }
                .disabled(!canCommit)
                .help(commitPushCopy.proHint ?? FizzL10n.text("提交已暂存改动并推送当前分支", "Commit staged changes and push the current branch"))
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
        case .fetch: return FizzL10n.text("检查云端有没有更新", "Check for updates")
        case .pull: return FizzCopy.pullAction(.plain).text
        case .push: return FizzL10n.text("上传已存版本到云端", "Upload saved versions")
        }
    }

    private func filesPanel(_ git: GitDetail) -> some View {
        let dirtyCopy = FizzCopy.uncommittedChanges(mode: copyMode)
        return Panel(
            title: dirtyCopy.text,
            symbol: "square.and.pencil",
            content: {
                if loadingWorkspace && changes.isEmpty {
                    ProgressView(FizzL10n.text("读取改动…", "Loading changes…"))
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if changes.isEmpty {
                    Text(copyMode == .plain ? FizzL10n.text("没有还没存的改动", "All changes are saved") : FizzL10n.text("工作区干净", "Working tree clean"))
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
            FizzIconButton(title: FizzL10n.text("全部暂存", copyMode == .plain ? "Select all" : "Stage all"), symbol: "plus", height: .compact) {
                performFileWrite(FizzL10n.text("暂存全部改动", "Stage all changes"), showDiff: true) {
                    await GitService.stageAll(in: directory)
                }
            }
            .disabled(isBusy || changes.allSatisfy { !$0.hasUnstagedChanges })

            FizzMenuButton(title: FizzL10n.text("更多文件操作", "More file actions")) {
                Button(FizzL10n.text("全部取消暂存", copyMode == .plain ? "Deselect all" : "Unstage all"), systemImage: "minus") {
                    performFileWrite(FizzL10n.text("取消全部暂存", "Unstage all changes"), showDiff: true) {
                        await GitService.unstageAll(in: directory)
                    }
                }
                .disabled(stagedCount == 0)

                Divider()

                Button(
                    copyMode == .plain ? FizzCopy.stashAction(.plain).text : FizzL10n.text("暂存当前改动", "Stash current changes"),
                    systemImage: "archivebox"
                ) {
                    performFileWrite(FizzL10n.text("暂存当前改动", "Stash current changes"), showDiff: true) {
                        await GitService.stashPush(in: directory)
                    }
                }
                .disabled(!hasDirtyChanges)
                .help(FizzCopy.stashAction(copyMode).proHint ?? "")

                Button(
                    copyMode == .plain ? FizzL10n.text("取回之前收起的改动", "Bring back saved changes") : FizzL10n.text("恢复最近一次 Stash", "Apply latest stash"),
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
                                Text(FizzL10n.text("已暂存", copyMode == .plain ? "Selected" : "Staged"))
                                    .foregroundStyle(.secondary)
                            }
                            if change.hasUnstagedChanges {
                                Text(FizzL10n.text("未暂存", copyMode == .plain ? "Not selected" : "Unstaged"))
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
            .accessibilityLabel(FizzL10n.text("\(change.path) Diff", copyMode == .plain ? "Changes to \(change.path)" : "Diff for \(change.path)"))
            .accessibilityValue(expandedPaths.contains(change.path) ? FizzL10n.text("已展开", "Expanded") : FizzL10n.text("已收起", "Collapsed"))
            .accessibilityHint(expandedPaths.contains(change.path) ? FizzL10n.text("收起 Diff", copyMode == .plain ? "Hide file changes" : "Collapse diff") : FizzL10n.text("展开 Diff", copyMode == .plain ? "Show file changes" : "Expand diff"))

            if change.hasStagedChanges {
                compactButton(FizzL10n.text("取消暂存", copyMode == .plain ? "Deselect" : "Unstage"), help: FizzL10n.text("取消暂存 \(change.path)", copyMode == .plain ? "Deselect \(change.path)" : "Unstage \(change.path)")) {
                    performFileWrite(FizzL10n.text("取消暂存 \(change.path)", copyMode == .plain ? "Deselect \(change.path)" : "Unstage \(change.path)"), showDiff: true) {
                        await GitService.unstage([change.path], in: directory)
                    }
                }
            }
            if change.hasUnstagedChanges {
                compactButton(FizzL10n.text("暂存", copyMode == .plain ? "Select" : "Stage"), help: FizzL10n.text("暂存 \(change.path)", copyMode == .plain ? "Select \(change.path) to save" : "Stage \(change.path)")) {
                    performFileWrite(FizzL10n.text("暂存 \(change.path)", copyMode == .plain ? "Select \(change.path) to save" : "Stage \(change.path)"), showDiff: true) {
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
                Text(FizzL10n.text("读取 Diff…", "Loading diff…"))
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
                        Text(FizzL10n.text("已截断", "Truncated"))
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
            Text(FizzL10n.text("没有可显示的 Diff", "No diff to show"))
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
        Panel(title: FizzL10n.text("分支", "Branches"), symbol: "arrow.triangle.branch") {
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
                            compactButton(FizzL10n.text("切换", "Switch"), help: FizzL10n.text("切换到 \(branch.name)", "Switch to \(branch.name)")) {
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
            title: copyMode == .plain ? FizzL10n.text("历史记录（真实版本与 AI 标记）", "Saved versions and AI checkpoints") : FizzL10n.text("最近提交", "Recent commits"),
            symbol: "clock.arrow.circlepath"
        ) {
            let entries = mixedTimelineEntries
            if entries.isEmpty {
                Text(FizzL10n.text("还没有历史记录", "No history yet"))
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
                                            TagChip(text: FizzL10n.text("真实版本", "Saved version"), tint: .secondary, compact: true)
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

                                Text(mark.isProtectionBaseline ? FizzL10n.text("基线", "Baseline") : FizzL10n.text("AI 标记", "AI checkpoint"))
                                    .font(FizzTypography.monoSmall)
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 54, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mark.projectCheckpointTitle)
                                        .font(FizzTypography.body)
                                    HStack(spacing: 6) {
                                        TagChip(
                                            text: mark.kind == .gitSnapshot ? FizzL10n.text("可还原标记", "Restorable checkpoint") : FizzL10n.text("纯记录", "Record only"),
                                            tint: mark.kind == .gitSnapshot ? Color.secondary : .secondary,
                                            compact: true
                                        )
                                        if mark.pinned {
                                            TagChip(text: FizzL10n.text("⭐ 已保留", "⭐ Pinned"), compact: true)
                                        }
                                        Text(Format.relative(mark.createdAt))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(FizzTypography.micro)
                                }

                                Spacer(minLength: 8)

                                if mark.kind == .gitSnapshot {
                                    FizzActionButton(title: mark.pinned ? FizzL10n.text("取消固定", "Unpin") : FizzL10n.text("固定保留", "Pin"), height: .compact) {
                                        Task {
                                            let success = await store.togglePin(mark: mark)
                                            if !success {
                                                ToastCenter.shared.show(
                                                    FizzL10n.text("暂时没能更新固定状态", "Couldn’t update the pin. Try again."),
                                                    symbol: "exclamationmark.triangle.fill",
                                                    tint: FizzTheme.statusWarning
                                                )
                                            }
                                        }
                                    }
                                    .help(mark.pinned ? FizzL10n.text("取消永久保留", "Stop keeping this checkpoint permanently") : FizzL10n.text("永久保留，不会被 Git 清理", "Keep permanently so Git won’t remove this checkpoint"))

                                    FizzActionButton(title: FizzL10n.text("看变化", "View changes"), height: .compact) {
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

        return Panel(title: FizzL10n.text("存个版本", "Save a version"), symbol: "bookmark.circle.fill") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                HStack(spacing: FizzSpacing.row) {
                    TextField(FizzL10n.text("写一句这次改了什么", "Describe what changed in one line"), text: Binding(
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
                        TagChip(text: FizzL10n.text("✦ AI 拟定", "✦ AI draft"), tint: Color.secondary, compact: true)
                    }
                }

                if git.remote != nil {
                    Toggle(FizzL10n.text("同时上传到云端", "Also upload this version"), isOn: $saveVersionAlsoPush)
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
                                    Text(envGuardIssue.title(for: copyMode))
                                        .font(FizzTypography.cardTitle)
                                    Text(envGuardIssue.detail)
                                        .font(FizzTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                FizzActionButton(title: FizzL10n.text("把 .env 加入忽略列表", "Ignore .env"), height: .compact) {
                                    Task { await fixEnvGitignore() }
                                }
                            }
                        }
                        if !trackedSecretFiles.isEmpty {
                            HStack(spacing: 6) {
                                FizzIcon(.sm, symbol: "key.fill")
                                    .foregroundStyle(.secondary)
                                Text(FizzL10n.text("已跟踪文件疑似含密钥：\(trackedSecretFiles.prefix(3).joined(separator: "、"))", "Possible secrets in tracked files: \(trackedSecretFiles.prefix(3).joined(separator: ", "))"))
                                    .font(FizzTypography.cardTitle)
                            }
                            Text(FizzL10n.text("建议先把真实密钥移到 .env 再上传到云端，避免泄露。", "Move real secrets into .env before uploading so they aren’t exposed."))
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
                FizzActionButton(title: FizzL10n.text("取消", "Cancel"), height: .compact) {
                    showInlineSaveVersion = false
                    showEnvGuardPanel = false
                }
                .disabled(isBusy)

                if shouldBlockPush {
                    FizzActionButton(title: FizzL10n.text("先处理密钥风险", "Review secrets first"), symbol: "exclamationmark.shield", height: .compact) {
                        showEnvGuardPanel.toggle()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    FizzActionButton(
                        title: saveVersionAlsoPush ? FizzL10n.text("保存并上传", "Save and upload") : FizzL10n.text("确认保存", "Save version"),
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
            push ? FizzL10n.text("保存并上传版本", "Save and upload version") : FizzL10n.text("存个版本", "Save a version"),
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
            FizzL10n.text("已把 .env 加入忽略列表", "Added .env to the ignore list"),
            symbol: "checkmark.shield.fill",
            tint: FizzTheme.statusSuccess,
            subtitle: FizzL10n.text("之后上传代码不会泄露这些密钥文件", "Future uploads will skip these secret files.")
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
        showDiff: Bool = false,
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
                    microViz: showDiff ? fileChangeMicroViz : .gitMerge
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
            push ? FizzL10n.text("提交并推送", "Commit and push") : FizzL10n.text("提交", "Commit"),
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
        performFileWrite(FizzL10n.text("切换到 \(branch.name)", "Switch to \(branch.name)")) {
            await GitService.switchBranch(branch.name, in: directory)
        }
    }

    private func performStashRestore() {
        performFileWrite(FizzL10n.text("恢复 Stash", "Apply stash"), showDiff: true) {
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
                title: Text(FizzL10n.text("\(action.title) \(project.displayName)？", "\(syncMenuTitle(for: action)) · \(project.displayName)?")),
                message: Text(action.confirmation(for: copyMode)),
                primaryButton: .cancel(Text(FizzL10n.text("取消", "Cancel"))),
                secondaryButton: .default(Text(FizzL10n.text(action.title, syncMenuTitle(for: action)))) {
                    Task { await perform(action) }
                }
            )
        case .switchBranch(let branch):
            Alert(
                title: Text(FizzL10n.text("切换到 \(branch.name)？", "Switch to \(branch.name)?")),
                message: Text(FizzL10n.text("当前有未提交改动。Git 会尝试保留改动；如与目标分支冲突，切换会失败并保持现场。", "Git will try to keep your uncommitted changes. If they conflict with the target branch, the switch will stop and your changes will stay here.")),
                primaryButton: .cancel(Text(FizzL10n.text("取消", "Cancel"))),
                secondaryButton: .default(Text(FizzL10n.text("继续切换", "Switch branch"))) {
                    switchBranch(branch)
                }
            )
        case .stashRestore:
            Alert(
                title: Text(FizzL10n.text("恢复最近一次 Stash？", "Apply the latest stash?")),
                message: Text(FizzL10n.text("当前工作区改动可能与 Stash 冲突。冲突时会保留 Stash，不会静默丢弃。", "Your working tree may conflict with the stash. If it does, Git will keep the stash.")),
                primaryButton: .cancel(Text(FizzL10n.text("取消", "Cancel"))),
                secondaryButton: .default(Text(FizzL10n.text("恢复", "Restore"))) {
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

    private var fileChangeMicroViz: ToastMicroViz {
        .diff(added: diffs.values.reduce(0) { $0 + $1.additions }, removed: diffs.values.reduce(0) { $0 + $1.deletions })
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
