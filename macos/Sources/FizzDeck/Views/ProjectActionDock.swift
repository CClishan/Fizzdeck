import SwiftUI

struct ProjectActionDock: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject

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
            HStack(spacing: 10) {
                status

                Spacer(minLength: 10)

                if run != nil {
                    runButton
                }
                if project.test != nil {
                    testButton
                }
                options
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
        }
        .frame(maxWidth: 640)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("运行与测试")
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
        .frame(minWidth: 150, alignment: .leading)
    }

    private var runButton: some View {
        Button {
            Task {
                if isRunning {
                    await actions.stop(project, store: store)
                } else {
                    await actions.launch(project, store: store)
                }
            }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 24)
                .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(actions.isBusy(project.path))
        .help(isRunning ? "停止开发服务" : "启动开发服务")
        .accessibilityLabel(isRunning ? "停止开发服务" : "启动开发服务")
    }

    private var testButton: some View {
        Button {
            if isTestRunning {
                actions.stopTests(project)
            } else {
                actions.runTests(project, store: store)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: testSymbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(testButtonTitle)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .help(isTestRunning ? "停止测试" : "运行测试")
        .accessibilityLabel(isTestRunning ? "停止测试" : "运行测试")
    }

    private var options: some View {
        Menu {
            if let run {
                Button {
                    SystemActions.openTerminal(project.path)
                } label: {
                    Label("在 Terminal 中打开", systemImage: "terminal")
                }
                Button {
                    SystemActions.copy(run.command)
                } label: {
                    Label("复制启动命令", systemImage: "doc.on.doc")
                }
                if isRunning, let url = run.previewURL {
                    Button {
                        SystemActions.openURL(url)
                    } label: {
                        Label("打开预览", systemImage: "safari")
                    }
                }
                Button {
                    actions.openLog(for: project)
                } label: {
                    Label("打开启动日志", systemImage: "doc.text.magnifyingglass")
                }
            }

            if let test = project.test {
                if run != nil { Divider() }
                Button {
                    actions.openLog(for: project, test: true)
                } label: {
                    Label("打开测试日志", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    SystemActions.copy(test.command)
                } label: {
                    Label("复制测试命令", systemImage: "doc.on.doc")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .controlSize(.small)
        .help("更多运行与测试操作")
        .accessibilityLabel("更多运行与测试操作")
    }

    private var statusTitle: String {
        if isTestRunning { return "测试中" }
        if isRunning { return "运行中" }
        return run == nil ? "测试" : "未启动"
    }

    private var statusDetail: String {
        if let message = actions.message(for: project.path), !message.isEmpty {
            return message
        }

        var parts: [String] = []
        if let run {
            parts.append(run.port > 0 ? "localhost:\(run.port)" : run.command)
        }
        if let testRun {
            parts.append(testStatusText(testRun))
        } else if let test = project.test {
            parts.append(test.command)
        }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        if let testRun {
            switch testRun.status {
            case .running: return .secondary
            case .passed: return .green
            case .failed: return .red
            }
        }
        if isRunning { return .green }
        return run == nil ? .secondary : .orange
    }

    private var testButtonTitle: String {
        if isTestRunning { return "停止" }
        return testRun == nil ? "测试" : "重测"
    }

    private var testSymbol: String {
        guard let testRun else { return "play.fill" }
        switch testRun.status {
        case .running: return "stop.fill"
        case .passed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }

    private func testStatusText(_ run: TestRunState) -> String {
        switch run.status {
        case .running:
            return "测试运行中"
        case .passed:
            return "测试通过 · \(String(format: "%.1f", run.duration ?? 0))s"
        case .failed:
            return "测试失败 · \(String(format: "%.1f", run.duration ?? 0))s"
        }
    }
}
