import SwiftUI

struct ProjectActionDock: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject
    let tab: ProjectTab

    private var run: RunConfig? {
        project.run
    }

    private var testRun: TestRunState? {
        actions.testRun(for: project.path)
    }

    private var isRunning: Bool {
        project.port == .running
    }

    private var isTestRunning: Bool {
        testRun?.status == .running
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                status

                Spacer(minLength: 8)

                if tab == .tests {
                    testActions
                } else {
                    runActions
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule())
        }
        .frame(maxWidth: 900)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab == .tests ? "测试操作" : "运行操作")
    }

    @ViewBuilder
    private var runActions: some View {
        if let run {
            runButton
            if isRunning, let url = run.previewURL {
                dockButton(
                    symbol: "safari",
                    title: "打开预览",
                    label: "打开预览"
                ) {
                    SystemActions.openURL(url)
                }
            }
            dockButton(
                symbol: "terminal",
                title: "在 Terminal 中打开",
                label: "Terminal"
            ) {
                SystemActions.openTerminal(project.path)
            }
            dockButton(
                symbol: "doc.on.doc",
                title: "复制启动命令",
                label: "复制命令"
            ) {
                SystemActions.copy(run.command)
            }
            dockButton(
                symbol: "doc.text.magnifyingglass",
                title: "打开启动日志",
                label: "启动日志"
            ) {
                actions.openLog(for: project)
            }
        }
    }

    @ViewBuilder
    private var testActions: some View {
        if let test = project.test {
            testButton
            dockButton(
                symbol: "list.bullet.rectangle",
                title: "打开测试日志",
                label: "测试日志"
            ) {
                actions.openLog(for: project, test: true)
            }
            dockButton(
                symbol: "doc.on.clipboard",
                title: "复制测试命令",
                label: "复制测试"
            ) {
                SystemActions.copy(test.command)
            }
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(reduceMotion ? .identity : .opacity)
                Text(statusDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 132, maxWidth: 220, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var runButton: some View {
        dockButton(
            symbol: isRunning ? "stop.fill" : "play.fill",
            title: isRunning ? "停止开发服务" : "启动开发服务",
            label: isRunning ? "停止服务" : "启动服务",
            disabled: actions.isBusy(project.path)
        ) {
            Task {
                if isRunning {
                    await actions.stop(project, store: store)
                } else {
                    await actions.launch(project, store: store)
                }
            }
        }
    }

    private var testButton: some View {
        dockButton(
            symbol: testSymbol,
            title: isTestRunning ? "停止测试" : "运行测试",
            label: isTestRunning ? "停止测试" : "运行测试"
        ) {
            if isTestRunning {
                actions.stopTests(project)
            } else {
                actions.runTests(project, store: store)
            }
        }
    }

    private func dockButton(
        symbol: String,
        title: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(width: 66, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private var statusTitle: String {
        if tab == .tests {
            switch testRun?.status {
            case .running: return "测试中"
            case .passed: return "测试通过"
            case .failed: return "测试失败"
            case nil: return project.test == nil ? "未配置测试" : "未测试"
            }
        }
        if isRunning { return "运行中" }
        return run == nil ? "未配置运行" : "未启动"
    }

    private var statusDetail: String {
        let message = tab == .tests
            ? actions.testMessage(for: project.path)
            : actions.message(for: project.path)
        if let message, !message.isEmpty {
            return message
        }

        if tab == .tests {
            return project.test?.command ?? "未识别测试命令"
        }

        var parts: [String] = []
        if let run {
            parts.append(run.port > 0 ? "localhost:\(run.port)" : run.command)
        }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        if tab == .tests {
            guard let testRun else { return .orange }
            switch testRun.status {
            case .running: return .secondary
            case .passed: return .green
            case .failed: return .red
            }
        }
        if isRunning { return .green }
        return run == nil ? .secondary : .orange
    }

    private var testSymbol: String {
        guard let testRun else { return "testtube.2" }
        switch testRun.status {
        case .running: return "stop.fill"
        case .passed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }
}
