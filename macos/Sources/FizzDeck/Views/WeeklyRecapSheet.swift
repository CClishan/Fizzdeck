import SwiftUI

struct WeeklyRecapSheet: View {
    @State private var recap: WeeklyRecap

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SummaryPreferences.enabledKey) private var aiEnabled = false
    @AppStorage(SummaryPreferences.consentAcceptedKey) private var summaryConsent = false
    @AppStorage(SummaryPreferences.providerKindKey) private var providerKind: SummaryProviderKind = .agentCLI
    @State private var showConsent = false
    @State private var consentFor: SummaryProviderKind?
    @State private var polished: String?
    @State private var polishing = false

    init(projects: [RepoProject]) {
        _recap = State(initialValue: WeeklyRecapService.build(projects: projects))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.panel)

            Divider()
                .opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: FizzSpacing.section) {
                    if recap.hasActivity {
                        summaryGrid
                        polishControls
                        activeProjects
                        if !recap.topFiles.isEmpty {
                            topFiles
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(FizzSpacing.page)
            }

            Divider()
                .opacity(0.35)

            footer
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, 14)
        }
        .frame(width: 580, height: 620)
        .background(FizzTheme.page)
        .alert("允许润色这份周报？", isPresented: $showConsent) {
            Button("取消", role: .cancel) {}
            Button("同意并润色") { consentFor = providerKind }
        } message: {
            Text("只向当前 AI 提供方（\(providerKind.title)）发送项目、会话、文件和提交数量及估算费用。不发送名称、路径、周报原文或聊天内容。仅本次有效。")
        }
        .onChange(of: aiEnabled && summaryConsent) { if !aiEnabled || !summaryConsent { resetPolish() } }
        .onChange(of: providerKind) { resetPolish() }
        .task(id: consentFor) {
            guard let consentFor else { return }
            polishing = true
            let result = await WeeklyRecapService.polish(WeeklyRecapFigures(recap), consentFor: consentFor)
            guard !Task.isCancelled, self.consentFor == consentFor else { return }
            SummaryEngine.shared.refreshUsageTotals()
            polished = result
            polishing = false
            if result == nil { self.consentFor = nil }
        }
    }

    private func resetPolish() {
        showConsent = false
        consentFor = nil
        polished = nil
        polishing = false
    }

    private var polishControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("AI 润色", isOn: Binding(get: { consentFor != nil }, set: { on in
                    if on { showConsent = true } else { resetPolish() }
                }))
                .toggleStyle(.switch)
                .disabled(!aiEnabled || !summaryConsent)
                if polishing { ProgressView().controlSize(.mini) }
                Spacer()
                if !aiEnabled || !summaryConsent {
                    Button("设置 AI 总结…") { openSettings() }.buttonStyle(.link)
                }
            }
            .controlSize(.small)
            if let polished { Text(verbatim: polished).font(.callout).textSelection(.enabled) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本周回顾")
                    .font(.system(size: 23, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("最近 7 天的本机记录")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                FizzIcon(symbol: "xmark", size: 11)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .help("关闭")
            .accessibilityLabel("关闭本周回顾")
        }
    }

    private var summaryGrid: some View {
        VStack(alignment: .trailing, spacing: 4) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], alignment: .leading, spacing: 10
            ) {
                metric("AI 对话", value: "\(recap.sessionCount) 次", symbol: "bubble.left.and.bubble.right")
                metric("改动文件", value: "\(recap.changedFileCount) 个", symbol: "doc.text")
                metric("保存版本", value: "\(recap.savedVersionCount) 个", symbol: "bookmark.fill")
                metric("估算费用", value: recap.cost.amountLabel, symbol: "dollarsign.circle")
            }
            if recap.cost.isPartial {
                Text("另有 \(recap.cost.unpriced) 次会话未计价")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                FizzIcon(symbol: symbol, size: 10)
                    .foregroundStyle(FizzTheme.accent)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fizzCard(radius: FizzRadius.control)
    }

    private var activeProjects: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("活跃项目")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 0) {
                ForEach(recap.activeProjects.prefix(8)) { project in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.system(size: 12.5, weight: .medium))
                            Text("\(project.sessionCount) 次对话 · \(project.changedFileCount) 个文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(project.savedVersionCount) 个版本")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)

                    if project.id != recap.activeProjects.prefix(8).last?.id {
                        Divider()
                            .opacity(0.25)
                    }
                }
            }
        }
    }

    private var topFiles: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("改得最多")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 0) {
                ForEach(Array(recap.topFiles.enumerated()), id: \.element.id) { index, file in
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14, alignment: .trailing)
                        Text(file.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(file.projectName) · \(file.sessionCount) 次")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)

                    if file.id != recap.topFiles.last?.id {
                        Divider()
                            .opacity(0.25)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            FizzIcon(symbol: "calendar.badge.clock", size: 24)
                .foregroundStyle(FizzTheme.accent)
            Text("这周还没有可回顾的内容")
                .font(.system(size: 15, weight: .semibold))
            Text("和 AI 聊一次或存一个版本后，这里会按本机记录自动汇总。不会上传任何内容。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("只复制到剪贴板，不会写入项目文件。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                SystemActions.copy(
                    recap.markdown(polishedSummary: polished),
                    feedback: "本周回顾已复制",
                    microViz: .compact(state: .done)
                )
            } label: {
                Label("复制 Markdown", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.glassProminent)
            .tint(FizzTheme.accent)
            .controlSize(.small)
            .disabled(!recap.hasActivity)
            .accessibilityLabel("复制本周回顾 Markdown")
        }
    }
}
