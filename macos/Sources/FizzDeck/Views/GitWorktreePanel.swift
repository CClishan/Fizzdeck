import SwiftUI

struct GitWorktreePanel: View {
    let directory: URL
    let gitRefresh: Int
    let gitIsBusy: Bool
    @Binding var isWriting: Bool
    let onGitChanged: (String) async -> Void

    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @Environment(ProjectActions.self) private var actions
    @State private var overview: GitWorktreeService.Overview?
    @State private var mainDirectory: URL?
    @State private var statusError: String?
    @State private var isRefreshing = true
    @State private var manualRefresh = 0
    @State private var dialog: DialogRequest?
    @State private var branchDraft = ""
    @State private var operationError: String?

    private var controlsBusy: Bool { gitIsBusy || isWriting || isRefreshing }
    private var mutationsDisabled: Bool { controlsBusy || statusError != nil || mainDirectory == nil }
    private var branchName: String { branchDraft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Panel(title: FizzL10n.text("并行工作区（Worktree）", copyMode == .plain ? "Parallel folders" : "Git worktrees"), symbol: "rectangle.stack") {
            if let statusError {
                Text(statusError)
                    .font(FizzTypography.body)
                    .fizzStatus(FizzTheme.statusWarning)
            }
            if let overview {
                if overview.rows.isEmpty {
                    Text(FizzL10n.text("还没有并行目录", "No parallel folders yet"))
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(overview.rows) { row in
                            worktreeRow(row, mainBranch: overview.mainBranch)
                            if row.id != overview.rows.last?.id {
                                Divider().opacity(0.25)
                            }
                        }
                    }
                }
            }
        } accessory: {
            HStack(spacing: FizzSpacing.row) {
                if isRefreshing || isWriting {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel(isWriting ? FizzL10n.text("正在处理并行目录", "Updating worktrees") : FizzL10n.text("正在读取并行工作区", "Loading worktrees"))
                }

                FizzMenuButton(title: FizzL10n.text("更多并行工作区操作", "More worktree actions")) {
                    Button(FizzL10n.text("刷新并行工作区", "Refresh worktrees"), systemImage: "arrow.clockwise") {
                        manualRefresh &+= 1
                    }
                }
                .disabled(controlsBusy)

                FizzActionButton(title: FizzL10n.text("新建并行目录", copyMode == .plain ? "New parallel folder" : "New worktree"), symbol: "plus", height: .compact, prominence: .primary, keyboardNavigation: true) {
                    guard let mainDirectory else { return }
                    branchDraft = ""
                    present(.create(mainDirectory))
                }
                .disabled(mutationsDisabled)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .task(id: RefreshRequest(directory: directory, git: gitRefresh, manual: manualRefresh)) {
            await loadStatus()
        }
        .sheet(item: $dialog) { request in
            dialogSheet(request.dialog)
                .interactiveDismissDisabled(isWriting)
        }
    }

    private func worktreeRow(_ row: GitWorktreeService.Row, mainBranch: String?) -> some View {
        let worktree = row.worktree
        let name = worktree.branch ?? worktree.head ?? worktree.displayName
        let identity = VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: name)
                .font(FizzTypography.mono(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)
            Text(verbatim: PathTools.displayPath(worktree.path))
                .font(FizzTypography.monoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(worktree.path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        let badges = statusBadges(row, mainBranch: mainBranch)
        let controls = rowActions(row, mainBranch: mainBranch).fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: FizzSpacing.grid) {
                identity
                badges
                controls
            }
            VStack(alignment: .leading, spacing: FizzSpacing.row) {
                HStack(spacing: FizzSpacing.grid) {
                    identity
                    controls
                }
                badges
            }
        }
        .padding(.vertical, FizzSpacing.row)
        .accessibilityElement(children: .contain)
    }

    private func statusBadges(_ row: GitWorktreeService.Row, mainBranch: String?) -> some View {
        FlowLayout(spacing: 4) {
            if row.worktree.isMain {
                TagChip(text: FizzL10n.text("主仓", copyMode == .plain ? "Main folder" : "Main"), compact: true)
            }
            if row.worktree.isDetached {
                TagChip(text: FizzL10n.text("未关联分支", copyMode == .plain ? "No branch" : "Detached HEAD"), compact: true)
            }
            if row.worktree.isLocked {
                TagChip(text: FizzL10n.text("已锁定", "Locked"), tint: FizzTheme.statusWarning, compact: true)
            }
            if row.worktree.isPrunable {
                TagChip(text: FizzL10n.text("待清理", copyMode == .plain ? "Ready to prune" : "Prunable"), tint: FizzTheme.statusWarning, compact: true)
            }
            if let changed = row.changedCount {
                TagChip(
                    text: changed == 0 ? FizzL10n.text("无未提交改动", copyMode == .plain ? "All changes saved" : "Clean") : FizzL10n.text("未提交 \(changed)", "\(changed) uncommitted"),
                    tint: changed == 0 ? .secondary : FizzTheme.statusWarning,
                    compact: true
                )
            } else {
                TagChip(text: FizzL10n.text("改动未知", "Changes unknown"), compact: true)
            }
            if let ahead = row.ahead, let behind = row.behind, let mainBranch {
                TagChip(text: FizzL10n.text("领先 \(ahead)", "\(ahead) ahead"), tint: ahead == 0 ? .secondary : Color.secondary, compact: true)
                    .help(FizzL10n.text("比主分支「\(mainBranch)」多的提交", "Commits ahead of the main branch “\(mainBranch)”"))
                TagChip(text: FizzL10n.text("落后 \(behind)", "\(behind) behind"), tint: behind == 0 ? .secondary : FizzTheme.statusWarning, compact: true)
                    .help(FizzL10n.text("比主分支「\(mainBranch)」少的提交", "Commits behind the main branch “\(mainBranch)”"))
            } else if !row.worktree.isMain {
                TagChip(text: FizzL10n.text("未比较主分支", "Not compared to main"), compact: true)
            }
        }
    }

    private func rowActions(_ row: GitWorktreeService.Row, mainBranch: String?) -> some View {
        let worktree = row.worktree
        return HStack(spacing: FizzSpacing.row) {
            FizzIconButton(title: FizzL10n.text("打开目录", "Open folder"), symbol: "folder", height: .compact) {
                SystemActions.open(worktree.path)
            }
            .disabled(worktree.isPrunable)

            FizzIconButton(title: FizzL10n.text("在终端打开", "Open in Terminal"), symbol: "terminal", height: .compact) {
                SystemActions.openTerminal(worktree.path)
            }
            .disabled(worktree.isPrunable)

            if !worktree.isMain {
                FizzIconButton(title: FizzL10n.text("合并回主分支", "Merge into main branch"), symbol: "arrow.triangle.merge", height: .compact) {
                    guard let mainBranch else { return }
                    present(.merge(worktree, into: mainBranch))
                }
                .disabled(mutationsDisabled || !row.canManage || mainBranch == nil)

                FizzIconButton(title: FizzL10n.text("安全移除并行目录", "Safely remove worktree"), symbol: "trash", height: .compact) {
                    present(.remove(worktree))
                }
                .disabled(mutationsDisabled || !row.canManage)
            }

            FizzMenuButton(title: FizzL10n.text("\(worktree.displayName) 的更多操作", "More actions for \(worktree.displayName)")) {
                Button(FizzL10n.text("在 Finder 中显示", "Show in Finder"), systemImage: "folder") {
                    SystemActions.reveal(worktree.path)
                }
                .disabled(worktree.isPrunable)
                Button(FizzL10n.text("复制目录路径", "Copy folder path"), systemImage: "doc.on.doc") {
                    SystemActions.copy(worktree.path)
                }
            }
        }
    }

    private func dialogSheet(_ dialog: Dialog) -> some View {
        VStack(alignment: .leading, spacing: FizzSpacing.panel) {
            FizzSheetHeader(title: dialog.title(for: copyMode), onClose: closeDialog)
                .disabled(isWriting)

            dialogContent(dialog)
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)

            if let operationError {
                Text(operationError)
                    .font(FizzTypography.body)
                    .fizzStatus(FizzTheme.statusWarning)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FizzSheetFooter {
                if isWriting {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel(FizzL10n.text("正在处理并行目录", "Updating worktrees"))
                }
                if case .conflict = dialog {
                    FizzActionButton(title: FizzL10n.text("完成", "Done"), prominence: .primary, action: closeDialog)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWriting)
                } else {
                    FizzActionButton(title: FizzL10n.text("取消", "Cancel"), role: .cancel, action: closeDialog)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isWriting)

                    switch dialog {
                    case .create(let mainDirectory):
                        confirmButton(FizzL10n.text("新建目录", "Create folder"), dialog: dialog)
                            .keyboardShortcut(.defaultAction)
                            .disabled(destination(beside: mainDirectory) == nil)
                    case .merge:
                        confirmButton(FizzL10n.text("合并", "Merge"), dialog: dialog)
                    case .remove(_, let discard):
                        confirmButton(discard == nil ? FizzL10n.text("移除目录", "Remove folder") : FizzL10n.text("丢弃并移除", "Discard and remove"), dialog: dialog, role: .destructive)
                    case .conflict:
                        EmptyView()
                    }
                }
            }
        }
        .padding(FizzSpacing.page)
        .frame(width: 480)
    }

    @ViewBuilder
    private func dialogContent(_ dialog: Dialog) -> some View {
        switch dialog {
        case .create(let mainDirectory):
            VStack(alignment: .leading, spacing: FizzSpacing.row) {
                TextField(FizzL10n.text("分支名", "Branch name"), text: $branchDraft, prompt: Text(FizzL10n.text("输入分支名，如 feature/new-page", "Enter a branch name, e.g. feature/new-page")))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.primary)
                    .disabled(isWriting)
                if let target = destination(beside: mainDirectory) {
                    Text(FizzL10n.text("将创建在：", "Folder location:"))
                    pathLine(target.path)
                } else if !branchName.isEmpty {
                    Text(FizzL10n.text("请输入有效的分支名。", "Enter a valid branch name."))
                        .fizzStatus(FizzTheme.statusWarning)
                }
            }
        case .merge(let worktree, let mainBranch):
            Text(FizzL10n.text("将「\(worktree.branch ?? worktree.displayName)」已提交的改动合并到「\(mainBranch)」。并行目录和分支都会保留。", "Merge committed changes from “\(worktree.branch ?? worktree.displayName)” into “\(mainBranch)”. The worktree and its branch will be kept."))
                .fixedSize(horizontal: false, vertical: true)
            pathLine(worktree.path)
        case .remove(let worktree, let discard):
            pathLine(worktree.path)
            if let discard {
                Text(FizzL10n.text("未提交改动：\(discard.changedCount) 项\nGit 忽略的内容：\(discard.ignoredCount) 项", "Uncommitted changes: \(discard.changedCount)\nGit-ignored items: \(discard.ignoredCount)"))
                Text(FizzL10n.text("这些内容会永久丢失，无法撤消。分支「\(worktree.branch ?? worktree.displayName)」会保留。", "These items will be permanently lost. This can’t be undone. The branch “\(worktree.branch ?? worktree.displayName)” will be kept."))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(FizzL10n.text("移除这个并行目录，保留分支「\(worktree.branch ?? worktree.displayName)」。如有未提交或被 Git 忽略的内容，会再次请你确认。", "Remove this worktree and keep the branch “\(worktree.branch ?? worktree.displayName)”. If it contains uncommitted or ignored files, you’ll be asked again."))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .conflict(let mainPath, let rollbackSucceeded, let editors):
            Text(
                rollbackSucceeded
                    ? FizzL10n.text("已用 git merge --abort 撤回合并，主仓已回到合并前。处理分支差异后可以重试。", "FizzDeck ran git merge --abort to restore the main worktree. Resolve the differences between the branches before trying again.")
                    : FizzL10n.text("未能用 git merge --abort 自动撤回。请打开主仓检查并处理当前的合并，再继续操作。", "Git couldn’t abort the merge. Open the main worktree and resolve the current merge before continuing.")
            )
            .fixedSize(horizontal: false, vertical: true)
            pathLine(mainPath)
            HStack(spacing: FizzSpacing.row) {
                FizzActionButton(title: FizzL10n.text("打开主仓目录", "Open main worktree"), symbol: "folder", height: .compact) {
                    SystemActions.open(mainPath)
                }
                FizzActionButton(title: FizzL10n.text("打开主仓终端", "Open main worktree in Terminal"), symbol: "terminal", height: .compact) {
                    SystemActions.openTerminal(mainPath)
                }
                if !editors.isEmpty {
                    FizzMenuButton(title: FizzL10n.text("用编辑器打开主仓", "Open main worktree in editor"), symbol: "chevron.left.forwardslash.chevron.right") {
                        ForEach(editors) { editor in
                            Button(FizzL10n.text("在 \(editor.title) 打开", "Open in \(editor.title)")) {
                                SystemActions.open(mainPath, in: editor)
                            }
                        }
                    }
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func pathLine(_ path: String) -> some View {
        Text(verbatim: path)
            .font(FizzTypography.mono)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func confirmButton(_ title: String, dialog: Dialog, role: ButtonRole? = nil) -> some View {
        FizzActionButton(title: title, prominence: .primary, role: role) {
            confirm(dialog)
        }
        .disabled(mutationsDisabled)
    }

    private func destination(beside mainDirectory: URL) -> URL? {
        GitWorktreeService.destination(for: branchName, beside: mainDirectory)
    }

    private func present(_ dialog: Dialog) {
        guard !mutationsDisabled else { return }
        operationError = nil
        self.dialog = DialogRequest(dialog: dialog)
    }

    private func closeDialog() {
        guard !isWriting else { return }
        dialog = nil
    }

    private func loadStatus() async {
        guard !Task.isCancelled else { return }
        isRefreshing = true
        defer { if !Task.isCancelled { isRefreshing = false } }
        do {
            let result = try await GitWorktreeService.status(in: directory)
            try Task.checkCancellation()
            overview = result
            mainDirectory = result.rows.first(where: { $0.worktree.isMain }).map { row in
                URL(fileURLWithPath: PathTools.canonical(row.worktree.path), isDirectory: true)
            }
            statusError = nil
        } catch {
            guard !Task.isCancelled else { return }
            statusError = error.localizedDescription
        }
    }

    private func confirm(_ dialog: Dialog) {
        guard !mutationsDisabled, let mainDirectory else { return }
        let branch = branchName
        if case .create(let previewDirectory) = dialog {
            guard previewDirectory == mainDirectory, destination(beside: previewDirectory) != nil else { return }
        }

        let actions = actions
        operationError = nil
        isWriting = true
        Task {
            defer { isWriting = false }
            do {
                let message: String
                switch dialog {
                case .create:
                    let worktree = try await GitWorktreeService.create(branch, in: mainDirectory)
                    message = FizzL10n.text("已为「\(worktree.branch ?? branch)」新建并行目录。", "Created a worktree for “\(worktree.branch ?? branch)”.")
                case .merge(let worktree, _):
                    message = try await GitWorktreeService.mergeIntoMain(worktree, in: mainDirectory)
                case .remove(let worktree, let discard):
                    try await GitWorktreeService.remove(
                        worktree, in: mainDirectory, confirmingDiscardOf: discard,
                        managedActivity: { actions.hasRunningWorktreeActivity(at: $0) }
                    )
                    message = FizzL10n.text("已移除并行目录，分支仍保留。", "Removed the worktree and kept the branch.")
                case .conflict:
                    return
                }
                self.dialog = nil
                ToastCenter.shared.show(message, symbol: "checkmark.circle.fill", tint: FizzTheme.statusSuccess)
                await onGitChanged(mainDirectory.path)
            } catch GitWorktreeService.Failure.dirtyRemoval(let discard) {
                if case .remove(let worktree, _) = dialog {
                    self.dialog = DialogRequest(dialog: .remove(worktree, discard: discard))
                }
            } catch GitWorktreeService.Failure.mergeConflict(let mainPath, let rollbackSucceeded) {
                let conflict = Dialog.conflict(
                    mainPath: mainPath,
                    rollbackSucceeded: rollbackSucceeded,
                    editors: ProjectEditor.available(for: mainPath)
                )
                self.dialog = DialogRequest(dialog: conflict)
                if !rollbackSucceeded {
                    await onGitChanged(mainPath)
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private struct RefreshRequest: Equatable {
        let directory: URL
        let git: Int
        let manual: Int
    }

    private struct DialogRequest: Identifiable {
        let id = UUID()
        let dialog: Dialog
    }

    private enum Dialog {
        case create(URL)
        case merge(GitWorktree, into: String)
        case remove(GitWorktree, discard: GitWorktreeService.DiscardConfirmation? = nil)
        case conflict(mainPath: String, rollbackSucceeded: Bool, editors: [ProjectEditor])

        func title(for copyMode: CopyMode) -> String {
            switch self {
            case .create: FizzL10n.text("新建并行目录", copyMode == .plain ? "New parallel folder" : "New worktree")
            case .merge: FizzL10n.text("合并回主分支？", "Merge into the main branch?")
            case .remove(_, let discard): discard == nil ? FizzL10n.text("移除并行目录？", "Remove this worktree?") : FizzL10n.text("丢弃改动并移除？", "Discard changes and remove this worktree?")
            case .conflict: FizzL10n.text("合并遇到冲突", "Merge conflict")
            }
        }
    }
}
