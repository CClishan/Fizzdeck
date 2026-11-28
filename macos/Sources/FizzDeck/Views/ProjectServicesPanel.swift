import SwiftUI

struct ServicesPanel: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(ProjectActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: RepoProject
    var hasTrialPanel = false
    @State private var scripts: [ProjectScript] = []
    @State private var checkIsTypecheck = false
    @State private var pinnedIDs: [String] = []
    @State private var selectedScriptID: String?
    @State private var pendingConflict: PortConflict?

    @State private var devRunning = false

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
        Group {
            if project.run != nil || showTestCard || !scripts.isEmpty {
                services
            }
        }
        .task(id: project.path) { await loadScripts() }
    }

    private var showTestCard: Bool {
        guard let test = project.test else { return false }
        // On the Run tab the shared trial panel owns these controls. Keep an existing legacy run stoppable.
        return !hasTrialPanel || testRunning || test.label == "lint" || (test.label == "check" && !checkIsTypecheck)
    }

    private var services: some View {
        Panel(title: "服务", symbol: "bolt.horizontal") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                if let run = project.run {
                    devCard(run)
                }
                if let conflict = actions.portConflict(for: project.path), !devRunning {
                    conflictNotice(conflict)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if showTestCard, let test = project.test {
                    testCard(test)
                }
                if !pinnedScripts.isEmpty {
                    Divider()
                    scriptsSection
                }
                feedback
            }
            .animation(
                FizzMotion.resolved(reduceMotion, FizzMotion.spring),
                value: actions.portConflict(for: project.path)
            )
        } accessory: {
            HStack(spacing: 8) {
                Text(runningCount > 0 ? "\(runningCount) 运行中" : "空闲")
                    .font(FizzTypography.monoSmall(.medium))
                    .foregroundStyle(.secondary)

                if !scripts.isEmpty {
                    scriptPinMenu
                }
            }
        }
        .alert(item: $pendingConflict) { conflict in
            Alert(
                title: Text("结束占用 :\(conflict.port) 的进程？"),
                message: Text(
                    "\(conflict.details)\n只向以上进程发送 SIGTERM。"
                ),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("结束并启动")) {
                    Task {
                        await actions.resolvePortConflictAndLaunch(
                            project,
                            conflict: conflict.confirmedByUser(),
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
                serviceStatus(active: devRunning, busy: busy)

                Text("dev")
                    .font(FizzTypography.cardTitle)

                Spacer(minLength: 4)

                if run.port > 0 {
                    Text(verbatim: ":\(run.port)")
                        .font(FizzTypography.mono)
                        .foregroundStyle(.secondary)
                }
            }

            Text(run.command)
                .font(FizzTypography.mono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(run.command)

            if run.port > 0 {
                DeveloperPortList(project: project) { devRunning = $0 }
                    .id(project.path)
            } else {
                Text("未配置预览端口").font(FizzTypography.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FizzSpacing.card)
        .fizzCard(radius: FizzRadius.card, fill: devRunning ? FizzTheme.selectedFill : FizzTheme.recessedFill)
    }

    private func conflictNotice(_ conflict: PortConflict) -> some View {
        HStack(spacing: FizzSpacing.row) {
            FizzIcon(.sm, symbol: "exclamationmark.triangle")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("端口 :\(conflict.port) 被占用")
                    .font(FizzTypography.cardTitle)
                Text(conflict.occupantSummary)
                    .font(FizzTypography.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let note = conflict.note {
                    Text(note)
                        .font(FizzTypography.micro)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            FizzActionButton(title: "结束占用进程并启动", height: .compact) {
                pendingConflict = conflict
            }
            .disabled(busy || !conflict.canStop)
            .help("确认后向占用 PID 发送 SIGTERM 并启动服务")
        }
        .padding(10)
        .background(
            FizzTheme.mutedFill,
            in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
    }

    private var scriptsSection: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.row) {
            HStack(spacing: 7) {
                Text("脚本")
                    .font(FizzTypography.cardTitle)
                Text("\(scripts.count)")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(pinnedScripts) { script in
                scriptCard(script)
            }

            if let selectedScript {
                scriptOutput(selectedScript)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            FizzMotion.resolved(reduceMotion, FizzMotion.spring),
            value: selectedScriptID
        )
    }

    private var scriptPinMenu: some View {
        FizzMenuButton(title: "固定脚本", symbol: "plus") {
            if unpinnedScripts.isEmpty {
                Text("全部脚本已固定")
            } else {
                ForEach(ProjectScriptSource.allCases, id: \.rawValue) { source in
                    let items = unpinnedScripts.filter { $0.source == source }
                    if !items.isEmpty {
                        Section(source.label) {
                            ForEach(items) { script in
                                Button("固定 \(script.name)") { pin(script) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func scriptCard(_ script: ProjectScript) -> some View {
        let run = actions.scriptRun(for: project, script: script)
        let running = run?.status == .running

        return HStack(spacing: FizzSpacing.row) {
            serviceStatus(active: running, busy: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: FizzSpacing.row) {
                    Text(script.name)
                        .font(FizzTypography.cardTitle)
                        .lineLimit(1)

                    if let run, let text = scriptStatusText(run) {
                        Text(text)
                            .font(FizzTypography.monoSmall)
                            .fizzStatus(scriptStatusColor(run.status))
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 5) {
                    TagChip(text: script.source.label, compact: true)
                    Text(script.command)
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(script.command)
                }
            }

            Spacer(minLength: 0)

            FizzMenuButton(title: "\(script.name) 的更多操作") {
                Button(selectedScriptID == script.id ? "收起输出" : "查看输出", systemImage: "terminal") {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                        selectedScriptID = selectedScriptID == script.id ? nil : script.id
                    }
                }
                Button("打开完整日志", systemImage: "arrow.up.right.square") {
                    actions.openScriptLog(script, project: project)
                }
                Button("取消固定", systemImage: "star.slash") { unpin(script) }
                    .disabled(running)
            }

            if running {
                FizzActionButton(title: "停止", height: .compact) {
                    actions.stopScript(script, project: project)
                }
                .help("停止 \(script.name)")
            } else {
                FizzActionButton(title: "运行", height: .compact) {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                        selectedScriptID = script.id
                    }
                    actions.runScript(script, project: project, store: store)
                }
                .disabled(ProjectTrialService.shared.runs[project.path].map { $0.status == .running && $0.choice.command == script.command } == true)
                .help("运行 \(script.command)")
            }
        }
        .padding(FizzSpacing.card)
        .fizzCard(radius: FizzRadius.card, fill: running ? FizzTheme.selectedFill : FizzTheme.recessedFill)
    }

    private func scriptOutput(_ script: ProjectScript) -> some View {
        let run = actions.scriptRun(for: project, script: script)
        let text = run?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(script.name)
                    .font(FizzTypography.monoSmall(.semibold))
                if let run {
                    TagChip(text: scriptStatusText(run) ?? "", tint: scriptStatusColor(run.status), compact: true)
                }
                Spacer(minLength: 8)
                FizzIconButton(title: "收起脚本输出", symbol: "xmark", height: .compact) {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                        selectedScriptID = nil
                    }
                }
            }

            ScrollView {
                Text(text.isEmpty ? "暂无输出" : text)
                    .font(FizzTypography.monoSmall)
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
        case .succeeded: FizzTheme.statusSuccess
        case .failed: FizzTheme.statusDanger
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
        ToastCenter.shared.show(
            "已固定 \(script.name)",
            symbol: "star.fill",
            tint: Color.secondary
        )
    }

    private func unpin(_ script: ProjectScript) {
        let ids = pinnedIDs.filter { $0 != script.id }
        pinnedIDs = ProjectScriptPreferences
            .setPinned(ids, for: project.path)
            .pinnedIDs(for: project.path)
        if selectedScriptID == script.id {
            selectedScriptID = nil
        }
        ToastCenter.shared.show(
            "已取消固定 \(script.name)",
            symbol: "star.slash",
            tint: .secondary
        )
    }

    private func loadScripts() async {
        let path = project.path
        let hasCheck = hasTrialPanel && project.test?.label == "check"
        let (found, checksTypes) = await Task.detached(priority: .utility) {
            let dir = URL(fileURLWithPath: path)
            let packageScripts = hasCheck ? FileTools.json(dir.appendingPathComponent("package.json"))?["scripts"] as? [String: String] : nil
            return (RunDetector.scripts(dir), TrialCommand.checksTypes(packageScripts?["check"]))
        }.value
        guard !Task.isCancelled else { return }
        checkIsTypecheck = checksTypes
        scripts = found
        pinnedIDs = ProjectScriptPreferences.load().pinnedIDs(for: path)
        if let selectedScriptID, !scripts.contains(where: { $0.id == selectedScriptID }) {
            self.selectedScriptID = nil
        }
    }

    private func testCard(_ test: TestCommand) -> some View {
        HStack(spacing: FizzSpacing.row) {
            serviceStatus(active: testRunning, busy: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: FizzSpacing.row) {
                    Text(test.label)
                        .font(FizzTypography.cardTitle)

                    if let testRun, let text = testStatusText(testRun) {
                        Text(text)
                            .font(FizzTypography.monoSmall)
                            .fizzStatus(testStatusColor(testRun.status))
                    }
                }

                Text(test.command)
                    .font(FizzTypography.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(test.command)
            }
            Spacer(minLength: 0)

            FizzActionButton(title: testRunning ? "停止" : "运行", height: .compact) {
                if testRunning {
                    actions.stopTests(project)
                } else {
                    actions.runTests(project, store: store)
                }
            }
            .help(testRunning ? "停止测试运行" : "运行测试命令")
            .accessibilityLabel(testRunning ? "停止测试运行" : "运行测试命令")
        }
        .padding(FizzSpacing.card)
        .fizzCard(radius: FizzRadius.card, fill: testRunning ? FizzTheme.selectedFill : FizzTheme.recessedFill)
    }

    @ViewBuilder
    private func serviceStatus(active: Bool, busy: Bool) -> some View {
        if busy {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else if active {
            RunningPulseDot()
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
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
        case .passed: FizzTheme.statusSuccess
        case .failed: FizzTheme.statusDanger
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
            FizzIcon(.xs, symbol: "info.circle")
                .foregroundStyle(.tertiary)
            Text(text)
                .font(FizzTypography.caption)
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
    @State private var showingErrorSheet = false

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
        let detectedError = LogErrorHelper.extractError(from: text)
        return Panel(title: "日志", symbol: "terminal") {
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    viewport
                    if let detectedError {
                        errorCallout(detectedError)
                    }
                }
            }
        } accessory: {
            HStack(spacing: 8) {
                if devAvailable && testAvailable {
                    sourceSwitcher
                } else if devAvailable || testAvailable {
                    Text(source.title)
                        .font(FizzTypography.monoSmall)
                        .foregroundStyle(.secondary)
                }

                FizzIconButton(
                    title: expanded ? "折叠日志" : "展开日志",
                    symbol: expanded ? "chevron.up" : "chevron.down",
                    height: .compact
                ) {
                    withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.quick)) {
                        expanded.toggle()
                    }
                }
                .accessibilityValue(expanded ? "已展开" : "已折叠")

                FizzIconButton(title: "打开完整日志", symbol: "arrow.up.forward.square", height: .compact) {
                    actions.openLog(for: project, test: source == .test)
                }
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
        .sheet(isPresented: $showingErrorSheet) {
            if let match = LogErrorHelper.extractError(from: text) {
                VStack(alignment: .leading, spacing: FizzSpacing.panel) {
                    FizzSheetHeader(title: "这是什么意思") {
                        showingErrorSheet = false
                    }

                    Label {
                        Text(match.plainExplanation)
                            .font(FizzTypography.sectionTitle)
                    } icon: {
                        FizzIcon(.lg, symbol: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                    }

                    Text("建议动作：\(match.suggestedAction)")
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(verbatim: match.contextBlock)
                            .font(FizzTypography.mono)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 180)
                    .background(FizzTheme.recessedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))

                    FizzSheetFooter {
                        FizzActionButton(title: "关闭", role: .cancel) {
                            showingErrorSheet = false
                        }
                        .keyboardShortcut(.cancelAction)
                        FizzActionButton(title: "复制求助 prompt", symbol: "doc.on.clipboard", prominence: .primary) {
                            copyHelpPrompt(match)
                            showingErrorSheet = false
                        }
                    }
                }
                .padding(FizzSpacing.page)
                .frame(width: 520)
            }
        }
    }

    private func errorCallout(_ match: LogErrorMatch) -> some View {
        HStack(spacing: 10) {
            FizzStatusDot(tint: FizzTheme.statusWarning)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.matchedLine)
                    .font(FizzTypography.mono(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(match.plainExplanation)
                    .font(FizzTypography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            FizzActionButton(title: "这是什么意思", height: .compact) {
                showingErrorSheet = true
            }

            FizzActionButton(title: "复制求助 prompt", height: .compact, prominence: .primary) {
                copyHelpPrompt(match)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(FizzTheme.mutedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
    }

    private func copyHelpPrompt(_ match: LogErrorMatch) {
        let prompt = LogErrorHelper.buildHelpPrompt(project: project, match: match)
        SystemActions.copy(prompt, feedback: nil)
        ToastCenter.shared.show("已复制求助 prompt，可直接粘贴给 AI", symbol: "doc.on.clipboard.fill", tint: Color.secondary)
    }

    private var sourceSwitcher: some View {
        Picker("日志来源", selection: $source) {
            ForEach(ProjectLogSource.allCases) { item in
                Text(item.title)
                    .accessibilityLabel(item == .dev ? "开发日志" : "测试日志")
                    .tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 94, height: FizzControlHeight.compact.rawValue)
        .focusable(interactions: .edit)
    }

    private var viewport: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.isEmpty ? "暂无日志输出" : text)
                        .font(FizzTypography.mono)
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
