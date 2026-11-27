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
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                showingPreview = true
            } else {
                copyNow()
            }
        } label: {
            HStack(spacing: 4) {
                FizzIcon(
                    symbol: copied ? "checkmark" : "doc.on.clipboard",
                    size: compact ? 10 : 11
                )
                .foregroundStyle(copied ? Color.green : FizzTheme.accent)

                Text(copied ? "已复制" : "复制接力卡")
                    .font(.system(size: compact ? 10.5 : 12, weight: .medium))
            }
        }
        .buttonStyle(.glass)
        .controlSize(compact ? .small : .regular)
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
        SystemActions.copy(result.markdown)

        let subtitle = result.redactedCount > 0
            ? "\(result.characterCount) 字 · 已打码 \(result.redactedCount) 处密钥"
            : "\(result.characterCount) 字 · 含 \(result.includedSessionCount) 次对话"

        ToastCenter.shared.show(
            "接力卡已复制",
            symbol: "doc.on.clipboard.fill",
            tint: FizzTheme.accent,
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

    let project: RepoProject
    var initialLimit = 3

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    @AppStorage(SummaryPreferences.enabledKey) private var aiEnabled = false
    @State private var sessionLimit: Int
    @State private var edition: Edition = .rule
    @State private var aiMarkdown: String?
    @State private var isGeneratingAI = false
    @State private var aiTimedOutToRule = false
    @State private var aiReadyBanner = false
    @State private var aiTask: Task<Void, Never>?

    init(project: RepoProject, initialLimit: Int = 3) {
        self.project = project
        self.initialLimit = initialLimit
        let clamped = [1, 3, 5].contains(initialLimit) ? initialLimit : 3
        _sessionLimit = State(initialValue: clamped)
    }

    private var ruleResult: HandoffCardResult {
        HandoffCardBuilder.build(
            project: project,
            sessionLimit: sessionLimit,
            copyMode: copyMode
        )
    }

    private var showingAIBody: Bool {
        edition == .ai && aiMarkdown != nil && !aiTimedOutToRule
    }

    private var showingAIShimmer: Bool {
        edition == .ai && isGeneratingAI && !aiTimedOutToRule && aiMarkdown == nil
    }

    private var activeMarkdown: String {
        if showingAIBody, let aiMarkdown {
            return aiMarkdown
        }
        return ruleResult.markdown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("接力卡预览 · \(project.displayName)")
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 8) {
                        Text("\(activeMarkdown.count) 字 · 含最近 \(ruleResult.includedSessionCount) 次对话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if ruleResult.redactedCount > 0 {
                            TagChip(
                                text: "已自动打码 \(ruleResult.redactedCount) 处密钥",
                                tint: .orange,
                                compact: true
                            )
                        }
                    }
                }

                Spacer(minLength: 12)

                if aiEnabled {
                    Picker("版本", selection: $edition) {
                        ForEach(Edition.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 146)
                }

                Picker("对话条数", selection: $sessionLimit) {
                    Text("最近 1 次").tag(1)
                    Text("最近 3 次").tag(3)
                    Text("最近 5 次").tag(5)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            if aiTimedOutToRule && isGeneratingAI {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("AI 仍在整理中，先显示规则版，不用干等…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if aiReadyBanner {
                HStack(spacing: 8) {
                    FizzIcon(symbol: "sparkles", size: 12)
                        .foregroundStyle(FizzTheme.accent)
                    Text("✦ AI 版已就绪")
                        .font(.caption.weight(.medium))
                    Button("切换查看") {
                        aiTimedOutToRule = false
                        aiReadyBanner = false
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FizzTheme.accent)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(FizzTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous))
            }

            Group {
                if showingAIShimmer {
                    VStack(alignment: .leading, spacing: 10) {
                        FizzShimmerPlaceholder(width: 320, height: 14)
                        FizzShimmerPlaceholder(width: 520, height: 12)
                        FizzShimmerPlaceholder(width: 460, height: 12)
                        FizzShimmerPlaceholder(width: 380, height: 12)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420, alignment: .topLeading)
                } else {
                    ScrollView {
                        Text(verbatim: activeMarkdown)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(minHeight: 280, maxHeight: 420)
                }
            }
            .background(
                FizzTheme.recessedFill,
                in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }

            HStack {
                Text("只复制到剪贴板，不会修改项目文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.glass)

                Button {
                    SystemActions.copy(activeMarkdown)
                    ToastCenter.shared.show(
                        "接力卡已复制",
                        symbol: "doc.on.clipboard.fill",
                        tint: FizzTheme.accent,
                        subtitle: "\(activeMarkdown.count) 字"
                    )
                    dismiss()
                } label: {
                    Label("复制到剪贴板", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.glassProminent)
                .tint(FizzTheme.accent)
            }
        }
        .padding(22)
        .frame(width: 640)
        .onChange(of: edition) {
            if edition == .ai {
                startAIGeneration()
            } else {
                aiTask?.cancel()
                isGeneratingAI = false
                aiTimedOutToRule = false
                aiReadyBanner = false
            }
        }
        .onChange(of: sessionLimit) {
            if edition == .ai {
                startAIGeneration()
            }
        }
        .onDisappear {
            aiTask?.cancel()
        }
    }

    private func startAIGeneration() {
        aiTask?.cancel()
        aiMarkdown = nil
        aiReadyBanner = false
        aiTimedOutToRule = false
        isGeneratingAI = true

        aiTask = Task {
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, isGeneratingAI, aiMarkdown == nil else { return }
                aiTimedOutToRule = true
            }

            let generated = await SummaryEngine.shared.generateHandoffMarkdown(
                for: project,
                sessionLimit: sessionLimit,
                copyMode: copyMode
            )
            timeoutTask.cancel()
            guard !Task.isCancelled else { return }

            isGeneratingAI = false
            if let generated, !generated.isEmpty {
                aiMarkdown = generated
                if aiTimedOutToRule {
                    aiReadyBanner = true
                }
            } else {
                aiTimedOutToRule = true
            }
        }
    }
}
