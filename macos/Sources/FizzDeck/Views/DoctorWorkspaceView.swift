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

    private var focusedHealthyCount: Int {
        partition.focused.filter { entry in
            (store.doctorReports[entry.project.path]?.severity ?? .healthy) == .healthy
        }.count
    }

    private var focusedAttentionCount: Int {
        partition.focused.count - focusedHealthyCount
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
            await refreshAll()
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("体检")
                    .font(.system(size: 27, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 6) {
                    if partition.focused.isEmpty {
                        Text("还没有关注或近期活跃项目，先关注几个在做的项目吧")
                    } else {
                        Text("关注的 \(partition.focused.count) 个项目：\(focusedHealthyCount) 个状态良好，\(focusedAttentionCount) 个需要处理")
                    }
                    if let checkedAt = store.lastDoctorCheckAt {
                        Text("· 上次检查 \(Format.relative(checkedAt))")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                Task { await refreshAll() }
            } label: {
                if store.isRunningDoctor {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(store.isRunningDoctor)
        }
    }

    private var focusedSection: some View {
        Panel(title: "关注项目（随时能跑起来）", symbol: "stethoscope") {
            if partition.focused.isEmpty {
                Text("当你在做项目时，这里会自动盯住「缺依赖」「端口占用」「密钥风险」和「没开版本保护」。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(partition.focused) { entry in
                        focusedProjectRow(entry.project)
                        if entry.id != partition.focused.last?.id {
                            Divider()
                                .opacity(0.25)
                        }
                    }

                    if partition.overflowActiveCount > 0 {
                        HStack {
                            Text("还有 \(partition.overflowActiveCount) 个近期活跃项目未列入关注上限")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("查看项目库") {
                                store.openLibrary()
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FizzTheme.accent)
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private func focusedProjectRow(_ project: RepoProject) -> some View {
        let report = store.doctorReports[project.path]
        let topIssue = report?.issues.first
        let severity = report?.severity ?? .healthy

        return HStack(spacing: 12) {
            Circle()
                .fill(severityColor(severity))
                .frame(width: 8, height: 8)

            ProjectBadgeIcon(project: project, size: 24, framed: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.system(size: 13, weight: .semibold))
                if let topIssue {
                    Text(topIssue.title)
                        .font(.caption)
                        .foregroundStyle(severityColor(topIssue.severity))
                        .lineLimit(1)
                } else {
                    Text("一切正常 · \(Format.relative(project.recent ?? project.sessions.lastSessionAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let topIssue, let fix = topIssue.fixAction {
                issueQuickButton(fix: fix, for: project)
            }

            Button {
                store.openProject(project, tab: .run)
            } label: {
                FizzIcon(symbol: "chevron.right", size: 11)
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("打开 \(project.displayName) 运行页")
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func issueQuickButton(fix: DoctorFixAction, for project: RepoProject) -> some View {
        switch fix {
        case .installDependencies(let command):
            let isInstalling = actions.installRun(for: project, command: command)?.status == .running
            Button(isInstalling ? "查看安装" : "安装依赖") {
                if isInstalling {
                    store.openProject(project, tab: .run)
                } else if DoctorPreferences.hasConfirmedFirstInstall() {
                    actions.runInstallDependencies(command: command, for: project, store: store)
                    store.openProject(project, tab: .run)
                } else {
                    pendingInstallTarget = (project, command)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        case .createEnvFromExample:
            Button("生成 .env") {
                Task {
                    if let url = DoctorService.createEnvFromExample(in: URL(fileURLWithPath: project.path)) {
                        SystemActions.open(url.path)
                        ToastCenter.shared.show("已根据模板生成 .env", symbol: "doc.badge.plus", tint: .green)
                    }
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        case .addEnvToGitignore:
            Button("加入忽略") {
                Task {
                    if LightweightProjectCheckService.addEnvFilesToGitignore(in: URL(fileURLWithPath: project.path)) {
                        ToastCenter.shared.show("已把 .env 加入忽略列表", symbol: "checkmark.shield.fill", tint: .green)
                    }
                    await store.refreshGit(for: project.path)
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        case .initGitRepository:
            Button("开启版本保护") {
                Task {
                    let res = await DoctorService.initGitRepository(in: URL(fileURLWithPath: project.path))
                    ToastCenter.shared.show(res.message, symbol: "checkmark.shield", tint: res.succeeded ? .green : .orange)
                    await store.refreshGit(for: project.path)
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        case .resolvePortConflict:
            Button("去处理") {
                store.openProject(project, tab: .run)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        case .inspectTrackedSecrets:
            Button("去处理") {
                store.openProject(project, tab: .version)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var idleCleanupSection: some View {
        Panel(
            title: "闲置整理与腾空间",
            symbol: "archivebox"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !idleSecretRiskProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(idleSecretRiskProjects, id: \.project.id) { entry in
                            HStack(spacing: 8) {
                                FizzIcon(symbol: "exclamationmark.shield.fill", size: 12)
                                    .foregroundStyle(.orange)
                                Text("闲置项目「\(entry.project.displayName)」存在密钥或未忽略 .env 风险")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Button("去处理") {
                                    store.openProject(entry.project, tab: .version)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
                        }
                    }
                }

                if cleanableProjects.isEmpty {
                    Text("没有命中依赖、缓存或构建产物的可腾空间目录。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("默认「移到废纸篓」（可随时在系统废纸篓放回或重新安装恢复）；共发现 \(cleanableProjects.count) 个项目、可腾出 \(Format.bytes(totalReusableBytes))。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .opacity(0.25)

                    VStack(spacing: 0) {
                        ForEach(cleanableProjects) { project in
                            HStack(spacing: 10) {
                                ProjectBadgeIcon(project: project, size: 22, framed: false)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("\(project.cleanup.items.count) 个目录 · \(project.cleanup.items.map(\.label).prefix(3).joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                Text(Format.bytes(project.cleanup.reusableBytes))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.orange)

                                if copyMode == .pro {
                                    Button("复制命令") {
                                        SystemActions.copy(
                                            "# \(project.displayName)\n\(project.cleanup.removalCommand)",
                                            microViz: .compact(state: .done)
                                        )
                                        ToastCenter.shared.show("已复制清理命令", symbol: "doc.on.doc", tint: FizzTheme.accent, subtitle: project.displayName)
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                }

                                Button("移到废纸篓") {
                                    pendingTrashProject = project
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 8)

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
                TagChip(text: "可省 \(Format.bytes(totalReusableBytes))", tint: .orange, compact: true)
            }
        }
    }

    private var machineEnvironmentSection: some View {
        Panel(title: "本机环境", symbol: "desktopcomputer") {
            if let env = store.machineEnv {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 8) {
                        TagChip(
                            text: env.gitInstalled ? "✓ Git 已就绪" : "⚠ 缺少 Git",
                            tint: env.gitInstalled ? .green : .red,
                            compact: true
                        )
                        TagChip(
                            text: env.nodeVersion.map { "✓ Node \($0)" } ?? "○ 未检测到 Node",
                            tint: env.nodeVersion != nil ? .green : .secondary,
                            compact: true
                        )
                        ForEach(env.cliTools) { tool in
                            TagChip(
                                text: tool.available ? "✓ \(tool.title)" : "○ \(tool.title) 未安装",
                                tint: tool.available ? .green : .secondary,
                                compact: true
                            )
                        }
                        if let disk = env.disk {
                            TagChip(
                                text: "磁盘剩余 \(Format.bytes(disk.free))",
                                tint: disk.free < 10_000_000_000 ? .orange : .secondary,
                                compact: true
                            )
                        }
                    }

                    if env.needsGitIdentity {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                FizzIcon(symbol: "exclamationmark.triangle.fill", size: 12)
                                    .foregroundStyle(.orange)
                                Text("Git 还没设置你的名字和邮箱（首次「存个版本」时需要）")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Button(showGitIdentityForm ? "收起" : "去设置") {
                                    gitNameDraft = env.gitUserName ?? ""
                                    gitEmailDraft = env.gitUserEmail ?? ""
                                    showGitIdentityForm.toggle()
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }

                            if showGitIdentityForm {
                                HStack(spacing: 8) {
                                    TextField("你的名字（如 Zhang San）", text: $gitNameDraft)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("你的邮箱（如 you@example.com）", text: $gitEmailDraft)
                                        .textFieldStyle(.roundedBorder)
                                    Button(isSavingIdentity ? "保存中…" : "保存") {
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
                                                tint: res.succeeded ? .green : .orange
                                            )
                                            if res.succeeded {
                                                showGitIdentityForm = false
                                                await store.refreshMachineEnvironment()
                                            }
                                        }
                                    }
                                    .buttonStyle(.glassProminent)
                                    .tint(FizzTheme.accent)
                                    .controlSize(.small)
                                    .disabled(isSavingIdentity)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在检查本机工具链…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshAll() async {
        await store.refreshDoctorForFocused(includeIdle: true)
        await store.refreshMachineEnvironment()
    }

    private func trashCleanup(for project: RepoProject) async {
        let dir = URL(fileURLWithPath: project.path)
        let result = DoctorService.trashCleanupItems(project.cleanup.items, in: dir)
        if let err = result.error {
            ToastCenter.shared.show(err, symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else {
            ToastCenter.shared.show(
                "已移入废纸篓（\(Format.bytes(result.freedBytes))）",
                symbol: "trash.fill",
                tint: .green,
                subtitle: "\(project.displayName) · 清理了 \(result.trashedCount) 个目录"
            )
        }
        await store.rescanProjects([project])
        await store.refreshDoctorForFocused(includeIdle: true)
    }

    private func severityColor(_ severity: DoctorSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .healthy: .green
        }
    }
}
