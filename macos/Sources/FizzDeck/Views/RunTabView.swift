import SwiftUI

struct RunTabView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions

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
                    Panel(title: "运行服务", symbol: "play.circle") {
                        Text("暂未识别到可自动启动的开发或测试命令")
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
            "首次联网安装依赖确认",
            isPresented: Binding(
                get: { pendingInstallCommand != nil },
                set: { if !$0 { pendingInstallCommand = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                pendingInstallCommand = nil
            }
            Button("确认安装") {
                guard let command = pendingInstallCommand else { return }
                pendingInstallCommand = nil
                DoctorPreferences.setConfirmedFirstInstall(true)
                actions.runInstallDependencies(command: command, for: project, store: store)
            }
        } message: {
            if let command = pendingInstallCommand {
                Text("将运行 `\(command)` 并联网下载项目依赖，下方会实时显示安装过程并可随时停止。之后同类一键安装不再弹窗。")
            }
        }
        .alert(
            "确认关闭占用端口的程序？",
            isPresented: Binding(
                get: { pendingPortConflict != nil },
                set: { if !$0 { pendingPortConflict = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                pendingPortConflict = nil
            }
            Button("关闭占用进程", role: .destructive) {
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
                Text("端口 :\(conflict.port)\n\(conflict.details)\n只向以上进程发送 SIGTERM。")
            }
        }
    }

    private func doctorIssuesPanel(_ report: DoctorProjectReport) -> some View {
        let dir = URL(fileURLWithPath: project.path)
        let installCmd = DoctorService.detectInstallCommand(in: dir)
        let installState = actions.installRun(for: project, command: installCmd)

        return Panel(
            title: report.issues.isEmpty ? "已忽略的体检项" : "开始之前有 \(report.issues.count) 个问题",
            symbol: report.issues.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill"
        ) {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                ForEach(report.issues) { issue in
                    HStack(alignment: .center, spacing: FizzSpacing.row) {
                        FizzStatusDot(tint: issue.severity == .critical ? FizzTheme.statusDanger : FizzTheme.statusWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(FizzTypography.cardTitle)
                            Text(issue.detail)
                                .font(FizzTypography.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        doctorFixButton(issue: issue)
                    }

                    if case .installDependencies = issue.fixAction,
                       let installState,
                       (!installState.output.isEmpty || installState.status == .running) {
                        ScrollView {
                            Text(installState.output.isEmpty ? "正在执行 \(installState.script.command)…" : LogTailReader.tail(installState.output, maxLines: 40))
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
                title: isRunning ? "停止" : "安装依赖",
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
            FizzActionButton(title: "生成 .env", height: .compact) {
                Task {
                    if let url = DoctorService.createEnvFromExample(in: dir) {
                        SystemActions.open(url.path)
                        ToastCenter.shared.show("已生成 .env", symbol: "doc.badge.plus", tint: FizzTheme.statusSuccess)
                    }
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }

        case .addEnvToGitignore:
            FizzActionButton(title: "把 .env 加入忽略", height: .compact) {
                Task {
                    if LightweightProjectCheckService.addEnvFilesToGitignore(in: dir) {
                        ToastCenter.shared.show("已把 .env 加入忽略列表", symbol: "checkmark.shield.fill", tint: FizzTheme.statusSuccess)
                    }
                    await store.refreshGit(for: project.path)
                    await store.refreshDoctor(for: project, scope: .focused)
                }
            }

        case .resolvePortConflict(let conflict):
            FizzActionButton(title: "核对占用进程…", height: .compact) {
                pendingPortConflict = conflict
            }
            .disabled(!conflict.canStop)

        case .initGitRepository:
            EnableVersionProtectionButton(project: project)

        case .inspectTrackedSecrets(let files):
            FizzActionButton(title: "查看文件", height: .compact) {
                if let first = files.first {
                    SystemActions.open("\(project.path)/\(first)")
                }
            }

        case .copyShellCommand(let command):
            FizzActionButton(title: "复制切换命令", height: .compact) {
                SystemActions.copy(
                    command,
                    feedback: "运行版本切换命令已复制",
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
