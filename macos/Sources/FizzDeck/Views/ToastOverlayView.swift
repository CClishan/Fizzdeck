import SwiftUI

struct ToastOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let center: ToastCenter

    @State private var stageHovered = false
    @State private var hoveredCards: Set<UUID> = []

    private let cardWidth: CGFloat = 372
    private let cardHeight: CGFloat = 64
    private let expandedGap: CGFloat = 10

    private var visibleMessages: [ToastMessage] {
        Array(center.messages.prefix(3))
    }

    private var expanded: Bool {
        stageHovered || !hoveredCards.isEmpty
    }

    static func stageHeight(
        visibleCount: Int,
        expanded: Bool,
        cardHeight: CGFloat = 64,
        expandedGap: CGFloat = 10
    ) -> CGFloat {
        guard visibleCount > 0 else { return 0 }
        let count = CGFloat(visibleCount)
        if expanded {
            return count * cardHeight + max(0, count - 1) * expandedGap
        }
        return cardHeight + max(0, count - 1) * 10
    }

    private var stageHeight: CGFloat {
        Self.stageHeight(
            visibleCount: visibleMessages.count,
            expanded: expanded,
            cardHeight: cardHeight,
            expandedGap: expandedGap
        )
    }

    var body: some View {
        if !visibleMessages.isEmpty {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .contentShape(Rectangle())

                ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                    ToastCardView(
                        message: message,
                        expanded: expanded,
                        onClose: {
                            withAnimation(FizzMotion.resolved(reduceMotion, FizzMotion.spring)) {
                                center.dismiss(id: message.id)
                            }
                        }
                    )
                    .offset(y: yOffset(for: index))
                    .scaleEffect(scale(for: index), anchor: .bottomTrailing)
                    .opacity(opacity(for: index))
                    .zIndex(Double(10 - index))
                    .allowsHitTesting(expanded || index == 0)
                    .onHover { inside in
                        if inside {
                            hoveredCards.insert(message.id)
                        } else {
                            hoveredCards.remove(message.id)
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
                }
            }
            .frame(width: cardWidth, height: stageHeight, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            .onHover { inside in
                stageHovered = inside
            }
            .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: expanded)
            .animation(
                FizzMotion.resolved(reduceMotion, FizzMotion.spring),
                value: visibleMessages.map(\.id)
            )
        }
    }

    private func yOffset(for index: Int) -> CGFloat {
        if expanded {
            return -CGFloat(index) * (cardHeight + expandedGap)
        }
        return -CGFloat(index) * 10
    }

    private func scale(for index: Int) -> CGFloat {
        if expanded { return 1 }
        switch index {
        case 0: return 1
        case 1: return 0.955
        case 2: return 0.91
        default: return 0.88
        }
    }

    private func opacity(for index: Int) -> Double {
        if expanded { return 1 }
        switch index {
        case 0: return 1
        case 1: return 0.9
        case 2: return 0.75
        default: return 0
        }
    }
}

private struct ToastCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let message: ToastMessage
    let expanded: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let microViz = message.microViz {
                ToastMicroVizView(viz: microViz)
            } else {
                FizzIcon(symbol: message.symbol, size: 14)
                    .foregroundStyle(message.tint)
                    .frame(width: 30, height: 32)
                    .background(message.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(message.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action = message.action {
                Button {
                    action.handler()
                } label: {
                    HStack(spacing: 4) {
                        if let symbol = action.symbol {
                            FizzIcon(symbol: symbol, size: 9)
                        }
                        Text(action.title)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(FizzTheme.elevatedFill, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(FizzTheme.stroke, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(action.title)
                .accessibilityLabel(action.title)
            }

            if expanded {
                Button(action: onClose) {
                    FizzIcon(symbol: "xmark", size: 8)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭提示")
                .accessibilityLabel("关闭提示")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 372, height: 64)
        .background(
            FizzTheme.cardFill,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(FizzTheme.stroke, lineWidth: 1)
        }
        .fizzAdaptiveShadow(.floating)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: expanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var subtitle: some View {
        if case .diff(let added, let removed) = message.microViz {
            HStack(spacing: 5) {
                if let subtitle = message.subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                if added > 0 {
                    Text("+\(added)").foregroundStyle(.green)
                }
                if removed > 0 {
                    Text("−\(removed)").foregroundStyle(.red)
                }
            }
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
        } else if let subtitle = message.subtitle {
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var accessibilityLabel: String {
        [
            message.title,
            message.subtitle,
            message.microViz?.accessibilitySummary,
            message.action?.title,
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }
}
