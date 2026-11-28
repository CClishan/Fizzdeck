import SwiftUI

struct RunTabView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions

    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    let project: RepoProject

    @State private var devLogExists = false
    @State private var testLogExists = false
    @State private var pendingInstallCommand: String?
    @State private var pendingPortConflict: PortConflict?

    private var testRun: TestRunState? {
        actions.testRun(for: project.path)
    }

    private var logAvailabilityKey: String {
        [
            project.path,
            project.port.rawValue,
            actions.isBusy(project.path) ? "busy" : "idle",
            testRun?.status.rawValue ?? "none",
        ].joined(separator: "|")
    }

    private var logsVisible: Bool {
        devLogExists || testLogExists || project.port == .running || testRun?.status == .running
    }

    private var installScriptStatus: ScriptRunStatus? {
        let cmd = DoctorService.detectInstallCommand(in: URL(fileURLWithPath: project.path))
        return actions.installRun(for: project, command: cmd)?.status
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                if let report = store.doctorReports[project.path], !report.issues.isEmpty || !store.doctorExemptions(for: project).isEmpty {
                    doctorIssuesPanel(report)
                }

                if project.run != nil || project.test != nil {
                    ServicesPanel(project: project, hasTrialPanel: true)
                } else {
                    Panel(title: FizzL10n.text("运行服务", "Run services"), symbol: "play.circle") {
                        Text(FizzL10n.text("暂未识别到可自动启动的开发或测试命令", "No development or test command found to run automatically."))
                            .font(FizzTypography.body)
                            .foregroundStyle(.secondary)
                    }
                }

                ProjectTrialPanel(project: project)

                if logsVisible {
                    ProjectLogsPanel(
                        project: project,
                        devAvailable: devLogExists,
                        testAvailable: testLogExists
                    )
                }
            }
            .padding(FizzSpacing.page)
        }
        .fizzTracksScrollPastTop()
        .task(id: logAvailabilityKey) {
            await refreshLogAvailability()
        }
        .task(id: project.path) {
            await store.refreshDoctor(for: project, scope: .focused, force: false)
        }
        .onChange(of: installScriptStatus) {
            if installScriptStatus == .succeeded || installScriptStatus == .failed || installScriptStatus == .stopped {
                Task { await store.refreshDoctor(for: project, scope: .focused) }
            }
        }
        .onChange(of: project.path) {
            devLogExists = false
            testLogExists = false
        }
        .alert(
            FizzL10n.text("首次联网安装依赖确认", "Allow the first dependency download?"),
            isPresented: Binding(
                get: { pendingInstallCommand != nil },
                set: { if !$0 { pendingInstallCommand = nil } }
            )
        ) {
            Button(FizzL10n.text("取消", "Cancel"), role: .cancel) {
                pendingInstallCommand = nil
            }
            Button(FizzL10n.text("确认安装", "Install")) {
                guard let command = pendingInstallCommand else { return }
                pendingInstallCommand = nil
                DoctorPreferences.setConfirmedFirstInstall(true)
                actions.runInstallDependencies(command: command, for: project, store: store)
            }
        } message: {
            if let command = pendingInstallCommand {
                Text(FizzL10n.text("将运行 `\(command)` 并联网下载项目依赖，下方会实时显示安装过程并可随时停止。之后同类一键安装不再弹窗。", "This runs \(command) to download the project’s dependencies. Watch the log below or stop the install at any time. Future one-click installs won’t ask again."))
            }
        }
        .alert(
            FizzL10n.text("确认关闭占用端口的程序？", "Stop the program using this port?"),
            isPresented: Binding(
                get: { pendingPortConflict != nil },
                set: { if !$0 { pendingPortConflict = nil } }
            )
        ) {
            Button(FizzL10n.text("取消", "Cancel"), role: .cancel) {
                pendingPortConflict = nil
            }
            Button(FizzL10n.text("关闭占用进程", "Stop process"), role: .destructive) {
                guard let conflict = pendingPortConflict else { return }
                pendingPortConflict = nil
                Task {
                    let result = await PortConflictService.terminateConfirmed(conflict.confirmedByUser())
                    ToastCenter.shared.show(
                        result.message,
                        symbol: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: result.succeeded ? FizzTheme.statusSuccess : FizzTheme.statusWarning
                    )
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }
        } message: {
            if let conflict = pendingPortConflict {
                Text(FizzL10n.text("端口 :\(conflict.port)\n\(conflict.details)\n只向以上进程发送 SIGTERM。", "Port \(conflict.port)\n\(conflict.details)\nOnly the listed processes will receive SIGTERM."))
            }
        }
    }

    private func doctorIssuesPanel(_ report: DoctorProjectReport) -> some View {
        Panel(
            title: report.issues.isEmpty ? FizzL10n.text("已忽略的体检项", "Ignored checks") : FizzL10n.text("开始之前有 \(report.issues.count) 个问题", "\(report.issues.count) \(report.issues.count == 1 ? "issue" : "issues") to review before running"),
            symbol: report.issues.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill"
        ) {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                ForEach(report.issues) { issue in
                    HStack(alignment: .center, spacing: FizzSpacing.row) {
                        FizzStatusDot(tint: issue.severity == .critical ? FizzTheme.statusDanger : FizzTheme.statusWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title(for: copyMode))
                                .font(FizzTypography.cardTitle)
                            Text(issue.detail)
                                .font(FizzTypography.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        doctorFixButton(issue: issue)
                    }

                    if case .installDependencies(let command) = issue.fixAction,
                       let installState = actions.installRun(for: project, command: command),
                       (!installState.output.isEmpty || installState.status == .running) {
                        ScrollView {
                            Text(installState.output.isEmpty ? FizzL10n.text("正在执行 \(installState.script.command)…", "Running \(installState.script.command)…") : LogTailReader.tail(installState.output, maxLines: 40))
                                .font(FizzTypography.monoSmall)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 110)
                        .background(
                            FizzTheme.recessedFill,
                            in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        )
                    }
                }
            }
        } accessory: {
            DoctorExemptionMenu(project: project)
        }
    }

    @ViewBuilder
    private func doctorFixButton(issue: DoctorIssue) -> some View {
        let dir = URL(fileURLWithPath: project.path)
        switch issue.fixAction {
        case .installDependencies(let command):
            let isRunning = actions.installRun(for: project, command: command)?.status == .running
            FizzActionButton(
                title: isRunning ? FizzL10n.text("停止", "Stop") : FizzL10n.text("安装依赖", "Install dependencies"),
                height: .compact,
                prominence: isRunning ? .secondary : .primary
            ) {
                if isRunning {
                    actions.stopInstallDependencies(command: command, for: project)
                } else if DoctorPreferences.hasConfirmedFirstInstall() {
                    actions.runInstallDependencies(command: command, for: project, store: store)
                } else {
                    pendingInstallCommand = command
                }
            }

        case .createEnvFromExample:
            FizzActionButton(title: FizzL10n.text("生成 .env", "Create .env"), height: .compact) {
                Task {
                    if let url = DoctorService.createEnvFromExample(in: dir) {
                        SystemActions.open(url.path)
                        ToastCenter.shared.show(FizzL10n.text("已生成 .env", "Created .env"), symbol: "doc.badge.plus", tint: FizzTheme.statusSuccess)
                    }
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }

        case .addEnvToGitignore:
            FizzActionButton(title: FizzL10n.text("把 .env 加入忽略", "Ignore .env"), height: .compact) {
                Task {
                    if LightweightProjectCheckService.addEnvFilesToGitignore(in: dir) {
                        ToastCenter.shared.show(FizzL10n.text("已把 .env 加入忽略列表", "Added .env to the ignore list"), symbol: "checkmark.shield.fill", tint: FizzTheme.statusSuccess)
                    }
                    await store.refreshGit(for: project.path)
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }

        case .resolvePortConflict(let conflict):
            FizzActionButton(title: FizzL10n.text("核对占用进程…", "Review process…"), height: .compact) {
                pendingPortConflict = conflict
            }
            .disabled(!conflict.canStop)

        case .initGitRepository:
            EnableVersionProtectionButton(project: project)

        case .inspectTrackedSecrets(let files):
            FizzActionButton(title: FizzL10n.text("查看文件", "View file"), height: .compact) {
                if let first = files.first {
                    SystemActions.open("\(project.path)/\(first)")
                }
            }

        case .copyShellCommand(let command):
            FizzActionButton(title: FizzL10n.text("复制切换命令", "Copy command"), height: .compact) {
                SystemActions.copy(
                    command,
                    feedback: FizzL10n.text("运行版本切换命令已复制", "Copied runtime switch command"),
                    microViz: .compact(state: .done)
                )
            }

        case nil:
            EmptyView()
        }
    }

    private func refreshLogAvailability() async {
        let devPath = actions.logPath(for: project)
        let testPath = actions.logPath(for: project, prefix: "test-")
        let result = await Task.detached(priority: .utility) {
            (FileTools.exists(devPath), FileTools.exists(testPath))
        }.value
        guard !Task.isCancelled else { return }
        devLogExists = result.0
        testLogExists = result.1
    }
}
