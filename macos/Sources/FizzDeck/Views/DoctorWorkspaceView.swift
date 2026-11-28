import SwiftUI

struct DoctorWorkspaceView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain

    @State private var scrolledPastTop = false
    @State private var pendingInstallTarget: (project: RepoProject, command: String)?
    @State private var pendingTrashProject: RepoProject?
    @State private var showGitIdentityForm = false
    @State private var gitNameDraft = ""
    @State private var gitEmailDraft = ""
    @State private var isSavingIdentity = false

    private var partition: FocusPartition {
        ProjectFocusPolicy.partition(projects: store.projects)
    }

    private var cleanableProjects: [RepoProject] {
        store.projects
            .filter { !$0.cleanup.items.isEmpty }
            .sorted { $0.cleanup.reusableBytes > $1.cleanup.reusableBytes }
    }

    private var idleSecretRiskProjects: [(project: RepoProject, report: DoctorProjectReport)] {
        partition.idle.compactMap { project in
            guard let report = store.doctorReports[project.path],
                  report.issues.contains(where: { $0.kind == .trackedSecrets || $0.kind == .unignoredEnvFile }) else {
                return nil
            }
            return (project, report)
        }
    }

    private var totalReusableBytes: Int64 {
        cleanableProjects.reduce(0) { $0 + $1.cleanup.reusableBytes }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                header
                focusedSection
                DeveloperPortsPanel()
                idleCleanupSection
                machineEnvironmentSection
            }
            .padding(FizzSpacing.page)
        }
        .fizzTracksScrollPastTop()
        .overlay(alignment: .top) {
            FizzScrollTopHairline(visible: scrolledPastTop)
        }
        .onPreferenceChange(FizzScrollPastTopKey.self) { scrolledPastTop = $0 }
        .task {
            await refreshAll(force: false)
        }
        .alert(
            "首次联网安装依赖确认",
            isPresented: Binding(
                get: { pendingInstallTarget != nil },
                set: { if !$0 { pendingInstallTarget = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                pendingInstallTarget = nil
            }
            Button("确认安装") {
                guard let target = pendingInstallTarget else { return }
                pendingInstallTarget = nil
                DoctorPreferences.setConfirmedFirstInstall(true)
                actions.runInstallDependencies(command: target.command, for: target.project, store: store)
                store.openProject(target.project, tab: .run)
            }
        } message: {
            if let target = pendingInstallTarget {
                Text("将在「\(target.project.displayName)」目录运行 `\(target.command)` 并联网下载依赖，之后可在运行页日志区实时查看或随时停止。以后同类一键修复将不再弹窗。")
            }
        }
        .alert(
            "将可清理目录移到废纸篓？",
            isPresented: Binding(
                get: { pendingTrashProject != nil },
                set: { if !$0 { pendingTrashProject = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                pendingTrashProject = nil
            }
            Button("移到废纸篓", role: .destructive) {
                guard let project = pendingTrashProject else { return }
                pendingTrashProject = nil
                Task { await trashCleanup(for: project) }
            }
        } message: {
            if let project = pendingTrashProject {
                Text("将把「\(project.displayName)」的 \(project.cleanup.items.count) 个缓存/构建目录（共 \(Format.bytes(project.cleanup.reusableBytes))）移到系统废纸篓，需要时仍可在废纸篓放回或重新生成。")
            }
        }
    }

    private var header: some View {
        let focused = partition.focused
        let summary: String
        if focused.isEmpty {
            summary = "还没有关注或近期活跃项目，先关注几个在做的项目吧"
        } else {
            let healthy = focused.count { store.doctorReports[$0.id]?.severity == .healthy }
            let attention = focused.count { (store.doctorReports[$0.id]?.actionableCount ?? 0) > 0 }
            summary = "关注的 \(focused.count) 个项目：\(healthy) 个状态良好，\(attention) 个需要处理"
        }
        let checkedAt = store.lastDoctorCheckAt.map { " · 上次检查 \(Format.relative($0))" } ?? ""

        return FizzPageHeader(title: "体检", subtitle: summary + checkedAt) {
            FizzActionButton(
                title: store.isRunningDoctor ? "检查中…" : "重新检查",
                symbol: "arrow.clockwise", prominence: .primary, keyboardNavigation: true
            ) {
                Task { await refreshAll() }
            }
            .disabled(store.isRunningDoctor)
        }
    }

    private var focusedSection: some View {
        let focus = partition
        return Panel(title: "关注项目（随时能跑起来）", symbol: "stethoscope") {
            if focus.focused.isEmpty {
                Text("当你在做项目时，这里会自动盯住「缺依赖」「端口占用」「密钥风险」和「没开版本保护」。")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(focus.focused) { entry in
                        focusedProjectRow(entry.project)
                        if entry.id != focus.focused.last?.id {
                            Divider()
                                .opacity(0.25)
                        }
                    }

                    if focus.overflowActiveCount > 0 {
                        Text("还有 \(focus.overflowActiveCount) 个近期活跃项目未列入关注上限")
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, FizzSpacing.row)
                    }
                }
            }
        } accessory: {
            if focus.overflowActiveCount > 0 {
                FizzActionButton(title: "查看项目库", height: .compact) {
                    store.openLibrary()
                }
            }
        }
    }

    private func focusedProjectRow(_ project: RepoProject) -> some View {
        let report = store.doctorReports[project.path]
        let topIssue = report?.issues.first { $0.kind != .cloudBehind }
        let severity = report?.severity ?? .healthy
        let fix = topIssue?.fixAction
        let hasCloudUpdate = project.behind > 0 && !store.doctorExemptions(for: project).contains(.cloudBehind)
        let exemptibleKinds = store.exemptibleIssues(for: project)
        let statusText: String = if let topIssue {
            topIssue.title
        } else if report == nil {
            "尚未检查"
        } else {
            hasCloudUpdate ? "云端有新提交" : "未发现问题"
        }

        return HStack(spacing: FizzSpacing.grid) {
            FizzStatusDot(tint: severityColor(severity))

            ProjectBadgeIcon(project: project, size: 24, framed: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(FizzTypography.cardTitle)
                    .lineLimit(1)
                Text(statusText)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: FizzSpacing.row)

            HStack(spacing: 6) {
                DoctorTrialMenu(project: project)

                if fix != nil || hasCloudUpdate || !exemptibleKinds.isEmpty {
                    FizzMenuButton(title: "\(project.displayName)的更多操作") {
                        if fix != nil || hasCloudUpdate {
                            Button("打开运行页", systemImage: "play.circle") {
                                store.openProject(project, tab: .run)
                            }
                        }
                        if !exemptibleKinds.isEmpty {
                            Section("体检豁免") {
                                DoctorExemptionItems(project: project, kinds: exemptibleKinds)
                            }
                        }
                    }
                }

                if hasCloudUpdate {
                    FizzActionButton(title: "云端领先 \(project.behind)", height: .compact) {
                        store.openProject(project, tab: .version)
                    }
                    .accessibilityLabel("云端领先 \(project.behind) 个提交，查看版本")
                }

                if let fix {
                    issueQuickButton(fix: fix, for: project)
                } else if !hasCloudUpdate {
                    FizzIconButton(title: "打开 \(project.displayName) 运行页", symbol: "chevron.right", height: .compact) {
                        store.openProject(project, tab: .run)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, FizzSpacing.row)
    }

    @ViewBuilder
    private func issueQuickButton(fix: DoctorFixAction, for project: RepoProject) -> some View {
        switch fix {
        case .installDependencies(let command):
            let isInstalling = actions.installRun(for: project, command: command)?.status == .running
            FizzActionButton(title: isInstalling ? "查看安装" : "安装依赖", height: .compact) {
                if isInstalling {
                    store.openProject(project, tab: .run)
                } else if DoctorPreferences.hasConfirmedFirstInstall() {
                    actions.runInstallDependencies(command: command, for: project, store: store)
                    store.openProject(project, tab: .run)
                } else {
                    pendingInstallTarget = (project, command)
                }
            }
        case .createEnvFromExample:
            FizzActionButton(title: "生成 .env", height: .compact) {
                Task {
                    if let url = DoctorService.createEnvFromExample(in: URL(fileURLWithPath: project.path)) {
                        SystemActions.open(url.path)
                        ToastCenter.shared.show("已根据模板生成 .env", symbol: "doc.badge.plus", tint: FizzTheme.statusSuccess)
                    }
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }
        case .addEnvToGitignore:
            FizzActionButton(title: "加入忽略", height: .compact) {
                Task {
                    if LightweightProjectCheckService.addEnvFilesToGitignore(in: URL(fileURLWithPath: project.path)) {
                        ToastCenter.shared.show("已把 .env 加入忽略列表", symbol: "checkmark.shield.fill", tint: FizzTheme.statusSuccess)
                    }
                    await store.refreshGit(for: project.path)
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }
        case .initGitRepository:
            EnableVersionProtectionButton(project: project)
        case .resolvePortConflict:
            FizzActionButton(title: "去处理", height: .compact) {
                store.openProject(project, tab: .run)
            }
        case .inspectTrackedSecrets:
            FizzActionButton(title: "去处理", height: .compact) {
                store.openProject(project, tab: .version)
            }
        case .copyShellCommand(let command):
            FizzActionButton(title: "复制切换命令", height: .compact) {
                SystemActions.copy(
                    command,
                    feedback: "运行版本切换命令已复制",
                    microViz: .compact(state: .done)
                )
            }
            .accessibilityLabel("复制运行时版本切换命令")
        }
    }

    private var idleCleanupSection: some View {
        Panel(
            title: "闲置整理与腾空间",
            symbol: "archivebox"
        ) {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                if !idleSecretRiskProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(idleSecretRiskProjects, id: \.project.id) { entry in
                            HStack(spacing: FizzSpacing.row) {
                                FizzIcon(.sm, symbol: "exclamationmark.shield.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text("闲置项目「\(entry.project.displayName)」存在密钥或未忽略 .env 风险")
                                    .font(FizzTypography.caption(.medium))
                                Spacer()
                                FizzActionButton(title: "去处理", height: .compact) {
                                    store.openProject(entry.project, tab: .version)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
                        }
                    }
                }

                if cleanableProjects.isEmpty {
                    Text("没有命中依赖、缓存或构建产物的可腾空间目录。")
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("默认「移到废纸篓」（可随时在系统废纸篓放回或重新安装恢复）；共发现 \(cleanableProjects.count) 个项目、可腾出 \(Format.bytes(totalReusableBytes))。")
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .opacity(0.25)

                    VStack(spacing: 0) {
                        ForEach(cleanableProjects) { project in
                            HStack(spacing: FizzSpacing.grid) {
                                ProjectBadgeIcon(project: project, size: 22, framed: false)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.displayName)
                                        .font(FizzTypography.cardTitle)
                                        .lineLimit(1)
                                    Text("\(project.cleanup.items.count) 个目录 · \(project.cleanup.items.map(\.label).prefix(3).joined(separator: ", "))")
                                        .font(FizzTypography.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: FizzSpacing.row)

                                Text(Format.bytes(project.cleanup.reusableBytes))
                                    .font(FizzTypography.mono(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 6) {
                                    if copyMode == .pro {
                                        FizzIconButton(title: "复制清理命令", symbol: "doc.on.doc", height: .compact) {
                                            SystemActions.copy(
                                                "# \(project.displayName)\n\(project.cleanup.removalCommand)",
                                                microViz: .compact(state: .done)
                                            )
                                            ToastCenter.shared.show("已复制清理命令", symbol: "doc.on.doc", tint: Color.secondary, subtitle: project.displayName)
                                        }
                                    }

                                    FizzActionButton(title: "移到废纸篓", height: .compact, role: .destructive) {
                                        pendingTrashProject = project
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.vertical, FizzSpacing.row)

                            if project.id != cleanableProjects.last?.id {
                                Divider()
                                    .opacity(0.25)
                            }
                        }
                    }
                }
            }
        } accessory: {
            if !cleanableProjects.isEmpty {
                TagChip(text: "可省 \(Format.bytes(totalReusableBytes))", tint: FizzTheme.statusWarning, compact: true)
            }
        }
    }

    private var machineEnvironmentSection: some View {
        Panel(title: "本机环境", symbol: "desktopcomputer") {
            if let env = store.machineEnv {
                VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                    FlowLayout(spacing: FizzSpacing.row) {
                        TagChip(
                            text: env.gitInstalled ? "✓ Git 已就绪" : "⚠ 缺少 Git",
                            tint: env.gitInstalled ? FizzTheme.statusSuccess : FizzTheme.statusDanger,
                            compact: true
                        )
                        TagChip(
                            text: env.nodeVersion.map { "✓ Node \($0)" } ?? "○ 未检测到 Node",
                            tint: env.nodeVersion != nil ? FizzTheme.statusSuccess : .secondary,
                            compact: true
                        )
                        TagChip(
                            text: env.pythonVersion.map { "✓ Python \($0)" } ?? "○ 未检测到 Python",
                            tint: env.pythonVersion != nil ? FizzTheme.statusSuccess : .secondary,
                            compact: true
                        )
                        ForEach(env.cliTools) { tool in
                            TagChip(
                                text: tool.available ? "✓ \(tool.title)" : "○ \(tool.title) 未安装",
                                tint: tool.available ? FizzTheme.statusSuccess : .secondary,
                                compact: true
                            )
                        }
                        if let disk = env.disk {
                            TagChip(
                                text: "磁盘剩余 \(Format.bytes(disk.free))",
                                tint: disk.free < 10_000_000_000 ? FizzTheme.statusWarning : .secondary,
                                compact: true
                            )
                        }
                    }

                    if env.needsGitIdentity {
                        VStack(alignment: .leading, spacing: FizzSpacing.row) {
                            HStack(spacing: FizzSpacing.row) {
                                FizzIcon(.sm, symbol: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text("Git 还没设置你的名字和邮箱（首次「存个版本」时需要）")
                                    .font(FizzTypography.caption(.medium))
                                Spacer()
                                FizzActionButton(title: showGitIdentityForm ? "收起" : "去设置", height: .compact) {
                                    gitNameDraft = env.gitUserName ?? ""
                                    gitEmailDraft = env.gitUserEmail ?? ""
                                    showGitIdentityForm.toggle()
                                }
                            }

                            if showGitIdentityForm {
                                HStack(spacing: FizzSpacing.row) {
                                    TextField("你的名字（如 Zhang San）", text: $gitNameDraft)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("你的邮箱（如 you@example.com）", text: $gitEmailDraft)
                                        .textFieldStyle(.roundedBorder)
                                    FizzActionButton(title: isSavingIdentity ? "保存中…" : "保存", height: .compact, prominence: .primary) {
                                        Task {
                                            isSavingIdentity = true
                                            defer { isSavingIdentity = false }
                                            let res = await DoctorService.configureGitIdentity(
                                                name: gitNameDraft,
                                                email: gitEmailDraft
                                            )
                                            ToastCenter.shared.show(
                                                res.message,
                                                symbol: res.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                                tint: res.succeeded ? FizzTheme.statusSuccess : FizzTheme.statusWarning
                                            )
                                            if res.succeeded {
                                                showGitIdentityForm = false
                                                await store.refreshMachineEnvironment()
                                            }
                                        }
                                    }
                                    .disabled(isSavingIdentity)
                                }
                            }
                        }
                        .padding(10)
                        .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
                    }
                }
            } else {
                HStack(spacing: FizzSpacing.row) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在检查本机工具链…")
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshAll(force: Bool = true) async {
        await store.refreshMachineEnvironment(force: force)
        await store.refreshDoctorForFocused(includeIdle: true, force: force)
    }

    private func trashCleanup(for project: RepoProject) async {
        let dir = URL(fileURLWithPath: project.path)
        let result = DoctorService.trashCleanupItems(project.cleanup.items, in: dir)
        if let err = result.error {
            ToastCenter.shared.show(err, symbol: "exclamationmark.triangle.fill", tint: FizzTheme.statusWarning)
        } else {
            ToastCenter.shared.show(
                "已移入废纸篓（\(Format.bytes(result.freedBytes))）",
                symbol: "trash.fill",
                tint: FizzTheme.statusSuccess,
                subtitle: "\(project.displayName) · 清理了 \(result.trashedCount) 个目录"
            )
        }
        await store.rescanProjects([project])
        await store.refreshDoctor(for: project, scope: .idle)
    }

    private func severityColor(_ severity: DoctorSeverity) -> Color {
        switch severity {
        case .critical: FizzTheme.statusDanger
        case .warning: FizzTheme.statusWarning
        case .healthy: FizzTheme.statusSuccess
        }
    }
}

struct DoctorExemptionMenu: View {
    @Environment(RepositoryStore.self) private var store
    let project: RepoProject

    var body: some View {
        let kinds = store.exemptibleIssues(for: project)
        if !kinds.isEmpty {
            FizzMenuButton(title: "\(project.displayName)的体检豁免") {
                DoctorExemptionItems(project: project, kinds: kinds)
            }
        }
    }
}

private struct DoctorExemptionItems: View {
    @Environment(RepositoryStore.self) private var store
    let project: RepoProject
    let kinds: [DoctorIssueKind]

    var body: some View {
        let exemptions = store.doctorExemptions(for: project)
        ForEach(kinds, id: \.self) { kind in
            let exempt = exemptions.contains(kind)
            Button("\(exempt ? "恢复" : "忽略")：\(kind.exemptionTitle)") {
                store.setDoctorExemption(kind, exempt: !exempt, for: project)
            }
        }
    }
}
