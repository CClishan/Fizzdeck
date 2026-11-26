import SwiftUI

struct ServicesPanel: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    let project: RepoProject
    @State private var scripts: [ProjectScript] = []
    @State private var pinnedIDs: [String] = []
    @State private var selectedScriptID: String?
    @State private var pendingConflict: PortConflict?

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
        (devRunning ? 1 : 0) + (testRunning ? 1 : 0) + runningScriptCount
    }

    private var runningScriptCount: Int {
        scripts.filter { actions.scriptRun(for: project, script: $0)?.status == .running }.count
    }

    private var pinnedScripts: [ProjectScript] {
        pinnedIDs.compactMap { id in scripts.first { $0.id == id } }
    }

    private var unpinnedScripts: [ProjectScript] {
        scripts.filter { !pinnedIDs.contains($0.id) }
    }

    private var selectedScript: ProjectScript? {
        pinnedScripts.first { $0.id == selectedScriptID }
    }

    var body: some View {
        Panel(title: "服务", symbol: "bolt.horizontal") {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: FizzSpacing.grid)],
                    spacing: FizzSpacing.grid
                ) {
                    if let run = project.run {
                        devCard(run)
                    }
                    if let test = project.test {
                        testCard(test)
                    }
                }
                if let conflict = actions.portConflict(for: project.path), !devRunning {
                    conflictNotice(conflict)
                }
                if !scripts.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                    scriptsSection
                }
                feedback
            }
        } accessory: {
            Text(runningCount > 0 ? "\(runningCount) 运行中" : "空闲")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(runningCount > 0 ? Color.green : Color.secondary)
        }
        .task(id: project.path) {
            await loadScripts()
        }
        .alert(item: $pendingConflict) { conflict in
            Alert(
                title: Text("结束占用 :\(conflict.port) 的进程？"),
                message: Text(
                    "\(conflict.occupantSummary)\n只会向确认后的目标 PID 发送 SIGTERM，不自动强杀。"
                ),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("结束并启动")) {
                    Task {
                        await actions.resolvePortConflictAndLaunch(
                            project,
                            conflict: conflict,
                            store: store
                        )
                    }
                }
            )
        }
    }

    private func devCard(_ run: RunConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusDot(active: devRunning, busy: busy)

                Text("dev")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 4)

                if run.port > 0 {
                    Text(verbatim: ":\(run.port)")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text(run.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(run.command)

            HStack(spacing: 6) {
                Spacer(minLength: 0)

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
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            devRunning ? FizzTheme.selectedFill : FizzTheme.recessedFill,
            in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(FizzTheme.hairline, lineWidth: 1)
        }
    }

    private func conflictNotice(_ conflict: PortConflict) -> some View {
        HStack(alignment: .top, spacing: 8) {
            FizzIcon(symbol: "exclamationmark.triangle", size: 12)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("端口 :\(conflict.port) 被占用")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(conflict.occupantSummary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let note = conflict.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            serviceButton("结束占用进程并启动", help: "确认后向占用 PID 发送 SIGTERM 并启动服务") {
                pendingConflict = conflict
            }
            .disabled(busy || conflict.occupants.isEmpty)
        }
        .padding(10)
        .background(
            Color.orange.opacity(0.09),
            in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        }
    }

    private var scriptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("脚本")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(scripts.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                scriptPinMenu
            }

            if pinnedScripts.isEmpty {
                Text("从菜单固定常用脚本后可直接运行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: FizzSpacing.grid)],
                    spacing: FizzSpacing.grid
                ) {
                    ForEach(pinnedScripts) { script in
                        scriptCard(script)
                    }
                }
            }

            if let selectedScript {
                scriptOutput(selectedScript)
            }
        }
    }

    private var scriptPinMenu: some View {
        Menu {
            if unpinnedScripts.isEmpty {
                Text("全部脚本已固定")
            } else {
                ForEach(ProjectScriptSource.allCases, id: \.rawValue) { source in
                    let items = unpinnedScripts.filter { $0.source == source }
                    if !items.isEmpty {
                        Section(source.label) {
                            ForEach(items) { script in
                                Button {
                                    pin(script)
                                } label: {
                                    Text("固定 \(script.name)")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label("固定脚本", systemImage: "star")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.mini)
        .fixedSize()
        .help("固定常用脚本")
    }

    private func scriptCard(_ script: ProjectScript) -> some View {
        let run = actions.scriptRun(for: project, script: script)
        let running = run?.status == .running

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusDot(active: running, busy: false)

                Text(script.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let run, let text = scriptStatusText(run) {
                    Text(text)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(scriptStatusColor(run.status))
                }

                Button {
                    unpin(script)
                } label: {
                    FizzIcon(symbol: "star.fill", size: 10)
                        .foregroundStyle(FizzTheme.accent)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)
                .help("取消固定 \(script.name)")
                .accessibilityLabel("取消固定 \(script.name)")
            }

            HStack(spacing: 5) {
                Text(script.source.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(FizzTheme.recessedFill, in: Capsule())
                Text(script.command)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(script.command)
            }

            HStack(spacing: 6) {
                serviceButton("输出", help: "查看 \(script.name) 输出") {
                    selectedScriptID = selectedScriptID == script.id ? nil : script.id
                }

                serviceButton("日志", help: "打开 \(script.name) 日志") {
                    actions.openScriptLog(script, project: project)
                }

                Spacer(minLength: 0)

                if running {
                    serviceButton("停止", help: "停止 \(script.name)") {
                        actions.stopScript(script, project: project)
                    }
                } else {
                    serviceButton("运行", help: "运行 \(script.command)") {
                        selectedScriptID = script.id
                        actions.runScript(script, project: project, store: store)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            running ? FizzTheme.selectedFill : FizzTheme.recessedFill,
            in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(FizzTheme.hairline, lineWidth: 1)
        }
    }

    private func scriptOutput(_ script: ProjectScript) -> some View {
        let run = actions.scriptRun(for: project, script: script)
        let text = run?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(script.name)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                if let run {
                    Text(scriptStatusText(run) ?? "")
                        .font(.system(size: 9.5))
                        .foregroundStyle(scriptStatusColor(run.status))
                }
                Spacer(minLength: 8)
                Button {
                    selectedScriptID = nil
                } label: {
                    FizzIcon(symbol: "xmark", size: 8)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("收起输出")
                .accessibilityLabel("收起脚本输出")
            }

            ScrollView {
                Text(text.isEmpty ? "暂无输出" : text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
            }
            .frame(height: 140)
            .background(
                FizzTheme.recessedFill,
                in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .strokeBorder(FizzTheme.hairline, lineWidth: 1)
            }
        }
    }

    private func scriptStatusText(_ run: ScriptRunState) -> String? {
        switch run.status {
        case .running:
            "运行中"
        case .succeeded:
            "完成 · \(String(format: "%.1fs", run.duration ?? 0))"
        case .failed:
            "失败 · \(String(format: "%.1fs", run.duration ?? 0))"
        case .stopped:
            "已停止"
        }
    }

    private func scriptStatusColor(_ status: ScriptRunStatus) -> Color {
        switch status {
        case .running: .secondary
        case .succeeded: .green
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private func pin(_ script: ProjectScript) {
        var ids = pinnedIDs
        guard !ids.contains(script.id) else { return }
        ids.append(script.id)
        pinnedIDs = ProjectScriptPreferences
            .setPinned(ids, for: project.path)
            .pinnedIDs(for: project.path)
    }

    private func unpin(_ script: ProjectScript) {
        let ids = pinnedIDs.filter { $0 != script.id }
        pinnedIDs = ProjectScriptPreferences
            .setPinned(ids, for: project.path)
            .pinnedIDs(for: project.path)
        if selectedScriptID == script.id {
            selectedScriptID = nil
        }
    }

    private func loadScripts() async {
        let path = project.path
        let found = await Task.detached(priority: .utility) {
            RunDetector.scripts(URL(fileURLWithPath: path))
        }.value
        guard !Task.isCancelled else { return }
        scripts = found
        pinnedIDs = ProjectScriptPreferences.load().pinnedIDs(for: path)
        if let selectedScriptID, !scripts.contains(where: { $0.id == selectedScriptID }) {
            self.selectedScriptID = nil
        }
    }

    private func testCard(_ test: TestCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusDot(active: testRunning, busy: false)

                Text(test.label)
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 4)

                if let testRun, let text = testStatusText(testRun) {
                    Text(text)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(testStatusColor(testRun.status))
                }
            }

            Text(test.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(test.command)

            HStack(spacing: 6) {
                Spacer(minLength: 0)

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
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
