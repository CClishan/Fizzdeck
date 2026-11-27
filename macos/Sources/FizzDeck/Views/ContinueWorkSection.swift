import SwiftUI

struct ContinueWorkSection: View {
    @Environment(RepositoryStore.self) private var store
    @AppStorage(CopyModePreferences.key) private var copyMode: CopyMode = .plain
    let items: [ContinueWorkItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    FizzIcon(symbol: "play.circle", size: 13)
                        .foregroundStyle(FizzTheme.accent)
                    Text(FizzCopy.continueWorkTitle(copyMode))
                        .font(.system(size: 13.5, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                if copyMode == .plain {
                    VStack(spacing: 8) {
                        if let first = items.first {
                            HeroContinueWorkCard(item: first) {
                                store.openProject(first.project, tab: .progress, sessionID: first.session.id)
                            }
                        }
                        ForEach(items.dropFirst()) { item in
                            CompactContinueWorkRow(item: item) {
                                store.openProject(item.project, tab: .progress, sessionID: item.session.id)
                            }
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: FizzSpacing.grid)],
                        spacing: FizzSpacing.grid
                    ) {
                        ForEach(items) { item in
                            ContinueWorkCard(item: item) {
                                store.openProject(item.project)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HeroContinueWorkCard: View {
    let item: ContinueWorkItem
    let openProgress: () -> Void

    private var summary: String {
        let cleaned = SessionSummaryText.clean(item.summary)
        return cleaned.isEmpty ? "\(item.toolTitle) 会话" : cleaned
    }

    private var metadataLine: String {
        var parts: [String] = []
        if item.touchedFileCount > 0 {
            parts.append("改了 \(item.touchedFileCount) 个文件")
        }
        if let mins = item.durationMinutes, mins > 0 {
            parts.append("\(mins) 分钟")
        }
        if let cost = Format.cost(item.session.costUSD, estimated: item.session.costIsEstimate ?? false) {
            parts.append(cost)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProjectBadgeIcon(project: item.project, size: 28, framed: false)

                Button(action: openProgress) {
                    Text(item.project.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                HomeToolBadge(tool: item.session.tool, compact: false)

                if item.endedWithError {
                    TagChip(text: "报错结束", tint: .orange, compact: true)
                }

                Spacer(minLength: 4)

                Text(Format.relative(item.modified))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Text("「\(summary)」")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            let aiSummary = SummaryEngine.shared.cachedOrRuleBasedSessionSummary(
                for: item.session,
                projectName: item.project.displayName,
                copyMode: .plain
            )
            if aiSummary.isAIGenerated {
                Text("✦ \(aiSummary.headline)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(FizzTheme.accent)
                    .lineLimit(1)
            }

            if !metadataLine.isEmpty {
                Text(metadataLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                SessionContinueButton(project: item.project, style: .prominent)
                HandoffCopyButton(project: item.project, compact: true)
                Button("看进度", action: openProgress)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FizzTheme.cardFill, in: RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
        .fizzAdaptiveShadow(.subtle)
    }
}

private struct CompactContinueWorkRow: View {
    let item: ContinueWorkItem
    let openProgress: () -> Void

    private var summary: String {
        let cleaned = SessionSummaryText.clean(item.summary)
        return cleaned.isEmpty ? "\(item.toolTitle) 会话" : cleaned
    }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: openProgress) {
                HStack(spacing: 8) {
                    ProjectBadgeIcon(project: item.project, size: 20, framed: false)
                    Text(item.project.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("「\(summary)」")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    if item.endedWithError {
                        FizzIcon(symbol: "exclamationmark.triangle.fill", size: 11)
                            .foregroundStyle(.orange)
                    }
                    Text(Format.relative(item.modified))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SessionContinueButton(project: item.project, style: .compact)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FizzTheme.cardFill, in: RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.inset, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
    }
}

private struct ContinueWorkCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ContinueWorkItem
    let openProject: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    private var summary: String {
        let cleaned = SessionSummaryText.clean(item.summary)
        return cleaned.isEmpty ? "\(item.toolTitle) 会话" : cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProjectBadgeIcon(project: item.project, size: 24, framed: false)

                Button(action: openProject) {
                    Text(item.project.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("打开 \(item.project.displayName)")

                Spacer(minLength: 4)

                HomeToolBadge(tool: item.session.tool, compact: false)
            }

            Text(summary)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)

            HStack(spacing: 8) {
                Text(Format.relative(item.modified))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                SessionContinueButton(project: item.project, style: .compact)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FizzTheme.cardFill, in: RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FizzRadius.card, style: .continuous)
                .strokeBorder(hovering ? FizzTheme.accent.opacity(0.24) : FizzTheme.stroke, lineWidth: 1)
        }
        .fizzAdaptiveShadow(hovering ? .raised : .subtle)
        .scaleEffect(pressed ? 0.988 : 1)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: pressed)
        .onHover { value in
            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                hovering = value
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true }
                }
                .onEnded { _ in
                    pressed = false
                }
        )
    }
}
