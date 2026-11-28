import SwiftUI

struct GitWorktreePanel: View {
    let directory: URL
    let gitRefresh: Int
    let gitIsBusy: Bool
    @Binding var isWriting: Bool
    let onGitChanged: (String) async -> Void

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
        Panel(title: "并行工作区（Worktree）", symbol: "rectangle.stack") {
            if let statusError {
                Text(statusError)
                    .font(FizzTypography.body)
                    .fizzStatus(FizzTheme.statusWarning)
            }
            if let overview {
                if overview.rows.isEmpty {
                    Text("还没有并行目录")
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
                        .accessibilityLabel(isWriting ? "正在处理并行目录" : "正在读取并行工作区")
                }

                FizzMenuButton(title: "更多并行工作区操作") {
                    Button("刷新并行工作区", systemImage: "arrow.clockwise") {
                        manualRefresh &+= 1
                    }
                }
                .disabled(controlsBusy)

                FizzActionButton(title: "新建并行目录", symbol: "plus", height: .compact, prominence: .primary, keyboardNavigation: true) {
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
        return HStack(spacing: FizzSpacing.grid) {
            VStack(alignment: .leading, spacing: 3) {
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

            statusBadges(row, mainBranch: mainBranch)
                .layoutPriority(1)
            rowActions(row, mainBranch: mainBranch)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
        }
        .padding(.vertical, FizzSpacing.row)
        .accessibilityElement(children: .contain)
    }

    private func statusBadges(_ row: GitWorktreeService.Row, mainBranch: String?) -> some View {
        FlowLayout(spacing: 4) {
            if row.worktree.isMain {
                TagChip(text: "主仓", compact: true)
            }
            if row.worktree.isDetached {
                TagChip(text: "未关联分支", compact: true)
            }
            if row.worktree.isLocked {
                TagChip(text: "已锁定", tint: FizzTheme.statusWarning, compact: true)
            }
            if row.worktree.isPrunable {
                TagChip(text: "待清理", tint: FizzTheme.statusWarning, compact: true)
            }
            if let changed = row.changedCount {
                TagChip(
                    text: changed == 0 ? "无未提交改动" : "未提交 \(changed)",
                    tint: changed == 0 ? .secondary : FizzTheme.statusWarning,
                    compact: true
                )
            } else {
                TagChip(text: "改动未知", compact: true)
            }
            if let ahead = row.ahead, let behind = row.behind, let mainBranch {
                TagChip(text: "领先 \(ahead)", tint: ahead == 0 ? .secondary : Color.secondary, compact: true)
                    .help("比主分支「\(mainBranch)」多的提交")
                TagChip(text: "落后 \(behind)", tint: behind == 0 ? .secondary : FizzTheme.statusWarning, compact: true)
                    .help("比主分支「\(mainBranch)」少的提交")
            } else if !row.worktree.isMain {
                TagChip(text: "未比较主分支", compact: true)
            }
        }
    }

    private func rowActions(_ row: GitWorktreeService.Row, mainBranch: String?) -> some View {
        let worktree = row.worktree
        return HStack(spacing: FizzSpacing.row) {
            FizzIconButton(title: "打开目录", symbol: "folder", height: .compact) {
                SystemActions.open(worktree.path)
            }
            .disabled(worktree.isPrunable)

            FizzIconButton(title: "在终端打开", symbol: "terminal", height: .compact) {
                SystemActions.openTerminal(worktree.path)
            }
            .disabled(worktree.isPrunable)

            if !worktree.isMain {
                FizzIconButton(title: "合并回主分支", symbol: "arrow.triangle.merge", height: .compact) {
                    guard let mainBranch else { return }
                    present(.merge(worktree, into: mainBranch))
                }
                .disabled(mutationsDisabled || !row.canManage || mainBranch == nil)

                FizzIconButton(title: "安全移除并行目录", symbol: "trash", height: .compact) {
                    present(.remove(worktree))
                }
                .disabled(mutationsDisabled || !row.canManage)
            }

            FizzMenuButton(title: "\(worktree.displayName) 的更多操作") {
                Button("在 Finder 中显示", systemImage: "folder") {
                    SystemActions.reveal(worktree.path)
                }
                .disabled(worktree.isPrunable)
                Button("复制目录路径", systemImage: "doc.on.doc") {
                    SystemActions.copy(worktree.path)
                }
            }
        }
    }

    private func dialogSheet(_ dialog: Dialog) -> some View {
        VStack(alignment: .leading, spacing: FizzSpacing.panel) {
            FizzSheetHeader(title: dialog.title, onClose: closeDialog)
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
                        .accessibilityLabel("正在处理并行目录")
                }
                if case .conflict = dialog {
                    FizzActionButton(title: "完成", prominence: .primary, action: closeDialog)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWriting)
                } else {
                    FizzActionButton(title: "取消", role: .cancel, action: closeDialog)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isWriting)

                    switch dialog {
                    case .create(let mainDirectory):
                        confirmButton("新建目录", dialog: dialog)
                            .keyboardShortcut(.defaultAction)
                            .disabled(destination(beside: mainDirectory) == nil)
                    case .merge:
                        confirmButton("合并", dialog: dialog)
                    case .remove(_, let discard):
                        confirmButton(discard == nil ? "移除目录" : "丢弃并移除", dialog: dialog, role: .destructive)
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
                TextField("分支名", text: $branchDraft, prompt: Text("输入分支名，如 feature/new-page"))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.primary)
                    .disabled(isWriting)
                if let target = destination(beside: mainDirectory) {
                    Text("将创建在：")
                    pathLine(target.path)
                } else if !branchName.isEmpty {
                    Text("请输入有效的分支名。")
                        .fizzStatus(FizzTheme.statusWarning)
                }
            }
        case .merge(let worktree, let mainBranch):
            Text("将「\(worktree.branch ?? worktree.displayName)」已提交的改动合并到「\(mainBranch)」。并行目录和分支都会保留。")
                .fixedSize(horizontal: false, vertical: true)
            pathLine(worktree.path)
        case .remove(let worktree, let discard):
            pathLine(worktree.path)
            if let discard {
                Text("未提交改动：\(discard.changedCount) 项\nGit 忽略的内容：\(discard.ignoredCount) 项")
                Text("这些内容会永久丢失，无法撤消。分支「\(worktree.branch ?? worktree.displayName)」会保留。")
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("移除这个并行目录，保留分支「\(worktree.branch ?? worktree.displayName)」。如有未提交或被 Git 忽略的内容，会再次请你确认。")
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .conflict(let mainPath, let rollbackSucceeded, let editors):
            Text(
                rollbackSucceeded
                    ? "已用 git merge --abort 撤回合并，主仓已回到合并前。处理分支差异后可以重试。"
                    : "未能用 git merge --abort 自动撤回。请打开主仓检查并处理当前的合并，再继续操作。"
            )
            .fixedSize(horizontal: false, vertical: true)
            pathLine(mainPath)
            HStack(spacing: FizzSpacing.row) {
                FizzActionButton(title: "打开主仓目录", symbol: "folder", height: .compact) {
                    SystemActions.open(mainPath)
                }
                FizzActionButton(title: "打开主仓终端", symbol: "terminal", height: .compact) {
                    SystemActions.openTerminal(mainPath)
                }
                if !editors.isEmpty {
                    FizzMenuButton(title: "用编辑器打开主仓", symbol: "chevron.left.forwardslash.chevron.right") {
                        ForEach(editors) { editor in
                            Button("在 \(editor.title) 打开") {
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
                    message = "已为「\(worktree.branch ?? branch)」新建并行目录。"
                case .merge(let worktree, _):
                    message = try await GitWorktreeService.mergeIntoMain(worktree, in: mainDirectory)
                case .remove(let worktree, let discard):
                    try await GitWorktreeService.remove(
                        worktree, in: mainDirectory, confirmingDiscardOf: discard,
                        managedActivity: { actions.hasRunningWorktreeActivity(at: $0) }
                    )
                    message = "已移除并行目录，分支仍保留。"
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

        var title: String {
            switch self {
            case .create: "新建并行目录"
            case .merge: "合并回主分支？"
            case .remove(_, let discard): discard == nil ? "移除并行目录？" : "丢弃改动并移除？"
            case .conflict: "合并遇到冲突"
            }
        }
    }
}
