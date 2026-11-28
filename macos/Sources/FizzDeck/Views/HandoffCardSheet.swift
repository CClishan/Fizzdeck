import AppKit
import SwiftUI

struct HandoffCopyButton: View {
    let project: RepoProject
    var compact = false
    var sessionLimit = 3

    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @State private var copied = false
    @State private var showingPreview = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        FizzActionButton(
            title: copied ? "已复制" : "复制接力卡",
            symbol: copied ? "checkmark" : "doc.on.clipboard",
            height: compact ? .compact : .standard
        ) {
            if NSEvent.modifierFlags.contains(.option) {
                showingPreview = true
            } else {
                copyNow()
            }
        }
        .help("复制项目进度给任意 AI 接着做（按住 ⌥ 点击可预览）")
        .accessibilityLabel("复制接力卡")
        .sheet(isPresented: $showingPreview) {
            HandoffCardSheet(project: project, initialLimit: sessionLimit)
        }
    }

    private func copyNow() {
        let result = HandoffCardBuilder.build(
            project: project,
            sessionLimit: sessionLimit,
            copyMode: copyMode
        )
        SystemActions.copy(result.markdown, feedback: nil)

        let subtitle = result.redactedCount > 0
            ? "\(result.characterCount) 字 · 已打码 \(result.redactedCount) 处密钥"
            : "\(result.characterCount) 字 · 含 \(result.includedSessionCount) 次对话"

        ToastCenter.shared.show(
            "接力卡已复制",
            symbol: "doc.on.clipboard.fill",
            tint: Color.secondary,
            subtitle: subtitle,
            action: ToastAction(title: "预览", symbol: "eye") {
                showingPreview = true
            }
        )

        copied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

struct HandoffCardSheet: View {
    private enum Edition: String, CaseIterable, Identifiable {
        case rule
        case ai

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rule: "规则版"
            case .ai: "✦ AI 版"
            }
        }
    }

    private struct RepairSnapshot {
        let projectPath: String
        let failure: HandoffFailure?
    }

    let project: RepoProject

    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectActions.self) private var actions
    @Environment(RepositoryStore.self) private var store
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @AppStorage(SummaryPreferences.enabledKey) private var aiEnabled = false
    @AppStorage(SummaryPreferences.consentAcceptedKey) private var summaryConsent = false
    @State private var sessionLimit: Int
    @State private var scenario: HandoffCardScenario = .resume
    @State private var repairSnapshot: RepairSnapshot?
    @State private var editors: [ProjectEditor] = []
    @State private var edition: Edition = .rule
    @State private var aiMarkdown: String?
    @State private var isGeneratingAI = false
    @State private var aiTimedOutToRule = false
    @State private var aiReadyBanner = false
    @State private var aiTask: Task<Void, Never>?

    init(project: RepoProject, initialLimit: Int = 3) {
        self.project = project
        let clamped = [1, 3, 5].contains(initialLimit) ? initialLimit : 3
        _sessionLimit = State(initialValue: clamped)
    }

    private var canUseAI: Bool { scenario == .resume && aiEnabled && summaryConsent }

    private var repairPath: String? { scenario == .fixError ? project.path : nil }

    private var scenarioSelection: Binding<HandoffCardScenario> {
        Binding(get: { scenario }, set: { choice in
            guard choice != scenario else { return }
            resetAI()
            repairSnapshot = nil
            scenario = choice
        })
    }

    private var editionSelection: Binding<Edition> {
        Binding(get: { edition }, set: { choice in
            guard choice != edition else { return }
            resetAI()
            if choice == .ai, canUseAI {
                edition = .ai
                startAIGeneration()
            }
        })
    }

    private var showingAIShimmer: Bool {
        edition == .ai && isGeneratingAI && !aiTimedOutToRule && aiMarkdown == nil
    }

    var body: some View {
        let waitingForRepair = repairPath != nil && repairSnapshot?.projectPath != repairPath
        let rule = HandoffCardBuilder.build(
            project: project, scenario: scenario, sessionLimit: sessionLimit, copyMode: copyMode,
            localFailure: waitingForRepair ? nil : repairSnapshot?.failure
        )
        let polished = canUseAI && edition == .ai && !aiTimedOutToRule ? aiMarkdown : nil
        let markdown = polished ?? rule.markdown

        VStack(spacing: 0) {
            FizzSheetHeader(title: "接力卡预览", subtitle: SecretRedactor.redact(project.displayName).text) { dismiss() }
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.panel)

            Divider()

            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                previewControls
                if !waitingForRepair {
                    HStack(spacing: FizzSpacing.row) {
                        let sessionCount = scenario == .resume ? " · 含最近 \(rule.includedSessionCount) 次对话" : ""
                        Text("\(markdown.count) 字\(sessionCount)")
                            .font(FizzTypography.caption)
                            .foregroundStyle(.secondary)
                        if rule.redactedCount > 0 {
                            TagChip(text: "已自动打码 \(rule.redactedCount) 处密钥", compact: true)
                        }
                    }
                }
                aiStatus
                preview(markdown, waitingForRepair: waitingForRepair)
            }
            .padding(FizzSpacing.page)

            Divider()

            footer(markdown)
                .disabled(waitingForRepair)
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: 640)
        .onExitCommand { dismiss() }
        .task(id: project.path) {
            let path = project.path
            let available = await Task.detached(priority: .utility) { ProjectEditor.available(for: path) }.value
            guard !Task.isCancelled else { return }
            editors = available
        }
        .task(id: repairPath) {
            guard let path = repairPath else { return }
            let failure = await HandoffCardBuilder.loadLocalFailure(
                for: project, actions: actions, projectPaths: store.projects.map(\.path)
            )
            guard !Task.isCancelled else { return }
            repairSnapshot = RepairSnapshot(projectPath: path, failure: failure)
        }
        .onChange(of: canUseAI) {
            if !canUseAI { resetAI() }
        }
        .onChange(of: sessionLimit) { resetAI() }
        .onChange(of: copyMode) { resetAI() }
        .onChange(of: project.path) { resetAI() }
        .onDisappear {
            aiTask?.cancel()
        }
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: FizzSpacing.row) {
            previewPicker("接力场景", items: HandoffCardScenario.allCases, selection: scenarioSelection) { $0.title }
            if scenario == .resume {
                HStack(spacing: FizzSpacing.row) {
                    if canUseAI {
                        previewPicker("版本", items: Edition.allCases, selection: editionSelection) { $0.title }
                            .help("选择 AI 版会发送脱敏后的项目接力信息进行润色")
                    }
                    previewPicker("对话条数", items: [1, 3, 5], selection: $sessionLimit) { "最近 \($0) 次" }
                }
            }
        }
    }

    private func footer(_ markdown: String) -> some View {
        FizzSheetFooter {
            FizzActionButton(title: "复制并打开终端", symbol: "terminal", height: .standard, prominence: .primary) {
                copy(markdown) { SystemActions.openTerminal(project.path) }
            }
            .keyboardShortcut(.defaultAction)

            FizzMenuButton(title: "其他复制方式", symbol: "chevron.down", height: .standard) {
                Button("只复制", systemImage: "doc.on.clipboard") { copy(markdown) }
                if !editors.isEmpty {
                    Divider()
                    ForEach(editors) { editor in
                        Button("复制并打开 \(editor.title)") {
                            copy(markdown) { SystemActions.open(project.path, in: editor) }
                        }
                    }
                }
            }
        }
    }

    private func copy(_ markdown: String, then open: () -> Void = {}) {
        let text = SecretRedactor.redact(markdown).text
        SystemActions.copy(text, feedback: nil)
        ToastCenter.shared.show("接力卡已复制", symbol: "doc.on.clipboard.fill", tint: FizzTheme.statusSuccess,
                                subtitle: "\(text.count) 字")
        open()
        dismiss()
    }

    private func previewPicker<Item: Hashable>(
        _ title: String, items: [Item], selection: Binding<Item>, label: @escaping (Item) -> String
    ) -> some View {
        FizzSegmentedCapsule(
            items: items, selection: selection, height: .compact,
            keyboardNavigation: true
        ) { item, _ in
            Text(label(item)).font(FizzTypography.caption(.medium))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var aiStatus: some View {
        if canUseAI && aiTimedOutToRule && isGeneratingAI {
            HStack(spacing: FizzSpacing.row) {
                ProgressView()
                    .controlSize(.mini)
                Text("AI 仍在整理中，先显示规则版，不用干等…")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } else if canUseAI && aiReadyBanner {
            HStack(spacing: FizzSpacing.row) {
                FizzIcon(.sm, symbol: "sparkles")
                    .foregroundStyle(Color.secondary)
                Text("AI 版已就绪")
                    .font(FizzTypography.caption(.medium))
                Spacer()
                FizzActionButton(title: "切换查看", height: .compact) {
                    aiTimedOutToRule = false
                    aiReadyBanner = false
                }
            }
            .padding(FizzSpacing.row)
            .background(FizzTheme.recessedFill, in: RoundedRectangle(cornerRadius: FizzRadius.control))
        }
    }

    private func preview(_ markdown: String, waitingForRepair: Bool) -> some View {
        Group {
            if waitingForRepair {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在整理本地失败记录")
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if canUseAI && showingAIShimmer {
                VStack(alignment: .leading, spacing: FizzSpacing.row) {
                    FizzShimmerPlaceholder(width: 320, height: 14)
                    FizzShimmerPlaceholder(width: 520, height: 12)
                    FizzShimmerPlaceholder(width: 460, height: 12)
                    FizzShimmerPlaceholder(width: 380, height: 12)
                    Spacer(minLength: 0)
                }
                .padding(FizzSpacing.panel)
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420, alignment: .topLeading)
            } else {
                ScrollView {
                    Text(verbatim: markdown)
                        .font(FizzTypography.mono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(FizzSpacing.panel)
                }
                .frame(minHeight: 280, maxHeight: 420)
            }
        }
        .background(FizzTheme.recessedFill, in: RoundedRectangle(cornerRadius: FizzRadius.inset))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
    }

    private func resetAI() {
        aiTask?.cancel()
        aiTask = nil
        edition = .rule
        aiMarkdown = nil
        aiReadyBanner = false
        aiTimedOutToRule = false
        isGeneratingAI = false
    }

    private func startAIGeneration() {
        guard canUseAI, edition == .ai else { return }
        isGeneratingAI = true

        aiTask = Task {
            guard !Task.isCancelled, canUseAI, edition == .ai else { return }
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, isGeneratingAI, aiMarkdown == nil else { return }
                aiTimedOutToRule = true
            }

            let generated = await withTaskCancellationHandler {
                await SummaryEngine.shared.generateHandoffMarkdown(
                    for: project, sessionLimit: sessionLimit, copyMode: copyMode
                )
            } onCancel: {
                timeoutTask.cancel()
            }
            timeoutTask.cancel()
            guard !Task.isCancelled, canUseAI, edition == .ai else { return }

            isGeneratingAI = false
            if let generated, !generated.isEmpty {
                aiMarkdown = SecretRedactor.redact(generated).text
                if aiTimedOutToRule {
                    aiReadyBanner = true
                }
            } else {
                aiTimedOutToRule = true
            }
        }
    }
}
