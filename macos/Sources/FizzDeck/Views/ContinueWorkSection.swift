import SwiftUI

struct ContinueWorkSection: View {
    @Environment(RepositoryStore.self) private var store
    let items: [ContinueWorkItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    FizzIcon(symbol: "play.circle", size: 13)
                        .foregroundStyle(FizzTheme.accent)
                    Text("继续工作")
                        .font(.system(size: 13.5, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

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
