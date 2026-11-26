import SwiftUI

struct ServicesPanel: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    let project: RepoProject

    private var devRunning: Bool {
        project.port == .running
    }

    private var testRun: TestRunState? {
        actions.testRun(for: project.path)
    }

    private var testRunning: Bool {
        testRun?.status == .running
    }

    private var busy: Bool {
        actions.isBusy(project.path)
    }

    private var runningCount: Int {
        (devRunning ? 1 : 0) + (testRunning ? 1 : 0)
    }

    var body: some View {
        Panel(title: "服务", symbol: "bolt.horizontal") {
            VStack(spacing: 8) {
                if let run = project.run {
                    devRow(run)
                }
                if let test = project.test {
                    testRow(test)
                }
                feedback
            }
        } accessory: {
            Text(runningCount > 0 ? "\(runningCount) 运行中" : "空闲")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(runningCount > 0 ? Color.green : Color.secondary)
        }
    }

    private func devRow(_ run: RunConfig) -> some View {
        HStack(spacing: 10) {
            statusDot(active: devRunning, busy: busy)

            VStack(alignment: .leading, spacing: 2) {
                Text("dev")
                    .font(.system(size: 13, weight: .semibold))
                Text(run.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if run.port > 0 {
                Text(verbatim: ":\(run.port)")
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if devRunning {
                if run.port > 0 {
                    serviceButton("预览", help: "在浏览器打开 localhost:\(run.port)") {
                        SystemActions.openURL("http://127.0.0.1:\(run.port)")
                    }
                }

                serviceButton("停止", help: "停止开发服务") {
                    Task { await actions.stop(project, store: store) }
                }
                .disabled(busy)
            } else {
                serviceButton("启动", help: "启动开发服务") {
                    Task { await actions.launch(project, store: store) }
                }
                .disabled(busy)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            devRunning ? FizzTheme.selectedFill : FizzTheme.recessedFill,
            in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(FizzTheme.hairline, lineWidth: 1)
        }
    }

    private func testRow(_ test: TestCommand) -> some View {
        HStack(spacing: 10) {
            statusDot(active: testRunning, busy: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(test.label)
                    .font(.system(size: 13, weight: .semibold))
                Text(test.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let testRun, let text = testStatusText(testRun) {
                Text(text)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(testStatusColor(testRun.status))
            }

            if testRunning {
                serviceButton("停止", help: "停止测试运行") {
                    actions.stopTests(project)
                }
            } else {
                serviceButton("运行", help: "运行测试命令") {
                    actions.runTests(project, store: store)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            testRunning ? FizzTheme.selectedFill : FizzTheme.recessedFill,
            in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(FizzTheme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func statusDot(active: Bool, busy: Bool) -> some View {
        if busy {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
    }

    private func serviceButton(
        _ title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)
        }
        .buttonStyle(.glass)
        .controlSize(.mini)
        .help(help)
        .accessibilityLabel(help)
    }

    private func testStatusText(_ run: TestRunState) -> String? {
        switch run.status {
        case .running:
            "运行中"
        case .passed:
            "通过 · \(duration(run))"
        case .failed:
            "失败 · \(duration(run))"
        }
    }

    private func testStatusColor(_ status: TestStatus) -> Color {
        switch status {
        case .running: .secondary
        case .passed: .green
        case .failed: .red
        }
    }

    private func duration(_ run: TestRunState) -> String {
        String(format: "%.1fs", run.duration ?? 0)
    }

    @ViewBuilder
    private var feedback: some View {
        let devMessage = actions.message(for: project.path)
        let testMessage = actions.testMessage(for: project.path)

        if devMessage != nil || testMessage != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let devMessage {
                    feedbackLine(devMessage)
                }
                if let testMessage {
                    feedbackLine(testMessage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    private func feedbackLine(_ text: String) -> some View {
        HStack(spacing: 5) {
            FizzIcon(symbol: "info.circle", size: 9)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(text)
    }
}

struct ProjectLogsPanel: View {
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject
    let devAvailable: Bool
    let testAvailable: Bool

    @State private var source: ProjectLogSource = .dev
    @State private var expanded = true
    @State private var text = ""

    private var testRun: TestRunState? {
        actions.testRun(for: project.path)
    }

    private var devActive: Bool {
        project.port == .running || actions.isBusy(project.path)
    }

    private var testActive: Bool {
        testRun?.status == .running
    }

    private var isActive: Bool {
        source == .dev ? devActive : testActive
    }

    private var logContext: ProjectLogContext {
        ProjectLogContext(
            projectPath: project.path,
            testStartedAt: testRun?.startedAt,
            devAvailable: devAvailable,
            testAvailable: testAvailable,
            testActive: testActive
        )
    }

    private var pollKey: String {
        [
            project.path,
            source.rawValue,
            expanded ? "expanded" : "collapsed",
            isActive ? "active" : "idle",
            devAvailable ? "dev" : "",
            testAvailable ? "test" : "",
        ].joined(separator: "|")
    }

    var body: some View {
        Panel(title: "日志", symbol: "terminal") {
            if expanded {
                viewport
            }
        } accessory: {
            HStack(spacing: 8) {
                if devAvailable && testAvailable {
                    sourceSwitcher
                } else if devAvailable || testAvailable {
                    Text(source.title)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                        expanded.toggle()
                    }
                } label: {
                    FizzIcon(symbol: expanded ? "chevron.up" : "chevron.down", size: 9)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "折叠日志" : "展开日志")
                .accessibilityLabel(expanded ? "折叠日志" : "展开日志")

                Button {
                    actions.openLog(for: project, test: source == .test)
                } label: {
                    FizzIcon(symbol: "arrow.up.forward.square", size: 11)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开完整日志")
                .accessibilityLabel("打开完整日志")
            }
        }
        .task(id: pollKey) {
            await poll()
        }
        .onAppear {
            source = ProjectLogSourcePolicy.resolve(
                current: logContext,
                previous: nil,
                selected: source
            )
        }
        .onChange(of: logContext) { previous, current in
            if previous.projectPath != current.projectPath {
                text = ""
            }
            source = ProjectLogSourcePolicy.resolve(
                current: current,
                previous: previous,
                selected: source
            )
        }
    }

    private var sourceSwitcher: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 1) {
                ForEach(ProjectLogSource.allCases) { item in
                    Button {
                        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                            source = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 10, weight: source == item ? .semibold : .medium))
                            .foregroundStyle(source == item ? Color.primary : Color.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background {
                                if source == item {
                                    Capsule()
                                        .fill(FizzTheme.elevatedFill)
                                        .fizzAdaptiveShadow(.subtle)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(source == item ? .isSelected : [])
                    .accessibilityRemoveTraits(source == item ? [] : .isSelected)
                    .accessibilityLabel(item == .dev ? "开发日志" : "测试日志")
                }
            }
            .padding(2)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("日志来源")
    }

    private var viewport: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.isEmpty ? "暂无日志输出" : text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id("log-bottom")
                }
            }
            .frame(height: 210)
            .background(
                FizzTheme.recessedFill,
                in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: text) {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
            proxy.scrollTo("log-bottom", anchor: .bottom)
        }
    }

    private func poll() async {
        await refresh()
        guard expanded, isActive else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(1_200))
            } catch {
                return
            }
            if Task.isCancelled { return }
            await refresh()
        }
    }

    private func refresh() async {
        if source == .test,
           let output = actions.testRun(for: project.path)?.output,
           !output.isEmpty {
            let value = LogTailReader.tail(output)
            guard !Task.isCancelled else { return }
            text = value
            return
        }

        let path = actions.logPath(for: project, prefix: source == .test ? "test-" : "")
        let value = await Task.detached(priority: .utility) {
            LogTailReader.read(path: path)
        }.value
        guard !Task.isCancelled else { return }
        text = value
    }
}
