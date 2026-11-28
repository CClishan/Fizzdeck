import SwiftUI

struct ProjectDetailView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    let project: RepoProject

    @State private var tab: ProjectTab = .progress
    @State private var detail: ProjectDetail = .empty
    @State private var loadingDetail = false
    @State private var scrolledPastTop = false
    @State private var noteDraft = ""
    @State private var showingCleanupSheet = false
    @State private var showingHandoffSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ProjectHero(
                project: project,
                onShowHandoff: { showingHandoffSheet = true }
            )
            Group {
                switch tab {
                case .progress:
                    ProgressTabView(project: project)
                case .run:
                    RunTabView(project: project)
                case .version:
                    GitTabView(project: project, detail: detail, loading: loadingDetail) {
                        await store.refreshGit(for: project.path)
                        await reloadDetail()
                    }
                    .id(project.path)
                case .info:
                    ProjectInfoTabView(
                        project: project,
                        docs: detail.docs,
                        noteDraft: $noteDraft,
                        saveNote: {
                            store.setNote(noteDraft, for: project)
                            ToastCenter.shared.show(FizzL10n.text("备注已保存", "Saved note"), symbol: "checkmark.circle.fill", tint: FizzTheme.statusSuccess)
                        },
                        onShowCleanup: {
                            showingCleanupSheet = true
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                FizzScrollTopHairline(
                    visible: scrolledPastTop
                )
            }
        }
        .task(id: project.path) {
            store.startWatchingGit(for: project.path)
            noteDraft = project.note
            let target = project.path
            loadingDetail = true
            detail = .empty
            let value = await store.detail(for: project)
            guard !Task.isCancelled, target == project.path else { return }
            detail = value
            loadingDetail = false
        }
        .onDisappear {
            store.stopWatchingGit()
        }
        .onChange(of: project.note) { _, value in
            if noteDraft != value { noteDraft = value }
        }
        .onAppear {
            applyRequestedTab()
            applyRequestedCleanupSheet()
        }
        .onChange(of: store.requestedTab) {
            applyRequestedTab()
        }
        .onChange(of: store.requestedCleanupSheet) {
            applyRequestedCleanupSheet()
        }
        .onPreferenceChange(FizzScrollPastTopKey.self) { value in
            scrolledPastTop = value
        }
        .sheet(isPresented: $showingHandoffSheet) {
            HandoffCardSheet(project: project)
        }
        .sheet(isPresented: $showingCleanupSheet) {
            VStack(spacing: 0) {
                FizzSheetHeader(title: FizzL10n.text("清理空间 · \(project.displayName)", "Free up space · \(project.displayName)")) {
                    showingCleanupSheet = false
                }
                .padding(FizzSpacing.panel)
                Divider()
                CleanupTabView(project: project)
            }
            .frame(minWidth: 680, minHeight: 460)
        }
        .focusedSceneValue(\.fizzProjectTab, $tab)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(FizzL10n.text("项目页签", "Project tabs"), selection: $tab.animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring))) {
                    ForEach(ProjectTab.allCases) { item in
                        Text(item.title(for: copyMode)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .tint(.secondary)
                .fixedSize()
                .focusable(interactions: .edit)
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { key in
                    guard key.modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return .ignored }
                    tab = tab.adjacent(forward: key.key == .rightArrow)
                    return .handled
                }
                .accessibilityValue(tab.title(for: copyMode))
            }
        }
    }

    private func applyRequestedCleanupSheet() {
        guard store.requestedCleanupSheet else { return }
        showingCleanupSheet = true
        store.requestedCleanupSheet = false
    }

    private func applyRequestedTab() {
        guard let requested = store.requestedTab else { return }
        tab = requested
        Task { @MainActor in
            await Task.yield()
            if store.requestedTab == requested {
                store.requestedTab = nil
            }
        }
    }

    private func reloadDetail() async {
        let target = project.path
        let value = await store.detail(for: project)
        guard !Task.isCancelled, target == project.path else { return }
        detail = value
    }
}

extension FocusedValues {
    @Entry var fizzProjectTab: Binding<ProjectTab>?
}

