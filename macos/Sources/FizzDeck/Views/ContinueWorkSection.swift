import SwiftUI

struct ContinueWorkSection: View {
    @Environment(RepositoryStore.self) private var store
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    let items: [ContinueWorkItem]

    var body: some View {
        Panel(title: FizzCopy.continueWorkTitle(copyMode), symbol: "play.circle", fillHeight: true) {
            if let first = items.first {
                VStack(spacing: FizzSpacing.row) {
                    ContinueWorkRow(item: first, featured: true, copyMode: copyMode) { open(first) }
                    ForEach(items.dropFirst()) { item in
                        ContinueWorkRow(item: item, featured: false, copyMode: copyMode) { open(item) }
                    }
                }
            } else {
                Text(FizzL10n.text("暂无可继续的对话", "No conversations to resume"))
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, FizzSpacing.row)
            }
        } accessory: {
            if !items.isEmpty {
                Text(FizzL10n.text("\(items.count) 项", SessionSummaryText.englishCount(items.count, "item")))
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func open(_ item: ContinueWorkItem) {
        store.openProject(item.project, tab: .progress, sessionID: item.session.id)
    }
}

private struct ContinueWorkRow: View {
    let item: ContinueWorkItem
    let featured: Bool
    let copyMode: CopyMode
    let onOpen: () -> Void

    private var summary: String {
        let cleaned = SessionSummaryText.clean(item.summary)
        return cleaned.isEmpty ? FizzL10n.text("\(item.toolTitle) 会话", "\(item.toolTitle) session") : cleaned
    }

    private var metadataLine: String {
        var parts = [Format.relative(item.modified)]
        if item.touchedFileCount > 0 { parts.append(FizzL10n.text("改了 \(item.touchedFileCount) 个文件", "\(SessionSummaryText.englishCount(item.touchedFileCount, "file")) changed")) }
        if let minutes = item.durationMinutes, minutes > 0 { parts.append(FizzL10n.text("\(minutes) 分钟", "\(minutes) min")) }
        if let cost = Format.cost(item.session.costUSD, estimated: item.session.costIsEstimate ?? false) {
            parts.append(cost)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if featured {
            VStack(alignment: .leading, spacing: FizzSpacing.row) {
                projectLink
                if copyMode == .plain, let summary = SummaryEngine.shared.sessionSummaries[item.session.stableID],
                   summary.isAIGenerated, summary.fingerprint == SummaryCacheStore.sessionFingerprint(for: item.session) {
                    Text("✦ \(summary.headline)")
                        .font(FizzTypography.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Text(metadataLine)
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: FizzSpacing.row) {
                    HandoffCopyButton(project: item.project, compact: true)
                    SessionContinueButton(project: item.project, style: .prominent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .fizzSubcard()
            .task(id: copyMode == .plain ? item.session : nil) {
                guard copyMode == .plain else { return }
                _ = SummaryEngine.shared.cachedOrRuleBasedSessionSummary(
                    for: item.session, projectName: item.project.displayName, copyMode: copyMode
                )
            }
        } else {
            HStack(spacing: FizzSpacing.row) {
                projectLink
                SessionContinueButton(project: item.project, style: .compact)
            }
            .padding(.vertical, 4)
        }
    }

    private var projectLink: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: FizzSpacing.row) {
                ProjectAccentDot(path: item.project.path).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.project.displayName)
                            .font(FizzTypography.cardTitle)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.endedWithError {
                            FizzIcon(.xs, symbol: "exclamationmark.triangle.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(FizzL10n.text("报错结束", "Failed"))
                        }
                        if featured { HomeToolBadge(tool: item.session.tool, compact: true) }
                    }
                    Text(summary)
                        .font(featured ? FizzTypography.body : FizzTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(featured ? 2 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(FizzL10n.text("查看 \(item.project.displayName) 的进度", "View Progress for \(item.project.displayName)"))
    }
}
