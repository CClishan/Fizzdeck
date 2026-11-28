import SwiftUI

struct MarkDiffRestoreSelection {
    static func defaultRestorePaths(for summary: MarkDiffSummary) -> Set<String> {
        Set(summary.modifiedOrDeleted.map(\.path))
    }

    static func defaultTrashPaths(for summary: MarkDiffSummary) -> Set<String> {
        []
    }
}

struct MarkDiffRestoreSheet: View {
    let project: RepoProject
    let mark: SessionMark
    var initialSelectedFile: String? = nil
    let onRestored: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(RepositoryStore.self) private var store

    @State private var currentMark: SessionMark
    @State private var summary: MarkDiffSummary?
    @State private var isLoadingSummary = true
    @State private var selectedRestorePaths: Set<String> = []
    @State private var selectedTrashPaths: Set<String> = []
    @State private var activeChange: MarkFileChange?
    @State private var diffs: [String: GitFileDiff] = [:]
    @State private var loadingDiffPaths: Set<String> = []
    @State private var showingConfirm = false
    @State private var isRestoring = false
    @State private var isTogglingPin = false
    @State private var restoreError: String?

    init(
        project: RepoProject,
        mark: SessionMark,
        initialSelectedFile: String? = nil,
        onRestored: @escaping () async -> Void
    ) {
        self.project = project
        self.mark = mark
        self.initialSelectedFile = initialSelectedFile
        self.onRestored = onRestored
        _currentMark = State(initialValue: mark)
    }

    private var directory: URL {
        URL(fileURLWithPath: project.path)
    }

    private var totalSelectedCount: Int {
        selectedRestorePaths.count + selectedTrashPaths.count
    }