private struct ProjectHero: View {
    let project: RepoProject
    let onShowHandoff: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: FizzSpacing.grid) {
            ProjectBadgeIcon(project: project, size: 42, framed: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(project.displayName)
                        .font(FizzTypography.pageTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if project.port == .running {
                        RunningPulseDot()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: PathTools.displayPath(project.path))
                    .font(FizzTypography.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(project.path)

                FlowLayout(spacing: 6) {
                    TagChip(text: project.groupTitle)
                        .frame(maxWidth: 200)
                        .help(project.groupTitle)
                    if let branch = project.branch {
                        TagChip(text: branch, tint: Color.secondary)
                            .frame(maxWidth: 200)
                            .help(branch)
                    }
                    if project.dirtyCount > 0 {
                        TagChip(text: FizzL10n.text("\(project.dirtyCount) 个改动", "\(project.dirtyCount) \(project.dirtyCount == 1 ? "change" : "changes")"), tint: FizzTheme.statusWarning)
                    }
                    if let tool = project.sessions.lastTool {
                        TagChip(
                            text: DetectedTool(rawValue: tool)?.title ?? tool.capitalized,
                            tint: Color.secondary
                        )
                    }
                    if let test = project.test {
                        TagChip(text: test.label)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProjectHeroActions(project: project, onShowHandoff: onShowHandoff)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(FizzSpacing.panel)
        .fizzCard(radius: FizzRadius.panel)
        .padding(.horizontal, FizzSpacing.page)
        .padding(.top, FizzSpacing.row)
    }
}

private struct ProjectHeroActions: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    let project: RepoProject
    let onShowHandoff: () -> Void

    @State private var removalRequest: ProjectRemovalRequest?
    @State private var removalError: String?
    @State private var removalWorking = false

    private var starTitle: String {
        copyMode == .plain
            ? (project.starred ? FizzL10n.text("取消关注", "Unfollow") : FizzL10n.text("加入关注", "Follow"))
            : (project.starred ? FizzL10n.text("取消星标", "Unstar") : FizzL10n.text("设为星标", "Star"))
    }

    var body: some View {
        HStack(spacing: FizzSpacing.row) {
            FizzIconButton(title: starTitle, symbol: project.starred ? "star.fill" : "star", height: .compact) {
                withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                    store.toggleStar(project)
                }
            }
            .foregroundStyle(project.starred ? Color.secondary : Color.primary)

            FizzMenuButton(title: FizzL10n.text("打开方式", "Open with"), symbol: "folder") {
                ProjectQuickActions(project: project)
            }

            FizzMenuButton(title: FizzL10n.text("更多项目操作", "More project actions")) {
                projectMenuItems
            }

            SessionContinueButton(project: project, style: .hero)
                .id(project.path)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FizzL10n.text("项目操作", "Project actions"))
        .sheet(item: $removalRequest) { request in
            ProjectRemovalSheet(
                project: project,
                mode: request.mode,
                blockedReason: removalBlockedReason,
                onCancel: { removalRequest = nil },
                onConfirm: { confirmation in
                    removalRequest = nil
                    removalWorking = true
                    Task {
                        let result = await store.removeProject(
                            project,
                            mode: request.mode,
                            confirmation: confirmation,
                            testRunning: actions.testRun(for: project.path)?.status == .running
                        )
                        removalWorking = false
                        if !result.success {
                            removalError = result.message
                        }
                    }
                }
            )
        }
        .alert(
            FizzL10n.text("无法移除项目", "Couldn’t remove project"),
            isPresented: Binding(
                get: { removalError != nil },
                set: { if !$0 { removalError = nil } }
            )
        ) {
            Button(FizzL10n.text("好", "OK")) { removalError = nil }
        } message: {
            Text(removalError ?? "")
        }
    }

    @ViewBuilder
    private var projectMenuItems: some View {
        Menu(FizzL10n.text("标签颜色", "Label color")) {
            Button(FizzL10n.text("无标签", "No label")) { store.setColor(nil, for: project) }
            ForEach(TagColor.allCases) { color in
                Button(color.label) { store.setColor(color, for: project) }
            }
        }
        ProjectGroupingMenu(project: project)
        Divider()

        Button {
            if let url = ArtworkFilePicker.pickImageURL(),
               store.setCustomArtwork(from: url, for: project) {
                ToastCenter.shared.show(FizzL10n.text("已更新项目封面", "Updated project cover"), symbol: "photo.badge.checkmark", tint: Color.secondary)
            }
        } label: {
            Label(project.artwork == nil ? FizzL10n.text("上传项目截图…", "Upload project screenshot…") : FizzL10n.text("替换项目截图…", "Replace project screenshot…"), systemImage: "photo.badge.plus")
        }
        if project.customArtwork != nil {
            Button(FizzL10n.text("恢复自动识别截图", "Restore automatic screenshot"), systemImage: "arrow.uturn.backward") {
                store.clearCustomArtwork(for: project)
                ToastCenter.shared.show(FizzL10n.text("已恢复自动识别封面", "Restored automatic cover"), symbol: "arrow.uturn.backward.circle.fill", tint: .secondary)
            }
        }

        Divider()

        Button(FizzL10n.text("复制接力卡", "Copy handoff card"), systemImage: "doc.on.clipboard") {
            let result = HandoffCardBuilder.build(project: project, copyMode: copyMode)
            SystemActions.copy(result.markdown, feedback: nil)
            let subtitle = result.redactedCount > 0
                ? FizzL10n.text("\(result.characterCount) 字 · 已打码 \(result.redactedCount) 处密钥", "\(result.characterCount) characters · Secrets redacted: \(result.redactedCount)")
                : FizzL10n.text("\(result.characterCount) 字 · 含 \(result.includedSessionCount) 次对话", "\(result.characterCount) characters · Sessions: \(result.includedSessionCount)")
            ToastCenter.shared.show(
                FizzL10n.text("接力卡已复制", "Copied handoff card"),
                symbol: "doc.on.clipboard.fill",
                tint: Color.secondary,
                subtitle: subtitle,
                action: ToastAction(title: FizzL10n.text("预览", "Preview"), symbol: "eye") { onShowHandoff() }
            )
        }
        Button(FizzL10n.text("预览接力卡…", "Preview handoff card…"), systemImage: "text.viewfinder", action: onShowHandoff)

        Divider()

        Button(FizzL10n.text("移入废纸篓…", "Move to Trash…"), role: .destructive) {
            removalRequest = ProjectRemovalRequest(mode: .trash)
        }
        Button(FizzL10n.text("永久删除…", "Delete permanently…"), role: .destructive) {
            removalRequest = ProjectRemovalRequest(mode: .permanent)
        }
    }

    private var removalBlockedReason: String? {
        if removalWorking { return FizzL10n.text("正在处理移除操作。", "Removal is in progress.") }
        if project.port == .running { return FizzL10n.text("先停止运行中的开发服务。", "Stop the development service first.") }
        if actions.testRun(for: project.path)?.status == .running {
            return FizzL10n.text("先停止运行中的测试。", "Stop the running tests first.")
        }
        if actions.isBusy(project.path) { return FizzL10n.text("正在启动或停止服务，稍后再试。", "A service is starting or stopping. Try again shortly.") }
        return nil
    }
}

private struct ProjectRemovalRequest: Identifiable {
    let mode: ProjectRemovalMode

    var id: String { mode.rawValue }
}

private struct ProjectRemovalSheet: View {
    let project: RepoProject
    let mode: ProjectRemovalMode
    let blockedReason: String?
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var confirmation = ""

    private var expectedName: String {
        URL(fileURLWithPath: project.path).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.panel) {
            FizzSheetHeader(title: "\(mode.title) \(project.displayName)", onClose: onCancel)

            Label {
                Text(mode.explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                FizzIcon(.lg, symbol: mode.symbol)
                    .foregroundStyle(.secondary)
            }
            .font(FizzTypography.body)

            if let blockedReason {
                Label(blockedReason, systemImage: "exclamationmark.triangle")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(FizzL10n.text("输入目录名「\(expectedName)」确认", "Type the folder name “\(expectedName)” to confirm"))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                TextField(expectedName, text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .font(FizzTypography.body)
            }

            FizzSheetFooter {
                FizzActionButton(title: FizzL10n.text("取消", "Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                FizzActionButton(title: mode.actionTitle, prominence: .primary, role: .destructive) {
                    onConfirm(confirmation)
                }
                .disabled(confirmation != expectedName || blockedReason != nil)
            }
        }
        .padding(FizzSpacing.page)
        .frame(width: 440)
    }
}