    private var formattedMarkTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: currentMark.createdAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            FizzSheetHeader(
                title: "看改了什么 · \(project.displayName)",
                subtitle: "\(currentMark.label ?? "对话开始前的样子") · \(formattedMarkTime)"
            ) { dismiss() }
            .disabled(isRestoring)
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.panel)

            Divider()

            markStatus
            contentBody

            Divider()

            footerBar
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: 820, height: 560)
        .background(FizzTheme.page)
        .interactiveDismissDisabled(isRestoring)
        .task(id: mark.id) {
            await loadSummary()
        }
        .alert("确认还原这些文件？", isPresented: $showingConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认还原", role: .destructive) {
                Task { await performRestore() }
            }
        } message: {
            Text(confirmMessage)
        }
    }

    @ViewBuilder
    private var markStatus: some View {
        if summary?.available == false || currentMark.pinned || currentMark.kind == .gitSnapshot {
            HStack(spacing: FizzSpacing.row) {
                if summary?.available == false {
                    TagChip(text: "已过期", tint: .secondary, compact: true)
                } else if currentMark.pinned {
                    TagChip(text: "已保留", tint: Color.secondary, compact: true)
                } else {
                    TagChip(text: "可安全还原", tint: FizzTheme.statusSuccess, compact: true)
                }

                Spacer(minLength: FizzSpacing.row)

                if currentMark.kind == .gitSnapshot && summary?.available == true {
                    FizzActionButton(
                        title: currentMark.pinned ? "取消保留" : "永久保留",
                        symbol: currentMark.pinned ? "star.fill" : "star",
                        height: .compact
                    ) {
                        Task { await togglePin() }
                    }
                    .disabled(isTogglingPin || isRestoring)
                }
            }
            .frame(minHeight: FizzControlHeight.compact.rawValue)
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.row)
            .background(FizzTheme.sidebar)

            Divider()
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if isLoadingSummary {
            VStack(spacing: FizzSpacing.row) {
                ProgressView()
                Text("正在对比这个时间点之后的变化…")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let summary, !summary.available {
            ContentUnavailableView(
                "这个标记已过期",
                systemImage: "clock.badge.exclamationmark",
                description: Text("这个对话标记超过 14 天已被 Git 清理，无法对比或还原。重要节点可以在过期前选择「永久保留」。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let summary,
                  summary.modifiedOrDeleted.isEmpty && summary.createdAfterMark.isEmpty {
            ContentUnavailableView(
                "和这个标记时完全一致",
                systemImage: "checkmark.circle",
                description: Text("从记下这个时间点到现在，工作区没有留下任何改动。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let summary {
            HStack(spacing: 0) {
                fileSidebar(summary)
                    .frame(width: 270)
                    .background(FizzTheme.sidebar)

                Divider()

                diffDetailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fileSidebar(_ summary: MarkDiffSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FizzSpacing.panel) {
                if !summary.modifiedOrDeleted.isEmpty {
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        HStack(spacing: FizzSpacing.row) {
                            Text("修改或删除的文件（\(summary.modifiedOrDeleted.count)）")
                                .font(FizzTypography.caption(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            FizzActionButton(
                                title: selectedRestorePaths.count == summary.modifiedOrDeleted.count ? "全不选" : "全选",
                                height: .compact
                            ) {
                                if selectedRestorePaths.count == summary.modifiedOrDeleted.count {
                                    selectedRestorePaths = []
                                } else {
                                    selectedRestorePaths = Set(summary.modifiedOrDeleted.map(\.path))
                                }
                            }
                        }
                        .padding(.horizontal, FizzSpacing.grid)

                        ForEach(summary.modifiedOrDeleted) { change in
                            fileRow(
                                change: change,
                                isChecked: Binding(
                                    get: { selectedRestorePaths.contains(change.path) },
                                    set: { checked in
                                        if checked {
                                            selectedRestorePaths.insert(change.path)
                                        } else {
                                            selectedRestorePaths.remove(change.path)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }

                if !summary.createdAfterMark.isEmpty {
                    VStack(alignment: .leading, spacing: FizzSpacing.row) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("对话后新建的文件（默认不删）")
                                .font(FizzTypography.caption(.semibold))
                                .foregroundStyle(.secondary)
                            Text("勾选后会移入系统废纸篓，不会直接彻底抹掉")
                                .font(FizzTypography.micro)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, FizzSpacing.grid)

                        ForEach(summary.createdAfterMark) { change in
                            fileRow(
                                change: change,
                                isChecked: Binding(
                                    get: { selectedTrashPaths.contains(change.path) },
                                    set: { checked in
                                        if checked {
                                            selectedTrashPaths.insert(change.path)
                                        } else {
                                            selectedTrashPaths.remove(change.path)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
            }
            .padding(.vertical, FizzSpacing.grid)
        }
    }

    private func fileRow(change: MarkFileChange, isChecked: Binding<Bool>) -> some View {
        let isActive = activeChange?.path == change.path
        let fileName = URL(fileURLWithPath: change.path).lastPathComponent

        return HStack(spacing: FizzSpacing.row) {
            Toggle("选择 \(fileName)", isOn: isChecked)
                .labelsHidden()
                .toggleStyle(.checkbox)

            Button {
                selectChange(change)
            } label: {
                HStack(spacing: FizzSpacing.row) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName)
                            .font(FizzTypography.body(isActive ? .semibold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if fileName != change.path {
                            Text(change.path)
                                .font(FizzTypography.monoSmall)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 4)

                    statusBadge(change.status)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, FizzSpacing.grid)
        .padding(.vertical, 6)
        .background(isActive ? FizzTheme.selectedFill : Color.clear)
    }

    private func statusBadge(_ status: MarkFileChangeStatus) -> some View {
        let (label, tint): (String, Color) = switch status {
        case .modified: ("修改", FizzTheme.statusWarning)
        case .deleted: ("删除", FizzTheme.statusDanger)
        case .createdAfterMark: ("新建", FizzTheme.statusSuccess)
        }
        return TagChip(text: label, tint: tint, compact: true)
    }

    @ViewBuilder
    private var diffDetailPane: some View {
        if let activeChange {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: FizzSpacing.row) {
                    Text(verbatim: activeChange.path)
                        .font(FizzTypography.mono(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: FizzSpacing.row)

                    if let diff = diffs[activeChange.path] {
                        if diff.additions > 0 {
                            Text("+\(diff.additions)")
                                .font(FizzTypography.monoSmall(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if diff.deletions > 0 {
                            Text("-\(diff.deletions)")
                                .font(FizzTypography.monoSmall(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, FizzSpacing.panel)
                .padding(.vertical, FizzSpacing.row)
                .background(FizzTheme.recessedFill)

                Divider()

                if loadingDiffPaths.contains(activeChange.path) {
                    HStack(spacing: FizzSpacing.row) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在生成改动对比…")
                            .font(FizzTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff = diffs[activeChange.path] {
                    if let note = diff.note, diff.isEmpty {
                        Text(note)
                            .font(FizzTypography.body)
                            .foregroundStyle(.secondary)
                            .padding(FizzSpacing.section)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else if diff.isEmpty {
                        Text("没有可展示的文本差异。")
                            .font(FizzTypography.body)
                            .foregroundStyle(.secondary)
                            .padding(FizzSpacing.section)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(diff.sections) { section in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(section.title)
                                            .font(FizzTypography.micro)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, FizzSpacing.grid)
                                            .padding(.vertical, 5)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(FizzTheme.elevatedFill.opacity(0.7))

                                        ForEach(section.lines) { line in
                                            GitDiffLineRow(line: line)
                                        }
                                    }
                                }
                            }
                        }
                        .background(FizzTheme.recessedFill)
                    }
                } else {
                    Text("点击左侧文件名可查看改动的每一行。")
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            Text("从左侧选择一个文件，即可查看改了哪些内容。")
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footerBar: some View {
        FizzSheetFooter {
            if let restoreError {
                Text(restoreError)
                    .font(FizzTypography.caption)
                    .fizzStatus(FizzTheme.statusWarning)
                    .lineLimit(2)
            } else if isRestoring {
                ProgressView().controlSize(.small)
                Text("正在还原…")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("还原前会自动再记一次当前状态，还原完也能点撤销。")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: FizzSpacing.row)

            FizzActionButton(title: "关闭", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isRestoring)

            FizzActionButton(
                title: totalSelectedCount > 0 ? "还原选中（\(totalSelectedCount)）" : "还原选中",
                prominence: .primary,
                role: .destructive
            ) {
                showingConfirm = true
            }
            .disabled(totalSelectedCount == 0 || isRestoring || summary?.available != true)
        }
    }

    private var confirmMessage: String {
        let restoreCount = selectedRestorePaths.count
        let trashCount = selectedTrashPaths.count
        var parts: [String] = []
        if restoreCount > 0 {
            parts.append("把 \(restoreCount) 个文件恢复到 \(formattedMarkTime) 时的样子")
        }
        if trashCount > 0 {
            parts.append("把 \(trashCount) 个新建文件移到废纸篓")
        }
        return "将\(parts.joined(separator: "，并"))。操作前会自动备份当前状态，随时可撤销。"
    }

    private func loadSummary() async {
        isLoadingSummary = true
        let result = await SessionMarkService.diffSummary(for: currentMark, in: directory)
        guard !Task.isCancelled else { return }
        summary = result
        selectedRestorePaths = MarkDiffRestoreSelection.defaultRestorePaths(for: result)
        selectedTrashPaths = MarkDiffRestoreSelection.defaultTrashPaths(for: result)
        isLoadingSummary = false

        let allChanges = result.modifiedOrDeleted + result.createdAfterMark
        if let initialSelectedFile {
            let normalizedInitial = initialSelectedFile
            let matched = allChanges.first { change in
                normalizedInitial == change.path
                    || normalizedInitial.hasSuffix("/" + change.path)
                    || URL(fileURLWithPath: normalizedInitial).lastPathComponent == URL(fileURLWithPath: change.path).lastPathComponent
            }
            if let matched {
                selectChange(matched)
                return
            }
        }
        if let first = allChanges.first {
            selectChange(first)
        }
    }

    private func selectChange(_ change: MarkFileChange) {
        activeChange = change
        guard diffs[change.path] == nil, !loadingDiffPaths.contains(change.path) else { return }
        loadingDiffPaths.insert(change.path)
        Task {
            let diff = await SessionMarkService.fileDiff(for: currentMark, change: change, in: directory)
            guard !Task.isCancelled else { return }
            diffs[change.path] = diff
            loadingDiffPaths.remove(change.path)
        }
    }

    private func togglePin() async {
        isTogglingPin = true
        defer { isTogglingPin = false }
        if await store.togglePin(mark: currentMark) {
            currentMark.pinned.toggle()
        }
    }

    private func performRestore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        restoreError = nil
        let restoreList = Array(selectedRestorePaths)
        let trashList = Array(selectedTrashPaths)
        let result = await SessionMarkService.restore(
            mark: currentMark,
            filesToRestore: restoreList,
            newlyCreatedToTrash: trashList,
            in: directory
        )
        guard result.succeeded else {
            restoreError = result.message
            return
        }

        store.reloadMarks()
        await onRestored()

        let addedViz = max(1, result.restoredCount)
        let removedViz = result.trashedCount
        let backupMark = result.preRestoreMark
        let subtitle: String? = if result.trashedCount > 0 {
            "\(result.trashedCount) 个新建文件已移入废纸篓（可在系统废纸篓找回）"
        } else {
            "随时可点击右侧「撤销」回到刚才的状态"
        }

        let undoAction: ToastAction? = if let backupMark, !restoreList.isEmpty {
            ToastAction(title: "撤销", symbol: "arrow.uturn.backward") { [store, directory, onRestored] in
                Task { @MainActor in
                    let undoResult = await SessionMarkService.restore(
                        mark: backupMark,
                        filesToRestore: restoreList,
                        newlyCreatedToTrash: [],
                        in: directory
                    )
                    store.reloadMarks()
                    await onRestored()
                    if undoResult.succeeded {
                        ToastCenter.shared.show(
                            "已撤销刚才的还原",
                            symbol: "arrow.uturn.backward.circle.fill",
                            tint: FizzTheme.statusSuccess,
                            subtitle: result.trashedCount > 0 ? "废纸篓里的新建文件请按需在废纸篓放回" : nil
                        )
                    } else {
                        ToastCenter.shared.show(
                            undoResult.message,
                            symbol: "exclamationmark.triangle.fill",
                            tint: FizzTheme.statusWarning
                        )
                    }
                }
            }
        } else {
            nil
        }

        ToastCenter.shared.show(
            "已还原 \(result.restoredCount + result.trashedCount) 个文件",
            symbol: "clock.arrow.circlepath",
            tint: FizzTheme.statusSuccess,
            subtitle: subtitle,
            microViz: .diff(added: addedViz, removed: removedViz),
            action: undoAction
        )
        dismiss()
    }
}
